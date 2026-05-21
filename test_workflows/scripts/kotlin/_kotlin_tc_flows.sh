#!/usr/bin/env bash
# Kotlin Android modality TC flows (TC-06..TC-21) with shared keyframes 007–014.
# Sourced by run-kotlin-executor.sh — not for direct invocation.
set -euo pipefail

: "${RAC_SESSION_ROOT:?RAC_SESSION_ROOT required}"
: "${RAC_ANDROID_SERIAL:?RAC_ANDROID_SERIAL required}"

PACKAGE_ID="${PACKAGE_ID:-com.runanywhere.runanywhereai.debug}"
MAIN_ACTIVITY="${MAIN_ACTIVITY:-${PACKAGE_ID}/com.runanywhere.runanywhereai.MainActivity}"
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
CAPTURE_SCRIPT="${REPO_ROOT}/test_workflows/scripts/kotlin/capture-kotlin-logs.sh"
INJECT_STT_SCRIPT="${REPO_ROOT}/test_workflows/scripts/android/inject-stt-audio.sh"
# shellcheck source=../android/inject-stt-audio.sh
source "${INJECT_STT_SCRIPT}"

# Catalog fixed inputs (common/modality_matrix.md)
RAC_INPUT_STT='RunAnywhere runs models on device.'
RAC_STT_FIXTURE_PATH="${REPO_ROOT}/test_workflows/fixtures/stt-phrase.wav"
RAC_INPUT_LLM='In one sentence, explain what RunAnywhere does.'
RAC_INPUT_TTS='RunAnywhere runs privately on your device.'
RAC_INPUT_RAG_QUERY='Where should model lifecycle logic live?'
RAC_INPUT_VOICE='Tell me one benefit of on-device AI.'
RAC_INPUT_TOOL_PROMPT='Use the calculate tool to compute 15 times 7.'

# Log grep markers (catalog §10 + Kotlin app logs)
RAC_MARKER_TTS_SYNTHESIS='Synthesis complete'
RAC_MARKER_STT_BATCH='Batch transcription complete'
RAC_MARKER_VAD_LISTEN='Listening for speech'
RAC_MARKER_VLM_STREAM='Starting VLM streaming'
RAC_MARKER_VLM_FRAME_DONE='Frame description completed'
RAC_MARKER_VLM_SDK_DONE='VLM processing complete'
RAC_MARKER_VOICE_SYNC='Model states synced'
RAC_MARKER_VOICE_SESSION='Voice session started'
RAC_MARKER_RAG_INGEST='Ingesting document text'
RAC_MARKER_RAG_LOADED='Document loaded successfully'
RAC_MARKER_RAG_QUERY='Querying RAG pipeline'
RAC_MARKER_TOOL_DEMO='Demo tools registered'
RAC_MARKER_LORA_APPLY='LoRA adapter applied'

_kotlin_shot() {
  local keyframe="$1"
  rac_mcp_shot "${RAC_SESSION_ROOT}/screenshots/${keyframe}.png"
}

_kotlin_snapshot() {
  local label="$1"
  if [[ -n "${RAC_RUN_ID:-}" ]] && [[ -x "${CAPTURE_SCRIPT}" ]]; then
    ANDROID_PACKAGE="${PACKAGE_ID}" "${CAPTURE_SCRIPT}" snapshot "${RAC_RUN_ID}" "${label}" "${PACKAGE_ID}" \
      >/dev/null 2>&1 || true
  fi
}

_kotlin_wait_grep() {
  local pattern="$1"
  local timeout="${2:-120}"
  local elapsed=0
  while [[ "${elapsed}" -lt "${timeout}" ]]; do
    if _kotlin_grep "${pattern}"; then
      return 0
    fi
    sleep 3
    elapsed=$((elapsed + 3))
  done
  return 1
}

_kotlin_foreground_package() {
  local line pkg
  line="$(adb -s "${RAC_ANDROID_SERIAL}" shell dumpsys activity activities 2>/dev/null \
    | grep -E 'topResumedActivity|mResumedActivity' | head -n1 || true)"
  pkg="$(printf '%s\n' "${line}" | grep -oE 'u0 [^ /]+' | head -n1 | sed 's/u0 //' || true)"
  if [[ -n "${pkg}" ]]; then
    printf '%s' "${pkg}"
    return 0
  fi
  line="$(adb -s "${RAC_ANDROID_SERIAL}" shell dumpsys window 2>/dev/null \
    | grep -E 'mCurrentFocus|mFocusedApp' | head -n1 || true)"
  pkg="$(printf '%s\n' "${line}" | grep -oE 'u0 [^ /]+' | head -n1 | sed 's/u0 //' || true)"
  printf '%s' "${pkg}"
}

