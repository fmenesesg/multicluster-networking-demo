#!/usr/bin/env bash
# Install host prerequisites for the multicluster connectivity demo.
# Pins: keep in sync with demo/VERSIONS.md
#
#   make install
#   export PATH="$HOME/.local/bin:$PATH"   # printed at end; not written to rc files
#   make prereq-check
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ROOT="$(demo_repo_root)"
BIN_DIR="${DEMO_INSTALL_BIN_DIR:-${HOME}/.local/bin}"
ARCH="$(uname -m)"
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"

# --- Pins (demo/VERSIONS.md) ---
KIND_VERSION="${KIND_VERSION:-v0.32.0}"
KUBECTL_VERSION="${KUBECTL_VERSION:-v1.36.1}"
HELM_VERSION="${HELM_VERSION:-v3.17.3}"
SKUPPER_VERSION="${SKUPPER_VERSION:-2.2.1}"
LINKERD_VERSION="${LINKERD_VERSION:-edge-26.6.3}"
# Prefer 0.11.1 over 0.12+ for Kind+Podman: 0.12 publishes ephemeral host ports
# (breaks demo README :8080/:8081/:45671/:55671). Override with CLOUD_PROVIDER_KIND_VERSION=.
CLOUD_PROVIDER_KIND_VERSION="${CLOUD_PROVIDER_KIND_VERSION:-v0.11.1}"
KUSTOMIZE_VERSION="${KUSTOMIZE_VERSION:-v5.6.0}"
MIN_INOTIFY_INSTANCES=512

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

warn() {
  printf 'warn: %s\n' "$*" >&2
}

info() {
  printf 'install: %s\n' "$*"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required host tool: $1"
}

sudo_run() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    fail "need root or sudo for: $*"
  fi
}

resolve_goarch() {
  case "${ARCH}" in
    x86_64 | amd64) printf 'amd64\n' ;;
    aarch64 | arm64) printf 'arm64\n' ;;
    *) fail "unsupported architecture: ${ARCH} (need amd64 or arm64)" ;;
  esac
}

ensure_bin_dir() {
  mkdir -p "${BIN_DIR}"
}

# Warn when installing over a different on-PATH binary or replacing an existing pin file.
warn_version_change() {
  local name="$1"
  local want="$2"
  local dest="${BIN_DIR}/${name}"
  local current=""
  local path_bin=""

  if path_bin="$(command -v "${name}" 2>/dev/null)"; then
    if [[ "${path_bin}" != "${dest}" ]]; then
      warn "${name}: PATH has ${path_bin} (will prefer ${dest} once PATH puts ${BIN_DIR} first)"
    fi
  fi
  if [[ -x "${dest}" ]]; then
    current="$(cli_version_string "${name}" "${dest}" || true)"
    if [[ -n "${current}" && "${current}" != *"${want}"* ]]; then
      warn "${name}: replacing ${current} → pin ${want} at ${dest}"
    elif [[ -n "${current}" ]]; then
      info "${name}: already at pin (${current}) — reinstalling ${want}"
    else
      warn "${name}: replacing existing ${dest} with pin ${want}"
    fi
  else
    info "${name}: installing pin ${want} → ${dest}"
  fi
}

cli_version_string() {
  local name="$1"
  local bin="$2"
  case "${name}" in
    kind) "${bin}" version 2>/dev/null | head -n1 || true ;;
    kubectl) "${bin}" version --client -o yaml 2>/dev/null | awk '/gitVersion:/ {print $2; exit}' || true ;;
    helm) "${bin}" version --short 2>/dev/null || true ;;
    skupper) "${bin}" version 2>/dev/null | head -n1 || true ;;
    linkerd) "${bin}" version --client --short 2>/dev/null || "${bin}" version --client 2>/dev/null | head -n1 || true ;;
    cloud-provider-kind) "${bin}" version 2>/dev/null || printf 'cloud-provider-kind\n' ;;
    kustomize) "${bin}" version 2>/dev/null | head -n1 || true ;;
    *) true ;;
  esac
}

download() {
  local url="$1"
  local out="$2"
  info "download ${url}"
  curl -fsSL --retry 3 --retry-delay 2 -o "${out}" "${url}"
}

