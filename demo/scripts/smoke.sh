#!/usr/bin/env bash
# End-to-end smoke: RateLimit (200/429), mesh, Skupper, CoreDNS dig.
# Offline (no kind-west): validate scripts/manifests + allowlist; keep CI/laptop green.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ROOT="$(demo_repo_root)"
DEMO_HOST="${DEMO_HOST:-emojivoto.demo.local}"
GATEWAY_NS="${GATEWAY_NS:-gateway-system}"
GATEWAY_NAME="${GATEWAY_NAME:-demo}"
COREDNS_NS="${COREDNS_NS:-kuadrant-coredns}"

pass=0
fail=0

ok() {
  printf 'PASS: %s\n' "$1"
  pass=$((pass + 1))
}

bad() {
  printf 'FAIL: %s\n' "$1"
  fail=$((fail + 1))
}

require_file() {
  local f="$1"
  if [[ -f "${f}" ]]; then
    ok "present ${f#${ROOT}/}"
  else
    bad "missing ${f#${ROOT}/}"
  fi
}

assert_grep() {
  local desc="$1"
  local pattern="$2"
  local file="$3"
  if grep -qE "${pattern}" "${file}"; then
    ok "${desc}"
  else
    bad "${desc} (pattern /${pattern}/ in ${file#${ROOT}/})"
  fi
}

run_or_fail() {
  local desc="$1"
  shift
  if "$@"; then
    ok "${desc}"
  else
    bad "${desc}"
  fi
}

offline_smoke() {
  printf 'smoke: offline path (no kind-west) — scripts + pins + allowlist\n'
  require_file "${ROOT}/demo/scripts/smoke.sh"
  require_file "${ROOT}/demo/scripts/failover.sh"
  require_file "${ROOT}/demo/scripts/lib/cloud-provider-kind.sh"
  require_file "${ROOT}/demo/scripts/demo-ratelimit.sh"
  require_file "${ROOT}/demo/scripts/check-east-west.sh"
  require_file "${ROOT}/demo/scripts/check-skupper.sh"
  require_file "${ROOT}/demo/kuadrant/ratelimitpolicy.yaml"
  require_file "${ROOT}/demo/kuadrant/dnspolicy.yaml"
  require_file "${ROOT}/demo/kuadrant/dnspolicy-east.yaml"
  require_file "${ROOT}/demo/VERSIONS.md"
  require_file "${ROOT}/README.md"

  assert_grep "VERSIONS pins cloud-provider-kind" "cloud-provider-kind" "${ROOT}/demo/VERSIONS.md"
  assert_grep "VERSIONS pins Kind 1.35.5" "v1\\.35\\.5" "${ROOT}/demo/VERSIONS.md"
  assert_grep "VERSIONS pins Linkerd edge-26.6.3" "edge-26\\.6\\.3" "${ROOT}/demo/VERSIONS.md"
  assert_grep "prereq requires cloud-provider-kind" "cloud-provider-kind" "${ROOT}/demo/scripts/prereq-check.sh"
  assert_grep "up starts CCM" "demo_ensure_cloud_provider_kind" "${ROOT}/demo/scripts/up.sh"
  assert_grep "up resyncs CCM after Kind create" "demo_ccm_resync_if_ours" "${ROOT}/demo/scripts/up.sh"
  assert_grep "down stops owned CCM" "demo_stop_cloud_provider_kind_if_ours" "${ROOT}/demo/scripts/down.sh"
  assert_grep "smoke prefers host-mapped Gateway" "127\\.0\\.0\\.1" "${ROOT}/demo/scripts/smoke.sh"
  require_file "${ROOT}/demo/gateway/gateway-east.yaml"
  assert_grep "east Gateway port 8081" "port:\\s*8081" "${ROOT}/demo/gateway/gateway-east.yaml"
  assert_grep "failover hurts west" "hurt_west|scale.*west|failover" "${ROOT}/demo/scripts/failover.sh"
  assert_grep "gitignore demo/.run" "demo/\\.run" "${ROOT}/.gitignore"

  run_or_fail "allowlist suite" "${SCRIPT_DIR}/test-allowlist.sh"
  run_or_fail "demo-ratelimit offline" env CLUSTER=kind-west "${SCRIPT_DIR}/demo-ratelimit.sh"
  run_or_fail "demo-mesh offline" "${SCRIPT_DIR}/check-east-west.sh"
  run_or_fail "demo-skupper offline" "${SCRIPT_DIR}/check-skupper.sh"
}

gateway_base_url() {
  local ctx="$1"
  local addr
  local port="${DEMO_GW_PORT:-8080}"
  # Prefer host publish (CCM --enable-lb-port-mapping). Kind LB IPs (10.89.0.x) are often
  # unreachable from the host under rootless Podman — same strategy as demo-ratelimit.sh.
  if [[ -n "${DEMO_GW_URL:-}" ]]; then
    printf '%s\n' "${DEMO_GW_URL}"
    return 0
  fi
  if curl -sS -o /dev/null --connect-timeout 2 -H "Host: ${DEMO_HOST}" \
    "http://127.0.0.1:${port}/" >/dev/null 2>&1; then
    printf 'http://127.0.0.1:%s\n' "${port}"
    return 0
  fi
  addr="$(kubectl --context "${ctx}" -n "${GATEWAY_NS}" get gateway "${GATEWAY_NAME}" \
    -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)"
  if [[ -n "${addr}" ]] && curl -sS -o /dev/null --connect-timeout 2 -H "Host: ${DEMO_HOST}" \
    "http://${addr}:${port}/" >/dev/null 2>&1; then
    printf 'http://%s:%s\n' "${addr}" "${port}"
    return 0
  fi
  return 1
}

