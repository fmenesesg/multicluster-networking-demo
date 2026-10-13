#!/usr/bin/env bash
# cloud-provider-kind lifecycle for Kind+Podman LoadBalancer (Skupper linkAccess + Gateway EXTERNAL-IP).
# Sourced by up.sh / down.sh. Starts CCM only when needed; down stops only a demo-owned process.
#
# Locked decision: cloud-provider-kind (NOT MetalLB).
# Podman: --enable-lb-port-mapping
# After Kind create: remove node.kubernetes.io/exclude-from-external-load-balancers (single-node Kind).

# shellcheck shell=bash

demo_run_dir() {
  printf '%s\n' "$(demo_repo_root)/demo/.run"
}

demo_ccm_pidfile() {
  printf '%s\n' "$(demo_run_dir)/cloud-provider-kind.pid"
}

demo_ccm_logfile() {
  printf '%s\n' "$(demo_run_dir)/cloud-provider-kind.log"
}

demo_ccm_owned_marker() {
  # Present only when this demo started the CCM process recorded in the pidfile.
  printf '%s\n' "$(demo_run_dir)/cloud-provider-kind.owned"
}

demo_ccm_bin() {
  command -v cloud-provider-kind 2>/dev/null || true
}

# True if a cloud-provider-kind process is already running (ours or user-owned).
demo_ccm_process_running() {
  pgrep -f '(^|/)cloud-provider-kind( |$)' >/dev/null 2>&1
}

