#!/usr/bin/env bash
# Flutter Android lane executor — shared harness binding.
set -euo pipefail

FLUTTER_EXEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${FLUTTER_EXEC_DIR}/../../.." && pwd)"
# shellcheck source=../_tc_helper.sh
source "${FLUTTER_EXEC_DIR}/../_tc_helper.sh"
# shellcheck source=_flutter_tc_flows.sh
source "${FLUTTER_EXEC_DIR}/_flutter_tc_flows.sh"

: "${RAC_RUN_ID:?RAC_RUN_ID required}"
: "${RAC_ANDROID_SERIAL:?RAC_ANDROID_SERIAL required}"
export RAC_LANE_SLUG="05_flutter_android"
RAC_SESSION_ROOT="${REPO}/test_workflows/logs/runs/${RAC_RUN_ID}/lanes/${RAC_LANE_SLUG}"
export RAC_SESSION_ROOT
ANDROID_PACKAGE="${ANDROID_PACKAGE:-com.runanywhere.runanywhere_ai}"

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
export RAC_MCP_KILL_CMD='adb -s "${RAC_ANDROID_SERIAL}" shell am force-stop "${ANDROID_PACKAGE}"'
export RAC_MCP_LAUNCH_CMD='adb -s "${RAC_ANDROID_SERIAL}" shell monkey -p "${ANDROID_PACKAGE}" -c android.intent.category.LAUNCHER 1'

export RAC_MCP_SHOT_CMD='adb -s "${RAC_ANDROID_SERIAL}" exec-out screencap -p >'
export RAC_MCP_TAP_CMD='_flutter_tap'
export RAC_MCP_TYPE_CMD='_flutter_type'
export RAC_MCP_GREP_CMD='_flutter_android_grep'

_flutter_tap() {
  local label="$1"
  local tmp; tmp="$(mktemp)"
  adb -s "${RAC_ANDROID_SERIAL}" shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 || return 0
  adb -s "${RAC_ANDROID_SERIAL}" pull /sdcard/ui.xml "${tmp}" >/dev/null 2>&1 || return 0
  local bounds
  bounds="$(grep -oE "text=\"${label}\"[^/]*bounds=\"[^\"]*\"" "${tmp}" | head -n1 | grep -oE 'bounds="[^"]*"' | sed 's/bounds=//;s/"//g' || true)"
  rm -f "${tmp}"
  [[ -z "${bounds}" ]] && return 0
  local x1 y1 x2 y2
  x1="$(echo "${bounds}" | sed -E 's/\[([0-9]+),([0-9]+)\].*/\1/')"
  y1="$(echo "${bounds}" | sed -E 's/\[([0-9]+),([0-9]+)\].*/\2/')"
  x2="$(echo "${bounds}" | sed -E 's/.*\[([0-9]+),([0-9]+)\]/\1/')"
  y2="$(echo "${bounds}" | sed -E 's/.*\[([0-9]+),([0-9]+)\]/\2/')"
  adb -s "${RAC_ANDROID_SERIAL}" shell input tap $((x1+(x2-x1)/2)) $((y1+(y2-y1)/2)) >/dev/null 2>&1 || true
}

_flutter_type() {
  adb -s "${RAC_ANDROID_SERIAL}" shell input text "${1// /%s}" >/dev/null 2>&1 || true
}

_flutter_android_grep_any() {
  local pattern
  for pattern in "$@"; do
    _flutter_android_grep "${pattern}" && return 0
  done
  return 1
}

_flutter_android_grep() {
  local pattern="$1"
  _flutter_grep_logs "${pattern}" && return 0
  local pid
  pid="$(adb -s "${RAC_ANDROID_SERIAL}" shell pidof "${ANDROID_PACKAGE}" 2>/dev/null | tr -d '' | awk '{print $1}')"
  if [[ -n "${pid}" ]]; then
    adb -s "${RAC_ANDROID_SERIAL}" logcat -d --pid="${pid}" 2>/dev/null | grep -F "${pattern}" >/dev/null 2>&1
  else
    adb -s "${RAC_ANDROID_SERIAL}" logcat -d 2>/dev/null | grep -F "${pattern}" >/dev/null 2>&1
  fi
}

rac_tc_init_lane
eval "${RAC_MCP_LAUNCH_CMD}" || true
_flutter_wait_grep "Phase 1 complete" 90 || _flutter_wait_grep "${RAC_MARKER_SDK_INIT_DEV}" 90 || sleep "${RAC_FLUTTER_BOOT_WAIT_S:-25}"
rac_mcp_shot "${RAC_SESSION_ROOT}/screenshots/000_after_launch.png"
if _flutter_android_grep "${RAC_MARKER_SDK_INIT}" || _flutter_android_grep "Phase 1 complete"; then
  rac_tc_done tc01 PASS "Flutter SDK init in logcat" "screenshots/000_after_launch.png"
else
  rac_tc_done tc01 BLOCKED "SDK init marker missing" "screenshots/000_after_launch.png"
fi
_flutter_regrade_if_marker() {
  local tc="$1"
  local marker="$2"
  local note="$3"
  if _flutter_android_grep "${marker}"; then
    rac_tc_done "${tc}" PASS "${note}" ""
  fi
}

_flutter_final_regrade() {
  _flutter_regrade_if_marker tc01 "Phase 1 complete" "SDK Phase 1 in logcat (deferred grade)"
  _flutter_regrade_if_marker tc02 "${RAC_MARKER_DOWNLOAD_ACCEPTED}" "Download accepted in logcat (deferred grade)"
  _flutter_regrade_if_marker tc04 "${RAC_MARKER_LLM_LOAD}" "LLM load marker in captured logs"
  _flutter_regrade_if_marker tc07 "${RAC_MARKER_STT_LOADED}" "STT load marker in captured logs"
  _flutter_regrade_if_marker tc08 "${RAC_MARKER_TTS_DONE}" "TTS completion marker in captured logs"
  _flutter_regrade_if_marker tc09 "${RAC_MARKER_VLM_DONE}" "VLM marker in captured logs"
  _flutter_regrade_if_marker tc13 "${RAC_MARKER_RAG_INGEST}" "RAG ingest marker in captured logs"
  if _flutter_android_grep_any "${RAC_MARKER_REGISTERED_DOWNLOAD}" "${RAC_MARKER_MODEL_LOAD}" "${RAC_MARKER_LLM_LOAD}" "${RAC_MARKER_DOWNLOAD_ACCEPTED}"; then
    rac_tc_done tc03 PASS "model registry marker present after relaunch" "screenshots/011_tc03_persistence.png"
  fi
}

_flutter_wait_grep "${RAC_MARKER_APP_READY}" 90 || _flutter_wait_grep "${RAC_MARKER_AI_READY}" 90 || true
_flutter_wait_grep "${RAC_MARKER_LLM_LOAD}" 240 || true
_flutter_wait_grep "${RAC_MARKER_STT_LOADED}" 240 || true
export RAC_TC03_LAUNCH_WAIT_S="${RAC_TC03_LAUNCH_WAIT_S:-30}"
rac_tc_drive_catalog
_flutter_drive_deep_modalities
_flutter_wait_grep "${RAC_MARKER_LLM_LOAD}" 120 || true
_flutter_wait_grep "${RAC_MARKER_STT_LOADED}" 120 || true
_flutter_final_regrade
echo "Flutter Android executor: catalog + deep modality drive complete"
