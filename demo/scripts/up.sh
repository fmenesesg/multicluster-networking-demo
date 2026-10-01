#!/usr/bin/env bash
# Idempotent demo bring-up for allowlisted sites only (kind-west, kind-east, podman-edge).
# Install order: prereqs → Kind → EG → Kuadrant/CoreDNS → Linkerd → apps → policies → Skupper.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/cloud-provider-kind.sh
source "${SCRIPT_DIR}/lib/cloud-provider-kind.sh"

ROOT="$(demo_repo_root)"
KIND_DIR="${ROOT}/demo/kind"
GATEWAY_DIR="${ROOT}/demo/gateway"
KUADRANT_DIR="${ROOT}/demo/kuadrant"
LINKERD_DIR="${ROOT}/demo/linkerd"
EMOJI_DIR="${ROOT}/demo/apps/emojivoto"
LEGACY_DIR="${ROOT}/demo/apps/legacy-emoji"
SKUPPER_DIR="${ROOT}/demo/skupper"
export KIND_EXPERIMENTAL_PROVIDER="${KIND_EXPERIMENTAL_PROVIDER:-podman}"

# Pins — keep in sync with demo/VERSIONS.md.
EG_CHART_VERSION="${EG_CHART_VERSION:-v1.7.0}"
KUADRANT_CHART_VERSION="${KUADRANT_CHART_VERSION:-1.5.2}"
DNS_OPERATOR_REF="${DNS_OPERATOR_REF:-v0.17.1}"
LINKERD_CLIENT_PIN="${LINKERD_CLIENT_PIN:-edge-26.6.3}"
SKUPPER_VERSION="${SKUPPER_VERSION:-2.2.1}"
SKUPPER_CONTROLLER_URL="${SKUPPER_CONTROLLER_URL:-https://github.com/skupperproject/skupper/releases/download/${SKUPPER_VERSION}/skupper-cluster-scope.yaml}"
SKUPPER_TOKEN_FILE="${SKUPPER_TOKEN_FILE:-${ROOT}/demo/skupper/.tokens/west.token}"

ensure_kind_cluster() {
  local name="$1"
  local config="$2"
  local created=0
  demo_require_allowlisted "${name}" "create" || return 1
  if demo_kind_exists "${name}"; then
    printf 'up: Kind cluster %s already exists — skipping create\n' "${name}"
    if ! kubectl --context "$(demo_kind_context "${name}")" --request-timeout=10s \
        get --raw=/readyz >/dev/null 2>&1; then
      printf 'error: existing cluster %s has no ready Kubernetes API; existence does not mean its node containers are running\n' "${name}" >&2
      printf 'hint: inspect its nodes with: kind get nodes --name %s; check their state with podman ps -a\n' "${name}" >&2
      printf 'hint: start stopped demo nodes, wait for the API, then rerun make up (see README recovery steps)\n' >&2
      return 1
    fi
  else
    printf 'up: creating Kind cluster %s (provider=%s)\n' "${name}" "${KIND_EXPERIMENTAL_PROVIDER}"
    # Node image pinned in demo/kind/*.yaml (kindest/node:v1.35.5@sha256:… for Linkerd).
    kind create cluster --name "${name}" --config "${config}"
    created=1
  fi
  # Single-node Kind labels the control-plane exclude-from-external-load-balancers by default;
  # cloud-provider-kind cannot assign EXTERNAL-IP until that label is cleared.
  demo_kind_enable_loadbalancer "${name}"
  # CCM lists Kind clusters on a timer; after a *new* create, restart demo-owned CCM so the
  # site is adopted promptly (kind-east was previously left without LBs).
  if [[ "${created}" -eq 1 ]]; then
    demo_ccm_resync_if_ours "create ${name}" || true
  fi
  if ! demo_wait_ccm_lb_ready "${name}" 60; then
    :
  fi
  # Existing clusters may predate the current CCM process — resync once if still no LB.
  if ! kubectl --context "$(demo_kind_context "${name}")" get svc -A \
      -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.status.loadBalancer.ingress[0].ip}{"\n"}{end}' \
      2>/dev/null | awk 'NF{found=1} END{exit !found}'; then
    printf 'up: [%s] no LB EXTERNAL-IP yet — resyncing CCM and retrying\n' "$(demo_kind_context "${name}")"
    demo_ccm_resync_if_ours "adopt ${name}" || true
    demo_wait_ccm_lb_ready "${name}" 90 || true
  fi
}

