#!/usr/bin/env bash
# Swift iOS modality flows beyond generic tab taps (TC-07 / TC-10 STT download).

_swift_dismiss_chat_onboarding() {
  _swift_tap_raw "${RAC_TAB_CHAT:-Chat}"
  sleep 1
  _swift_tap_raw "Get Started"
  sleep 1
}

_swift_sim_privacy_grants() {
  xcrun simctl privacy "$(_swift_sim_udid)" grant microphone "${BUNDLE_ID:-com.runanywhere.RunAnywhere}" >/dev/null 2>&1 || true
  xcrun simctl privacy "$(_swift_sim_udid)" grant photos "${BUNDLE_ID:-com.runanywhere.RunAnywhere}" >/dev/null 2>&1 || true
}

_swift_open_transcribe() {
  _swift_tap_raw "${RAC_TAB_MORE:-More}"
  sleep 1
  _swift_tap_raw "${RAC_TAB_TRANSCRIBE:-Transcribe}"
  sleep 2
  _swift_tap_raw "Allow" || _swift_tap_raw "OK" || true
  sleep 1
}

_swift_stt_outcome_reached() {
  _swift_grep_any \
    "${RAC_MARKER_MODEL_LOAD}" \
    "${RAC_MARKER_STT_LOADED}" \
    "${RAC_MARKER_DOWNLOAD_ACCEPTED}" \
    "${RAC_MARKER_STT_UI_READY}" \
    "Ready to transcribe" \
    "${RAC_MARKER_DOWNLOAD_FAILED}" \
    "${RAC_MARKER_DOWNLOAD_PLAN_REJECTED}" \
    "${RAC_MARKER_DOWNLOAD_START_REJECTED}" \
    "Download failed for"
}


_swift_tap_stt_get_button() {
  local y
  for y in 220 260 300 340 380; do
    _swift_tap_xy_logical 350 "${y}" || true
    sleep 0.25
  done
  _swift_tap_raw "Get" || _swift_tap_raw "71.5 MB" || true
}

_swift_drive_stt_download() {
  local lane_root="${RAC_SESSION_ROOT:?}"
  local wait_s="${RAC_STT_DOWNLOAD_WAIT_S:-180}"
  local elapsed=0

  _swift_stt_flow_started=1

  _swift_launch_app
  _swift_dismiss_chat_onboarding
  _swift_open_transcribe
  rac_mcp_shot "${lane_root}/screenshots/013_transcribe.png"
  _swift_capture snapshot tc07_stt_tab 2>/dev/null || true

  # STTViewModel auto-prepare runs on Transcribe tab appear; sheet open is optional.
  sleep 3
  _swift_tap_raw "Get Started" || true
  sleep 1
  rac_mcp_shot "${lane_root}/screenshots/013b_stt_model_sheet.png"
  _swift_capture snapshot tc07_stt_sheet 2>/dev/null || true

  while [[ "${elapsed}" -lt "${wait_s}" ]]; do
    if _swift_stt_outcome_reached; then
      break
    fi
    sleep 5
    elapsed=$((elapsed + 5))
    _swift_capture snapshot "tc07_stt_wait_${elapsed}" 2>/dev/null || true
    if [[ $((elapsed % 60)) -eq 0 ]]; then
      _swift_launch_app
      _swift_open_transcribe
    fi
  done

  _swift_tap_raw "Use" || true
  sleep 2
  rac_mcp_shot "${lane_root}/screenshots/013c_stt_after_download.png"
  _swift_capture snapshot tc07_stt_done 2>/dev/null || true
}

_swift_finalize_tc07_tc10() {
  local evidence status notes tc10_status tc10_notes shot_tc10

  if [[ -f "${RAC_SESSION_ROOT:-}/screenshots/013c_stt_after_download.png" ]]; then
    shot_tc10="screenshots/013c_stt_after_download.png"
  elif [[ -f "${RAC_SESSION_ROOT:-}/screenshots/013b_stt_model_sheet.png" ]]; then
    shot_tc10="screenshots/013b_stt_model_sheet.png"
  else
    shot_tc10="screenshots/013_transcribe.png"
  fi

  if ! evidence="$(_swift_tc07_evidence)"; then
    rac_tc_done tc07 BLOCKED "never reached Transcribe / no STT evidence" "screenshots/013_transcribe.png"
    rac_tc_done tc10 BLOCKED "TC-07 STT flow incomplete" "${shot_tc10}"
    return 0
  fi

  _swift_tc07_status_from_evidence "${evidence}" | {
    IFS=$'\t' read -r status notes
    rac_tc_done tc07 "${status}" "${notes}" "screenshots/013_transcribe.png"
    tc10_status="${status}"
    tc10_notes="STT screen UX (${notes})"
    if [[ "${evidence}" == limited:download_error_surfaced ]] || [[ "${evidence}" == *download_error* ]]; then
      tc10_status="BLOCKED"
      tc10_notes="download error surfaced in logs (CLUSTER-08)"
    elif [[ "${evidence}" == limited:stt_sheet_reached_no_logs ]]; then
      tc10_status="BLOCKED"
      tc10_notes="reached STT model sheet; no download/load markers (SWIFT-IOS-001)"
    fi
    rac_tc_done tc10 "${tc10_status}" "${tc10_notes}" "${shot_tc10}"
  }
}

