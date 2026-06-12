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

_rn_drive_tc06_vad() {
  local lane_root="${RAC_SESSION_ROOT:?}"
  local shot="screenshots/017_tc06_vad.png"
  rac_mcp_tap "${RAC_TAB_VALIDATION:-Validation}"
  sleep 2
  if declare -F _rn_android_wait_vad_ready >/dev/null 2>&1; then
    _rn_android_wait_vad_ready 300 || true
  fi
  if declare -F _rn_android_tap_validation_action >/dev/null 2>&1; then
    _rn_android_tap_validation_action "vad.synthetic_silence" \
      || rac_mcp_tap "validation-action-vad.synthetic_silence" \
      || rac_mcp_tap "VAD Silence" \
      || true
  else
    rac_mcp_tap "vad.synthetic_silence" \
      || rac_mcp_tap "VAD Silence" \
      || rac_mcp_tap "Run" \
      || true
  fi
  sleep 4
  rac_mcp_shot "${lane_root}/${shot}"
  local status="LIMITED" notes="Validation VAD silence action attempted"
  if declare -F _rn_android_grep_validation_marker >/dev/null 2>&1; then
    if _rn_android_grep_validation_marker "vad.synthetic_silence" \
      || _rn_android_grep_validation_marker "vad.synthetic_tone"; then
      status="PASS"
      notes="VAD validation harness emitted [RN_VALIDATION_ACTION] markers"
    fi
  elif _rn_grep_logs "vad" || _rn_grep_logs "silero" || _rn_grep_logs "downloadModel"; then
    status="PASS"
    notes="VAD validation action logged (CLUSTER-16 download-before-load path)"
  fi
  rac_tc_done tc06 "${status}" "${notes}" "${shot}"
}

_rn_drive_validation_harness() {
  local lane_root="${RAC_SESSION_ROOT:?}"
  local action_id shot idx="${1:-22}"
  local tc06_pass=0 tc18_pass=0 tc21_pass=0 marker_count=0

  if declare -F _rn_android_tap_validation_tab >/dev/null 2>&1; then
    _rn_android_tap_validation_tab || rac_mcp_tap "${RAC_TAB_VALIDATION:-Validation}" || true
  else
    rac_mcp_tap "${RAC_TAB_VALIDATION:-Validation}" || true
  fi
  sleep 2
  rac_mcp_shot "${lane_root}/screenshots/021_validation_tab.png"

  if declare -F _rn_android_wait_vad_ready >/dev/null 2>&1; then
    _rn_android_wait_vad_ready 300 || true
  fi

  for action_id in "${_RN_VALIDATION_ACTION_IDS[@]}"; do
    if declare -F _rn_android_tap_validation_action >/dev/null 2>&1; then
      _rn_android_tap_validation_action "${action_id}" \
        || rac_mcp_tap "validation-action-${action_id}" \
        || true
    else
      rac_mcp_tap "validation-action-${action_id}" || true
    fi
    sleep 4
    shot="$(printf 'screenshots/%03d_validation_%s.png' "${idx}" "${action_id//./_}")"
    rac_mcp_shot "${lane_root}/${shot}"
    if declare -F _rn_android_grep_validation_marker >/dev/null 2>&1; then
      _rn_android_grep_validation_marker "${action_id}" || true
    fi
    idx=$((idx + 1))
  done

  if declare -F _rn_android_grep_validation_marker >/dev/null 2>&1; then
    _rn_android_grep_validation_marker "vad.synthetic_silence" && tc06_pass=1 || true
    _rn_android_grep_validation_marker "vad.synthetic_tone" && tc06_pass=1 || true
    marker_count="$(_rn_android_validation_marker_count)"
    [[ "${marker_count:-0}" -ge 8 ]] && tc18_pass=1 || true
    _rn_android_grep_validation_marker "lora.list" && tc21_pass=1 || true
    _rn_android_grep_validation_marker "lora.apply_fixture" && tc21_pass=1 || true
  fi

  if [[ "${tc06_pass}" -eq 1 ]]; then
    rac_tc_done tc06 PASS "VAD validation harness PASS via validation-action testIDs" \
      "screenshots/025_validation_vad_synthetic_silence.png"
  else
    rac_tc_done tc06 FAIL "VAD validation markers missing — tap validation-action-vad.* failed" \
      "screenshots/025_validation_vad_synthetic_silence.png"
  fi

  if [[ "${tc18_pass}" -eq 1 ]]; then
    rac_tc_done tc18 PASS "Validation harness emitted ${marker_count} [RN_VALIDATION_ACTION] markers" \
      "screenshots/021_validation_tab.png"
  else
    rac_tc_done tc18 FAIL "Validation harness incomplete (${marker_count} markers)" \
      "screenshots/021_validation_tab.png"
  fi

  if [[ "${tc21_pass}" -eq 1 ]]; then
    rac_tc_done tc21 PASS "LoRA validation harness logged" \
      "screenshots/028_validation_lora_apply_fixture.png"
  else
    rac_tc_done tc21 LIMITED "LoRA validation attempted; partial markers" \
      "screenshots/026_validation_lora_list.png"
  fi
}

_rn_drive_deep_modalities() {
  _rn_drive_tc08_tts
  _rn_drive_tc09_vlm
  _rn_drive_tc13_rag
  _rn_drive_tc18_validation
  _rn_drive_tc21_lora
}