ensure_podman_edge() {
  local name="podman-edge"
  demo_require_allowlisted "${name}" "create" || return 1
  if podman network exists "${name}" >/dev/null 2>&1; then
    printf 'up: Podman network %s already exists — skipping create\n' "${name}"
    return 0
  fi
  printf 'up: creating Podman network %s (edge site placeholder)\n' "${name}"
  podman network create "${name}" >/dev/null
}

install_envoy_gateway() {
  local ctx="$1"
  printf 'up: [%s] Envoy Gateway %s\n' "${ctx}" "${EG_CHART_VERSION}"
  helm upgrade --install eg oci://docker.io/envoyproxy/gateway-helm \
    --version "${EG_CHART_VERSION}" \
    --namespace envoy-gateway-system \
    --create-namespace \
    --kube-context "${ctx}" \
    -f "${GATEWAY_DIR}/values-eg.yaml" \
    --wait --timeout 5m
  kubectl --context "${ctx}" -n envoy-gateway-system \
    wait --timeout=5m --for=condition=Available deployment/envoy-gateway
  # GatewayClass is NOT created by the Helm chart — apply explicitly.
  kubectl --context "${ctx}" apply -f "${GATEWAY_DIR}/gatewayclass.yaml"
  # Skip mesh inject on EG control plane (Helm-owned NS).
  kubectl --context "${ctx}" label ns envoy-gateway-system \
    linkerd.io/inject=disabled --overwrite
  kubectl --context "${ctx}" annotate ns envoy-gateway-system \
    linkerd.io/inject=disabled --overwrite
}

install_kuadrant() {
  local ctx="$1"
  printf 'up: [%s] Kuadrant operator %s\n' "${ctx}" "${KUADRANT_CHART_VERSION}"
  helm repo add kuadrant https://kuadrant.io/helm-charts/ --force-update >/dev/null 2>&1 || true
  helm upgrade --install kuadrant-operator kuadrant/kuadrant-operator \
    --version "${KUADRANT_CHART_VERSION}" \
    --namespace kuadrant-system \
    --create-namespace \
    --kube-context "${ctx}" \
    --wait --timeout 5m
  kubectl --context "${ctx}" apply -f "${KUADRANT_DIR}/kuadrant.yaml"
  kubectl --context "${ctx}" label ns kuadrant-system \
    linkerd.io/inject=disabled --overwrite
  kubectl --context "${ctx}" annotate ns kuadrant-system \
    linkerd.io/inject=disabled --overwrite
  # Limitador/Authorino roll out asynchronously; do not hard-fail if slow on laptop.
  kubectl --context "${ctx}" -n kuadrant-system wait --timeout=3m \
    --for=condition=Ready kuadrant/kuadrant 2>/dev/null || \
    printf 'up: [%s] Kuadrant Ready wait timed out — continue; check later\n' "${ctx}"
}

