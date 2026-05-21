#!/usr/bin/env bash
# Swift iOS lane executor — drives TC-02..TC-21 via the shared mobile harness.
set -euo pipefail

SWIFT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${SWIFT_SCRIPT_DIR}/../../.." && pwd)"
CAPTURE_SCRIPT="${SWIFT_SCRIPT_DIR}/capture-swift-logs.sh"

# shellcheck source=../_tc_helper.sh
source "${SWIFT_SCRIPT_DIR}/../_tc_helper.sh"
# shellcheck source=_swift_log_lib.sh
source "${SWIFT_SCRIPT_DIR}/_swift_log_lib.sh"

: "${RAC_RUN_ID:?RAC_RUN_ID required}"
export RAC_LANE_SLUG="02_swift_ios"
export RAC_IOS_SIM_UDID="${RAC_IOS_SIM_UDID:-booted}"
RAC_SESSION_ROOT="${REPO}/test_workflows/logs/runs/${RAC_RUN_ID}/lanes/${RAC_LANE_SLUG}"
export RAC_SESSION_ROOT
BUNDLE_ID="${BUNDLE_ID:-com.runanywhere.RunAnywhere}"
IOS_PROCESS_FILTER="${IOS_PROCESS_FILTER:-RunAnywhereAI}"
export IOS_PROCESS_FILTER

export RAC_TAB_CHAT="Chat"
export RAC_TAB_MORE="More"
export RAC_TAB_TRANSCRIBE="Transcribe"
export RAC_TAB_SPEAK="Speak"
export RAC_TAB_VISION="Vision"
export RAC_TAB_VOICE="Voice"
export RAC_TAB_DOCS="Document Q&A"
export RAC_TAB_STORAGE="Storage"
export RAC_TAB_SETTINGS="Settings"
# More hub rows (catalog §5): tap More before these labels.
export RAC_SWIFT_MORE_HUB_LABELS="Transcribe Speak Document Q&A Storage Voice Detection"

export RAC_MCP_SHOT_CMD='_swift_shot'
export RAC_MCP_TAP_CMD='_swift_tap'
export RAC_MCP_TYPE_CMD='_swift_type'
export RAC_MCP_GREP_CMD='_swift_grep'

_swift_shot() {
  local out="$1"
  xcrun simctl io "${RAC_IOS_SIM_UDID}" screenshot "${out}" >/dev/null 2>&1 || true
}

_swift_tap_raw() {
  local label="$1"
  if [[ -n "${RAC_MCP_TAP_HTTP:-}" ]]; then
    curl -fsS -X POST "${RAC_MCP_TAP_HTTP}" --data-urlencode "label=${label}" >/dev/null 2>&1 || true
    return 0
  fi
  xcrun simctl ui "${RAC_IOS_SIM_UDID}" tap --label "${label}" >/dev/null 2>&1 || true
}

_swift_tap() {
  local label="$1"
  if [[ " ${RAC_SWIFT_MORE_HUB_LABELS} " == *" ${label} "* ]]; then
    _swift_tap_raw "${RAC_TAB_MORE}"
    sleep 1
  fi
  _swift_tap_raw "${label}"
}

_swift_type() {
  local text="$1"
  xcrun simctl io "${RAC_IOS_SIM_UDID}" send-text "${text}" >/dev/null 2>&1 || true
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

_swift_capture_stop() {
  _swift_capture stop
}

_swift_regrade_tc07() {
  local evidence status notes
  if ! evidence="$(_swift_tc07_evidence)"; then
    return 0
  fi
  _swift_tc07_status_from_evidence "${evidence}" | {
    IFS=$'\t' read -r status notes
    rac_tc_done tc07 "${status}" "${notes}" "screenshots/013_transcribe.png"
  }
}

trap _swift_capture_stop EXIT
_swift_capture start

rac_tc_init_lane
sleep 5
rac_mcp_shot "${RAC_SESSION_ROOT}/screenshots/000_after_launch.png"
_swift_capture snapshot tc01_init
if _swift_tc01_ready; then
  rac_tc_done tc01 PASS "SDK init or app-ready marker in sim logs" "screenshots/000_after_launch.png"
else
  rac_tc_done tc01 BLOCKED "no SDK init / app-ready marker in captured logs" "screenshots/000_after_launch.png"
fi

rac_tc_drive_catalog
_swift_capture snapshot post_catalog
_swift_regrade_tc07
echo "Swift iOS executor: catalog drive complete"
