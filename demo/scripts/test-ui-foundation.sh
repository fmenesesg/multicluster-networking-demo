#!/usr/bin/env bash
# Offline suite: UI foundation + Phase A via make ui / lib/ (Kind-free).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MAKEFILE="${ROOT}/Makefile"
README="${ROOT}/README.md"
KUADRANT_README="${ROOT}/demo/kuadrant/README.md"
UI_COMMON="${SCRIPT_DIR}/ui-common.sh"
UI_SH="${SCRIPT_DIR}/ui.sh"
UI_DOWN="${SCRIPT_DIR}/ui-down.sh"
PHASE_A="${SCRIPT_DIR}/ui/_phase_a.sh"
PHASE_B="${SCRIPT_DIR}/ui/_phase_b.sh"
PHASE_C="${SCRIPT_DIR}/ui/_phase_c.sh"
LIB_COMMON="${SCRIPT_DIR}/lib/common.sh"

pass=0
fail=0

assert_ok() {
  local desc="$1"
  shift
  local out rc
  set +e
  out="$("$@" 2>&1)"
  rc=$?
  set -e
  if [[ "${rc}" -ne 0 ]]; then
    printf 'FAIL: %s (exit %s)\n' "${desc}" "${rc}"
    printf '  output: %s\n' "${out}"
    fail=$((fail + 1))
    return
  fi
  printf 'PASS: %s\n' "${desc}"
  pass=$((pass + 1))
}

assert_fails_with() {
  local desc="$1"
  local needle="$2"
  shift 2
  local out rc
  set +e
  out="$("$@" 2>&1)"
  rc=$?
  set -e
  if [[ "${rc}" -eq 0 ]]; then
    printf 'FAIL: %s (expected non-zero exit)\n' "${desc}"
    printf '  output: %s\n' "${out}"
    fail=$((fail + 1))
    return
  fi
  if ! grep -qiE "${needle}" <<<"${out}"; then
    printf 'FAIL: %s (exit %s but missing /%s/)\n' "${desc}" "${rc}" "${needle}"
    printf '  output: %s\n' "${out}"
    fail=$((fail + 1))
    return
  fi
  printf 'PASS: %s\n' "${desc}"
  pass=$((pass + 1))
}

assert_output_contains() {
  local desc="$1"
  local needle="$2"
  shift 2
  local out rc
  set +e
  out="$("$@" 2>&1)"
  rc=$?
  set -e
  if [[ "${rc}" -ne 0 ]]; then
    printf 'FAIL: %s (exit %s)\n' "${desc}" "${rc}"
    printf '  output: %s\n' "${out}"
    fail=$((fail + 1))
    return
  fi
  if ! grep -qF "${needle}" <<<"${out}"; then
    printf 'FAIL: %s (missing %q)\n' "${desc}" "${needle}"
    printf '  output: %s\n' "${out}"
    fail=$((fail + 1))
    return
  fi
  printf 'PASS: %s\n' "${desc}"
  pass=$((pass + 1))
}

assert_output_lacks() {
  local desc="$1"
  local needle="$2"
  shift 2
  local out rc
  set +e
  out="$("$@" 2>&1)"
  rc=$?
  set -e
  if [[ "${rc}" -ne 0 ]]; then
    printf 'FAIL: %s (exit %s)\n' "${desc}" "${rc}"
    printf '  output: %s\n' "${out}"
    fail=$((fail + 1))
    return
  fi
  if grep -qF "${needle}" <<<"${out}"; then
    printf 'FAIL: %s (unexpected %q)\n' "${desc}" "${needle}"
    printf '  output: %s\n' "${out}"
    fail=$((fail + 1))
    return
  fi
  printf 'PASS: %s\n' "${desc}"
  pass=$((pass + 1))
}

assert_file_contains() {
  local desc="$1"
  local needle="$2"
  local file="$3"
  if grep -qF "${needle}" "${file}"; then
    printf 'PASS: %s\n' "${desc}"
    pass=$((pass + 1))
  else
    printf 'FAIL: %s (missing %q in %s)\n' "${desc}" "${needle}" "${file}"
    fail=$((fail + 1))
  fi
}

