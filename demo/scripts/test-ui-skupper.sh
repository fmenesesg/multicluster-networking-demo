#!/usr/bin/env bash
# Offline suite: Phase C observer + teardown via make ui surface (Kind-free).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MAKEFILE="${ROOT}/Makefile"
VERSIONS="${ROOT}/demo/VERSIONS.md"
SKUPPER_README="${ROOT}/demo/skupper/README.md"
VALUES="${ROOT}/demo/skupper/network-observer/values.yaml"
CHECK_SKUPPER="${SCRIPT_DIR}/check-skupper.sh"
UI_COMMON="${SCRIPT_DIR}/ui-common.sh"
PHASE_A="${SCRIPT_DIR}/ui/_phase_a.sh"
PHASE_B="${SCRIPT_DIR}/ui/_phase_b.sh"
PHASE_C="${SCRIPT_DIR}/ui/_phase_c.sh"
UI_SH="${SCRIPT_DIR}/ui.sh"
UI_DOWN="${SCRIPT_DIR}/ui-down.sh"
DOWN_SH="${SCRIPT_DIR}/down.sh"

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

up_recipe="$(awk '/^up:/{flag=1; next} /^[^[:space:]#]/{flag=0} flag' "${MAKEFILE}")"
if grep -E 'ui-' <<<"${up_recipe}" >/dev/null 2>&1; then
  printf 'FAIL: Makefile up recipe references ui-*\n'
  fail=$((fail + 1))
else
  printf 'PASS: Makefile up has no ui-* deps\n'
  pass=$((pass + 1))
fi

if grep -Eiq 'network-observer|_phase_c|ui-skupper' "${SCRIPT_DIR}/up.sh"; then
  printf 'FAIL: up.sh appears to install observer / Phase C\n'
  fail=$((fail + 1))
else
  printf 'PASS: up.sh does not install observer\n'
  pass=$((pass + 1))
fi

assert_ok "make -n ui dry-runs" make -C "${ROOT}" -n ui
assert_ok "make -n ui-down dry-runs" make -C "${ROOT}" -n ui-down

if [[ -f "${PHASE_C}" ]]; then
  printf 'PASS: phase C private script present\n'
  pass=$((pass + 1))
else
  printf 'FAIL: missing %s\n' "${PHASE_C}"
  fail=$((fail + 1))
fi
if [[ -e "${SCRIPT_DIR}/ui-skupper.sh" || -e "${SCRIPT_DIR}/ui-skupper-check.sh" ]]; then
  printf 'FAIL: old ui-skupper*.sh still present\n'
  fail=$((fail + 1))
else
  printf 'PASS: old ui-skupper*.sh removed\n'
  pass=$((pass + 1))
fi

assert_file_contains \
  "network-observer values exist" \
  "auth:" \
  "${VALUES}"
assert_file_contains \
  "values pin ClusterIP (no LB)" \
  "ClusterIP" \
  "${VALUES}"
assert_file_lacks \
  "values have no hardcoded password" \
  "BASIC_AUTH_PASSWORD=" \
  "${VALUES}"
assert_file_lacks \
  "values have no plaintext password key" \
  "password:" \
  "${VALUES}"

assert_file_contains \
  "VERSIONS.md pins network-observer 2.2.1" \
  "network-observer" \
  "${VERSIONS}"
assert_file_contains \
  "VERSIONS.md observer version 2.2.1" \
  "2.2.1" \
  "${VERSIONS}"
assert_file_contains \
  "VERSIONS.md prefers 8443" \
  "127.0.0.1:8443" \
  "${VERSIONS}"
assert_file_contains \
  "VERSIONS.md notes 2nd Prometheus / RAM" \
  "Prometheus" \
  "${VERSIONS}"

assert_file_contains \
  "skupper README documents make ui Phase C" \
  "make ui" \
  "${SKUPPER_README}"
assert_file_contains \
  "skupper README HTTPS URL contract" \
  "https://127.0.0.1:8443/" \
  "${SKUPPER_README}"
assert_file_contains \
  "skupper README mentions podman-edge preference" \
  "podman-edge" \
  "${SKUPPER_README}"
assert_file_contains \
  "skupper README mentions west fallback" \
  "kind-west" \
  "${SKUPPER_README}"

assert_file_contains \
  "phase C prints ACCESS_URL contract style" \
  "ACCESS_URL" \
  "${PHASE_C}"
assert_file_contains \
  "phase C prefers 8443" \
  "8443" \
  "${PHASE_C}"
assert_file_contains \
  "phase C uses curl -k for probe" \
  "curl -k" \
  "${PHASE_C}"
