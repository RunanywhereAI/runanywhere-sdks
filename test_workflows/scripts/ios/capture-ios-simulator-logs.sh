#!/usr/bin/env bash
# Low-level simctl log stream → runs/<run-id>/lanes/*/logs/ (via RAC_SESSION_ROOT)
set -euo pipefail

RAC_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/_session_lib.sh
source "${RAC_SCRIPTS}/lib/_session_lib.sh"

usage() {
  cat <<'USAGE'
Usage:
  capture-ios-simulator-logs.sh start <run-id> [process-filter]
  capture-ios-simulator-logs.sh snapshot <run-id> <label> [process-filter]
  capture-ios-simulator-logs.sh stop <run-id> [process-filter]

Environment: IOS_SIM_UDID, IOS_PROCESS_FILTER
USAGE
}

[[ $# -lt 2 ]] && { usage; exit 2; }

cmd="$1"
run_id="$2"
label="${3:-}"
proc_filter="${4:-${IOS_PROCESS_FILTER:-RunAnywhereAI}}"

if [[ -n "${RAC_SESSION_ROOT:-}" ]]; then
  log_root="${RAC_SESSION_ROOT}/logs"
  pid_file="${RAC_SESSION_ROOT}/.pids/simlog.pid"
else
  log_root="$(rac_repo_root)/test_workflows/logs/runs/${run_id}/lanes/_adhoc_ios/logs"
  pid_file="$(rac_repo_root)/test_workflows/logs/runs/${run_id}/lanes/_adhoc_ios/.pids/simlog.pid"
  mkdir -p "${log_root}" "$(dirname "${pid_file}")"
fi

sim_target="${IOS_SIM_UDID:-booted}"
mkdir -p "${log_root}" "$(dirname "${pid_file}")"

predicate() {
  printf "subsystem CONTAINS[c] 'com.runanywhere' OR process CONTAINS[c] '%s' OR processImagePath CONTAINS[c] '%s' OR composedMessage CONTAINS[c] 'RunAnywhere' OR composedMessage CONTAINS[c] 'rac_' OR composedMessage CONTAINS[c] 'Phase 1 complete' OR composedMessage CONTAINS[c] 'Model load succeeded'" "$1" "$1"
}

start_logs() {
  xcrun simctl list devices booted > "${log_root}/simctl_booted_devices.log" 2>&1 || true
  xcrun simctl spawn "${sim_target}" log stream --style compact --level debug --info --debug \
    --predicate "$(predicate "${proc_filter}")" > "${log_root}/ios_live.log" 2>&1 &
  echo $! > "${pid_file}"
  # Host unified log mirrors Simulator os_log for grep during snapshots.
  log stream --style compact --level debug --info --debug \
    --predicate "$(predicate "${proc_filter}")" >> "${log_root}/ios_live.log" 2>&1 &
  echo $! >> "${pid_file}"
}

snapshot_logs() {
  local snap="${label:-snapshot}"
  xcrun simctl spawn "${sim_target}" log show --last 15m --style compact --info --debug \
    --predicate "$(predicate "${proc_filter}")" > "${log_root}/ios_snapshot_${snap}.log" 2>&1 || true
  log show --last 15m --style compact --info --debug \
    --predicate "$(predicate "${proc_filter}")" >> "${log_root}/ios_snapshot_${snap}.log" 2>&1 || true
}

stop_logs() {
  if [[ -f "${pid_file}" ]]; then
    while read -r pid; do
      [[ -n "${pid}" ]] && kill "${pid}" 2>/dev/null || true
    done < "${pid_file}"
    rm -f "${pid_file}"
  fi
  xcrun simctl spawn "${sim_target}" log show --last 15m --style compact --info --debug \
    --predicate "$(predicate "${proc_filter}")" > "${log_root}/ios_final.log" 2>&1 || true
  log show --last 15m --style compact --info --debug \
    --predicate "$(predicate "${proc_filter}")" >> "${log_root}/ios_final.log" 2>&1 || true
}

case "${cmd}" in
  start) start_logs ;;
  snapshot) snapshot_logs ;;
  stop) stop_logs ;;
  *) usage; exit 2 ;;
esac