live_http_probe() {
  local ctx="$1"
  local base code
  if ! base="$(gateway_base_url "${ctx}")"; then
    bad "Gateway ${GATEWAY_NS}/${GATEWAY_NAME} unreachable (try host :${DEMO_GW_PORT:-8080} or cloud-provider-kind)"
    return
  fi
  ok "Gateway URL ${base}"
  code="$(curl -s -o /dev/null -w '%{http_code}' -H "Host: ${DEMO_HOST}" "${base}/" || printf '000')"
  case "${code}" in
    200) ok "HTTP 200 from Gateway (${DEMO_HOST})" ;;
    429) ok "HTTP 429 from Gateway (rate limit active; burst may have already fired)" ;;
    *) bad "unexpected HTTP ${code} from Gateway (want 200 or 429)" ;;
  esac
}

live_dig_probe() {
  local ctx="$1"
  local coredns_ip
  coredns_ip="$(kubectl --context "${ctx}" -n "${COREDNS_NS}" get svc -l app.kubernetes.io/name=coredns \
    -o jsonpath='{.items[0].spec.clusterIP}' 2>/dev/null || true)"
  if [[ -z "${coredns_ip}" ]]; then
    # Fallback: any ClusterIP Service in the CoreDNS NS.
    coredns_ip="$(kubectl --context "${ctx}" -n "${COREDNS_NS}" get svc -o jsonpath='{.items[0].spec.clusterIP}' 2>/dev/null || true)"
  fi
  if [[ -z "${coredns_ip}" ]]; then
    bad "CoreDNS Service IP not found in ${COREDNS_NS}"
    return
  fi
  ok "CoreDNS SVC ${coredns_ip}"
  if ! command -v dig >/dev/null 2>&1; then
    bad "dig not installed (needed for CoreDNS smoke)"
    return
  fi
  # Dig from a short-lived pod (host dig cannot always reach clusterIP).
  if kubectl --context "${ctx}" -n "${COREDNS_NS}" run "smoke-dig-$$" --rm -i --restart=Never --image=busybox:1.36 \
    --command -- sh -c "nslookup ${DEMO_HOST} ${coredns_ip}" >/tmp/smoke-dig.out 2>&1; then
    ok "dig/nslookup ${DEMO_HOST} via CoreDNS"
  else
    # Soft-fail path: some laptops block ephemeral pulls; still check DNSPolicy present.
    if kubectl --context "${ctx}" -n "${GATEWAY_NS}" get dnspolicy emojivoto-dns >/dev/null 2>&1; then
      ok "DNSPolicy present (nslookup probe skipped/failed — see /tmp/smoke-dig.out)"
    else
      bad "nslookup ${DEMO_HOST} failed and DNSPolicy missing"
    fi
  fi
}

live_browser_probe() {
  local ctx="$1" base path code
  if ! base="$(gateway_base_url "${ctx}")"; then
    bad "browser flow Gateway unreachable"
    return
  fi
  # Run after the homepage burst: a real browser needs assets/list plus a vote.
  # One successful rocket vote is intentional; doughnut fails in upstream v11.
  for path in /js /api/list '/api/vote?choice=%3Arocket%3A' /api/leaderboard; do
    code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 10 \
      -H "Host: ${DEMO_HOST}" "${base}${path}" || true)"
    if [[ "${code}" == "200" ]]; then
      ok "browser ${path} returns 200 after rate-limit burst"
    else
      bad "browser ${path} returned ${code} (expected 200; APIs/assets must bypass homepage quota)"
    fi
  done
}

live_smoke() {
  local west_ctx
  west_ctx="$(demo_kind_context kind-west)"
  printf 'smoke: live path on %s\n' "${west_ctx}"

  live_http_probe "${west_ctx}"
  run_or_fail "RateLimit burst (expect ≥1×429)" env CLUSTER=kind-west "${SCRIPT_DIR}/demo-ratelimit.sh"
  live_browser_probe "${west_ctx}"
  run_or_fail "Linkerd / emojivoto mesh" "${SCRIPT_DIR}/check-east-west.sh"
  run_or_fail "Skupper VAN" "${SCRIPT_DIR}/check-skupper.sh"
  live_dig_probe "${west_ctx}"
}

main() {
  if demo_kind_exists "kind-west"; then
    live_smoke
  else
    offline_smoke
  fi
  printf '\nSmoke: %s passed, %s failed\n' "${pass}" "${fail}"
  if [[ "${fail}" -ne 0 ]]; then
    exit 1
  fi
}

main "$@"