assert_file_lacks() {
  local desc="$1"
  local needle="$2"
  local file="$3"
  if grep -qF "${needle}" "${file}"; then
    printf 'FAIL: %s (unexpected %q in %s)\n' "${desc}" "${needle}" "${file}"
    fail=$((fail + 1))
  else
    printf 'PASS: %s\n' "${desc}"
    pass=$((pass + 1))
  fi
}

assert_file_exists() {
  local desc="$1"
  local file="$2"
  if [[ -f "${file}" ]]; then
    printf 'PASS: %s\n' "${desc}"
    pass=$((pass + 1))
  else
    printf 'FAIL: %s (missing %s)\n' "${desc}" "${file}"
    fail=$((fail + 1))
  fi
}

# --- make up has no ui-* deps ---
up_recipe="$(awk '/^up:/{flag=1; next} /^[^[:space:]#]/{flag=0} flag' "${MAKEFILE}")"
if grep -E 'ui-' <<<"${up_recipe}" >/dev/null 2>&1; then
  printf 'FAIL: Makefile up recipe references ui-*\n'
  printf '  recipe: %s\n' "${up_recipe}"
  fail=$((fail + 1))
else
  printf 'PASS: Makefile up has no ui-* deps\n'
  pass=$((pass + 1))
fi

# Public surface: ui + ui-down; refuse old Make names
if grep -qE '^ui:' "${MAKEFILE}"; then
  printf 'PASS: Makefile has ui target\n'
  pass=$((pass + 1))
else
  printf 'FAIL: Makefile missing ui target\n'
  fail=$((fail + 1))
fi

if grep -qE '^ui-down:' "${MAKEFILE}"; then
  printf 'PASS: Makefile has ui-down target\n'
  pass=$((pass + 1))
else
  printf 'FAIL: Makefile missing ui-down target\n'
  fail=$((fail + 1))
fi

for old in ui-app ui-app-check ui-linkerd ui-linkerd-check ui-skupper ui-skupper-check talk-up; do
  if grep -qE "^${old}:" "${MAKEFILE}"; then
    printf 'FAIL: Makefile still has removed target %s\n' "${old}"
    fail=$((fail + 1))
  else
    printf 'PASS: Makefile hard-cut removes %s\n' "${old}"
    pass=$((pass + 1))
  fi
done

help_out="$(make -C "${ROOT}" help 2>&1)"
if grep -qE '^[[:space:]]*make ui[[:space:]]' <<<"${help_out}" && \
   grep -qE '^[[:space:]]*make ui-down[[:space:]]' <<<"${help_out}"; then
  printf 'PASS: make help lists ui and ui-down\n'
  pass=$((pass + 1))
else
  printf 'FAIL: make help missing ui / ui-down\n'
  fail=$((fail + 1))
fi
# Match public Make target lines only (not test-ui-linkerd / test-ui-skupper suite names).
if grep -Eiq 'make ui-app|make ui-linkerd|make ui-skupper|make talk-up' <<<"${help_out}"; then
  printf 'FAIL: make help still lists old UI names\n'
  fail=$((fail + 1))
else
  printf 'PASS: make help omits old per-phase UI names\n'
  pass=$((pass + 1))
fi

assert_file_exists "ui.sh dispatcher present" "${UI_SH}"
assert_file_exists "lib/common.sh present" "${LIB_COMMON}"
assert_file_exists "phase A private script present" "${PHASE_A}"
if [[ -e "${SCRIPT_DIR}/ui-app.sh" || -e "${SCRIPT_DIR}/ui-app-check.sh" ]]; then
  printf 'FAIL: old ui-app*.sh still present\n'
  fail=$((fail + 1))
else
  printf 'PASS: old ui-app*.sh removed\n'
  pass=$((pass + 1))
fi

# --- refuse reserved ports ---
# shellcheck disable=SC1091
source "${UI_COMMON}"