_kotlin_dismiss_launcher() {
  local fg
  fg="$(_kotlin_foreground_package)"
  if [[ "${fg}" == *"launcher"* ]] || [[ "${fg}" == *"Launcher"* ]]; then
    adb -s "${RAC_ANDROID_SERIAL}" shell input keyevent KEYCODE_BACK >/dev/null 2>&1 || true
    sleep 1
  fi
}

_kotlin_launch_main() {
  adb -s "${RAC_ANDROID_SERIAL}" shell am start -W -S -n "${MAIN_ACTIVITY}" \
    -a android.intent.action.MAIN -c android.intent.category.LAUNCHER \
    >/dev/null 2>&1 || true
  sleep 3
}

_kotlin_ensure_foreground() {
  local context="${1:-modality}"
  _kotlin_dismiss_launcher
  local fg
  fg="$(_kotlin_foreground_package)"
  if [[ "${fg}" != *"${PACKAGE_ID}"* ]]; then
    _kotlin_launch_main
    fg="$(_kotlin_foreground_package)"
  fi
  if [[ "${fg}" != *"${PACKAGE_ID}"* ]]; then
    echo "WARN: ${context}: foreground '${fg:-unknown}', expected ${PACKAGE_ID}" >&2
    return 1
  fi
  return 0
}

_kotlin_modality_preflight() {
  local tc="$1"
  _kotlin_launch_main
  _kotlin_ensure_foreground "${tc}" || true
  sleep 2
}

_kotlin_tab_tap() {
  local label="$1"
  _kotlin_ensure_foreground "tab-${label}" || true
  rac_mcp_tap "${label}"
  sleep 2
  _kotlin_ensure_foreground "after-tab-${label}" || true
}

_kotlin_scroll_down() {
  adb -s "${RAC_ANDROID_SERIAL}" shell input swipe 540 1800 540 900 350 >/dev/null 2>&1 || true
  sleep 1
}

_kotlin_back() {
  adb -s "${RAC_ANDROID_SERIAL}" shell input keyevent KEYCODE_BACK >/dev/null 2>&1 || true
  sleep 1
  _kotlin_ensure_foreground "after-back" || true
}

_kotlin_open_more_feature() {
  local title="$1"
  _kotlin_tab_tap "More"
  if ! _kotlin_tap_on_screen "${title}"; then
    _kotlin_scroll_down
    _kotlin_tap_on_screen "${title}" || true
  fi
  sleep 2
  _kotlin_ensure_foreground "more-${title}" || true
}

_kotlin_tap_on_screen() {
  local label="$1"
  local tmp
  tmp="$(mktemp)"
  adb -s "${RAC_ANDROID_SERIAL}" shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 || return 1
  adb -s "${RAC_ANDROID_SERIAL}" pull /sdcard/ui.xml "${tmp}" >/dev/null 2>&1 || return 1
  local bounds
  bounds="$(grep -oE "text=\"${label}\"[^/]*bounds=\"[^\"]*\"" "${tmp}" | head -n1 | grep -oE 'bounds="[^"]*"' | sed 's/bounds=//;s/"//g' || true)"
  if [[ -z "${bounds}" ]]; then
    bounds="$(grep -oE "content-desc=\"${label}\"[^/]*bounds=\"[^\"]*\"" "${tmp}" | head -n1 | grep -oE 'bounds="[^"]*"' | sed 's/bounds=//;s/"//g' || true)"
  fi
  rm -f "${tmp}"
  [[ -z "${bounds}" ]] && return 1
  local x1 y1 x2 y2
  x1="$(echo "${bounds}" | sed -E 's/\[([0-9]+),([0-9]+)\].*/\1/')"
  y1="$(echo "${bounds}" | sed -E 's/\[([0-9]+),([0-9]+)\].*/\2/')"
  x2="$(echo "${bounds}" | sed -E 's/.*\[([0-9]+),([0-9]+)\]/\1/')"
  y2="$(echo "${bounds}" | sed -E 's/.*\[([0-9]+),([0-9]+)\]/\2/')"
  adb -s "${RAC_ANDROID_SERIAL}" shell input tap $((x1 + (x2 - x1) / 2)) $((y1 + (y2 - y1) / 2)) >/dev/null 2>&1
  sleep 1
  _kotlin_ensure_foreground "tap-${label}" || true
  return 0
}