install_coredns() {
  local ctx="$1"
  local cluster_name="${ctx#kind-}"
  printf 'up: [%s] Kuadrant CoreDNS (%s) zone demo.local\n' "${ctx}" "${DNS_OPERATOR_REF}"
  if ! command -v kustomize >/dev/null 2>&1; then
    printf 'up: [%s] error: kustomize required for CoreDNS (install to ~/.local/bin; see demo/VERSIONS.md)\n' "${ctx}" >&2
    return 1
  fi
  # Quay tag v0.17.1 may 404; pull :latest, retag, load into Kind (rootless often cannot pull from node).
  local coredns_img="quay.io/kuadrant/coredns-kuadrant:${DNS_OPERATOR_REF}"
  if ! podman image exists "${coredns_img}" 2>/dev/null; then
    podman pull quay.io/kuadrant/coredns-kuadrant:latest
    podman tag quay.io/kuadrant/coredns-kuadrant:latest "${coredns_img}"
  fi
  local tar
  tar="$(mktemp -t coredns-kuadrant.XXXXXX.tar)"
  podman save -o "${tar}" "${coredns_img}"
  kind load image-archive --name "${cluster_name}" "${tar}" >/dev/null
  rm -f "${tar}"

  # ServiceMonitor CRD is optional; strip those docs (line-grep breaks multi-doc YAML).
  local coredns_manifest
  coredns_manifest="$(mktemp -t coredns-kuadrant.XXXXXX.yaml)"
  kustomize build --enable-helm \
    "https://github.com/Kuadrant/dns-operator/config/coredns?ref=${DNS_OPERATOR_REF}" \
    | awk '
        BEGIN { RS="---\n"; ORS="" }
        {
          body = $0
          if (body ~ /(^|\n)kind:[[:space:]]*ServiceMonitor([[:space:]]|$)/) next
          gsub(/^\n+|\n+$/, "", body)
          if (body == "") next
          print "---\n" body "\n"
        }
      ' > "${coredns_manifest}"
  kubectl --context "${ctx}" apply --filename="${coredns_manifest}" --validate=false
  rm -f "${coredns_manifest}"

  kubectl --context "${ctx}" apply -f "${LINKERD_DIR}/skip-namespaces.yaml"
  kubectl --context "${ctx}" label ns kuadrant-coredns linkerd.io/inject=disabled --overwrite 2>/dev/null || true
  kubectl --context "${ctx}" -n kuadrant-coredns create configmap kuadrant-coredns \
    --from-file=Corefile="${KUADRANT_DIR}/coredns/Corefile" \
    -o yaml --dry-run=client | kubectl --context "${ctx}" apply -f -
  # Rootless Podman cannot bind host :53 — force ClusterIP for CoreDNS Service.
  kubectl --context "${ctx}" -n kuadrant-coredns get svc -o name 2>/dev/null | while read -r svc; do
    kubectl --context "${ctx}" -n kuadrant-coredns patch "${svc}" \
      --type=merge -p '{"spec":{"type":"ClusterIP"}}' >/dev/null 2>&1 || true
  done
  kubectl --context "${ctx}" -n kuadrant-coredns set image deploy/kuadrant-coredns \
    "coredns=${coredns_img}" >/dev/null 2>&1 || true
  kubectl --context "${ctx}" -n kuadrant-coredns patch deploy kuadrant-coredns --type=json \
    -p='[{"op":"replace","path":"/spec/template/spec/containers/0/imagePullPolicy","value":"IfNotPresent"}]' \
    >/dev/null 2>&1 || true
  kubectl --context "${ctx}" -n kuadrant-coredns rollout restart deployment \
    -l app.kubernetes.io/name=coredns 2>/dev/null || true
  kubectl --context "${ctx}" -n kuadrant-coredns wait --timeout=3m \
    --for=condition=Available deployment -l app.kubernetes.io/name=coredns 2>/dev/null || \
    printf 'up: [%s] CoreDNS Available wait timed out — continue\n' "${ctx}"
}

warn_linkerd_client_pin() {
  local client
  client="$(linkerd version --client --short 2>/dev/null || true)"
  if [[ "${client}" != "${LINKERD_CLIENT_PIN}" ]]; then
    printf 'up: warn: linkerd client is %q; pin is %s (see demo/VERSIONS.md)\n' \
      "${client:-unknown}" "${LINKERD_CLIENT_PIN}"
  fi
}

