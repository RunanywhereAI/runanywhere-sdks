#!/usr/bin/env bash
# React Native iOS lane executor — ensures Metro is running before drive.
set -euo pipefail

RAC_RN_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="${RAC_RN_SCRIPT_DIR}"
REPO="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=../_tc_helper.sh
source "${RAC_RN_SCRIPT_DIR}/../_tc_helper.sh"
# shellcheck source=_rn_tc_flows.sh
source "${RAC_RN_SCRIPT_DIR}/_rn_tc_flows.sh"

: "${RAC_RUN_ID:?RAC_RUN_ID required}"
export RAC_LANE_SLUG="04_react_native_ios"
export RAC_IOS_SIM_UDID="${RAC_IOS_SIM_UDID:-booted}"
RAC_SESSION_ROOT="${REPO}/test_workflows/logs/runs/${RAC_RUN_ID}/lanes/${RAC_LANE_SLUG}"
export RAC_SESSION_ROOT
BUNDLE_ID="${BUNDLE_ID:-com.runanywhere.runanywhereai}"

mkdir -p "${RAC_SESSION_ROOT}/logs"
"${RAC_RN_SCRIPT_DIR}/ensure-metro.sh" "${RAC_SESSION_ROOT}/logs/metro.log"

# Simulator cycle pre-step (RN-IOS-009): when an explicit UDID is
# provided, shut down stale boots and boot the target before driving
# the lane. Skip when the caller asked for the implicit "booted"
# simulator since shutting down would steal another agent's sim.
if [[ "${RAC_IOS_SIM_UDID}" != "booted" ]]; then
  {
    xcrun simctl shutdown all 2>&1 || true
    xcrun simctl boot "${RAC_IOS_SIM_UDID}" 2>&1 || true
    xcrun simctl bootstatus "${RAC_IOS_SIM_UDID}" -b 2>&1 || true
  } >> "${RAC_SESSION_ROOT}/logs/simctl_boot.log"
fi

"${RAC_RN_SCRIPT_DIR}/capture-react-native-logs.sh" start "${RAC_RUN_ID}" ios

export RAC_TAB_CHAT="Chat"
export RAC_TAB_TRANSCRIBE="Transcribe"
export RAC_TAB_SPEAK="Speak"
export RAC_TAB_VISION="Vision"
export RAC_TAB_VOICE="Voice"
export RAC_TAB_DOCS="RAG"
export RAC_TAB_STORAGE="Settings"
export RAC_TAB_SETTINGS="Settings"
export RAC_TAB_VALIDATION="Validation"

export RAC_TC13_DRIVE_CMD='_rn_drive_tc13_rag'
export RAC_MCP_KILL_CMD='xcrun simctl terminate "${RAC_IOS_SIM_UDID}" "${BUNDLE_ID}" >/dev/null 2>&1 || true'
export RAC_MCP_LAUNCH_CMD='xcrun simctl launch "${RAC_IOS_SIM_UDID}" "${BUNDLE_ID}" >/dev/null 2>&1 || true'

export RAC_MCP_SHOT_CMD='xcrun simctl io "${RAC_IOS_SIM_UDID}" screenshot'
export RAC_MCP_TAP_CMD='_rn_ios_tap'
export RAC_MCP_TYPE_CMD='xcrun simctl io "${RAC_IOS_SIM_UDID}" send-text'
export RAC_MCP_GREP_CMD='_rn_grep_logs'

_rn_ios_tap() {
  local label="$1"
  if [[ -n "${RAC_MCP_TAP_HTTP:-}" ]]; then
    curl -fsS -X POST "${RAC_MCP_TAP_HTTP}" --data-urlencode "label=${label}" >/dev/null 2>&1 || true
    return 0
  fi
  xcrun simctl ui "${RAC_IOS_SIM_UDID}" tap --label "${label}" >/dev/null 2>&1 || true
}

rac_tc_init_lane
sleep 8
rac_mcp_shot "${RAC_SESSION_ROOT}/screenshots/000_after_launch.png"
if _rn_grep_logs "[App] All models registered" \
  || _rn_grep_logs "[App] SDK initialized in DEVELOPMENT mode" \
  || _rn_grep_logs "${RAC_MARKER_SDK_INIT}"; then
  rac_tc_done tc01 PASS "App + JS bundle ready (metro.log)" "screenshots/000_after_launch.png"
else
  rac_tc_done tc01 BLOCKED "no JS-side ready marker in metro/ios logs" "screenshots/000_after_launch.png"
fi

rac_tc_drive_catalog
_rn_drive_deep_modalities
echo "RN iOS executor: catalog + deep modality drive complete"