for port in 8080 8081 18080 18081 45671 55671; do
  assert_fails_with \
    "refuse reserved port ${port}" \
    "refusing reserved|reserved demo port" \
    bash -c "source '${UI_COMMON}'; demo_ui_refuse_reserved_port '${port}'"
done

assert_fails_with \
  "demo_pick_free_port refuses preferred 8080" \
  "refusing reserved|reserved demo port" \
  bash -c "source '${UI_COMMON}'; demo_pick_free_port 8080"

assert_ok \
  "demo_pick_free_port accepts preferred 50750 when free-or-next" \
  bash -c "source '${UI_COMMON}'; p=\$(demo_pick_free_port 50750); [[ -n \"\$p\" ]] && ! demo_ui_is_reserved_port \"\$p\""

# --- bad CLUSTER / never kind-cluster (Phase A via private PHASE=) ---
assert_fails_with \
  "ui PHASE=a refuses CLUSTER=kind-cluster" \
  "refusing|allowlist|kind-cluster" \
  env CLUSTER=kind-cluster PHASE=a UI_SKIP_PROBE=1 "${UI_SH}"

assert_fails_with \
  "ui PHASE=a aborts unknown CLUSTER" \
  "refusing|allowlist" \
  env CLUSTER=evil-cluster PHASE=a UI_SKIP_PROBE=1 "${UI_SH}"

assert_fails_with \
  "ui-down refuses CLUSTER=kind-cluster" \
  "refusing|allowlist|kind-cluster" \
  env CLUSTER=kind-cluster "${SCRIPT_DIR}/ui-down.sh"

# --- Phase A ACCESS_URL contract (offline: skip live probe) ---
assert_output_contains \
  "phase A prints ACCESS_URL west contract" \
  "ACCESS_URL=http://emojivoto.demo.local:8080/" \
  env PHASE=a UI_SKIP_PROBE=1 "${UI_SH}"

assert_output_lacks \
  "phase A does not prescribe bare IP URL without Host" \
  "ACCESS_URL=http://127.0.0.1:8080/" \
  env PHASE=a UI_SKIP_PROBE=1 "${UI_SH}"

assert_output_contains \
  "phase A mentions /etc/hosts" \
  "emojivoto.demo.local" \
  env PHASE=a UI_SKIP_PROBE=1 "${UI_SH}"

assert_ok \
  "make -n ui dry-runs" \
  make -C "${ROOT}" -n ui

# Fail-fast contract offline: B then C order; set -e; no continue-on-error
assert_file_contains \
  "ui.sh uses set -e fail-fast" \
  "set -euo pipefail" \
  "${UI_SH}"
assert_file_contains \
  "ui.sh allows UI_DIR override for harnesses" \
  'UI_DIR="${UI_DIR:-' \
  "${UI_SH}"
if grep -q 'run_phase a' "${UI_SH}" && grep -q 'run_phase b' "${UI_SH}" && grep -q 'run_phase c' "${UI_SH}"; then
  printf 'PASS: ui.sh runs A then B then C\n'
  pass=$((pass + 1))
else
  printf 'FAIL: ui.sh missing sequential A/B/C\n'
  fail=$((fail + 1))
fi
# Drive real ui.sh with stub phases via UI_DIR (mid-B fail ⇒ C not started)
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT
cat >"${tmpdir}/_phase_a.sh" <<'EOF'
#!/usr/bin/env bash
printf 'stub A ACCESS_URL=http://emojivoto.demo.local:8080/\n'
EOF
cat >"${tmpdir}/_phase_b.sh" <<'EOF'
#!/usr/bin/env bash
printf 'stub B failing\n' >&2
exit 7
EOF
cat >"${tmpdir}/_phase_c.sh" <<'EOF'
#!/usr/bin/env bash
printf 'stub C should not run\n' >"${UI_FAILFAST_MARKER}"
exit 0
EOF
chmod +x "${tmpdir}"/_phase_*.sh
marker="${tmpdir}/c-ran"
set +e
out="$(
  UI_DIR="${tmpdir}" UI_FAILFAST_MARKER="${marker}" PHASE=all "${UI_SH}" 2>&1
)"
rc=$?
set -e
if [[ "${rc}" -eq 0 ]]; then
  printf 'FAIL: fail-fast ui.sh expected non-zero (got 0)\n'
  fail=$((fail + 1))