install_linkerd() {
  local ctx="$1"
  warn_linkerd_client_pin
  printf 'up: [%s] Linkerd control plane (CLI %s, values=%s)\n' \
    "${ctx}" "${LINKERD_CLIENT_PIN}" "${LINKERD_DIR}/values.yaml"
  if kubectl --context "${ctx}" -n linkerd get configmap linkerd-config >/dev/null 2>&1; then
    # Idempotent re-up: `linkerd install` refuses when present and prints to stdout,
    # which makes `kubectl apply` fail with "no objects passed to apply".
    printf 'up: [%s] Linkerd already installed — upgrade (idempotent re-up)\n' "${ctx}"
    linkerd --context "${ctx}" upgrade --crds 2>/dev/null \
      | kubectl --context "${ctx}" apply -f - >/dev/null 2>&1 || true
    linkerd --context "${ctx}" upgrade -f "${LINKERD_DIR}/values.yaml" 2>/dev/null \
      | kubectl --context "${ctx}" apply -f - >/dev/null 2>&1 || true
  else
    linkerd --context "${ctx}" install --crds \
      | kubectl --context "${ctx}" apply -f -
    linkerd --context "${ctx}" install -f "${LINKERD_DIR}/values.yaml" \
      | kubectl --context "${ctx}" apply -f -
  fi
  # Re-assert skip inject on N-S namespaces after mesh CRDs land.
  kubectl --context "${ctx}" apply -f "${LINKERD_DIR}/skip-namespaces.yaml"
  kubectl --context "${ctx}" label ns envoy-gateway-system kuadrant-system \
    linkerd.io/inject=disabled --overwrite 2>/dev/null || true
  kubectl --context "${ctx}" annotate ns envoy-gateway-system kuadrant-system \
    linkerd.io/inject=disabled --overwrite 2>/dev/null || true
  if ! linkerd --context "${ctx}" check --wait 5m; then
    printf 'up: [%s] linkerd check did not fully pass — continue; re-run make demo-mesh\n' "${ctx}"
  fi
}

deploy_emojivoto() {
  local cluster="$1"
  local ctx
  ctx="$(demo_kind_context "${cluster}")"
  printf 'up: [%s] emojivoto namespace (mesh inject) + apps\n' "${ctx}"
  kubectl --context "${ctx}" apply -f "${EMOJI_DIR}/namespace.yaml"
  case "${cluster}" in
    kind-west)
      kubectl --context "${ctx}" apply -f "${EMOJI_DIR}/west.yaml"
      ;;
    kind-east)
      kubectl --context "${ctx}" apply -f "${EMOJI_DIR}/east.yaml"
      ;;
    *)
      printf 'up: [%s] no emojivoto variant for %s\n' "${ctx}" "${cluster}"
      return 0
      ;;
  esac
  kubectl --context "${ctx}" -n emojivoto wait --timeout=3m \
    --for=condition=Available deployment --all 2>/dev/null || \
    printf 'up: [%s] emojivoto Available wait timed out — continue\n' "${ctx}"
}

apply_gateway_policies() {
  local cluster="$1"
  local ctx
  ctx="$(demo_kind_context "${cluster}")"
  printf 'up: [%s] GatewayClass + Gateway + RateLimit + DNSPolicy\n' "${ctx}"
  # Ensure meshed app NS exists before HTTPRoute (cross-namespace parent still ok).
  kubectl --context "${ctx}" apply -f "${EMOJI_DIR}/namespace.yaml"
  kubectl --context "${ctx}" apply -f "${GATEWAY_DIR}/gatewayclass.yaml"
  if [[ "${cluster}" == "kind-east" ]]; then
    # East uses :8081 so CCM host port-mapping does not collide with west :8080.
    kubectl --context "${ctx}" apply -f "${GATEWAY_DIR}/gateway-east.yaml"
  else
    kubectl --context "${ctx}" apply -f "${GATEWAY_DIR}/gateway.yaml"
  fi
  kubectl --context "${ctx}" apply -f "${KUADRANT_DIR}/coredns-provider.yaml"
  kubectl --context "${ctx}" apply -f "${KUADRANT_DIR}/ratelimitpolicy.yaml"
  if [[ "${cluster}" == "kind-east" ]]; then
    kubectl --context "${ctx}" apply -f "${KUADRANT_DIR}/dnspolicy-east.yaml"
  else
    kubectl --context "${ctx}" apply -f "${KUADRANT_DIR}/dnspolicy.yaml"
  fi
  # Wait briefly for EG to accept/program the Gateway (needs GatewayClass + CCM for LB).
  local waited=0
  while (( waited < 90 )); do
    local programmed
    programmed="$(kubectl --context "${ctx}" -n gateway-system get gateway demo \
      -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || true)"
    if [[ "${programmed}" == "True" ]]; then
      printf 'up: [%s] Gateway demo Programmed=True\n' "${ctx}"
      return 0
    fi
    sleep 5
    waited=$((waited + 5))
  done
  printf 'up: [%s] Gateway demo not Programmed yet — check GatewayClass eg + cloud-provider-kind\n' "${ctx}"
}

