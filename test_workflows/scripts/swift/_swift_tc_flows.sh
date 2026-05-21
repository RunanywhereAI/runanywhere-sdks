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

  _swift_dismiss_chat_onboarding
  _swift_open_transcribe
  rac_mcp_shot "${lane_root}/screenshots/013_transcribe.png"

  _swift_tap_raw "Get Started"
  sleep 1
  rac_mcp_shot "${lane_root}/screenshots/013b_stt_model_sheet.png"

  _swift_tap_raw "Sherpa Whisper Tiny" || _swift_tap_raw "Whisper" || true
  sleep 0.5
  _swift_tap_stt_get_button

  while [[ "${elapsed}" -lt "${wait_s}" ]]; do
    if _swift_stt_outcome_reached; then
      break
    fi
    sleep 5
    elapsed=$((elapsed + 5))
    if [[ $((elapsed % 30)) -eq 0 ]]; then
      _swift_tap_stt_get_button
    fi
  done

  _swift_tap_raw "Use" || true
  sleep 2
  rac_mcp_shot "${lane_root}/screenshots/013c_stt_after_download.png"
  _swift_capture snapshot tc07_stt 2>/dev/null || true
}

_swift_finalize_tc07_tc10() {
  local evidence status notes tc10_status tc10_notes
  if ! evidence="$(_swift_tc07_evidence)"; then
    rac_tc_done tc07 BLOCKED "never reached Transcribe / no STT evidence" "screenshots/013_transcribe.png"
    rac_tc_done tc10 BLOCKED "TC-07 STT flow incomplete" "screenshots/013_transcribe.png"
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
    fi
    rac_tc_done tc10 "${tc10_status}" "${tc10_notes}" "screenshots/013c_stt_after_download.png"
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
  sleep 2
}

_swift_drive_tc19_benchmarks() {
  local lane_root="${RAC_SESSION_ROOT:?}"
  local shot_pre="screenshots/030_tc19_benchmarks.png"
  local shot_run="screenshots/031_tc19_benchmarks_run.png"
  local wait_s="${RAC_BENCHMARK_WAIT_S:-900}"
  local elapsed=0
  local status notes

  _swift_ensure_llm_on_disk || true
  _swift_open_benchmarks
  rac_mcp_shot "${lane_root}/${shot_pre}"

  _swift_tap_raw "All" || true
  sleep 0.5
  _swift_tap_raw "Run All Benchmarks"
  sleep 2
  _swift_capture snapshot tc19_start 2>/dev/null || true

  while [[ "${elapsed}" -lt "${wait_s}" ]]; do
    if _swift_tc19_history_ready; then
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

