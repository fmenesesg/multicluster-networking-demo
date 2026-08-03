#!/usr/bin/env bash
# Invoked by demo/scripts/ui.sh. Not a public Make target.
# Phase C (private) — Skupper network-observer. Not part of make up.
# Prefer podman-edge; Helm chart requires Kubernetes → fallback west `skupper`.
# HTTPS PF prefer 8443; print ACCESS_URL + basic-auth once (demo/.run/, gitignored).
# Merged start+validate (observer HTTPS + basic-auth once).
# Never uses CCM LB. Does not change skip-inject / VAN wiring.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../ui-common.sh"

OBSERVER_CHART="${UI_C_CHART:-oci://quay.io/skupper/helm/network-observer}"
OBSERVER_VERSION="${UI_C_VERSION:-2.2.1}"
RELEASE_NAME="${UI_C_RELEASE:-skupper-network-observer}"
PREFERRED_PORT="${UI_C_PORT:-8443}"
NAMESPACE="${UI_C_NAMESPACE:-skupper}"
VALUES_FILE="$(demo_repo_root)/demo/skupper/network-observer/values.yaml"
PID_NAME="ui-skupper-observer"
URL_FILE_NAME="ui-skupper-access-url"
AUTH_FILE_NAME="ui-skupper-basic-auth"
SITE_FILE_NAME="ui-skupper-site"
WAIT_TIMEOUT="${UI_C_WAIT:-5m}"

demo_ui_access_url_file() {
  printf '%s/%s\n' "$(demo_ui_run_dir)" "${URL_FILE_NAME}"
}

demo_ui_auth_file() {
  printf '%s/%s\n' "$(demo_ui_run_dir)" "${AUTH_FILE_NAME}"
}

demo_ui_site_file() {
  printf '%s/%s\n' "$(demo_ui_run_dir)" "${SITE_FILE_NAME}"
}

stop_existing_pf() {
  demo_ui_stop_pf "Skupper network-observer" "${PID_NAME}" "${PREFERRED_PORT}" "${URL_FILE_NAME}" || true
}

# Prefer podman-edge when explicitly forced or as first choice; Helm needs Kind.
resolve_install_site() {
  local preferred="${UI_C_SITE:-podman-edge}"
  if [[ -n "${CLUSTER:-}" ]]; then
    demo_require_allowlisted "${CLUSTER}" "target" || return 1
    if [[ "${CLUSTER}" == "podman-edge" ]]; then
      preferred="podman-edge"
    elif [[ "${CLUSTER}" == "kind-west" ]]; then
      preferred="kind-west"
    elif [[ "${CLUSTER}" == "kind-east" ]]; then
      printf 'error: Phase C observer install is not east-primary (got kind-east); use podman-edge preference or kind-west fallback\n' >&2
      return 1
    fi
  fi

  case "${preferred}" in
    podman-edge)
      printf 'ui phase C: prefer SITE=podman-edge — Helm chart cannot install on Podman Skupper site\n' >&2
      printf 'ui phase C: falling back to SITE=kind-west namespace %s\n' "${NAMESPACE}" >&2
      printf 'kind-west\n'
      ;;
    kind-west)
      printf 'kind-west\n'
      ;;
    *)
      printf 'error: unsupported UI_C_SITE=%q (use podman-edge or kind-west)\n' "${preferred}" >&2
      return 1
      ;;
  esac
}

extract_basic_auth() {
  local ctx="$1"
  local ns="$2"
  local secret="${RELEASE_NAME}-auth"
  local raw user pass
  # Wait for setup Job to create PLAIN htpasswd.
  local i
  for i in $(seq 1 60); do
    if kubectl --context "${ctx}" -n "${ns}" get secret "${secret}" >/dev/null 2>&1; then
      raw="$(kubectl --context "${ctx}" -n "${ns}" get secret "${secret}" \
        -o jsonpath='{.data.htpasswd}' 2>/dev/null | base64 -d 2>/dev/null || true)"
      if [[ "${raw}" == *":{PLAIN}"* ]]; then
        user="$(sed -n 's/^\([^:]*\):{PLAIN}\(.*\)$/\1/p' <<<"${raw}" | head -1)"
        pass="$(sed -n 's/^\([^:]*\):{PLAIN}\(.*\)$/\2/p' <<<"${raw}" | head -1)"
        if [[ -n "${user}" && -n "${pass}" ]]; then
          printf '%s\n%s\n' "${user}" "${pass}"
          return 0
        fi
      fi
    fi
    sleep 2
  done
  printf 'error: could not read basic-auth from secret %s/%s\n' "${ns}" "${secret}" >&2
  return 1
}