install_north_south() {
  local cluster="$1"
  local ctx
  ctx="$(demo_kind_context "${cluster}")"
  if ! demo_kind_exists "${cluster}"; then
    printf 'up: skip N-S on %s — cluster not present\n' "${cluster}"
    return 0
  fi
  install_envoy_gateway "${ctx}"
  install_kuadrant "${ctx}"
  install_coredns "${ctx}"
}

install_east_west() {
  local cluster="$1"
  local ctx
  ctx="$(demo_kind_context "${cluster}")"
  if ! demo_kind_exists "${cluster}"; then
    printf 'up: skip E-W on %s — cluster not present\n' "${cluster}"
    return 0
  fi
  install_linkerd "${ctx}"
  deploy_emojivoto "${cluster}"
  # Policies after mesh+apps so Gateway→web-svc and mesh coexist on a full stack.
  apply_gateway_policies "${cluster}"
}

warn_skupper_client_pin() {
  local client
  client="$(skupper version 2>/dev/null | head -n1 | tr -d '[:space:]')"
  if [[ "${client}" != *"${SKUPPER_VERSION}"* ]]; then
    printf 'up: warn: skupper client is %q; pin is %s (see demo/VERSIONS.md)\n' \
      "${client:-unknown}" "${SKUPPER_VERSION}"
  fi
}

install_skupper_controller() {
  local ctx="$1"
  warn_skupper_client_pin
  printf 'up: [%s] Skupper controller %s\n' "${ctx}" "${SKUPPER_VERSION}"
  kubectl --context "${ctx}" apply -f "${SKUPPER_CONTROLLER_URL}"
  # Controller often lands in namespace skupper; keep mesh off.
  kubectl --context "${ctx}" apply -f "${SKUPPER_DIR}/namespace.yaml"
  kubectl --context "${ctx}" label ns skupper linkerd.io/inject=disabled --overwrite 2>/dev/null || true
  kubectl --context "${ctx}" annotate ns skupper linkerd.io/inject=disabled --overwrite 2>/dev/null || true
  kubectl --context "${ctx}" -n skupper wait --timeout=3m \
    --for=condition=Available deployment --all 2>/dev/null || \
    printf 'up: [%s] Skupper controller Available wait timed out — continue\n' "${ctx}"
}

