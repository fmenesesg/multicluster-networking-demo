#!/usr/bin/env bash
# Shared helpers for opt-in talk UI scripts (Phase A/B/C).
# Reserved ports must never be used for dashboard port-forwards.
# shellcheck source=lib/common.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

# Gateway / CCM / Skupper host ports — never for UI PF.
DEMO_UI_RESERVED_PORTS=(8080 8081 18080 18081 45671 55671)

demo_ui_run_dir() {
  local root
  root="$(demo_repo_root)"
  printf '%s\n' "${DEMO_UI_RUN_DIR:-${root}/demo/.run}"
}

demo_ui_ensure_run_dir() {
  local d
  d="$(demo_ui_run_dir)"
  mkdir -p "${d}"
  printf '%s\n' "${d}"
}

demo_ui_pidfile() {
  local name="$1"
  printf '%s/%s.pid\n' "$(demo_ui_run_dir)" "${name}"
}

demo_ui_portfile() {
  local name="$1"
  printf '%s/%s.port\n' "$(demo_ui_run_dir)" "${name}"
}

# Persist PF pid + port and detach from this shell (survives script/pipeline exit).
# Usage: demo_ui_record_pf <name> <pid> <port>
demo_ui_record_pf() {
  local name="${1:-}"
  local pid="${2:-}"
  local port="${3:-}"
  local pidfile portfile

  if [[ -z "${name}" || -z "${pid}" || -z "${port}" ]]; then
    printf 'error: demo_ui_record_pf requires name pid port\n' >&2
    return 1
  fi
  demo_ui_refuse_reserved_port "${port}" || return 1
  demo_ui_ensure_run_dir >/dev/null

  pidfile="$(demo_ui_pidfile "${name}")"
  portfile="$(demo_ui_portfile "${name}")"
  printf '%s\n' "${pid}" >"${pidfile}"
  printf '%s\n' "${port}" >"${portfile}"
  # Detach so `{ make ui; } | tee` / phase-script exit does not SIGHUP the PF.
  disown "${pid}" 2>/dev/null || true

  if [[ ! -f "${pidfile}" || ! -f "${portfile}" ]]; then
    printf 'error: failed to persist PF pid/port files for %s under %s\n' \
      "${name}" "$(demo_ui_run_dir)" >&2
    return 1
  fi
}

# Best-effort kill of listeners bound to 127.0.0.1 / ::1 only (never reserved CCM ports).
# Prefer ss scoped to loopback — never broad fuser kill of PORT/tcp (would hit all interfaces).
demo_ui_kill_localhost_port() {
  local port="${1:-}"
  local pids

  demo_ui_refuse_reserved_port "${port}" || return 1
  if ! command -v ss >/dev/null 2>&1; then
    printf 'ui: warn: ss not found; cannot safely kill loopback listeners on port %s\n' "${port}" >&2
    return 1
  fi
  # Match only 127.0.0.1:PORT or [::1]:PORT (demo UI PFs bind --address 127.0.0.1).
  pids="$(ss -ltnp 2>/dev/null \
    | grep -E "(127\\.0\\.0\\.1|\\[::1\\]):${port}\\s" \
    | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' \
    | sort -u || true)"
  if [[ -n "${pids}" ]]; then
    # shellcheck disable=SC2086
    kill ${pids} 2>/dev/null || true
  fi
}