_swift_ensure_llm_on_disk() {
  if _swift_llm_artifact_on_disk; then
    return 0
  fi
  local wait_s="${RAC_LLM_DOWNLOAD_WAIT_S:-600}"
  local elapsed=0

  _swift_tap_raw "${RAC_TAB_CHAT:-Chat}"
  sleep 1
  _swift_tap_raw "Get Started" || _swift_tap_raw "Select Model" || _swift_tap_raw "Change" || true
  sleep 1
  _swift_tap_raw "SmolLM2" || _swift_tap_raw "SmolLM" || true
  sleep 0.5
  _swift_tap_raw "Get" || true

  while [[ "${elapsed}" -lt "${wait_s}" ]]; do
    if _swift_llm_artifact_on_disk       || _swift_grep_any "${RAC_MARKER_DOWNLOAD_ACCEPTED}" "Registered downloaded model"; then
      break
    fi
    sleep 10
    elapsed=$((elapsed + 10))
    if [[ $((elapsed % 30)) -eq 0 ]]; then
      _swift_tap_raw "Get" || true
    fi
  done

  _swift_tap_raw "Use" || true
  sleep 2
  _swift_llm_artifact_on_disk
}

_swift_open_benchmarks() {
  _swift_tap_raw "${RAC_TAB_SETTINGS:-Settings}"
  sleep 1
  _swift_scroll_settings_down
  _swift_tap_raw "Benchmarks"
  # Allow BenchmarkDashboardView .task refresh + registry rescan before Run All.
  sleep 5
}

_swift_drive_tc19_benchmarks() {
  local lane_root="${RAC_SESSION_ROOT:?}"
  local shot_pre="screenshots/030_tc19_benchmarks.png"
  local shot_run="screenshots/031_tc19_benchmarks_run.png"
  local prefetch_wait="${RAC_LLM_DOWNLOAD_WAIT_S:-600}"
  local wait_s="${RAC_BENCHMARK_WAIT_S:-900}"
  local elapsed=0
  local status notes

  _swift_launch_app
  local sdk_wait="${RAC_SDK_READY_WAIT_S:-180}"
  elapsed=0
  while [[ "${elapsed}" -lt "${sdk_wait}" ]]; do
    if _swift_grep_any "${RAC_MARKER_AI_READY}" "${RAC_MARKER_SDK_INIT_ALT}" "SDK successfully initialized"; then
      break
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done

  elapsed=0
  while [[ "${elapsed}" -lt "${prefetch_wait}" ]]; do
    if _swift_llm_artifact_on_disk; then
      break
    fi
    sleep 10
    elapsed=$((elapsed + 10))
  done

  if ! _swift_llm_artifact_on_disk; then
    rac_tc_done tc19 BLOCKED "no LLM artifact on disk after prefetch" "${shot_pre}"
    return 0
  fi

  _swift_open_benchmarks
  rac_mcp_shot "${lane_root}/${shot_pre}"

  # BenchmarkViewModel auto-selects on-disk models; tap All only if the Models row is visible.
  _swift_tap_raw "All" || true
  sleep 1
  _swift_tap_raw "Run All Benchmarks"
  sleep 5
  _swift_capture snapshot tc19_start 2>/dev/null || true

  while [[ "${elapsed}" -lt "${wait_s}" ]]; do
    if _swift_tc19_history_ready || _swift_grep_any "${RAC_MARKER_BENCHMARK_SAVED}"; then
      break
    fi
    sleep 10
    elapsed=$((elapsed + 10))
  done

  rac_mcp_shot "${lane_root}/${shot_run}"
  _swift_capture snapshot tc19_end 2>/dev/null || true

  if _swift_tc19_history_ready; then
    status="PASS"
    notes="benchmark history saved with non-zero duration and results"
  else
    status="FAIL"
    notes="Run All finished without benchmark history (missing duration or empty results)"
  fi
  rac_tc_done tc19 "${status}" "${notes}" "${shot_run}"
}

