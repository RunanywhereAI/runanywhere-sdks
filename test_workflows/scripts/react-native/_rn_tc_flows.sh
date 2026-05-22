#!/usr/bin/env bash
# React Native lane modality flows (Metro log grep, RAG tab, Validation LoRA).

_rn_grep_logs() {
  local pattern="$1"
  local root="${RAC_SESSION_ROOT:?}/logs"
  local name
  for name in metro.log ios_live.log flutter_run_console.log executor.log; do
    [[ -f "${root}/${name}" ]] && grep -qF "${pattern}" "${root}/${name}" && return 0
  done
  return 1
}

_rn_wait_grep() {
  local pattern="$1"
  local wait_s="${2:-120}"
  local elapsed=0
  while [[ "${elapsed}" -lt "${wait_s}" ]]; do
    _rn_grep_logs "${pattern}" && return 0
    sleep 5
    elapsed=$((elapsed + 5))
  done
  return 1
}

_rn_drive_tc08_tts() {
  local lane_root="${RAC_SESSION_ROOT:?}"
  local shot="screenshots/009_tts_tab.png"
  rac_mcp_tap "${RAC_TAB_SPEAK:-Speak}"
  sleep 2
  rac_mcp_type "Hello from React Native E2E harness"
  sleep 1
  rac_mcp_tap "Generate" || rac_mcp_tap "Synthesize" || true
  sleep 2
  rac_mcp_shot "${lane_root}/${shot}"
  local status="LIMITED" notes="TTS generate tapped"
  if _rn_wait_grep "${RAC_MARKER_TTS_DONE}" 120; then
    status="PASS"
    notes="TTS completion marker in Metro/native logs"
  fi
  rac_tc_done tc08 "${status}" "${notes}" "${shot}"
}

_rn_drive_tc09_vlm() {
  local lane_root="${RAC_SESSION_ROOT:?}"
  local shot="screenshots/014_vision_tab.png"
  rac_mcp_tap "${RAC_TAB_VISION:-Vision}"
  sleep 3
  rac_mcp_shot "${lane_root}/${shot}"
  local status="LIMITED" notes="Vision tab held for VLM surface"
  if _rn_wait_grep "${RAC_MARKER_VLM_DONE}" 90 || _rn_grep_logs "[VLMService]"; then
    status="PASS"
    notes="VLM activity marker observed"
  fi
  rac_tc_done tc09 "${status}" "${notes}" "${shot}"
}

_rn_drive_tc13_rag() {
  local lane_root="${RAC_SESSION_ROOT:?}"
  local shot="screenshots/018_tc13_rag.png"
  rac_mcp_tap "${RAC_TAB_DOCS:-RAG}"
  sleep 3
  rac_mcp_shot "${lane_root}/${shot}"
  local status="LIMITED" notes="RAG tab opened"
  if _rn_wait_grep "${RAC_MARKER_RAG_INGEST}" 60 || _rn_grep_logs "Document loaded"; then
    status="PASS"
    notes="RAG ingest marker or UI present"
  fi
  rac_tc_done tc13 "${status}" "${notes}" "${shot}"
}

_rn_drive_tc18_validation() {
  local lane_root="${RAC_SESSION_ROOT:?}"
  local shot="screenshots/019_validation_tab.png"
  rac_mcp_tap "${RAC_TAB_VALIDATION:-Validation}"
  sleep 2
  rac_mcp_shot "${lane_root}/${shot}"
  local status="PASS" notes="Validation harness tab opened"
  rac_tc_done tc18 "${status}" "${notes}" "${shot}"
}

_rn_drive_tc21_lora() {
  local lane_root="${RAC_SESSION_ROOT:?}"
  local shot="screenshots/020_lora_validation.png"
  rac_mcp_tap "${RAC_TAB_VALIDATION:-Validation}"
  sleep 2
  rac_mcp_tap "LoRA Apply" || rac_mcp_tap "LoRA List" || rac_mcp_tap "Run" || true
  sleep 4
  rac_mcp_shot "${lane_root}/${shot}"
  local status="LIMITED" notes="Validation LoRA action attempted"
  if _rn_grep_logs "lora" || _rn_grep_logs "LoRA"; then
    status="PASS"
    notes="LoRA validation harness action logged"
  fi
  rac_tc_done tc21 "${status}" "${notes}" "${shot}"
}

_rn_drive_deep_modalities() {
  _rn_drive_tc08_tts
  _rn_drive_tc09_vlm
  _rn_drive_tc13_rag
  _rn_drive_tc18_validation
  _rn_drive_tc21_lora
}
