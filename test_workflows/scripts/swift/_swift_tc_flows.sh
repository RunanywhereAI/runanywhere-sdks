#!/usr/bin/env bash
# Swift iOS modality flows beyond generic tab taps (TC-07 / TC-10 STT download).
set -euo pipefail

_swift_dismiss_chat_onboarding() {
  _swift_tap_raw "${RAC_TAB_CHAT:-Chat}"
  sleep 1
  _swift_tap_raw "Get Started"
  sleep 1
}

_swift_open_transcribe() {
  _swift_tap_raw "${RAC_TAB_MORE:-More}"
  sleep 1
  _swift_tap_raw "${RAC_TAB_TRANSCRIBE:-Transcribe}"
  sleep 2
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

_swift_drive_stt_download() {
  local lane_root="${RAC_SESSION_ROOT:?}"
  local shot="screenshots/013_transcribe.png"
  local wait_s="${RAC_STT_DOWNLOAD_WAIT_S:-180}"
  local elapsed=0

  _swift_dismiss_chat_onboarding
  _swift_open_transcribe
  rac_mcp_shot "${lane_root}/${shot}"

  # STT empty state → model sheet
  _swift_tap_raw "Get Started"
  sleep 1
  rac_mcp_shot "${lane_root}/screenshots/013b_stt_model_sheet.png"

  # Sherpa Whisper Tiny → download (Get / size chip on first row)
  _swift_tap_raw "Sherpa Whisper Tiny" || _swift_tap_raw "Whisper" || true
  sleep 0.5
  _swift_tap_raw "Get" || _swift_tap_raw "71.5 MB" || true

  while [[ "${elapsed}" -lt "${wait_s}" ]]; do
    if _swift_stt_outcome_reached; then
      break
    fi
    sleep 5
    elapsed=$((elapsed + 5))
    # Retry Get if still on sheet (CLUSTER-08 stuck button)
    if (( elapsed % 30 == 0 )); then
      _swift_tap_raw "Get" || _swift_tap_raw "71.5 MB" || true
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
    if [[ "${evidence}" == limited:download_error_surfaced* ]] || [[ "${evidence}" == *download_error* ]]; then
      tc10_status="BLOCKED"
      tc10_notes="download error surfaced in logs (CLUSTER-08)"
    fi
    rac_tc_done tc10 "${tc10_status}" "${tc10_notes}" "screenshots/013c_stt_after_download.png"
  }
}