RAC_INPUT_TTS='RunAnywhere runs privately on your device.'
RAC_INPUT_RAG_QUERY='Where should model lifecycle logic live?'

_swift_back() {
  _swift_tap_raw "Back" || _swift_tap_xy_logical 30 60 || true
  sleep 1
}

_swift_open_speak() {
  _swift_tap_raw "${RAC_TAB_MORE:-More}"
  sleep 1
  _swift_tap_raw "${RAC_TAB_SPEAK:-Speak}"
  sleep 2
}

_swift_push_rag_fixture() {
  local repo_root="${REPO:-${REPO_ROOT:-}}"
  local fixture="${repo_root}/test_workflows/fixtures/rag-sample.txt"
  local dest="${RAC_SESSION_ROOT}/fixtures"
  mkdir -p "${dest}"
  local json_out="${dest}/rag-sample.json"
  {
    printf '{"title":"RunAnywhere RAG fixture","body":'
    python3 -c 'import json,sys; print(json.dumps(open(sys.argv[1]).read()))' "${fixture}" 2>/dev/null \
      || printf '"RunAnywhere keeps model lifecycle logic in C++. The SDK registers backends such as LlamaCPP and ONNX/Sherpa on device."'
    printf '}\n'
  } > "${json_out}"
  cp "${json_out}" "${TMPDIR:-/tmp}/rag-sample.json" 2>/dev/null || cp "${json_out}" /tmp/rag-sample.json
  local container
  if container="$(_swift_app_data_container 2>/dev/null)"; then
    mkdir -p "${container}/Documents/E2E"
    cp "${json_out}" "${container}/Documents/E2E/rag-sample.json"
    cp "${json_out}" "${container}/Documents/rag-sample.json"
  fi
}

_swift_seed_vlm_photo() {
  local img="${RAC_SESSION_ROOT}/fixtures/vlm-sample.jpg"
  mkdir -p "$(dirname "${img}")"
  if [[ ! -s "${img}" ]]; then
    python3 - "${img}" <<'PY' 2>/dev/null || true
import base64, sys
open(sys.argv[1], "wb").write(base64.b64decode(
    "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDABALDA4MChAODQ4SERATGCgaGBYWGDEjJR0oOjM9PDkzODdASFxOQERXRTc4UG1RV19iZ2hnPk1xeXBkeFxlZ2P/2wBDAQEGBgcGBj0jJz0jQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0P/wAARCAABAAEDAREAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAb/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAGf/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABBQL/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAEDAQE/AX//xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAECAQE/AX//2Q=="
))
PY
  fi
  [[ -s "${img}" ]] && xcrun simctl addmedia "$(_swift_sim_udid)" "${img}" >/dev/null 2>&1 || true
}

_swift_tts_ready() {
  _swift_grep_any \
    "${RAC_MARKER_TTS_DONE}" \
    "Speech generation complete" \
    "Model load succeeded for vits-piper" \
    "Download completed for vits-piper"
}

_swift_ensure_tts_model_loaded() {
  local dl_wait=0
  while [[ "${dl_wait}" -lt 360 ]]; do
    if _swift_grep_any "Model load succeeded for vits-piper" "Download completed for vits-piper"; then
      return 0
    fi
    _swift_tap_raw "Get Started" || _swift_tap_raw "Select Model" || true
    sleep 2
    _swift_tap_raw "Piper TTS (US English - Medium)" || _swift_tap_raw "Piper" || _swift_tap_raw "US English" || true
    sleep 2
    _swift_tap_stt_get_button
    sleep 10
    _swift_tap_raw "Use" || true
    sleep 5
    dl_wait=$((dl_wait + 19))
    if [[ $((dl_wait % 57)) -eq 0 ]]; then
      _swift_launch_app
      _swift_open_speak
    fi
  done
}

_swift_ensure_vlm_model_loaded() {
  local dl_wait=0
  while [[ "${dl_wait}" -lt 360 ]]; do
    if _swift_grep_any "Model load succeeded for smolvlm" "Download completed for smolvlm"; then
      return 0
    fi
    _swift_tap_raw "Get Started" || _swift_tap_raw "Select Model" || true
    sleep 2
    _swift_tap_raw "SmolVLM 500M Instruct" || _swift_tap_raw "SmolVLM" || true
    sleep 2
    _swift_tap_stt_get_button
    sleep 10
    _swift_tap_raw "Use" || true
    sleep 5
    dl_wait=$((dl_wait + 19))
  done
}