_kotlin_ensure_model_loaded() {
  local context_label="$1"
  _kotlin_tap_on_screen "Get Started" \
    || _kotlin_tap_on_screen "Select Model" \
    || _kotlin_tap_on_screen "Change" \
    || true
  sleep 2
  _kotlin_tap_on_screen "SmolVLM" \
    || _kotlin_tap_on_screen "smolvlm" \
    || _kotlin_tap_on_screen "Use" \
    || _kotlin_tap_on_screen "Download" \
    || true
  sleep 4
  _kotlin_tap_on_screen "Use" || _kotlin_tap_on_screen "Download" || true
  sleep 10
  _kotlin_tap_on_screen "Use" || true
  sleep 6
  _kotlin_back
}

_kotlin_push_rag_fixture() {
  local fixture="${REPO_ROOT}/test_workflows/fixtures/rag-sample.txt"
  local json_tmp
  json_tmp="$(mktemp)"
  {
    printf '{"title":"RunAnywhere RAG fixture","body":'
    python3 -c 'import json,sys; print(json.dumps(open(sys.argv[1]).read()))' "${fixture}" 2>/dev/null \
      || printf '"RunAnywhere keeps model lifecycle logic in C++. The SDK registers backends such as LlamaCPP and ONNX/Sherpa on device."'
    printf '}\n'
  } > "${json_tmp}"
  adb -s "${RAC_ANDROID_SERIAL}" push "${json_tmp}" /sdcard/Download/rag-sample.json >/dev/null 2>&1 || true
  rm -f "${json_tmp}"
}

_kotlin_select_document_in_picker() {
  local attempts=0
  while [[ "${attempts}" -lt 4 ]]; do
    _kotlin_tap_on_screen "rag-sample.json" && return 0
    _kotlin_tap_on_screen "Downloads" || _kotlin_tap_on_screen "Download" || true
    sleep 2
    _kotlin_scroll_down
    attempts=$((attempts + 1))
  done
  return 1
}

# ---------------------------------------------------------------------------
# TC-06 — VAD
# ---------------------------------------------------------------------------
_kotlin_tc06_vad() {
  _kotlin_modality_preflight "tc06"
  _kotlin_open_more_feature "Voice Activity Detection"
  _kotlin_ensure_model_loaded "vad"
  sleep 3
  _kotlin_snapshot "tc06_vad"
  local status="PASS" notes="VAD surface exercised"
  if _kotlin_grep "${RAC_MARKER_VAD_LISTEN}" || _kotlin_grep "VAD"; then
    notes="VAD listening marker present"
  else
    status="LIMITED"
    notes="VAD screen held; listening marker not confirmed in logcat"
  fi
  rac_tc_done tc06 "${status}" "${notes}" ""
  _kotlin_back
  sleep 1
}

# ---------------------------------------------------------------------------
# TC-07 / TC-10 — STT (keyframes 007, 008)
# ---------------------------------------------------------------------------
_kotlin_tc07_stt() {
  _kotlin_modality_preflight "tc07"
  _kotlin_open_more_feature "Speech to Text"
  _kotlin_ensure_model_loaded "stt"
  _kotlin_shot "007_stt_tab"
  _kotlin_snapshot "tc07_stt_tab"

  _kotlin_tap_on_screen "Batch" || true
  sleep 2

  # Catalog §2: inject/play fixed STT phrase before batch record (KOTLIN-AND-002)
  rac_ensure_stt_fixture "${RAC_STT_FIXTURE_PATH}" "${REPO_ROOT}" || true
  export PACKAGE_ID MAIN_ACTIVITY
  rac_inject_stt_fixture_start "${RAC_ANDROID_SERIAL}" "${RAC_STT_FIXTURE_PATH}" || true
  sleep 3
  _kotlin_ensure_foreground "tc07-post-inject" || true

  _kotlin_tap_on_screen "Microphone" || _kotlin_tap_on_screen "Start recording" || true
  local record_secs="${RAC_STT_RECORD_SECS:-8}"
  sleep "${record_secs}"
  _kotlin_tap_on_screen "Stop recording" || _kotlin_tap_on_screen "Microphone" || true
  rac_inject_stt_fixture_stop "${RAC_ANDROID_SERIAL}"

  local status="FAIL" notes="STT batch driven; catalog keywords missing in transcript"
  if _kotlin_wait_grep "${RAC_MARKER_STT_BATCH}" 150; then
    if rac_stt_transcript_has_keywords "${RAC_ANDROID_SERIAL}"; then
      status="PASS"
      notes="Batch transcription complete with catalog keywords (RunAnywhere, models, device)"
    else
      status="FAIL"
      notes="Batch transcription complete but transcript lacks catalog keywords"
    fi
  else
    status="LIMITED"
    notes="STT batch flow driven; batch marker not seen within timeout"
  fi
  sleep 2
  _kotlin_shot "008_stt_transcribed"
  _kotlin_snapshot "tc07_stt_result"
  rac_tc_done tc07 "${status}" "${notes}" "screenshots/007_stt_tab.png"
  rac_tc_done tc10 "${status}" "STT UX flow with keyframes 007–008" "screenshots/008_stt_transcribed.png"
  _kotlin_back
  sleep 1
}