demo_ccm_pid_alive() {
  local pid="$1"
  [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null
}

# Prepare a single-node Kind control-plane to accept LoadBalancer services.
demo_kind_enable_loadbalancer() {
  local name="$1"
  local ctx node
  ctx="$(demo_kind_context "${name}")"
  if ! demo_kind_exists "${name}"; then
    return 0
  fi
  printf 'up: [%s] enabling LoadBalancer (clear exclude-from-external-load-balancers)\n' "${ctx}"
  while IFS= read -r node; do
    [[ -z "${node}" ]] && continue
    kubectl --context "${ctx}" label node "${node}" \
      node.kubernetes.io/exclude-from-external-load-balancers- \
      --overwrite >/dev/null 2>&1 || true
  done < <(kubectl --context "${ctx}" get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
}

# Start cloud-provider-kind in the background if nothing is watching Kind LBs yet.
# Pidfile + owned marker live under demo/.run/ so make down only kills our instance.
demo_ensure_cloud_provider_kind() {
  local bin pidfile logfile owned run_dir
  bin="$(demo_ccm_bin)"
  if [[ -z "${bin}" ]]; then
    printf 'error: cloud-provider-kind not in PATH (required for Kind LoadBalancer / Skupper linkAccess)\n' >&2
    printf 'hint: go install sigs.k8s.io/cloud-provider-kind@latest\n' >&2
    printf 'hint: or install a release binary into ~/.local/bin (see demo/VERSIONS.md)\n' >&2
    return 1
  fi

  run_dir="$(demo_run_dir)"
  pidfile="$(demo_ccm_pidfile)"
  logfile="$(demo_ccm_logfile)"
  owned="$(demo_ccm_owned_marker)"
  mkdir -p "${run_dir}"

  if [[ -f "${pidfile}" ]]; then
    local old_pid
    old_pid="$(tr -d '[:space:]' <"${pidfile}" || true)"
    if demo_ccm_pid_alive "${old_pid}"; then
      printf 'up: cloud-provider-kind already running (pid %s, demo pidfile)\n' "${old_pid}"
      return 0
    fi
    rm -f "${pidfile}" "${owned}"
  fi

  if demo_ccm_process_running; then
    printf 'up: cloud-provider-kind already running (external) — not starting a second instance\n'
    printf 'up: make down will NOT stop that external process\n'
    return 0
  fi

  demo_ccm_start_process "${bin}" "${logfile}" "${pidfile}" "${owned}"
}

# Start (or restart) a demo-owned CCM process. Exports KIND_EXPERIMENTAL_PROVIDER=podman
# so List() sees Podman Kind clusters (required on this demo host).
demo_ccm_start_process() {
  local bin="$1"
  local logfile="$2"
  local pidfile="$3"
  local owned="$4"
  local new_pid

  printf 'up: starting cloud-provider-kind --enable-lb-port-mapping (log %s)\n' "${logfile#$(demo_repo_root)/}"
  # Podman Kind clusters are invisible to CCM unless the provider env is set.
  nohup setsid env KIND_EXPERIMENTAL_PROVIDER="${KIND_EXPERIMENTAL_PROVIDER:-podman}" \
    "${bin}" --enable-lb-port-mapping </dev/null >"${logfile}" 2>&1 &
  new_pid=$!
  sleep 1
  if ! demo_ccm_pid_alive "${new_pid}"; then
    printf 'error: cloud-provider-kind exited immediately — see %s\n' "${logfile}" >&2
    return 1
  fi
  printf '%s\n' "${new_pid}" >"${pidfile}"
  touch "${owned}"
  printf 'up: cloud-provider-kind pid %s (owned by demo; stopped on make down)\n' "${new_pid}"
}

# Restart demo-owned CCM so it re-lists Kind clusters (picks up kind-east created after start).
# No-op (with a hint) when CCM is external / not demo-owned.
demo_ccm_resync_if_ours() {
  local reason="${1:-kind create}"
  local bin pidfile logfile owned old_pid

  bin="$(demo_ccm_bin)"
  pidfile="$(demo_ccm_pidfile)"
  logfile="$(demo_ccm_logfile)"
  owned="$(demo_ccm_owned_marker)"

  if [[ ! -f "${owned}" ]]; then
    printf 'up: CCM not demo-owned — after %s, restart cloud-provider-kind manually so new Kind sites get LBs\n' \
      "${reason}"
    return 0
  fi
  if [[ -z "${bin}" ]]; then
    printf 'error: cloud-provider-kind missing during resync\n' >&2
    return 1
  fi

  old_pid=""
  if [[ -f "${pidfile}" ]]; then
    old_pid="$(tr -d '[:space:]' <"${pidfile}" || true)"
  fi
  if demo_ccm_pid_alive "${old_pid}"; then
    printf 'up: restarting demo-owned cloud-provider-kind (pid %s) after %s\n' "${old_pid}" "${reason}"
    kill "${old_pid}" 2>/dev/null || true
    sleep 1
    if demo_ccm_pid_alive "${old_pid}"; then
      kill -9 "${old_pid}" 2>/dev/null || true
      sleep 1
    fi
  fi
  rm -f "${pidfile}"
  # Truncate log for the new process so adoption lines are easy to spot.
  : >"${logfile}"
  demo_ccm_start_process "${bin}" "${logfile}" "${pidfile}" "${owned}"
}

# Wait until a Kind cluster has at least one LoadBalancer with an EXTERNAL-IP (CCM adopted it).
demo_wait_ccm_lb_ready() {
  local name="$1"
  local wait_max="${2:-90}"
  local ctx waited=0 ip
  ctx="$(demo_kind_context "${name}")"
  if ! demo_kind_exists "${name}"; then
    return 0
  fi
  printf 'up: [%s] waiting up to %ss for cloud-provider-kind LoadBalancer EXTERNAL-IP\n' "${ctx}" "${wait_max}"
  while (( waited < wait_max )); do
    ip="$(kubectl --context "${ctx}" get svc -A \
      -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.status.loadBalancer.ingress[0].ip}{"\n"}{end}' \
      2>/dev/null | awk 'NF{print; exit}')"
    if [[ -n "${ip}" ]]; then
      printf 'up: [%s] CCM LoadBalancer ready (EXTERNAL-IP %s)\n' "${ctx}" "${ip}"
      return 0
    fi
    sleep 5
    waited=$((waited + 5))
  done
  printf 'up: [%s] warn: no LoadBalancer EXTERNAL-IP after %ss — Gateway/Skupper may stay Pending\n' \
    "${ctx}" "${wait_max}"
  return 1
}

# Stop CCM only if demo/.run marker says we started it.
demo_stop_cloud_provider_kind_if_ours() {
  local pidfile owned pid
  pidfile="$(demo_ccm_pidfile)"
  owned="$(demo_ccm_owned_marker)"

  if [[ ! -f "${owned}" ]]; then
    if [[ -f "${pidfile}" ]]; then
      printf 'down: cloud-provider-kind pidfile present but not demo-owned — leaving process alone\n'
    else
      printf 'down: cloud-provider-kind not started by this demo — leave any user CCM running\n'
    fi
    return 0
  fi

  if [[ ! -f "${pidfile}" ]]; then
    rm -f "${owned}"
    printf 'down: demo-owned CCM marker present but pidfile missing — cleaned marker\n'
    return 0
  fi

  pid="$(tr -d '[:space:]' <"${pidfile}" || true)"
  if demo_ccm_pid_alive "${pid}"; then
    printf 'down: stopping demo-owned cloud-provider-kind (pid %s)\n' "${pid}"
    kill "${pid}" 2>/dev/null || true
    # Give it a moment; escalate only for our pid.
    sleep 1
    if demo_ccm_pid_alive "${pid}"; then
      kill -9 "${pid}" 2>/dev/null || true
    fi
  else
    printf 'down: demo-owned cloud-provider-kind pid %s already stopped\n' "${pid:-unknown}"
  fi
  rm -f "${pidfile}" "${owned}"
}
