#!/usr/bin/env bash
# Flutter iOS lane executor — shared harness binding.
set -euo pipefail

FLUTTER_EXEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${FLUTTER_EXEC_DIR}/../../.." && pwd)"
# shellcheck source=../_tc_helper.sh
source "${FLUTTER_EXEC_DIR}/../_tc_helper.sh"
# shellcheck source=_flutter_tc_flows.sh
source "${FLUTTER_EXEC_DIR}/_flutter_tc_flows.sh"

: "${RAC_RUN_ID:?RAC_RUN_ID required}"
export RAC_LANE_SLUG="06_flutter_ios"
export RAC_IOS_SIM_UDID="${RAC_IOS_SIM_UDID:-booted}"
export RAC_TC03_LAUNCH_WAIT_S="${RAC_TC03_LAUNCH_WAIT_S:-120}"
RAC_SESSION_ROOT="${REPO}/test_workflows/logs/runs/${RAC_RUN_ID}/lanes/${RAC_LANE_SLUG}"
export RAC_SESSION_ROOT
FLUTTER_BUNDLE_ID="${FLUTTER_BUNDLE_ID:-com.runanywhere.runanywhereAi}"

export RAC_TAB_CHAT="Chat"
export RAC_TAB_TRANSCRIBE="STT"
export RAC_TAB_SPEAK="Speak"
export RAC_TAB_VISION="Vision"
export RAC_TAB_VOICE="Voice"
export RAC_TAB_DOCS=""
export RAC_TAB_STORAGE="Settings"
export RAC_TAB_SETTINGS="Settings"
export RAC_TAB_VALIDATION=""

export RAC_TC_DEFER="tc07,tc10,tc08,tc09,tc13"
export RAC_TC_DEFER_NOTE="dedicated Flutter modality flows"

export RAC_TC13_DRIVE_CMD='_flutter_drive_tc13_rag'
export RAC_MCP_KILL_CMD='xcrun simctl terminate "${RAC_IOS_SIM_UDID}" "${FLUTTER_BUNDLE_ID}" >/dev/null 2>&1 || true'
export RAC_MCP_LAUNCH_CMD='xcrun simctl launch "${RAC_IOS_SIM_UDID}" "${FLUTTER_BUNDLE_ID}"'

export RAC_MCP_SHOT_CMD='xcrun simctl io "${RAC_IOS_SIM_UDID}" screenshot'
export RAC_MCP_TAP_CMD='_flutter_ios_tap'

_flutter_ios_type() {
  local text="$1"
  osascript >/dev/null 2>&1 <<APPLESCRIPT || true
tell application "Simulator" to activate
delay 0.2
tell application "System Events"
  keystroke "${text}"
end tell
APPLESCRIPT
}

export RAC_MCP_TYPE_CMD='_flutter_ios_type'
export RAC_MCP_GREP_CMD='_flutter_grep_logs'


_flutter_launch_app() {
  open -a Simulator >/dev/null 2>&1 || true
  xcrun simctl terminate "${RAC_IOS_SIM_UDID}" "com.runanywhere.RunAnywhere" >/dev/null 2>&1 || true
  xcrun simctl launch "${RAC_IOS_SIM_UDID}" "${FLUTTER_BUNDLE_ID}" >/dev/null 2>&1 || true
  sleep 3
}

_flutter_ios_tap() {
  local label="$1"
  xcrun simctl ui "${RAC_IOS_SIM_UDID}" tap --label "${label}" >/dev/null 2>&1 || true
}


_flutter_finalize_lane_grades() {
  if _flutter_grep_logs "${RAC_MARKER_DOWNLOAD_ACCEPTED}"; then
    rac_tc_done tc02 PASS "download accepted marker in captured logs" "screenshots/010_download.png"
  fi
  if _flutter_grep_logs "${RAC_MARKER_MODEL_LOAD}" || _flutter_grep_logs "${RAC_MARKER_REGISTERED_DOWNLOAD}" || _flutter_grep_logs "LLM model loaded"; then
    rac_tc_done tc04 PASS "model load/registry marker in captured logs" "screenshots/011_load.png"
  fi
  if _flutter_grep_logs "${RAC_MARKER_TTS_DONE}" || _flutter_grep_logs "Speech generation complete"; then
    rac_tc_done tc08 PASS "TTS completion marker in captured logs" "screenshots/009_tts_tab.png"
  fi
  if _flutter_grep_logs "${RAC_MARKER_VLM_DONE}" || _flutter_grep_logs "VLM streaming completed"; then
    rac_tc_done tc09 PASS "VLM marker in captured logs" "screenshots/014_vision_tab.png"
  fi
  if _flutter_grep_logs "${RAC_MARKER_RAG_INGEST}" || _flutter_grep_logs "Document loaded successfully"; then
    rac_tc_done tc13 PASS "RAG/document marker in captured logs" "screenshots/018_tc13_rag.png"
  fi
}

rac_tc_init_lane
_flutter_launch_app
sleep "${RAC_FLUTTER_IOS_BOOT_WAIT_S:-120}"
rac_mcp_shot "${RAC_SESSION_ROOT}/screenshots/000_after_launch.png"
if _flutter_grep_logs "${RAC_MARKER_SDK_INIT}" \
  || _flutter_grep_logs "SDK Phase 1" \
  || _flutter_grep_logs "Phase 1 complete"; then
  rac_tc_done tc01 PASS "Flutter iOS SDK init in captured console/ios logs" "screenshots/000_after_launch.png"
else
  rac_tc_done tc01 BLOCKED "SDK init marker missing in flutter_run_console/ios_live logs" "screenshots/000_after_launch.png"
fi
rac_tc_drive_catalog
_flutter_drive_deep_modalities
_flutter_finalize_lane_grades

echo "Flutter iOS executor: catalog + deep modality drive complete"