_swift_drive_tc08_tts() {
  local lane_root="${RAC_SESSION_ROOT:?}"
  local status="LIMITED" notes="TTS Speak tapped; waiting for completion log"
  local elapsed=0

  _swift_launch_app
  _swift_open_speak
  rac_mcp_shot "${lane_root}/screenshots/009_tts_tab.png"
  _swift_capture snapshot tc08_tts_tab 2>/dev/null || true

  _swift_ensure_tts_model_loaded

  while [[ "${elapsed}" -lt 180 ]]; do
    if _swift_grep "${RAC_MARKER_TTS_DONE}"; then
      status="PASS"
      notes="TTS speech generation complete observed in logs"
      break
    fi
    _swift_type "${RAC_INPUT_TTS}"
    sleep 1
    _swift_tap_raw "Speak"
    if _swift_wait_grep "${RAC_MARKER_TTS_DONE}" 120; then
      status="PASS"
      notes="TTS speech generation complete observed in logs"
      break
    fi
    elapsed=$((elapsed + 15))
    sleep 5
  done

  rac_mcp_shot "${lane_root}/screenshots/010_tts_played.png"
  _swift_capture snapshot tc08_tts_played 2>/dev/null || true
  rac_tc_done tc08 "${status}" "${notes}" "screenshots/009_tts_tab.png"
}

_swift_drive_tc09_vlm() {
  local lane_root="${RAC_SESSION_ROOT:?}"
  local status="LIMITED" notes="VLM gallery analyze triggered; awaiting stream completion"

  _swift_seed_vlm_photo
  _swift_launch_app
  _swift_tap_raw "${RAC_TAB_VISION:-Vision}"
  sleep 2
  _swift_tap_raw "Vision Chat" || true
  sleep 2
  _swift_ensure_vlm_model_loaded
  rac_mcp_shot "${lane_root}/screenshots/013_vision_tab.png"
  _swift_capture snapshot tc09_vision_tab 2>/dev/null || true

  _swift_tap_raw "Photos" || true
  sleep 4
  _swift_tap_xy_logical 200 600 || true
  sleep 2
  _swift_tap_xy_logical 200 600 || true
  sleep 10

  if _swift_wait_grep "${RAC_MARKER_VLM_DONE}" 300; then
    status="PASS"
    notes="VLM streaming completed marker observed in logs"
  fi

  rac_mcp_shot "${lane_root}/screenshots/014_vision_response.png"
  _swift_capture snapshot tc09_vision_response 2>/dev/null || true
  rac_tc_done tc09 "${status}" "${notes}" "screenshots/014_vision_response.png"
  _swift_back
}

_swift_drive_tc13_rag() {
  local lane_root="${RAC_SESSION_ROOT:?}"
  local status="LIMITED" notes="RAG document flow driven"

  _swift_push_rag_fixture
  local sim_dl="${HOME}/Library/Developer/CoreSimulator/Devices/$(_swift_sim_udid)/data/Downloads"
  mkdir -p "${sim_dl}"
  cp "${RAC_SESSION_ROOT}/fixtures/rag-sample.json" "${sim_dl}/rag-sample.json" 2>/dev/null || true

  _swift_launch_app
  _swift_tap_raw "${RAC_TAB_MORE:-More}"
  sleep 1
  _swift_tap_raw "${RAC_TAB_DOCS:-Document Q&A}"
  sleep 2

  _swift_tap_raw "Embedding Model" || true
  sleep 1
  _swift_tap_raw "All MiniLM" || _swift_tap_raw "Use" || _swift_tap_raw "Get" || true
  sleep 2
  _swift_tap_stt_get_button
  sleep 8
  _swift_back

  _swift_tap_raw "LLM Model" || true
  sleep 1
  _swift_tap_raw "SmolLM2" || _swift_tap_raw "SmolLM" || _swift_tap_raw "Use" || true
  sleep 2
  _swift_tap_stt_get_button
  sleep 8
  _swift_back

  _swift_tap_raw "Select Document" || true
  sleep 2
  _swift_tap_raw "Downloads" || true
  sleep 2
  _swift_tap_raw "rag-sample.json" || true
  sleep 8

  if _swift_wait_grep "${RAC_MARKER_RAG_INGEST}" 180; then
    status="PASS"
    notes="RAG ingest completed"
    _swift_type "${RAC_INPUT_RAG_QUERY:-What does RunAnywhere do?}"
    sleep 1
    _swift_tap_raw "Send" || _swift_tap_xy_logical 370 780 || true
    if _swift_wait_grep "${RAC_MARKER_RAG_QUERY}" 180; then
      notes="RAG ingest + query completed"
    else
      status="LIMITED"
      notes="RAG ingest OK; query marker missing"
    fi
    sleep 3
  fi

  _swift_capture snapshot tc13_rag 2>/dev/null || true
  rac_tc_done tc13 "${status}" "${notes}" ""
  _swift_back
}