assert_file_contains \
  "ui-down uninstalls observer" \
  "helm uninstall" \
  "${UI_DOWN}"
assert_file_contains \
  "ui-down uninstalls Viz" \
  "viz uninstall" \
  "${UI_DOWN}"
assert_file_contains \
  "down.sh best-effort ui-down" \
  "ui-down" \
  "${DOWN_SH}"

assert_fails_with \
  "phase C refuses CLUSTER=kind-cluster" \
  "refusing|allowlist|kind-cluster" \
  env CLUSTER=kind-cluster "${PHASE_C}"

assert_fails_with \
  "ui PHASE=c refuses CLUSTER=kind-cluster" \
  "refusing|allowlist|kind-cluster" \
  env CLUSTER=kind-cluster PHASE=c "${UI_SH}"

assert_fails_with \
  "ui-down refuses CLUSTER=kind-cluster" \
  "refusing|allowlist|kind-cluster" \
  env CLUSTER=kind-cluster "${UI_DOWN}"

assert_file_contains \
  "ui-down documents CCM ports untouched" \
  "8080/8081/18080/18081/45671/55671" \
  "${UI_DOWN}"
if grep -Eiq 'cloud-provider-kind|kill.*8080|fuser.*8080' "${UI_DOWN}"; then
  printf 'FAIL: ui-down appears to touch CCM / reserved host ports\n'
  fail=$((fail + 1))
else
  printf 'PASS: ui-down does not touch CCM process or reserved host ports\n'
  pass=$((pass + 1))
fi

assert_file_contains \
  "ui-down uses shared PF stop helper" \
  "demo_ui_stop_pf" \
  "${UI_DOWN}"
assert_file_contains \
  "ui-common records PF pid+port" \
  "demo_ui_record_pf" \
  "${UI_COMMON}"
assert_file_contains \
  "ui-common port-fallback stop" \
  "trying port fallback" \
  "${UI_COMMON}"
assert_file_contains \
  "ui-common scopes kill to 127.0.0.1" \
  "127.0.0.1" \
  "${UI_COMMON}"
if grep -Eiq 'fuser[[:space:]]+-k' "${UI_COMMON}"; then
  printf 'FAIL: ui-common still uses broad fuser -k (all interfaces)\n'
  fail=$((fail + 1))
else
  printf 'PASS: ui-common does not use broad fuser -k\n'
  pass=$((pass + 1))
fi
assert_file_contains \
  "ui-common verifies port free before claiming cleared" \
  "listener still present" \
  "${UI_COMMON}"
# Live offline: demo_ui_record_pf writes pid+port and disowns the job
# shellcheck disable=SC1091
source "${UI_COMMON}"
record_name="ui-test-record-pf"
record_port=59999
sleep 120 &
record_pid=$!
if ! demo_ui_record_pf "${record_name}" "${record_pid}" "${record_port}"; then
  printf 'FAIL: demo_ui_record_pf returned non-zero\n'
  fail=$((fail + 1))
  kill "${record_pid}" 2>/dev/null || true
else
  got_pid="$(tr -d '[:space:]' <"$(demo_ui_pidfile "${record_name}")" || true)"
  got_port="$(tr -d '[:space:]' <"$(demo_ui_portfile "${record_name}")" || true)"
  if [[ "${got_pid}" != "${record_pid}" || "${got_port}" != "${record_port}" ]]; then
    printf 'FAIL: demo_ui_record_pf wrote pid=%q port=%q (want %s/%s)\n' \
      "${got_pid}" "${got_port}" "${record_pid}" "${record_port}"
    fail=$((fail + 1))
  elif ! kill -0 "${record_pid}" 2>/dev/null; then
    printf 'FAIL: demo_ui_record_pf left process dead\n'
    fail=$((fail + 1))
  elif jobs -p 2>/dev/null | grep -qx "${record_pid}"; then
    printf 'FAIL: demo_ui_record_pf did not disown pid %s\n' "${record_pid}"
    fail=$((fail + 1))
  else
    printf 'PASS: demo_ui_record_pf persists pid+port and disowns job\n'
    pass=$((pass + 1))
  fi
  kill "${record_pid}" 2>/dev/null || true
  wait "${record_pid}" 2>/dev/null || true
  rm -f "$(demo_ui_pidfile "${record_name}")" "$(demo_ui_portfile "${record_name}")"
