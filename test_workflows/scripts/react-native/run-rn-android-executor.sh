#!/usr/bin/env bash
# React Native Android lane executor — drives TC-02..TC-21 via shared harness.
set -euo pipefail

RAC_RN_EXEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${RAC_RN_EXEC_DIR}/../../.." && pwd)"

# shellcheck source=../_tc_helper.sh
source "${RAC_RN_EXEC_DIR}/../_tc_helper.sh"
# shellcheck source=_rn_tc_flows.sh
source "${RAC_RN_EXEC_DIR}/_rn_tc_flows.sh"
# shellcheck source=_rn_android_lib.sh
source "${RAC_RN_EXEC_DIR}/_rn_android_lib.sh"

: "${RAC_RUN_ID:?RAC_RUN_ID required}"
: "${RAC_ANDROID_SERIAL:?RAC_ANDROID_SERIAL required}"
export RAC_LANE_SLUG="03_react_native_android"
RAC_SESSION_ROOT="${REPO}/test_workflows/logs/runs/${RAC_RUN_ID}/lanes/${RAC_LANE_SLUG}"
export RAC_SESSION_ROOT
PACKAGE_ID="${PACKAGE_ID:-com.runanywhereaI}"

mkdir -p "${RAC_SESSION_ROOT}/logs"
"${RAC_RN_EXEC_DIR}/ensure-metro.sh" "${RAC_SESSION_ROOT}/logs/metro.log"

# Ensure RN bundle can reach Metro on the host (RN-AND-006).
# adb reverse must be re-applied per device/session — running after
# install / before app launch is the safe spot.
adb -s "${RAC_ANDROID_SERIAL}" reverse tcp:8081 tcp:8081 \
  >> "${RAC_SESSION_ROOT}/logs/adb_reverse.log" 2>&1 || true

"${RAC_RN_EXEC_DIR}/capture-react-native-logs.sh" start "${RAC_RUN_ID}" android

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
export RAC_MCP_KILL_CMD='adb -s "${RAC_ANDROID_SERIAL}" shell am force-stop "${PACKAGE_ID}"'
export RAC_MCP_LAUNCH_CMD='adb -s "${RAC_ANDROID_SERIAL}" shell monkey -p "${PACKAGE_ID}" -c android.intent.category.LAUNCHER 1'

export RAC_MCP_SHOT_CMD='_rn_android_shot'
export RAC_MCP_TAP_CMD='_rn_android_tap'
export RAC_MCP_TYPE_CMD='_rn_android_type'
export RAC_MCP_GREP_CMD='_rn_android_grep'

rac_tc_init_lane
sleep 5
rac_mcp_shot "${RAC_SESSION_ROOT}/screenshots/000_after_launch.png"
if _rn_android_grep "[App] All models registered" \
  || _rn_android_grep "[App] SDK initialized in DEVELOPMENT mode" \
  || _rn_android_grep "${RAC_MARKER_SDK_INIT}"; then
  rac_tc_done tc01 PASS "SDK/JS init in metro or pid-filtered logcat" "screenshots/000_after_launch.png"
else
  rac_tc_done tc01 BLOCKED "SDK init marker missing in metro/logcat" "screenshots/000_after_launch.png"
fi

rac_tc_drive_catalog
_rn_drive_deep_modalities
_rn_drive_validation_harness
echo "RN Android executor: catalog + deep modality + validation harness complete"