if ! command -v helm >/dev/null 2>&1; then
  printf 'error: helm not found (need v3.17.x)\n' >&2
  exit 1
fi
if ! command -v kubectl >/dev/null 2>&1; then
  printf 'error: kubectl not found\n' >&2
  exit 1
fi
if [[ ! -f "${VALUES_FILE}" ]]; then
  printf 'error: missing Helm values %s\n' "${VALUES_FILE}" >&2
  exit 1
fi

site="$(resolve_install_site)" || exit 1
if ! demo_kind_exists "${site}"; then
  printf 'error: Kind cluster %s not present (run make up first)\n' "${site}" >&2
  exit 1
fi

ctx="$(demo_kind_context "${site}")"
demo_ui_ensure_run_dir >/dev/null
printf '%s\n' "${site}" >"$(demo_ui_site_file)"

printf 'ui phase C: installing network-observer %s on SITE=%s ns=%s (context %s)\n' \
  "${OBSERVER_VERSION}" "${site}" "${NAMESPACE}" "${ctx}"
printf 'ui phase C: chart %s — never CCM LB; bundled Prometheus OK (2nd Prom / RAM note in VERSIONS)\n' \
  "${OBSERVER_CHART}"

helm upgrade --install "${RELEASE_NAME}" "${OBSERVER_CHART}" \
  --version "${OBSERVER_VERSION}" \
  --kube-context "${ctx}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  -f "${VALUES_FILE}" \
  --wait \
  --timeout "${WAIT_TIMEOUT}"

printf 'ui phase C: waiting for deployment/%s ready\n' "${RELEASE_NAME}"
kubectl --context "${ctx}" -n "${NAMESPACE}" \
  rollout status "deployment/${RELEASE_NAME}" --timeout="${WAIT_TIMEOUT}"

auth_lines="$(extract_basic_auth "${ctx}" "${NAMESPACE}")" || exit 1
auth_user="$(sed -n '1p' <<<"${auth_lines}")"
auth_pass="$(sed -n '2p' <<<"${auth_lines}")"
auth_file="$(demo_ui_auth_file)"
umask 077
printf 'BASIC_AUTH_USER=%s\nBASIC_AUTH_PASSWORD=%s\n' "${auth_user}" "${auth_pass}" >"${auth_file}"
chmod 600 "${auth_file}"

port="$(demo_pick_free_port "${PREFERRED_PORT}")" || exit 1
access_url="https://127.0.0.1:${port}/"

stop_existing_pf

printf 'ui phase C: starting HTTPS PF 127.0.0.1:%s → svc/%s:443 (no CCM LB)\n' \
  "${port}" "${RELEASE_NAME}"
kubectl --context "${ctx}" -n "${NAMESPACE}" port-forward \
  "service/${RELEASE_NAME}" "${port}:443" \
  --address 127.0.0.1 \
  >"$(demo_ui_run_dir)/ui-skupper-observer.log" 2>&1 &
pf_pid=$!
demo_ui_record_pf "${PID_NAME}" "${pf_pid}" "${port}" || exit 1
printf '%s\n' "${access_url}" >"$(demo_ui_access_url_file)"

ready=0
for _ in $(seq 1 60); do
  code="$(curl -k -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 5 \
    -u "${auth_user}:${auth_pass}" "${access_url}" 2>/dev/null || true)"
  case "${code}" in
    200|301|302|307|308) ready=1; break ;;
  esac
  if ! kill -0 "${pf_pid}" 2>/dev/null; then
    printf 'error: observer PF exited early; see %s\n' \
      "$(demo_ui_run_dir)/ui-skupper-observer.log" >&2
    exit 1
  fi
  sleep 1
done

if [[ "${ready}" -ne 1 ]]; then
  printf 'error: network-observer not reachable at %s\n' "${access_url}" >&2
  exit 1
fi

demo_print_access_url "phase C — Skupper network-observer" "${access_url}" \
  "SITE=${site}" \
  "BASIC_AUTH_USER=${auth_user}" \
  "BASIC_AUTH_PASSWORD=${auth_pass}" \
  "BASIC_AUTH_FILE=${auth_file}" \
  "access: localhost HTTPS port-forward only — never CCM LB" \
  "teardown: make ui-down"
