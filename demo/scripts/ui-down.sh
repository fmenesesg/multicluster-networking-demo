#!/usr/bin/env bash
# Tear down Phase B/C UI surfaces only. Phase A is docs/hosts (reminder only).
# Stops recorded PF pids; uninstalls Linkerd Viz + network-observer when present.
# Never touches kind-cluster or CCM/Gateway ports (8080/8081/18080/18081/45671/55671).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/ui-common.sh"

RELEASE_NAME="${UI_C_RELEASE:-skupper-network-observer}"
OBSERVER_NS="${UI_C_NAMESPACE:-skupper}"

if [[ -n "${CLUSTER:-}" ]]; then
  demo_require_allowlisted "${CLUSTER}" "target" || exit 1
fi

printf 'ui-down: Phase A — no process teardown (hosts/docs only; keep /etc/hosts entries)\n'

# --- Phase B: stop Viz dashboard PF + uninstall Viz ---
demo_ui_stop_pf "Linkerd Viz dashboard" "ui-linkerd-dashboard" \
  "${UI_B_PORT:-50750}" "ui-linkerd-access-url" || true
rm -f "$(demo_ui_run_dir)/ui-linkerd-access-url"
rm -f "$(demo_ui_run_dir)/ui-linkerd-dashboard.log"

viz_uninstalled=0
if command -v linkerd >/dev/null 2>&1 && demo_kind_exists "kind-west"; then
  ctx="$(demo_kind_context kind-west)"
  if kubectl --context "${ctx}" get ns linkerd-viz >/dev/null 2>&1; then
    printf 'ui-down: uninstalling Linkerd Viz on kind-west\n'
    # Best-effort: viz uninstall may fail if control plane already gone.
    if linkerd --context "${ctx}" viz uninstall 2>/dev/null \
      | kubectl --context "${ctx}" delete -f - >/dev/null 2>&1; then
      viz_uninstalled=1
      printf 'ui-down: Linkerd Viz uninstall applied on %s\n' "${ctx}"
    else
      kubectl --context "${ctx}" delete ns linkerd-viz --ignore-not-found --wait=false >/dev/null 2>&1 || true
      printf 'ui-down: Linkerd Viz namespace delete requested on %s (best-effort)\n' "${ctx}"
      viz_uninstalled=1
    fi
  else
    printf 'ui-down: Phase B — linkerd-viz namespace not present\n'
  fi
else
  printf 'ui-down: Phase B — skip Viz uninstall (no linkerd CLI or kind-west)\n'
fi

# --- Phase C: stop observer PF + helm uninstall ---
demo_ui_stop_pf "Skupper network-observer" "ui-skupper-observer" \
  "${UI_C_PORT:-8443}" "ui-skupper-access-url" || true
rm -f "$(demo_ui_run_dir)/ui-skupper-access-url"
rm -f "$(demo_ui_run_dir)/ui-skupper-observer.log"
# Auth file is runtime secret material — remove on teardown.
rm -f "$(demo_ui_run_dir)/ui-skupper-basic-auth"

site_file="$(demo_ui_run_dir)/ui-skupper-site"
observer_site="kind-west"
if [[ -f "${site_file}" ]]; then
  observer_site="$(tr -d '[:space:]' <"${site_file}" || true)"
  [[ -z "${observer_site}" ]] && observer_site="kind-west"
fi
rm -f "${site_file}"

observer_uninstalled=0
if command -v helm >/dev/null 2>&1 && demo_kind_exists "${observer_site}"; then
  ctx="$(demo_kind_context "${observer_site}")"
  if helm status "${RELEASE_NAME}" --kube-context "${ctx}" --namespace "${OBSERVER_NS}" >/dev/null 2>&1; then
    printf 'ui-down: helm uninstall %s from SITE=%s ns=%s\n' \
      "${RELEASE_NAME}" "${observer_site}" "${OBSERVER_NS}"
    helm uninstall "${RELEASE_NAME}" --kube-context "${ctx}" --namespace "${OBSERVER_NS}" \
      --wait --timeout 2m >/dev/null 2>&1 \
      || helm uninstall "${RELEASE_NAME}" --kube-context "${ctx}" --namespace "${OBSERVER_NS}" >/dev/null 2>&1 \
      || true
    observer_uninstalled=1
    printf 'ui-down: network-observer release removed (best-effort)\n'
  else
    printf 'ui-down: Phase C — helm release %s not present on %s\n' \
      "${RELEASE_NAME}" "${observer_site}"
  fi
else
  printf 'ui-down: Phase C — skip observer uninstall (no helm or site %s)\n' "${observer_site}"
fi

printf 'ui-down: summary — Viz uninstall=%s observer uninstall=%s\n' \
  "${viz_uninstalled}" "${observer_uninstalled}"
printf 'ui-down: CCM/Gateway ports 8080/8081/18080/18081/45671/55671 left untouched\n'
printf 'ui-down: Phase A reminder — hosts/docs only; no process to stop\n'