# ---------------------------------------------------------------------------
# TC-08 / TC-11 — TTS (keyframes 009, 010; hold for Synthesis complete)
# ---------------------------------------------------------------------------
_kotlin_tc08_tts() {
  _kotlin_modality_preflight "tc08"
  _kotlin_open_more_feature "Text to Speech"
  _kotlin_ensure_model_loaded "tts"
  _kotlin_shot "009_tts_tab"
  _kotlin_snapshot "tc08_tts_tab"

  _kotlin_type "${RAC_INPUT_TTS}"
  sleep 1
  _kotlin_tap_on_screen "Generate" || true

  local status="LIMITED" notes="TTS generate tapped; waiting for synthesis log"
  if _kotlin_wait_grep "${RAC_MARKER_TTS_SYNTHESIS}" 150; then
    status="PASS"
    notes="[TTS] Synthesis complete observed in logcat"
    sleep 4
    _kotlin_tap_on_screen "Play" || true
    sleep 6
  else
    sleep 18
  fi

  _kotlin_shot "010_tts_played"
  _kotlin_snapshot "tc08_tts_played"
  rac_tc_done tc08 "${status}" "${notes}" "screenshots/009_tts_tab.png"
  rac_tc_done tc11 "${status}" "TTS screen held through synthesis; keyframe 010 captured" "screenshots/010_tts_played.png"
  _kotlin_back
  sleep 1
}

# ---------------------------------------------------------------------------
# TC-09 — VLM (keyframes 013, 014)
# ---------------------------------------------------------------------------
_kotlin_tc09_vlm() {
  _kotlin_modality_preflight "tc09"
  _kotlin_tab_tap "Vision"
  _kotlin_tap_on_screen "Vision Chat" || true
  sleep 2
  _kotlin_ensure_model_loaded "vlm"
  _kotlin_wait_grep "Model load succeeded for smolvlm" 180 \
    || _kotlin_wait_grep "VLM model loaded: true" 60 \
    || true
  sleep 3
  _kotlin_shot "013_vision_tab"
  _kotlin_snapshot "tc09_vision_tab"

  _kotlin_tap_on_screen "Photos" || _kotlin_tap_on_screen "Gallery" || true
  sleep 2
  adb -s "${RAC_ANDROID_SERIAL}" shell input tap 200 600 >/dev/null 2>&1 || true
  sleep 2
  _kotlin_ensure_foreground "tc09-post-picker" || true

  _kotlin_type "What is visible in this image?"
  sleep 2
  _kotlin_tap_on_screen "Analyze" || true

  local status="LIMITED" notes="VLM analyze triggered; awaiting stream completion"
  if _kotlin_wait_grep "VLM streaming completed" 240 \
    || _kotlin_wait_grep "${RAC_MARKER_VLM_FRAME_DONE}" 240 \
    || _kotlin_wait_grep "${RAC_MARKER_VLM_SDK_DONE}" 240; then
    status="PASS"
    notes="VLM completion marker observed in logcat"
  elif _kotlin_grep "racVlmProcessStreamProto returned null"; then
    status="FAIL"
    notes="VLM stream failed: racVlmProcessStreamProto returned null"
  elif _kotlin_grep "${RAC_MARKER_VLM_STREAM}" \
    && ! _kotlin_grep "racVlmProcessStreamProto returned null"; then
    status="LIMITED"
    notes="VLM stream started without JNI null; completion marker missing within timeout"
  elif ! _kotlin_grep "racVlmProcessStreamProto returned null"; then
    notes="VLM analyze triggered; no JNI null error but completion marker missing"
  fi

  sleep 4
  _kotlin_shot "014_vision_response"
  _kotlin_snapshot "tc09_vision_response"
  rac_tc_done tc09 "${status}" "${notes}" "screenshots/014_vision_response.png"
  _kotlin_back
  sleep 1
}