elif [[ -f "${marker}" ]]; then
  printf 'FAIL: fail-fast ui.sh started Phase C after B failure\n'
  fail=$((fail + 1))
elif ! grep -q 'stub B failing' <<<"${out}"; then
  printf 'FAIL: fail-fast ui.sh missing B failure output\n'
  fail=$((fail + 1))
elif ! grep -q 'ui: starting Phase B' <<<"${out}"; then
  printf 'FAIL: fail-fast did not run real ui.sh (missing Phase B banner)\n'
  fail=$((fail + 1))
else
  printf 'PASS: fail-fast B failure skips Phase C (real ui.sh)\n'
  pass=$((pass + 1))
fi

# Phase env knobs follow letter vocab (not legacy UI_APP_*/UI_LINKERD_*/UI_SKUPPER_*)
assert_file_contains \
  "phase A uses UI_A_* knobs" \
  "UI_A_SHOW_EAST" \
  "${PHASE_A}"
if grep -Eiq 'UI_APP_|UI_LINKERD_|UI_SKUPPER_' "${PHASE_A}" "${PHASE_B}" "${PHASE_C}" "${UI_DOWN}"; then
  printf 'FAIL: legacy UI_APP_/UI_LINKERD_/UI_SKUPPER_ knobs still present\n'
  fail=$((fail + 1))
else
  printf 'PASS: phase/ui-down knobs use UI_A_/UI_B_/UI_C_ vocab\n'
  pass=$((pass + 1))
fi

# --- README / docs contracts ---
assert_file_contains \
  "README documents /etc/hosts for app access" \
  "/etc/hosts" \
  "${README}"
assert_file_contains \
  "README documents emojivoto.demo.local host" \
  "emojivoto.demo.local" \
  "${README}"
assert_file_contains \
  "README documents west Gateway :8080" \
  ":8080" \
  "${README}"
assert_file_contains \
  "README Phase A ACCESS_URL contract" \
  "ACCESS_URL=http://emojivoto.demo.local:8080/" \
  "${README}"
assert_file_contains \
  "README marks Phase A as Browser / opt-in" \
  "Phase A" \
  "${README}"
assert_file_contains \
  "README documents make ui" \
  "make ui" \
  "${README}"
assert_file_contains \
  "README bans Kuadrant Grafana as talk UI" \
  "Kuadrant Grafana" \
  "${README}"
assert_file_contains \
  "README bans Envoy admin / Kiali / Dashboard talk surfaces" \
  "Kiali" \
  "${README}"
assert_file_contains \
  "README RateLimit path is make demo-ratelimit" \
  "make demo-ratelimit" \
  "${README}"
assert_file_contains \
  "README RateLimit wow is HTTP 429" \
  "429" \
  "${README}"
assert_file_contains \
  "kuadrant README critical path is RateLimitPolicy 429" \
  "RateLimitPolicy" \
  "${KUADRANT_README}"
assert_file_contains \
  "kuadrant README documents 429 wow" \
  "429" \
  "${KUADRANT_README}"

assert_file_contains \
  "README failover path is make failover" \
  "make failover" \
  "${README}"
assert_file_contains \
  "README failover verifies via dig / CoreDNS" \
  "dig" \
  "${README}"
assert_file_contains \
  "kuadrant README failover is make failover DNS path" \
  "make failover" \
  "${KUADRANT_README}"
assert_file_contains \
  "kuadrant README failover asserts CoreDNS answers" \
  "CoreDNS" \
  "${KUADRANT_README}"

printf '\nUI foundation suite: %s passed, %s failed\n' "${pass}" "${fail}"
if [[ "${fail}" -ne 0 ]]; then
  exit 1
fi
