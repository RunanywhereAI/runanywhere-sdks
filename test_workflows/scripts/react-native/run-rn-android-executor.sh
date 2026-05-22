#!/usr/bin/env bash
# React Native Android lane executor — drives TC-02..TC-21 via shared harness.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=../_tc_helper.sh
source "${SCRIPT_DIR}/../_tc_helper.sh"
# shellcheck source=_rn_tc_flows.sh
source "${SCRIPT_DIR}/_rn_tc_flows.sh"

: "${RAC_RUN_ID:?RAC_RUN_ID required}"
: "${RAC_ANDROID_SERIAL:?RAC_ANDROID_SERIAL required}"
export RAC_LANE_SLUG="03_react_native_android"
RAC_SESSION_ROOT="${REPO}/test_workflows/logs/runs/${RAC_RUN_ID}/lanes/${RAC_LANE_SLUG}"
export RAC_SESSION_ROOT
PACKAGE_ID="${PACKAGE_ID:-com.runanywhereaI}"

mkdir -p "${RAC_SESSION_ROOT}/logs"
"${SCRIPT_DIR}/ensure-metro.sh" "${RAC_SESSION_ROOT}/logs/metro.log"
"${SCRIPT_DIR}/capture-react-native-logs.sh" start "${RAC_RUN_ID}" android

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

_rn_android_shot() {
  local out="$1"
  adb -s "${RAC_ANDROID_SERIAL}" exec-out screencap -p > "${out}" 2>/dev/null || true
}

_rn_android_tap() {
  local label="$1"
  local tmp
  tmp="$(mktemp)"
  if ! adb -s "${RAC_ANDROID_SERIAL}" shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; then
    rm -f "${tmp}"
    return 0
  fi
  adb -s "${RAC_ANDROID_SERIAL}" pull /sdcard/ui.xml "${tmp}" >/dev/null 2>&1 || true
  local bounds
  bounds="$(grep -oE "(content-desc|text)=\"${label}\"[^/]*bounds=\"[^\"]*\"" "${tmp}" | head -n1 | grep -oE 'bounds="[^"]*"' | sed 's/bounds=//;s/"//g' || true)"
  rm -f "${tmp}"
  [[ -z "${bounds}" ]] && return 0
  local x1 y1 x2 y2
  x1="$(echo "${bounds}" | sed -E 's/\[([0-9]+),([0-9]+)\].*/\1/')"
  y1="$(echo "${bounds}" | sed -E 's/\[([0-9]+),([0-9]+)\].*/\2/')"
  x2="$(echo "${bounds}" | sed -E 's/.*\[([0-9]+),([0-9]+)\]/\1/')"
  y2="$(echo "${bounds}" | sed -E 's/.*\[([0-9]+),([0-9]+)\]/\2/')"
  adb -s "${RAC_ANDROID_SERIAL}" shell input tap $((x1+(x2-x1)/2)) $((y1+(y2-y1)/2)) >/dev/null 2>&1 || true
}

_rn_android_type() {
  local text="$1"
  adb -s "${RAC_ANDROID_SERIAL}" shell input text "${text// /%s}" >/dev/null 2>&1 || true
}

_rn_android_grep() {
  local pattern="$1"
  _rn_grep_logs "${pattern}" && return 0
  local pid
  pid="$(adb -s "${RAC_ANDROID_SERIAL}" shell pidof "${PACKAGE_ID}" 2>/dev/null | tr -d '\r' | awk '{print $1}')"
  if [[ -n "${pid}" ]]; then
    adb -s "${RAC_ANDROID_SERIAL}" logcat -d --pid="${pid}" 2>/dev/null | grep -F "${pattern}" >/dev/null 2>&1
  else
    adb -s "${RAC_ANDROID_SERIAL}" logcat -d 2>/dev/null | grep -F "${pattern}" >/dev/null 2>&1
  fi
}

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
echo "RN Android executor: catalog + deep modality drive complete"
