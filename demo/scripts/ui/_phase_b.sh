#!/usr/bin/env bash
# Phase B (private) — Linkerd Viz west-only: install + PF + validate.
# Invoked by demo/scripts/ui.sh. Not a public Make target.
# Never uses CCM LB. Does not change skip-inject / N-S namespaces.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../ui-common.sh"

LINKERD_CLIENT_PIN="${LINKERD_CLIENT_PIN:-edge-26.6.3}"
PREFERRED_PORT="${UI_B_PORT:-50750}"
VIZ_WAIT="${UI_B_WAIT:-5m}"
PID_NAME="ui-linkerd-dashboard"
URL_FILE_NAME="ui-linkerd-access-url"

warn_linkerd_client_pin() {
  local client
  client="$(linkerd version --client --short 2>/dev/null || true)"
  if [[ "${client}" != "${LINKERD_CLIENT_PIN}" ]]; then
    printf 'ui phase B: warn: linkerd client is %q; pin is %s (see demo/VERSIONS.md)\n' \
      "${client:-unknown}" "${LINKERD_CLIENT_PIN}" >&2
  fi
}

demo_ui_access_url_file() {
  printf '%s/%s\n' "$(demo_ui_run_dir)" "${URL_FILE_NAME}"
}

stop_existing_dashboard() {
  demo_ui_stop_pf "Linkerd Viz dashboard" "${PID_NAME}" "${PREFERRED_PORT}" "${URL_FILE_NAME}" || true
}

cluster="$(demo_ui_resolve_cluster_or_abort)" || exit 1
if [[ "${cluster}" != "kind-west" ]]; then
  printf 'error: Phase B Linkerd Viz is west-only (got %q); unset CLUSTER or use kind-west\n' \
    "${cluster}" >&2
  exit 1
fi

if ! command -v linkerd >/dev/null 2>&1; then
  printf 'error: linkerd CLI not found (need %s)\n' "${LINKERD_CLIENT_PIN}" >&2
  exit 1
fi
if ! command -v kubectl >/dev/null 2>&1; then
  printf 'error: kubectl not found\n' >&2
  exit 1
fi

warn_linkerd_client_pin

if ! demo_kind_exists "${cluster}"; then
  printf 'error: Kind cluster %s not present (run make up first)\n' "${cluster}" >&2
  exit 1
fi

ctx="$(demo_kind_context "${cluster}")"
demo_ui_ensure_run_dir >/dev/null

printf 'ui phase B: installing Linkerd Viz on %s (context %s, CLI pin %s)\n' \
  "${cluster}" "${ctx}" "${LINKERD_CLIENT_PIN}"
linkerd --context "${ctx}" viz install \
  | kubectl --context "${ctx}" apply -f -

printf 'ui phase B: waiting for Viz (%s)\n' "${VIZ_WAIT}"
if ! linkerd --context "${ctx}" viz check --wait "${VIZ_WAIT}"; then
  printf 'error: linkerd viz check failed on %s\n' "${ctx}" >&2
  exit 1
fi

port="$(demo_pick_free_port "${PREFERRED_PORT}")" || exit 1
access_url="http://127.0.0.1:${port}/"

stop_existing_dashboard

printf 'ui phase B: starting dashboard PF on 127.0.0.1:%s (no CCM LB)\n' "${port}"
linkerd --context "${ctx}" viz dashboard \
  --address 127.0.0.1 \
  --port "${port}" \
  --show url \
  --wait "${VIZ_WAIT}" \
  >"$(demo_ui_run_dir)/ui-linkerd-dashboard.log" 2>&1 &
dash_pid=$!
demo_ui_record_pf "${PID_NAME}" "${dash_pid}" "${port}" || exit 1
printf '%s\n' "${access_url}" >"$(demo_ui_access_url_file)"

ready=0
for _ in $(seq 1 60); do
  code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 3 \
    "${access_url}" 2>/dev/null || true)"
  case "${code}" in
    200|301|302|307|308) ready=1; break ;;
  esac
  if ! kill -0 "${dash_pid}" 2>/dev/null; then
    printf 'error: dashboard process exited early; see %s\n' \
      "$(demo_ui_run_dir)/ui-linkerd-dashboard.log" >&2
    exit 1
  fi
  sleep 1
done

if [[ "${ready}" -ne 1 ]]; then
  printf 'error: Viz dashboard not reachable at %s\n' "${access_url}" >&2
  exit 1
fi

demo_print_access_url "phase B — Linkerd Viz" "${access_url}" \
  "cluster: ${cluster} (west-only)" \
  "access: localhost port-forward only — never CCM LB" \
  "teardown PF: make ui-down"