apply_skupper_kind_site() {
  local cluster="$1"
  local ctx site_file
  ctx="$(demo_kind_context "${cluster}")"
  site_file="${SKUPPER_DIR}/sites/${cluster}.yaml"
  printf 'up: [%s] Skupper Site from %s\n' "${ctx}" "${site_file#${ROOT}/}"
  kubectl --context "${ctx}" apply -f "${SKUPPER_DIR}/namespace.yaml"
  kubectl --context "${ctx}" apply -f "${site_file}"
  kubectl --context "${ctx}" apply -f "${SKUPPER_DIR}/connectors/voting-attached.yaml"
  kubectl --context "${ctx}" apply -f "${SKUPPER_DIR}/connectors/voting-binding.yaml"
  kubectl --context "${ctx}" apply -f "${SKUPPER_DIR}/listeners/voting-van.yaml"
  kubectl --context "${ctx}" apply -f "${SKUPPER_DIR}/listeners/legacy-emoji.yaml"
  # Site Ready needs LoadBalancer via cloud-provider-kind; wait, then continue with a clear hint.
  local waited=0
  local wait_max="${SKUPPER_SITE_WAIT_SEC:-90}"
  while (( waited < wait_max )); do
    if skupper --context "${ctx}" -n skupper site status 2>/dev/null | grep -qiE 'ready|ok|running'; then
      printf 'up: [%s] Skupper site Ready\n' "${ctx}"
      return 0
    fi
    sleep 5
    waited=$((waited + 5))
  done
  if ! skupper --context "${ctx}" -n skupper site status 2>/dev/null; then
    printf 'up: [%s] Skupper site not Ready after %ss — check cloud-provider-kind + Gateway EXTERNAL-IP\n' \
      "${ctx}" "${wait_max}"
    printf 'up: [%s] hint: make sure demo/.run/cloud-provider-kind.pid is alive; see demo/skupper/README.md\n' "${ctx}"
  fi
}

ensure_legacy_emoji() {
  printf 'up: starting legacy-emoji on podman-edge\n'
  "${LEGACY_DIR}/run.sh"
}

ensure_skupper_podman_site() {
  printf 'up: Podman Skupper site podman-edge (%s)\n' "${SKUPPER_VERSION}"
  skupper system install -p podman >/dev/null 2>&1 || \
    printf 'up: skupper system install returned non-zero — continue if already installed\n'
  skupper system apply -p podman -n podman-edge -f "${SKUPPER_DIR}/sites/podman-edge.yaml"
  skupper system apply -p podman -n podman-edge -f "${SKUPPER_DIR}/connectors/legacy-emoji-podman.yaml"
  skupper system start -p podman -n podman-edge 2>/dev/null || \
    printf 'up: skupper system start returned non-zero — site may already be running\n'
  # Always query with -n podman-edge (default NS is not the demo site).
  if skupper -p podman -n podman-edge site status 2>/dev/null | grep -qiE 'ready|ok'; then
    printf 'up: podman-edge Skupper site Ready\n'
  else
    printf 'up: warn: podman-edge site not Ready yet — check: skupper -p podman -n podman-edge site status\n'
  fi
}

skupper_has_ready_west_link() {
  # Tokens issued by this demo use kind-west-<uuid> as the Link name.
  skupper "$@" link status 2>/dev/null \
    | awk '$1 ~ /^kind-west-/ && $2 == "Ready" { ready=1 } END { exit !ready }'
}

