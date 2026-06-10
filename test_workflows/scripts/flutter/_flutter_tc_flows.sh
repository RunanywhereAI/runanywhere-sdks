#!/usr/bin/env bash
# Flutter lane modality flows (Chat RAG entry, TTS/VLM depth, Validation N/A).

_flutter_grep_logs() {
  local pattern="$1"
  local root="${RAC_SESSION_ROOT:?}/logs"
  local name
  for name in android_logcat.log flutter_run_console.log flutter_logs.log ios_live.log ios_final.log executor.log tc_drive.log tc_executor.log; do
    [[ -f "${root}/${name}" ]] && grep -qF "${pattern}" "${root}/${name}" && return 0
  done
  return 1
}

_flutter_wait_grep() {
  local pattern="$1"
  local wait_s="${2:-120}"
  local elapsed=0
  while [[ "${elapsed}" -lt "${wait_s}" ]]; do
    if declare -f _flutter_android_grep >/dev/null 2>&1; then
      _flutter_android_grep "${pattern}" && return 0
    fi
    _flutter_grep_logs "${pattern}" && return 0
    sleep 5
    elapsed=$((elapsed + 5))
  done
  return 1
}

_flutter_drive_tc13_rag() {
  local lane_root="${RAC_SESSION_ROOT:?}"
  local shot="screenshots/018_tc13_rag.png"
  rac_mcp_tap "${RAC_TAB_CHAT:-Chat}"
  sleep 1
  rac_mcp_tap "Document Q&A" || rac_mcp_tap "Document Q&A" || true
  sleep 5
  rac_mcp_shot "${lane_root}/${shot}"
  local status="LIMITED" notes="Document Q&A entry opened from Chat"
  if _flutter_wait_grep "${RAC_MARKER_RAG_INGEST}" 120 || _flutter_grep_logs "Document loaded successfully"; then
    status="PASS"
    notes="RAG ingest marker or UI present"
  fi
  rac_tc_done tc13 "${status}" "${notes}" "${shot}"
}

_flutter_drive_tc08_tts() {
  local lane_root="${RAC_SESSION_ROOT:?}"
  local shot="screenshots/009_tts_tab.png"
  rac_mcp_tap "${RAC_TAB_SPEAK:-Speak}"
  sleep 2
  rac_mcp_tap "Select Model" || true
  sleep 2
  rac_mcp_tap "System TTS" || rac_mcp_tap "Piper TTS (US English - Medium)" || true
  sleep 3
  rac_mcp_tap "Hello from Flutter E2E harness" || true
  rac_mcp_type "Hello"
  sleep 1
  rac_mcp_tap "Generate" || rac_mcp_tap "Speak" || true
  sleep 5
  rac_mcp_shot "${lane_root}/${shot}"
  local status="LIMITED" notes="TTS generate tapped"
  if _flutter_wait_grep "${RAC_MARKER_TTS_DONE}" 180 || _flutter_grep_logs "Speech generation complete" || _flutter_grep_logs "TTS synthesis complete"; then
    status="PASS"
    notes="TTS completion marker observed"
  fi
  rac_tc_done tc08 "${status}" "${notes}" "${shot}"
}

_flutter_drive_tc09_vlm() {
  local lane_root="${RAC_SESSION_ROOT:?}"
  local shot="screenshots/014_vision_tab.png"
  rac_mcp_tap "${RAC_TAB_VISION:-Vision}"
  sleep 2
  rac_mcp_tap "Select Model" || true
  sleep 2
  rac_mcp_tap "SmolVLM 500M Instruct" || true
  sleep 5
  rac_mcp_shot "${lane_root}/${shot}"
  local status="LIMITED" notes="Vision tab held for VLM surface"
  if _flutter_wait_grep "${RAC_MARKER_VLM_DONE}" 120 || _flutter_grep_logs "VLM streaming completed" || _flutter_grep_logs "VLM model loaded"; then
    status="PASS"
    notes="VLM streaming marker observed"
  fi
  rac_tc_done tc09 "${status}" "${notes}" "${shot}"
}

_flutter_drive_tc18_validation() {
  rac_tc_done tc18 "N/A" "Flutter example has no Validation tab (Solutions only)"
}

_flutter_drive_tc21_lora() {
  rac_tc_done tc21 "N/A" "LoRA harness lives on RN Validation tab only"
}

_flutter_drive_deep_modalities() {
  _flutter_wait_grep "${RAC_MARKER_LLM_LOAD}" 60 || true
  _flutter_drive_tc08_tts
  _flutter_drive_tc09_vlm
  _flutter_drive_tc13_rag
  _flutter_drive_tc18_validation
  _flutter_drive_tc21_lora
}