fi
run_dir="$(demo_ui_ensure_run_dir)"
fake_pidfile="$(demo_ui_pidfile ui-skupper-observer)"
fake_portfile="$(demo_ui_portfile ui-skupper-observer)"
printf '1\n' >"${fake_pidfile}"
printf '8443\n' >"${fake_portfile}"
out="$(CLUSTER= "${UI_DOWN}" 2>&1 || true)"
if [[ -f "${fake_pidfile}" || -f "${fake_portfile}" ]]; then
  printf 'FAIL: ui-down did not remove observer pid/port files after run\n'
  fail=$((fail + 1))
else
  printf 'PASS: ui-down clears recorded observer pid/port files\n'
  pass=$((pass + 1))
fi
if grep -qE 'ui-skupper-observer|Skupper network-observer|pidfile stale|port fallback' <<<"${out}"; then
  printf 'PASS: ui-down reports observer PF teardown\n'
  pass=$((pass + 1))
else
  printf 'FAIL: ui-down did not mention observer PF teardown\n'
  printf '  output: %s\n' "${out}"
  fail=$((fail + 1))
fi
rm -f "${fake_pidfile}" "${fake_portfile}"

# Port-fallback path: no pidfile, portfile present (verify warning regression).
printf '8443\n' >"$(demo_ui_portfile ui-skupper-observer)"
out_fb="$(CLUSTER= "${UI_DOWN}" 2>&1 || true)"
if [[ -f "$(demo_ui_portfile ui-skupper-observer)" ]]; then
  printf 'FAIL: ui-down left observer portfile after fallback path\n'
  fail=$((fail + 1))
else
  printf 'PASS: ui-down clears observer portfile on fallback path\n'
  pass=$((pass + 1))
fi
if grep -q 'port fallback' <<<"${out_fb}"; then
  printf 'PASS: ui-down reports port fallback when pidfile missing\n'
  pass=$((pass + 1))
else
  printf 'FAIL: ui-down did not report port fallback\n'
  printf '  output: %s\n' "${out_fb}"
  fail=$((fail + 1))
fi
rm -f "$(demo_ui_portfile ui-skupper-observer)"

assert_output_contains \
  "Phase A ACCESS_URL contract" \
  "ACCESS_URL=http://emojivoto.demo.local:8080/" \
  env UI_SKIP_PROBE=1 "${PHASE_A}"

assert_file_contains \
  "Phase B script prefers 50750 URL shape" \
  "http://127.0.0.1:" \
  "${PHASE_B}"

assert_file_contains \
  "Phase C script builds https://127.0.0.1 URL" \
  "https://127.0.0.1:" \
  "${PHASE_C}"

if grep -qE 'https://127\.0\.0\.1:\$\{port\}/|PREFERRED_PORT=.*8443' "${PHASE_C}"; then
  printf 'PASS: Phase C prefers port 8443 for ACCESS_URL\n'
  pass=$((pass + 1))
else
  printf 'FAIL: Phase C missing preferred 8443 ACCESS_URL construction\n'
  fail=$((fail + 1))
fi

demo_skupper_recipe="$(awk '/^demo-skupper:/{flag=1; next} /^[^[:space:]#]/{flag=0} flag' "${MAKEFILE}")"
if grep -E 'ui-skupper|[^a-z]ui[^a-z]' <<<"${demo_skupper_recipe}" >/dev/null 2>&1; then
  printf 'FAIL: Makefile demo-skupper recipe references ui\n'
  printf '  recipe: %s\n' "${demo_skupper_recipe}"
  fail=$((fail + 1))
else
  printf 'PASS: Makefile demo-skupper has no ui dep\n'
  pass=$((pass + 1))
fi
assert_file_contains \
  "demo-skupper invokes check-skupper (VAN path)" \
  "check-skupper.sh" \
  "${MAKEFILE}"
if grep -Eiq 'ui-skupper|network-observer|_phase_c' "${CHECK_SKUPPER}"; then
  printf 'FAIL: check-skupper.sh requires observer / Phase C\n'
  fail=$((fail + 1))
else
  printf 'PASS: check-skupper.sh has no observer dependency\n'
  pass=$((pass + 1))
fi
assert_file_contains \
  "skupper README says observer not part of make up" \
  "Not** part of \`make up\`" \
  "${SKUPPER_README}"
assert_file_contains \
  "skupper README says VAN works without observer" \
  "VAN critical path works without it" \
  "${SKUPPER_README}"
assert_file_contains \
  "skupper README marks observer opt-in only" \
  "Opt-in only" \
  "${SKUPPER_README}"

printf '\nUI skupper/teardown suite: %s passed, %s failed\n' "${pass}" "${fail}"
if [[ "${fail}" -ne 0 ]]; then
  exit 1
fi
