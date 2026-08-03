#!/usr/bin/env bash
# Public talk UI dispatcher: Phase A → B → C (start+validate each), fail-fast.
# Optional private: PHASE=all|a|b|c (not listed in Make help).
# Path: make up first, then make ui. Tear down B/C with make ui-down.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Override UI_DIR for offline fail-fast harnesses (default: real phase scripts).
UI_DIR="${UI_DIR:-${SCRIPT_DIR}/ui}"
PHASE="${PHASE:-all}"

run_phase() {
  local letter="$1"
  local script="${UI_DIR}/_phase_${letter}.sh"
  if [[ ! -x "${script}" ]]; then
    printf 'error: missing phase script %s\n' "${script}" >&2
    return 1
  fi
  printf 'ui: starting Phase %s\n' "$(echo "${letter}" | tr '[:lower:]' '[:upper:]')"
  "${script}"
  printf 'ui: Phase %s ok\n' "$(echo "${letter}" | tr '[:lower:]' '[:upper:]')"
}

case "${PHASE}" in
  all)
    run_phase a
    run_phase b
    run_phase c
    ;;
  a|b|c)
    run_phase "${PHASE}"
    ;;
  *)
    printf 'error: PHASE must be all|a|b|c (got %q)\n' "${PHASE}" >&2
    exit 1
    ;;
esac

printf 'ui: done (PHASE=%s)\n' "${PHASE}"
