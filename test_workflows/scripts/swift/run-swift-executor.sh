#!/usr/bin/env bash
# Swift iOS lane executor — drives TC-02..TC-21 via the shared mobile harness.
set -euo pipefail

SWIFT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${SWIFT_SCRIPT_DIR}/../../.." && pwd)"
export REPO
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
export RAC_SETTINGS_PRE_SCROLL_CMD='_swift_scroll_settings_down'
export RAC_SWIFT_MORE_HUB_LABELS="Transcribe Speak Document Q&A Storage Voice Detection"

export RAC_MCP_SHOT_CMD='_swift_shot'
export RAC_MCP_TAP_CMD='_swift_tap'
export RAC_MCP_TYPE_CMD='_swift_type'
export RAC_MCP_GREP_CMD='_swift_grep'

# TC-07/10 need the dedicated STT download flow; catalog must not stamp LIMITED early.
export RAC_TC_DEFER="tc07,tc10,tc08,tc09,tc13"
export RAC_TC_DEFER_NOTE="dedicated modality flows"

_swift_shot() {
  local out="$1"
  xcrun simctl io "${RAC_IOS_SIM_UDID}" screenshot "${out}" >/dev/null 2>&1 || true
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

_swift_finalize_ran=0
_swift_stt_flow_started=0
_swift_finalize_once() {
  [[ "${_swift_finalize_ran}" -eq 1 ]] && return 0
  [[ "${_swift_stt_flow_started}" -eq 1 ]] || return 0
  _swift_finalize_ran=1
  _swift_finalize_tc07_tc10
}

_swift_on_exit() {
  _swift_finalize_once
  _swift_capture_stop
}

trap _swift_on_exit EXIT
_swift_capture start

rac_tc_init_lane
_swift_sim_privacy_grants
_swift_launch_app
sleep 5
_swift_dismiss_chat_onboarding
rac_mcp_shot "${RAC_SESSION_ROOT}/screenshots/000_after_launch.png"
_swift_capture snapshot tc01_init
if _swift_tc01_ready; then
  rac_tc_done tc01 PASS "SDK init or app-ready marker in sim logs" "screenshots/000_after_launch.png"
else
  rac_tc_done tc01 BLOCKED "no SDK init / app-ready marker in captured logs" "screenshots/000_after_launch.png"
fi

rac_tc_drive_catalog
_swift_drive_stt_download
_swift_capture snapshot post_stt
_swift_drive_tc08_tts
_swift_drive_tc09_vlm
_swift_drive_tc13_rag
_swift_finalize_once
_swift_drive_tc19_benchmarks
_swift_capture snapshot post_tc19 2>/dev/null || true
echo "Swift iOS executor: catalog drive complete"
