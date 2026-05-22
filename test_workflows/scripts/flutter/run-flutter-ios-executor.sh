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

export RAC_TC13_DRIVE_CMD='_flutter_drive_tc13_rag'
export RAC_MCP_KILL_CMD='xcrun simctl terminate "${RAC_IOS_SIM_UDID}" "${FLUTTER_BUNDLE_ID}"'
export RAC_MCP_LAUNCH_CMD='xcrun simctl launch "${RAC_IOS_SIM_UDID}" "${FLUTTER_BUNDLE_ID}"'

export RAC_MCP_SHOT_CMD='xcrun simctl io "${RAC_IOS_SIM_UDID}" screenshot'
export RAC_MCP_TAP_CMD='_flutter_ios_tap'
export RAC_MCP_TYPE_CMD='xcrun simctl io "${RAC_IOS_SIM_UDID}" send-text'
export RAC_MCP_GREP_CMD='_flutter_grep_logs'

_flutter_ios_tap() {
  local label="$1"
  xcrun simctl ui "${RAC_IOS_SIM_UDID}" tap --label "${label}" >/dev/null 2>&1 || true
}

rac_tc_init_lane
sleep 5
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
echo "Flutter iOS executor: catalog + deep modality drive complete"
