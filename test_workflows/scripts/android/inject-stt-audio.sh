#!/usr/bin/env bash
# Inject catalog STT phrase audio for Android E2E (emulator attachmic / host playback fallback).
# Catalog §2 / modality_matrix.md: "RunAnywhere runs models on device."
set -euo pipefail

RAC_STT_PHRASE="${RAC_STT_PHRASE:-RunAnywhere runs models on device.}"
RAC_STT_FIXTURE="${RAC_STT_FIXTURE:-test_workflows/fixtures/stt-phrase.wav}"

_rac_android_emulator_console_port() {
  local serial="$1"
  if [[ "${serial}" =~ ^emulator-([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

_rac_emulator_console_cmd() {
  local serial="$1"
  local cmd="$2"
  local port
  port="$(_rac_android_emulator_console_port "${serial}")" || return 1
  printf '%s\n' "${cmd}" | nc -w 2 "localhost" "${port}" >/dev/null 2>&1
}

rac_ensure_stt_fixture() {
  local out="$1"
  local repo_root="${2:-}"
  if [[ -f "${out}" ]]; then
    return 0
  fi
  mkdir -p "$(dirname "${out}")"
  local tmp_aiff tmp_wav
  tmp_aiff="$(mktemp /tmp/rac-stt-phrase.XXXXXX.aiff)"
  tmp_wav="$(mktemp /tmp/rac-stt-phrase.XXXXXX.wav)"
  if command -v say >/dev/null 2>&1; then
    say -v Samantha -r 160 -o "${tmp_aiff}" "${RAC_STT_PHRASE}"
    if command -v ffmpeg >/dev/null 2>&1; then
      ffmpeg -y -loglevel error -i "${tmp_aiff}" -ar 16000 -ac 1 -sample_fmt s16 "${out}"
    elif command -v afconvert >/dev/null 2>&1; then
      afconvert "${tmp_aiff}" "${tmp_wav}" -d LEI16 -f WAVE -r 16000 -c 1
      mv "${tmp_wav}" "${out}"
    else
      rm -f "${tmp_aiff}" "${tmp_wav}"
      return 1
    fi
    rm -f "${tmp_aiff}" "${tmp_wav}"
    return 0
  fi
  if [[ -n "${repo_root}" ]] && [[ -f "${repo_root}/test_workflows/fixtures/stt-phrase.wav" ]]; then
    cp "${repo_root}/test_workflows/fixtures/stt-phrase.wav" "${out}"
    return 0
  fi
  rm -f "${tmp_aiff}" "${tmp_wav}"
  return 1
}

rac_inject_stt_fixture_start() {
  local serial="$1"
  local fixture="$2"
  fixture="$(cd "$(dirname "${fixture}")" && pwd)/$(basename "${fixture}")"
  [[ -f "${fixture}" ]] || return 1

  local play_fixture="${fixture}"
  if command -v ffmpeg >/dev/null 2>&1; then
    play_fixture="${TMPDIR:-/tmp}/rac_stt_phrase_boost.wav"
    ffmpeg -y -loglevel error -i "${fixture}" -af volume=8.0 "${play_fixture}" 2>/dev/null || play_fixture="${fixture}"
  fi

  export RAC_STT_INJECT_MODE=""
  if _rac_emulator_console_cmd "${serial}" "avd attachmic "${play_fixture}""; then
    RAC_STT_INJECT_MODE="attachmic"
    return 0
  fi

  if _rac_emulator_console_cmd "${serial}" "avd hostmicon"; then
    RAC_STT_INJECT_MODE="hostmicon"
    touch "${TMPDIR:-/tmp}/rac_stt_injecting"
    if command -v afplay >/dev/null 2>&1; then
      ( while [[ -f "${TMPDIR:-/tmp}/rac_stt_injecting" ]]; do afplay "${play_fixture}"; done ) &
      echo $! > "${TMPDIR:-/tmp}/rac_stt_afplay.pid"
    elif command -v ffplay >/dev/null 2>&1; then
      ( while [[ -f "${TMPDIR:-/tmp}/rac_stt_injecting" ]]; do
        ffplay -nodisp -autoexit -loglevel quiet "${play_fixture}"
      done ) &
      echo $! > "${TMPDIR:-/tmp}/rac_stt_afplay.pid"
    fi
    return 0
  fi

  if command -v afplay >/dev/null 2>&1; then
    RAC_STT_INJECT_MODE="hostspeaker"
    touch "${TMPDIR:-/tmp}/rac_stt_injecting"
    ( while [[ -f "${TMPDIR:-/tmp}/rac_stt_injecting" ]]; do afplay "${play_fixture}"; done ) &
    echo $! > "${TMPDIR:-/tmp}/rac_stt_afplay.pid"
    return 0
  fi
  if command -v ffplay >/dev/null 2>&1; then
    RAC_STT_INJECT_MODE="hostspeaker"
    touch "${TMPDIR:-/tmp}/rac_stt_injecting"
    ( while [[ -f "${TMPDIR:-/tmp}/rac_stt_injecting" ]]; do
      ffplay -nodisp -autoexit -loglevel quiet "${play_fixture}"
    done ) &
    echo $! > "${TMPDIR:-/tmp}/rac_stt_afplay.pid"
    return 0
  fi
  adb -s "${serial}" push "${fixture}" /sdcard/Download/stt-phrase.wav >/dev/null 2>&1 || true
  RAC_STT_INJECT_MODE="speaker_push_only"
}

rac_inject_stt_fixture_stop() {
  local serial="$1"
  rm -f "${TMPDIR:-/tmp}/rac_stt_injecting"
  case "${RAC_STT_INJECT_MODE:-}" in
    attachmic)
      _rac_emulator_console_cmd "${serial}" "avd detachmic" || true
      ;;
    hostmicon|hostspeaker)
      if [[ -f "${TMPDIR:-/tmp}/rac_stt_afplay.pid" ]]; then
        kill "$(cat "${TMPDIR:-/tmp}/rac_stt_afplay.pid")" 2>/dev/null || true
        rm -f "${TMPDIR:-/tmp}/rac_stt_afplay.pid"
      fi
      if [[ "${RAC_STT_INJECT_MODE:-}" == "hostmicon" ]]; then
        _rac_emulator_console_cmd "${serial}" "avd hostmicoff" || true
      fi
      ;;
    speaker_push_only)
      ;;
  esac
  unset RAC_STT_INJECT_MODE
}

rac_stt_batch_transcript_line() {
  local serial="$1"
  {
    adb -s "${serial}" logcat -d -s SpeechToTextViewModel:* System.out:* RunAnywhere:* 2>/dev/null || true
    adb -s "${serial}" logcat -d 2>/dev/null || true
  } | grep -E 'Batch transcription complete' | tail -n1 || true
}

rac_stt_batch_transcript_nonempty() {
  local line="$1"
  [[ -n "${line}" ]] || return 1
  if echo "${line}" | grep -Eq '\([0-9]+ms, [1-9][0-9]* words?\)'; then
    return 0
  fi
  echo "${line}" | grep -Eqi 'Batch transcription complete:[[:space:]]*[^[:space:()]+'
}

rac_stt_transcript_has_keywords() {
  local serial="$1"
  local line="${2:-}"
  if [[ -z "${line}" ]]; then
    line="$(rac_stt_batch_transcript_line "${serial}")"
  fi
  [[ -n "${line}" ]] || return 1
  local hits=0
  echo "${line}" | grep -Eqi 'run[[:space:]]*any(where|way)|runanywhere|any[[:space:]]*way|anywhere' && hits=$((hits + 1))
  echo "${line}" | grep -Eqi 'model|modal|smooth' && hits=$((hits + 1))
  echo "${line}" | grep -qi 'device' && hits=$((hits + 1))
  [[ "${hits}" -ge 2 ]]
}