link_skupper_van() {
  local west_ctx east_ctx
  local east_ready=0 podman_ready=0
  west_ctx="$(demo_kind_context kind-west)"
  east_ctx="$(demo_kind_context kind-east)"
  mkdir -p "$(dirname "${SKUPPER_TOKEN_FILE}")"
  if ! demo_kind_exists "kind-west"; then
    printf 'up: skip Skupper linking — kind-west not present\n'
    return 0
  fi
  if ! demo_kind_exists "kind-east" || skupper_has_ready_west_link --context "${east_ctx}" -n skupper; then
    east_ready=1
  fi
  if skupper_has_ready_west_link -p podman -n podman-edge; then
    podman_ready=1
  fi
  if [[ "${east_ready}" -eq 1 && "${podman_ready}" -eq 1 ]]; then
    printf 'up: existing Skupper links to kind-west are Ready — skipping token issue/redeem\n'
    return 0
  fi
  printf 'up: issuing Skupper token from kind-west (hub)\n'
  # Multiple redemptions: east + podman-edge (+ retries). Fail hard so make up
  # success implies the required three-site VAN is linked (skupper-van contract).
  if ! skupper --context "${west_ctx}" -n skupper token issue "${SKUPPER_TOKEN_FILE}" \
    --redemptions-allowed 5 --expiration-window 24h --timeout 2m; then
    printf 'up: token issue failed — LoadBalancer/linkAccess not ready yet\n'
    printf 'up: hint: cloud-provider-kind must be running with --enable-lb-port-mapping; see demo/VERSIONS.md\n'
    printf 'up: retry after: kubectl --context %s -n skupper get site,svc\n' "${west_ctx}"
    return 1
  fi
  if [[ "${east_ready}" -eq 0 ]]; then
    printf 'up: redeeming token on kind-east\n'
    if ! skupper --context "${east_ctx}" -n skupper token redeem "${SKUPPER_TOKEN_FILE}" --timeout 2m; then
      printf 'up: east token redeem failed\n'
      return 1
    fi
  fi
  if [[ "${podman_ready}" -eq 1 ]]; then
    printf 'up: podman-edge already linked to kind-west — skipping redeem\n'
    return 0
  fi
  printf 'up: redeeming token on podman-edge (Option C: CCM localhost + SANs)\n'
  if "${SCRIPT_DIR}/lib/redeem-podman-skupper.sh"; then
    printf 'up: podman-edge linked into VAN (127.0.0.1 CCM path)\n'
  else
    printf 'up: podman-edge link failed — re-run ./demo/scripts/lib/redeem-podman-skupper.sh; see demo/skupper/README.md\n'
    return 1
  fi
  # Confirm Kind sees 3 sites (west+east+podman) when possible.
  skupper --context "${west_ctx}" -n skupper site status 2>/dev/null || true
  skupper -p podman -n podman-edge link status 2>/dev/null || true
}

install_skupper_van() {
  local cluster="$1"
  if ! demo_kind_exists "${cluster}"; then
    printf 'up: skip Skupper on %s — cluster not present\n' "${cluster}"
    return 0
  fi
  local ctx
  ctx="$(demo_kind_context "${cluster}")"
  install_skupper_controller "${ctx}"
  apply_skupper_kind_site "${cluster}"
}

bring_up_target() {
  local target="$1"
  case "${target}" in
    kind-west)
      ensure_kind_cluster "kind-west" "${KIND_DIR}/west.yaml"
      install_north_south "kind-west"
      install_east_west "kind-west"
      install_skupper_van "kind-west"
      ;;
    kind-east)
      ensure_kind_cluster "kind-east" "${KIND_DIR}/east.yaml"
      install_north_south "kind-east"
      install_east_west "kind-east"
      install_skupper_van "kind-east"
      ;;
    podman-edge)
      ensure_podman_edge
      ensure_legacy_emoji
      ensure_skupper_podman_site
      ;;
    *)
      demo_require_allowlisted "${target}" "create"
      ;;
  esac
}

main() {
  local targets=()
  local target resolved
  local want_west=0 want_east=0 want_podman=0
  # Allowlist gate BEFORE prereq side effects so CLUSTER=kind-cluster fails fast.
  if ! resolved="$(demo_resolve_targets)"; then
    exit 1
  fi
  while IFS= read -r target; do
    [[ -n "${target}" ]] && targets+=("${target}")
  done <<<"${resolved}"

  "${SCRIPT_DIR}/prereq-check.sh"

  # Kind LoadBalancer CCM before any Kind create (Skupper linkAccess + Gateway EXTERNAL-IP).
  local need_kind=0
  for target in "${targets[@]}"; do
    if demo_is_kind_site "${target}"; then
      need_kind=1
      break
    fi
  done
  if [[ "${need_kind}" -eq 1 ]]; then
    demo_ensure_cloud_provider_kind || exit 1
  fi

  for target in "${targets[@]}"; do
    bring_up_target "${target}"
    case "${target}" in
      kind-west) want_west=1 ;;
      kind-east) want_east=1 ;;
      podman-edge) want_podman=1 ;;
    esac
  done

  # Link after all selected sites exist (hub → spokes).
  if [[ "${want_west}" -eq 1 && ( "${want_east}" -eq 1 || "${want_podman}" -eq 1 ) ]]; then
    link_skupper_van
  fi

  printf 'up: done (targets: %s)\n' "${targets[*]}"
}

main "$@"
