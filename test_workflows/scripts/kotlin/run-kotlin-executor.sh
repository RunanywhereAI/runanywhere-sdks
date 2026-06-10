#!/usr/bin/env bash
# Kotlin Android lane executor — TC-01 + full modality catalog (TC-06..TC-21).
# Drives shared keyframes 007–014 and holds TTS/Voice/RAG until log markers appear.
set -euo pipefail

KOTLIN_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${KOTLIN_SCRIPT_DIR}/../../.." && pwd)"

: "${RAC_RUN_ID:?RAC_RUN_ID required}"
: "${RAC_ANDROID_SERIAL:?RAC_ANDROID_SERIAL required (set via session-manage.sh lane kotlin)}"
export RAC_LANE_SLUG="01_kotlin_android"
RAC_SESSION_ROOT="${REPO}/test_workflows/logs/runs/${RAC_RUN_ID}/lanes/${RAC_LANE_SLUG}"
export RAC_SESSION_ROOT
export REPO_ROOT="${REPO}"

PACKAGE_ID="${PACKAGE_ID:-com.runanywhere.runanywhereai.debug}"
ANDROID_PACKAGE="${ANDROID_PACKAGE:-${PACKAGE_ID}}"
MAIN_ACTIVITY="${MAIN_ACTIVITY:-${PACKAGE_ID}/com.runanywhere.runanywhereai.MainActivity}"
export PACKAGE_ID MAIN_ACTIVITY

# shellcheck source=../_tc_helper.sh
source "${KOTLIN_SCRIPT_DIR}/../_tc_helper.sh"

# Kotlin bottom tabs (catalog §4) — More hub for STT/TTS/VAD/RAG/LoRA/Benchmarks
export RAC_TAB_CHAT="Chat"
export RAC_TAB_VISION="Vision"
export RAC_TAB_VOICE="Voice"
export RAC_TAB_MORE="More"
export RAC_TAB_SETTINGS="Settings"

export RAC_MCP_SHOT_CMD='adb -s "${RAC_ANDROID_SERIAL}" exec-out screencap -p >'
export RAC_MCP_TAP_CMD='_kotlin_tap'
export RAC_MCP_TYPE_CMD='_kotlin_type'
export RAC_MCP_GREP_CMD='_kotlin_grep'

_kotlin_tap() {
  local label="$1"
  _kotlin_tap_on_screen "${label}" || true
}

_kotlin_type() {
  local text="$1"
  adb -s "${RAC_ANDROID_SERIAL}" shell input text "${text// /%s}" >/dev/null 2>&1 || true
}

_kotlin_logcat_snapshot() {
  local tail_lines="${1:-2500}"
  adb -s "${RAC_ANDROID_SERIAL}" logcat -d -t "${tail_lines}" -s \
    RunAnywhere:* VLM:* System.out:* \
    SpeechToTextViewModel:* TextToSpeechViewModel:* VLMViewModel:* \
    ModelSelectionViewModel:* RunAnywhereApplication:* VoiceAssistantViewModel:* \
    RAGViewModel:* LoraViewModel:* CppBridgeVLM:* 2>/dev/null || true
}

_kotlin_grep() {
  local pattern="$1"
  if _kotlin_logcat_snapshot | grep -F "${pattern}" >/dev/null 2>&1; then
    return 0
  fi
  adb -s "${RAC_ANDROID_SERIAL}" logcat -d -t 5000 2>/dev/null | grep -F "${pattern}" >/dev/null 2>&1
}

# shellcheck source=_kotlin_tc_flows.sh
source "${KOTLIN_SCRIPT_DIR}/_kotlin_tc_flows.sh"

rac_tc_init_lane
_kotlin_launch_main
adb -s "${RAC_ANDROID_SERIAL}" shell pm grant "${PACKAGE_ID}" android.permission.RECORD_AUDIO \
  >/dev/null 2>&1 || true
adb -s "${RAC_ANDROID_SERIAL}" shell pm grant "${PACKAGE_ID}" android.permission.CAMERA \
  >/dev/null 2>&1 || true
_kotlin_ensure_foreground "tc01-launch" || true
sleep 5
_kotlin_shot "000_app_launch"
if _kotlin_grep "SDK Phase 1 ready" || _kotlin_grep "${RAC_MARKER_SDK_INIT}"; then
  rac_tc_done tc01 PASS "SDK init seen in logcat" "screenshots/000_app_launch.png"
else
  rac_tc_done tc01 BLOCKED "SDK init marker missing" "screenshots/000_app_launch.png"
fi

# Push RAG JSON fixture before modality sweep (catalog §2)
_kotlin_push_rag_fixture

# Full modality flows — replaces generic rac_tc_drive_catalog (wrong tab labels for Kotlin)
_kotlin_drive_modality_catalog

echo "Kotlin Android executor: modality catalog complete (keyframes 007–014)"
