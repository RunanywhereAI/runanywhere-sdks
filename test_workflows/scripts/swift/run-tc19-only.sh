#!/usr/bin/env bash
# TC-19 benchmarks only — skips catalog/STT flows for faster SWIFT-IOS-002 verification.
set -euo pipefail

SWIFT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${SWIFT_SCRIPT_DIR}/../../.." && pwd)"
CAPTURE_SCRIPT="${SWIFT_SCRIPT_DIR}/capture-swift-logs.sh"

# shellcheck source=../_tc_helper.sh
source "${SWIFT_SCRIPT_DIR}/../_tc_helper.sh"
# shellcheck source=_swift_log_lib.sh
source "${SWIFT_SCRIPT_DIR}/_swift_log_lib.sh"
# shellcheck source=_swift_tap_lib.sh
source "${SWIFT_SCRIPT_DIR}/_swift_tap_lib.sh"
# shellcheck source=_swift_tc_flows.sh
source "${SWIFT_SCRIPT_DIR}/_swift_tc_flows.sh"

: "${RAC_RUN_ID:?RAC_RUN_ID required}"
export RAC_LANE_SLUG="02_swift_ios"
export RAC_IOS_SIM_UDID="${RAC_IOS_SIM_UDID:-booted}"
RAC_SESSION_ROOT="${REPO}/test_workflows/logs/runs/${RAC_RUN_ID}/lanes/${RAC_LANE_SLUG}"
export RAC_SESSION_ROOT
BUNDLE_ID="${BUNDLE_ID:-com.runanywhere.RunAnywhere}"
IOS_PROCESS_FILTER="${IOS_PROCESS_FILTER:-RunAnywhereAI}"
export IOS_PROCESS_FILTER

export RAC_MCP_SHOT_CMD='_swift_shot'
export RAC_MCP_TAP_CMD='_swift_tap'
export RAC_MCP_TYPE_CMD='_swift_type'
export RAC_MCP_GREP_CMD='_swift_grep'

_swift_shot() {
  local out="$1"
  xcrun simctl io "${RAC_IOS_SIM_UDID}" screenshot "${out}" >/dev/null 2>&1 || true
}

_swift_tap() {
  _swift_tap_raw "$1"
}

_swift_type() {
  xcrun simctl io "${RAC_IOS_SIM_UDID}" send-text "$1" >/dev/null 2>&1 || true
}

_swift_capture() {
  local cmd="$1"
  local label="${2:-}"
  [[ -x "${CAPTURE_SCRIPT}" ]] || return 0
  if [[ "${cmd}" == "snapshot" ]]; then
    "${CAPTURE_SCRIPT}" snapshot "${RAC_RUN_ID}" "${label}" "${IOS_PROCESS_FILTER}" >/dev/null 2>&1 || true
  else
    "${CAPTURE_SCRIPT}" "${cmd}" "${RAC_RUN_ID}" "" "${IOS_PROCESS_FILTER}" >/dev/null 2>&1 || true
  fi
}

trap '_swift_capture stop' EXIT
_swift_capture start

rac_tc_init_lane
_swift_sim_privacy_grants
_swift_drive_tc19_benchmarks
echo "TC-19 only: complete"
