#!/usr/bin/env bash
# Fail-fast host prerequisite gate before demo bring-up.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

MIN_INOTIFY_INSTANCES=512
# cloud-provider-kind: Kind LoadBalancer for Skupper linkAccess + Gateway EXTERNAL-IP (NOT MetalLB).
REQUIRED_CLIS=(podman kind kubectl helm skupper linkerd cloud-provider-kind kustomize curl openssl python3 dig setsid)

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

check_cli() {
  local bin="$1"
  if ! command -v "${bin}" >/dev/null 2>&1; then
    if [[ "${bin}" == "cloud-provider-kind" ]]; then
      fail "missing prerequisite CLI: cloud-provider-kind (Kind LoadBalancer). Install: go install sigs.k8s.io/cloud-provider-kind@latest  OR place a release binary in ~/.local/bin — see demo/VERSIONS.md"
    fi
    fail "missing prerequisite CLI: ${bin}"
  fi
}

check_inotify() {
  local current
  local inotify_path="${INOTIFY_MAX_USER_INSTANCES_PATH:-/proc/sys/fs/inotify/max_user_instances}"
  if [[ ! -r "${inotify_path}" ]]; then
    fail "cannot read fs.inotify.max_user_instances at ${inotify_path} (required >= ${MIN_INOTIFY_INSTANCES})"
  fi
  current="$(cat "${inotify_path}")"
  if [[ "${current}" -lt "${MIN_INOTIFY_INSTANCES}" ]]; then
    fail "fs.inotify.max_user_instances is ${current}; raise to at least ${MIN_INOTIFY_INSTANCES} before multi-Kind (e.g. sudo sysctl -w fs.inotify.max_user_instances=${MIN_INOTIFY_INSTANCES})"
  fi
}

check_podman_ready() {
  if ! podman info >/dev/null 2>&1; then
    fail "missing prerequisite: podman is installed but not usable (podman info failed)"
  fi
}

main() {
  local bin
  for bin in "${REQUIRED_CLIS[@]}"; do
    check_cli "${bin}"
  done
  check_podman_ready
  check_inotify
  printf 'prereq-check: ok (CLIs present incl. cloud-provider-kind; inotify >= %s; podman usable)\n' \
    "${MIN_INOTIFY_INSTANCES}"
}

main "$@"
