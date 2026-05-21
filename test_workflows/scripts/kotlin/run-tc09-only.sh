#!/usr/bin/env bash
# Quick VLM (TC-09) harness check — skips TC-01/06/07/08.
set -euo pipefail

KOTLIN_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${KOTLIN_SCRIPT_DIR}/../../.." && pwd)"
: "${RAC_RUN_ID:?RAC_RUN_ID required}"
: "${RAC_ANDROID_SERIAL:?RAC_ANDROID_SERIAL required}"
export RAC_LANE_SLUG="01_kotlin_android"
export RAC_SESSION_ROOT="${REPO}/test_workflows/logs/runs/${RAC_RUN_ID}/lanes/${RAC_LANE_SLUG}"
export REPO_ROOT="${REPO}"
export PACKAGE_ID="${PACKAGE_ID:-com.runanywhere.runanywhereai.debug}"
export MAIN_ACTIVITY="${MAIN_ACTIVITY:-${PACKAGE_ID}/com.runanywhere.runanywhereai.MainActivity}"

# shellcheck source=../_tc_helper.sh
source "${KOTLIN_SCRIPT_DIR}/../_tc_helper.sh"

export RAC_MCP_SHOT_CMD='adb -s "${RAC_ANDROID_SERIAL}" exec-out screencap -p >'
export RAC_MCP_TAP_CMD='_kotlin_tap'
export RAC_MCP_TYPE_CMD='_kotlin_type'
export RAC_MCP_GREP_CMD='_kotlin_grep'

_kotlin_tap() {
  _kotlin_tap_on_screen "$1" || true
}

_kotlin_type() {
  adb -s "${RAC_ANDROID_SERIAL}" shell input text "${1// /%s}" >/dev/null 2>&1 || true
}

_kotlin_logcat_snapshot() {
  adb -s "${RAC_ANDROID_SERIAL}" logcat -d -t 2500 -s \
    RunAnywhere:* VLM:* VLMViewModel:* ModelSelectionViewModel:* CppBridgeVLM:* 2>/dev/null || true
}

_kotlin_grep() {
  _kotlin_logcat_snapshot | grep -F "$1" >/dev/null 2>&1
}

# shellcheck source=_kotlin_tc_flows.sh
source "${KOTLIN_SCRIPT_DIR}/_kotlin_tc_flows.sh"

rac_tc_init_lane
_kotlin_launch_main
adb -s "${RAC_ANDROID_SERIAL}" shell pm grant "${PACKAGE_ID}" android.permission.CAMERA \
  >/dev/null 2>&1 || true
_kotlin_ensure_foreground "tc09-only" || true
sleep 3
_kotlin_tc09_vlm