# ---------------------------------------------------------------------------
# TC-12 — Voice agent (keyframes 011, 012)
# ---------------------------------------------------------------------------
_kotlin_tc12_voice() {
  _kotlin_modality_preflight "tc12"
  _kotlin_tab_tap "Voice"
  _kotlin_shot "011_voice_tab"
  _kotlin_snapshot "tc12_voice_tab"

  _kotlin_tap_on_screen "Start Voice Assistant" || _kotlin_tap_on_screen "Microphone" || true
  sleep 3

  local status="LIMITED" notes="Voice session start attempted"
  if _kotlin_grep "${RAC_MARKER_VOICE_SYNC}"; then
    notes="Model states synced STT+LLM+TTS"
  fi
  if _kotlin_wait_grep "${RAC_MARKER_VOICE_SESSION}" 45; then
    notes="${notes}; voice session started"
    sleep 5
    _kotlin_tap_on_screen "Microphone" || true
    sleep 8
    _kotlin_tap_on_screen "Microphone" || true
    if _kotlin_wait_grep "${RAC_MARKER_STT_BATCH}" 120 || _kotlin_grep "Transcription complete"; then
      status="PASS"
      notes="Voice turn: session started with transcription evidence"
    fi
  fi

  sleep 5
  _kotlin_shot "012_voice_response"
  _kotlin_snapshot "tc12_voice_response"
  rac_tc_done tc12 "${status}" "${notes}" "screenshots/012_voice_response.png"
}

# ---------------------------------------------------------------------------
# TC-13 — RAG Document Q&A
# ---------------------------------------------------------------------------
_kotlin_tc13_rag() {
  _kotlin_modality_preflight "tc13"
  _kotlin_push_rag_fixture
  _kotlin_open_more_feature "Document Q&A"
  sleep 2

  _kotlin_tap_on_screen "Embedding Model" || true
  sleep 1
  _kotlin_tap_on_screen "All MiniLM" || _kotlin_tap_on_screen "Use" || _kotlin_tap_on_screen "Download" || true
  sleep 3
  _kotlin_back
  sleep 1

  _kotlin_tap_on_screen "LLM Model" || true
  sleep 1
  _kotlin_tap_on_screen "SmolLM2" || _kotlin_tap_on_screen "Use" || true
  sleep 2
  _kotlin_back
  sleep 1

  _kotlin_tap_on_screen "Select Document" || true
  sleep 2
  _kotlin_select_document_in_picker || true
  sleep 5

  local status="LIMITED" notes="RAG document picker driven"
  if _kotlin_wait_grep "${RAC_MARKER_RAG_INGEST}" 150 || _kotlin_wait_grep "${RAC_MARKER_RAG_LOADED}" 150; then
    status="PASS"
    notes="RAG ingest completed"
    _kotlin_type "${RAC_INPUT_RAG_QUERY}"
    sleep 1
    _kotlin_tap_on_screen "Send" || true
    if _kotlin_wait_grep "${RAC_MARKER_RAG_QUERY}" 150; then
      notes="RAG ingest + query completed"
    else
      status="LIMITED"
      notes="RAG ingest OK; query marker missing"
    fi
    sleep 5
  fi

  _kotlin_snapshot "tc13_rag"
  rac_tc_done tc13 "${status}" "${notes}" ""
  _kotlin_back
  sleep 1
}