install_file() {
  local src="$1"
  local dest="$2"
  chmod +x "${src}"
  install -m 0755 "${src}" "${dest}"
}

install_podman() {
  if command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
    info "podman: already usable ($(podman version -f '{{.Client.Version}}' 2>/dev/null || echo present))"
    return 0
  fi
  if command -v podman >/dev/null 2>&1; then
    warn "podman present but not usable (podman info failed) — not auto-fixing; check user session / socket"
    return 0
  fi
  if ! command -v dnf >/dev/null 2>&1; then
    fail "podman missing and dnf not available — install podman 5.x manually"
  fi
  info "podman: installing via dnf (sudo)"
  sudo_run dnf install -y podman
  podman info >/dev/null 2>&1 || fail "podman installed but still not usable (podman info failed)"
}

# Host tools required by prereq-check after demo scripts (not downloaded as release binaries).
ensure_host_tools() {
  local missing=()
  local pkg
  command -v python3 >/dev/null 2>&1 || missing+=("python3")
  command -v dig >/dev/null 2>&1 || missing+=("bind-utils")
  command -v setsid >/dev/null 2>&1 || missing+=("util-linux")
  if [[ "${#missing[@]}" -eq 0 ]]; then
    info "host tools: python3 dig setsid present"
    return 0
  fi
  if ! command -v dnf >/dev/null 2>&1; then
    fail "missing host tools (${missing[*]}) and dnf not available — install python3, bind-utils, util-linux"
  fi
  info "host tools: installing via dnf: ${missing[*]} (sudo)"
  for pkg in "${missing[@]}"; do
    sudo_run dnf install -y "${pkg}"
  done
  command -v python3 >/dev/null 2>&1 || fail "python3 still missing after dnf install"
  command -v dig >/dev/null 2>&1 || fail "dig still missing after dnf install (package bind-utils)"
  command -v setsid >/dev/null 2>&1 || fail "setsid still missing after dnf install (package util-linux)"
}

ensure_inotify() {
  local path="${INOTIFY_MAX_USER_INSTANCES_PATH:-/proc/sys/fs/inotify/max_user_instances}"
  local current
  [[ -r "${path}" ]] || fail "cannot read ${path}"
  current="$(cat "${path}")"
  if [[ "${current}" -ge "${MIN_INOTIFY_INSTANCES}" ]]; then
    info "inotify max_user_instances=${current} (ok)"
    return 0
  fi
  warn "inotify max_user_instances=${current} → raising to ${MIN_INOTIFY_INSTANCES} (sudo sysctl)"
  sudo_run sysctl -w "fs.inotify.max_user_instances=${MIN_INOTIFY_INSTANCES}"
  info "optional persist: echo 'fs.inotify.max_user_instances=${MIN_INOTIFY_INSTANCES}' | sudo tee /etc/sysctl.d/99-demo-inotify.conf && sudo sysctl --system"
}

install_kind() {
  local goarch tmp
  goarch="$(resolve_goarch)"
  warn_version_change kind "${KIND_VERSION}"
  tmp="$(mktemp)"
  download "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-${OS}-${goarch}" "${tmp}"
  install_file "${tmp}" "${BIN_DIR}/kind"
  rm -f "${tmp}"
}

install_kubectl() {
  local goarch tmp
  goarch="$(resolve_goarch)"
  warn_version_change kubectl "${KUBECTL_VERSION}"
  tmp="$(mktemp)"
  download "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/${OS}/${goarch}/kubectl" "${tmp}"
  install_file "${tmp}" "${BIN_DIR}/kubectl"
  rm -f "${tmp}"
}

install_helm() {
  local goarch tmpdir
  goarch="$(resolve_goarch)"
  warn_version_change helm "${HELM_VERSION}"
  tmpdir="$(mktemp -d)"
  download "https://get.helm.sh/helm-${HELM_VERSION}-${OS}-${goarch}.tar.gz" "${tmpdir}/helm.tgz"
  tar -xzf "${tmpdir}/helm.tgz" -C "${tmpdir}"
  install_file "${tmpdir}/${OS}-${goarch}/helm" "${BIN_DIR}/helm"
  rm -rf "${tmpdir}"
}

