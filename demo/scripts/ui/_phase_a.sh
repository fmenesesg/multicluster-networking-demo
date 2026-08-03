#!/usr/bin/env bash
# Phase A (private) — hosts hint + ACCESS_URL + hostname probe (200|429).
# Invoked by demo/scripts/ui.sh. Not a public Make target.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../ui-common.sh"

WEST_URL="http://emojivoto.demo.local:8080/"
EAST_URL="http://emojivoto.demo.local:8081/"
SHOW_EAST="${UI_A_SHOW_EAST:-1}"
CHECK_EAST="${UI_A_CHECK_EAST:-0}"
CURL_TIMEOUT="${UI_A_CURL_TIMEOUT:-5}"
# Offline contract tests may set UI_SKIP_PROBE=1 (private; not Make help).
SKIP_PROBE="${UI_SKIP_PROBE:-0}"

if [[ -n "${CLUSTER:-}" ]]; then
  demo_require_allowlisted "${CLUSTER}" "target" || exit 1
fi

probe_hostname() {
  local url="$1"
  local code
  code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout "${CURL_TIMEOUT}" --max-time "${CURL_TIMEOUT}" \
    "${url}" 2>/dev/null || true)"
  case "${code}" in
    200|429) return 0 ;;
    *) return 1 ;;
  esac
}

demo_print_access_url "phase A — app" "${WEST_URL}" \
  "hosts: add '127.0.0.1 emojivoto.demo.local' to /etc/hosts (once)" \
  "browser: open ${WEST_URL} (hostname required — not bare http://127.0.0.1:8080/ without Host)" \
  "optional east Gateway: ${EAST_URL}" \
  "probe: HTTP GET ${WEST_URL} expect 200 or 429 after make up + hosts"

if [[ "${SHOW_EAST}" == "1" ]]; then
  printf 'ACCESS_URL_EAST=%s\n' "${EAST_URL}"
fi

if [[ "${UI_A_OPEN:-0}" == "1" ]] && command -v xdg-open >/dev/null 2>&1; then
  xdg-open "${WEST_URL}" >/dev/null 2>&1 || true
fi

if [[ "${SKIP_PROBE}" == "1" ]]; then
  printf 'ui phase A: UI_SKIP_PROBE=1 — skipping live hostname probe\n'
  exit 0
fi

if ! probe_hostname "${WEST_URL}"; then
  printf 'error: west app not reachable at %s (need make up + /etc/hosts emojivoto.demo.local → 127.0.0.1)\n' \
    "${WEST_URL}" >&2
  exit 1
fi
printf 'ok: west %s reachable (200/429)\n' "${WEST_URL}"

if [[ "${CHECK_EAST}" == "1" ]]; then
  if ! probe_hostname "${EAST_URL}"; then
    printf 'error: east app not reachable at %s\n' "${EAST_URL}" >&2
    exit 1
  fi
  printf 'ok: east %s reachable (200/429)\n' "${EAST_URL}"
fi