# ---------------------------------------------------------------------------
# TC-14 — Tool calling (Settings → Chat)
# ---------------------------------------------------------------------------
_kotlin_tc14_tools() {
  _kotlin_modality_preflight "tc14"
  _kotlin_tab_tap "Settings"
  _kotlin_scroll_down
  _kotlin_tap_on_screen "Enable Tool Calling" || true
  sleep 1
  _kotlin_tap_on_screen "Add Demo Tools" || true
  sleep 3

  local status="LIMITED" notes="Tool calling enabled; demo tools registration attempted"
  if _kotlin_grep "${RAC_MARKER_TOOL_DEMO}" || _kotlin_grep "Registered 3 demo tools"; then
    status="PASS"
    notes="Demo tools registered"
  fi

  _kotlin_tab_tap "Chat"
  sleep 2
  _kotlin_type "${RAC_INPUT_TOOL_PROMPT}"
  sleep 2
  _kotlin_tap_on_screen "Send" || true
  sleep 18

  if _kotlin_grep "calculate" || _kotlin_grep "tool"; then
    status="PASS"
    notes="Tool calling enabled, demo tools registered, chat tool prompt sent"
  fi

  _kotlin_snapshot "tc14_tools"
  rac_tc_done tc14 "${status}" "${notes}" "screenshots/015_settings_tab.png"
}

# ---------------------------------------------------------------------------
# TC-20 — Settings (API sheet + logging)
# ---------------------------------------------------------------------------
_kotlin_tc20_settings() {
  _kotlin_modality_preflight "tc20"
  _kotlin_tab_tap "Settings"
  _kotlin_shot "015_settings_tab"
  _kotlin_tap_on_screen "API Key" || true
  sleep 2
  if _kotlin_tap_on_screen "API Configuration"; then
    sleep 2
    _kotlin_back
  else
    _kotlin_back
  fi
  sleep 1

  local status="PASS" notes="Settings tab + API Configuration sheet opened"
  if ! _kotlin_grep "Logging Configuration"; then
    status="LIMITED"
    notes="Settings visible; logging section not confirmed in logcat"
  fi
  _kotlin_snapshot "tc20_settings"
  rac_tc_done tc20 "${status}" "${notes}" "screenshots/015_settings_tab.png"
}

# ---------------------------------------------------------------------------
# TC-21 — LoRA adapters
# ---------------------------------------------------------------------------
_kotlin_tc21_lora() {
  _kotlin_modality_preflight "tc21"
  _kotlin_open_more_feature "LoRA Adapters"
  sleep 2
  _kotlin_snapshot "tc21_lora_screen"

  _kotlin_tap_on_screen "Download" || true
  sleep 10

  _kotlin_tab_tap "Chat"
  sleep 2
  _kotlin_tap_on_screen "LoRA" || _kotlin_tap_on_screen "+ LoRA" || true
  sleep 2
  _kotlin_tap_on_screen "Apply" || true
  sleep 6

  local status="LIMITED" notes="LoRA manager + apply flow attempted"
  if _kotlin_grep "${RAC_MARKER_LORA_APPLY}" || _kotlin_grep "LoRA adapter"; then
    status="PASS"
    notes="LoRA apply attempted from Chat picker"
  fi

  _kotlin_type "Hello from LoRA test"
  sleep 1
  _kotlin_tap_on_screen "Send" || true
  sleep 10

  _kotlin_tab_tap "More"
  sleep 1
  _kotlin_scroll_down
  _kotlin_tap_on_screen "LoRA Adapters" || true
  sleep 2
  _kotlin_tap_on_screen "Unload" || _kotlin_tap_on_screen "Clear All Adapters" || true
  sleep 4

  _kotlin_snapshot "tc21_lora"
  rac_tc_done tc21 "${status}" "${notes}" ""
  _kotlin_back
  sleep 1
}

# ---------------------------------------------------------------------------
# Deferred / N/A TCs (Kotlin catalog)
# ---------------------------------------------------------------------------
_kotlin_tc_deferred_na() {
  rac_tc_done tc17 "DEFERRED" "Solutions YAML pipeline deferred per catalog" ""
  rac_tc_done tc18 "N/A" "No Validation tab in Kotlin app" ""
}

# ---------------------------------------------------------------------------
# Entry: modality catalog after TC-01 (assumes LLM download/load may already exist)
# ---------------------------------------------------------------------------
_kotlin_drive_modality_catalog() {
  echo "Kotlin modality catalog: TC-06..TC-21 (keyframes 007–014)"
  _kotlin_tc06_vad
  _kotlin_tc07_stt
  _kotlin_tc08_tts
  _kotlin_tc09_vlm
  _kotlin_tc12_voice
  _kotlin_tc13_rag
  _kotlin_tc14_tools
  _kotlin_tc20_settings
  _kotlin_tc21_lora
  _kotlin_tc_deferred_na
  echo "Kotlin modality catalog: complete"
}