# Stop a recorded UI port-forward by pidfile; fall back to .port / access-url / preferred port.
# Usage: demo_ui_stop_pf <label> <name> [preferred_port] [access_url_file_basename]
demo_ui_stop_pf() {
  local label="${1:-}"
  local name="${2:-}"
  local preferred_port="${3:-}"
  local url_basename="${4:-}"
  local pidfile portfile urlfile pid port had_pidfile=0

  pidfile="$(demo_ui_pidfile "${name}")"
  portfile="$(demo_ui_portfile "${name}")"

  if [[ -f "${pidfile}" ]]; then
    had_pidfile=1
    pid="$(tr -d '[:space:]' <"${pidfile}" || true)"
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}" 2>/dev/null || true
      wait "${pid}" 2>/dev/null || true
      printf 'ui: stopped %s PF (pid %s)\n' "${label}" "${pid}"
    else
      printf 'ui: %s pidfile stale (pid %s) — cleaned\n' "${label}" "${pid:-empty}"
    fi
    rm -f "${pidfile}"
  fi

  port=""
  if [[ -f "${portfile}" ]]; then
    port="$(tr -d '[:space:]' <"${portfile}" || true)"
  fi
  if [[ -z "${port}" && -n "${url_basename}" ]]; then
    urlfile="$(demo_ui_run_dir)/${url_basename}"
    if [[ -f "${urlfile}" ]]; then
      port="$(sed -n 's#.*://[^:]*:\([0-9][0-9]*\)/.*#\1#p' <"${urlfile}" | head -1 || true)"
    fi
  fi
  if [[ -z "${port}" && -n "${preferred_port}" ]]; then
    port="${preferred_port}"
  fi

  if [[ "${had_pidfile}" -eq 0 ]]; then
    if [[ -f "${portfile}" ]] || { [[ -n "${port}" ]] && demo_ui_port_in_use "${port}"; }; then
      printf 'ui: %s — no pidfile (%s); trying port fallback\n' "${label}" "${name}"
    fi
  fi

  if [[ -n "${port}" ]] && ! demo_ui_is_reserved_port "${port}" && demo_ui_port_in_use "${port}"; then
    demo_ui_kill_localhost_port "${port}" || true
    # Brief wait so ss sees the closed socket before we claim success.
    sleep 0.2
    if demo_ui_port_in_use "${port}"; then
      printf 'ui: warn: listener still present on port %s after teardown (%s)\n' "${port}" "${label}" >&2
    else
      printf 'ui: cleared leftover listener on 127.0.0.1:%s (%s)\n' "${port}" "${label}"
    fi
  fi
  rm -f "${portfile}"
  return 0
}

demo_ui_is_reserved_port() {
  local port="${1:-}"
  local p
  for p in "${DEMO_UI_RESERVED_PORTS[@]}"; do
    if [[ "${port}" == "${p}" ]]; then
      return 0
    fi
  done
  return 1
}

demo_ui_refuse_reserved_port() {
  local port="${1:-}"
  if [[ -z "${port}" ]]; then
    printf 'error: empty port is not allowed\n' >&2
    return 1
  fi
  if ! [[ "${port}" =~ ^[0-9]+$ ]]; then
    printf 'error: invalid port %q\n' "${port}" >&2
    return 1
  fi
  if demo_ui_is_reserved_port "${port}"; then
    printf 'error: refusing reserved demo port %s (CCM/Gateway/Skupper: 8080 8081 18080 18081 45671 55671)\n' \
      "${port}" >&2
    return 1
  fi
}

# Prefer preferred_port when free and not reserved; otherwise scan upward.
# Usage: demo_pick_free_port [preferred_port] [start] [end]
demo_pick_free_port() {
  local preferred="${1:-}"
  local start="${2:-50000}"
  local end="${3:-50999}"
  local candidate

  if [[ -n "${preferred}" ]]; then
    demo_ui_refuse_reserved_port "${preferred}" || return 1
    if ! demo_ui_port_in_use "${preferred}"; then
      printf '%s\n' "${preferred}"
      return 0
    fi
  fi

  candidate="${start}"
  while (( candidate <= end )); do
    if ! demo_ui_is_reserved_port "${candidate}" && ! demo_ui_port_in_use "${candidate}"; then
      printf '%s\n' "${candidate}"
      return 0
    fi
    candidate=$((candidate + 1))
  done
  printf 'error: no free port in range %s-%s (skipping reserved demo ports)\n' "${start}" "${end}" >&2
  return 1
}

demo_ui_port_in_use() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -ltn 2>/dev/null | grep -qE ":${port}\\s"
    return $?
  fi
  if command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1
    return $?
  fi
  # Best-effort: try binding with bash /dev/tcp probe via timeout+curl not available;
  # assume free if we cannot probe.
  return 1
}

# Print speaker-visible banner. Usage: demo_print_access_url <phase-label> <url> [extra lines…]
demo_print_access_url() {
  local phase="${1:-}"
  local url="${2:-}"
  shift 2 || true
  printf '\n=== Talk UI (%s) ===\n' "${phase}"
  printf 'ACCESS_URL=%s\n' "${url}"
  local line
  for line in "$@"; do
    printf '%s\n' "${line}"
  done
  printf '\n'
}

# Validate CLUSTER when set (ui helpers that touch clusters). Never kind-cluster.
demo_ui_resolve_cluster_or_abort() {
  if [[ -n "${CLUSTER:-}" ]]; then
    demo_require_allowlisted "${CLUSTER}" "target" || return 1
    printf '%s\n' "${CLUSTER}"
    return 0
  fi
  printf '%s\n' "kind-west"
}