install_skupper() {
  local goarch tmpdir
  goarch="$(resolve_goarch)"
  warn_version_change skupper "${SKUPPER_VERSION}"
  tmpdir="$(mktemp -d)"
  download "https://github.com/skupperproject/skupper/releases/download/${SKUPPER_VERSION}/skupper-cli-${SKUPPER_VERSION}-${OS}-${goarch}.tgz" \
    "${tmpdir}/skupper.tgz"
  tar -xzf "${tmpdir}/skupper.tgz" -C "${tmpdir}" skupper
  install_file "${tmpdir}/skupper" "${BIN_DIR}/skupper"
  rm -rf "${tmpdir}"
}

install_linkerd() {
  local goarch tmp
  goarch="$(resolve_goarch)"
  warn_version_change linkerd "${LINKERD_VERSION}"
  tmp="$(mktemp)"
  # Official edge CLI asset naming: linkerd2-cli-<ver>-linux-<arch>
  download "https://github.com/linkerd/linkerd2/releases/download/${LINKERD_VERSION}/linkerd2-cli-${LINKERD_VERSION}-${OS}-${goarch}" \
    "${tmp}"
  install_file "${tmp}" "${BIN_DIR}/linkerd"
  rm -f "${tmp}"
}

install_cloud_provider_kind() {
  local goarch tmpdir ver_naked
  goarch="$(resolve_goarch)"
  ver_naked="${CLOUD_PROVIDER_KIND_VERSION#v}"
  warn_version_change cloud-provider-kind "${CLOUD_PROVIDER_KIND_VERSION}"
  tmpdir="$(mktemp -d)"
  download "https://github.com/kubernetes-sigs/cloud-provider-kind/releases/download/${CLOUD_PROVIDER_KIND_VERSION}/cloud-provider-kind_${ver_naked}_${OS}_${goarch}.tar.gz" \
    "${tmpdir}/ccm.tgz"
  tar -xzf "${tmpdir}/ccm.tgz" -C "${tmpdir}"
  if [[ ! -f "${tmpdir}/cloud-provider-kind" ]]; then
    fail "cloud-provider-kind binary missing from release archive"
  fi
  install_file "${tmpdir}/cloud-provider-kind" "${BIN_DIR}/cloud-provider-kind"
  rm -rf "${tmpdir}"
}

install_kustomize() {
  local goarch tmpdir
  goarch="$(resolve_goarch)"
  warn_version_change kustomize "${KUSTOMIZE_VERSION}"
  tmpdir="$(mktemp -d)"
  download "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}/kustomize_${KUSTOMIZE_VERSION}_${OS}_${goarch}.tar.gz" \
    "${tmpdir}/kustomize.tgz"
  tar -xzf "${tmpdir}/kustomize.tgz" -C "${tmpdir}"
  install_file "${tmpdir}/kustomize" "${BIN_DIR}/kustomize"
  rm -rf "${tmpdir}"
}

print_path_help() {
  cat <<EOF

install: done — put demo CLIs first on PATH (this shell):

  export PATH="${BIN_DIR}:\$PATH"

Optional idempotent snippet for ~/.zshrc (paste once; safe to re-paste):

  # multicluster-networking-demo CLIs
  case ":\$PATH:" in
    *":${BIN_DIR}:"*) ;;
    *) export PATH="${BIN_DIR}:\$PATH" ;;
  esac

Then verify:

  make prereq-check

EOF
}

main() {
  need_cmd curl
  need_cmd tar
  need_cmd install
  [[ "${OS}" == "linux" ]] || fail "only linux is supported by make install (got ${OS})"
  ensure_bin_dir

  # Ensure our bin dir wins for the rest of this script + final prereq-check.
  export PATH="${BIN_DIR}:${PATH}"

  install_podman
  ensure_host_tools
  ensure_inotify
  install_kind
  install_kubectl
  install_helm
  install_skupper
  install_linkerd
  install_cloud_provider_kind
  install_kustomize

  info "running prereq-check with PATH=${BIN_DIR}:…"
  "${SCRIPT_DIR}/prereq-check.sh"
  print_path_help
}

main "$@"
