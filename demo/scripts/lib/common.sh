#!/usr/bin/env bash
# Shared allowlist and helpers for demo lifecycle scripts.
# Allowlist ONLY: kind-west, kind-east, podman-edge. NEVER touch kind-cluster.

# shellcheck disable=SC2034
DEMO_KIND_CLUSTERS=(kind-west kind-east)
DEMO_PODMAN_SITES=(podman-edge)
DEMO_ALLOWLIST=(kind-west kind-east podman-edge)

# All entry points must discover the same Podman clusters as up.sh.
export KIND_EXPERIMENTAL_PROVIDER="${KIND_EXPERIMENTAL_PROVIDER:-podman}"

demo_repo_root() {
  local here
  # This file lives at demo/scripts/lib/common.sh → three levels up is repo root.
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
  printf '%s\n' "${here}"
}

demo_is_allowlisted() {
  local name="${1:-}"
  local site
  for site in "${DEMO_ALLOWLIST[@]}"; do
    if [[ "${name}" == "${site}" ]]; then
      return 0
    fi
  done
  return 1
}

demo_require_allowlisted() {
  local name="${1:-}"
  local action="${2:-operate on}"
  if [[ -z "${name}" ]]; then
    printf 'error: empty site/cluster name is not allowed\n' >&2
    return 1
  fi
  if ! demo_is_allowlisted "${name}"; then
    printf 'error: refusing to %s %q — not in demo allowlist (kind-west, kind-east, podman-edge)\n' \
      "${action}" "${name}" >&2
    printf 'hint: never create, reuse, or destroy kind-cluster from these scripts\n' >&2
    return 1
  fi
}

# If CLUSTER is set, validate it against the allowlist. Prints the resolved
# target list (one per line) to stdout: either the single CLUSTER or the full allowlist.
demo_resolve_targets() {
  if [[ -n "${CLUSTER:-}" ]]; then
    demo_require_allowlisted "${CLUSTER}" "target" || return 1
    printf '%s\n' "${CLUSTER}"
    return 0
  fi
  local site
  for site in "${DEMO_ALLOWLIST[@]}"; do
    printf '%s\n' "${site}"
  done
}

demo_kind_exists() {
  local name="$1"
  kind get clusters 2>/dev/null | grep -qx "${name}"
}

# Kind context for cluster name (e.g. kind-west → kind-kind-west).
demo_kind_context() {
  local name="$1"
  printf 'kind-%s\n' "${name}"
}

demo_is_kind_site() {
  local name="$1"
  local c
  for c in "${DEMO_KIND_CLUSTERS[@]}"; do
    if [[ "${name}" == "${c}" ]]; then
      return 0
    fi
  done
  return 1
}

demo_remove_kube_context() {
  local name="$1"
  local ctx="kind-${name}"
  if kubectl config get-contexts -o name 2>/dev/null | grep -qx "${ctx}"; then
    kubectl config delete-context "${ctx}" >/dev/null 2>&1 || true
  fi
  if kubectl config get-clusters 2>/dev/null | grep -qx "${ctx}"; then
    kubectl config delete-cluster "${ctx}" >/dev/null 2>&1 || true
  fi
  if kubectl config get-users 2>/dev/null | grep -qx "${ctx}"; then
    kubectl config delete-user "${ctx}" >/dev/null 2>&1 || true
  fi
}
