#!/usr/bin/env bash
# Shared Swift iOS log grep + TC grading helpers for executor and analyzer.
# shellcheck disable=SC2034
set -euo pipefail

SWIFT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_log_markers.sh
source "${SWIFT_SCRIPT_DIR}/../_log_markers.sh"

_swift_sim_target() {
  printf '%s' "${RAC_IOS_SIM_UDID:-${IOS_SIM_UDID:-booted}}"
}

_swift_log_predicate() {
  printf "subsystem CONTAINS[c] 'com.runanywhere' OR process CONTAINS[c] 'RunAnywhereAI' OR process CONTAINS[c] 'RunAnywhere' OR processImagePath CONTAINS[c] 'RunAnywhereAI' OR composedMessage CONTAINS[c] 'RunAnywhere' OR composedMessage CONTAINS[c] 'rac_'"
}

_swift_log_files() {
  local root="${1:-${RAC_SESSION_ROOT:-}/logs}"
  [[ -d "${root}" ]] || return 0
  find "${root}" -maxdepth 1 -type f \( -name 'ios_*.log' -o -name 'executor.log' \) 2>/dev/null | sort
}

_swift_grep_file() {
  local pattern="$1"
  local file="$2"
  [[ -f "${file}" ]] && grep -Fq "${pattern}" "${file}"
}

_swift_grep_live() {
  local pattern="$1"
  xcrun simctl spawn "$(_swift_sim_target)" log show --style syslog --info --debug --last 5m \
    --predicate "$(_swift_log_predicate)" 2>/dev/null | grep -Fq "${pattern}"
}

_swift_grep() {
  local pattern="$1"
  local f
  while IFS= read -r f; do
    if _swift_grep_file "${pattern}" "${f}"; then
      return 0
    fi
  done < <(_swift_log_files)
  _swift_grep_live "${pattern}"
}

_swift_grep_any() {
  local pattern
  for pattern in "$@"; do
    _swift_grep "${pattern}" && return 0
  done
  return 1
}

_swift_grep_regex() {
  local pattern="$1"
  local f
  while IFS= read -r f; do
    [[ -f "${f}" ]] && grep -Eq "${pattern}" "${f}" && return 0
  done < <(_swift_log_files)
  xcrun simctl spawn "$(_swift_sim_target)" log show --style syslog --info --debug --last 5m \
    --predicate "$(_swift_log_predicate)" 2>/dev/null | grep -Eq "${pattern}"
}

# TC-01: SDK init log markers OR iOS app-ready os_log (web parity: __RUNANYWHERE_AI_READY__).
_swift_tc01_ready() {
  _swift_grep_any \
    "${RAC_MARKER_SDK_INIT}" \
    "${RAC_MARKER_SDK_INIT_ALT}" \
    "${RAC_MARKER_SDK_INIT_DEV}" \
    "${RAC_MARKER_SDK_SERVICES}" \
    "${RAC_MARKER_APP_READY}" \
    "Phase 1 complete"
}

# TC-07: model load, surfaced download error (CLUSTER-08), or transcribe UI ready text.
_swift_tc07_evidence() {
  if _swift_grep_any \
    "${RAC_MARKER_MODEL_LOAD}" \
    "${RAC_MARKER_STT_LOADED}" \
    "${RAC_MARKER_DOWNLOAD_ACCEPTED}"; then
    printf '%s\n' "pass:model_or_download_marker"
    return 0
  fi
  if _swift_grep_any \
    "${RAC_MARKER_DOWNLOAD_FAILED}" \
    "${RAC_MARKER_DOWNLOAD_PLAN_REJECTED}" \
    "${RAC_MARKER_DOWNLOAD_START_REJECTED}" \
    "Download failed for"; then
    printf '%s\n' "limited:download_error_surfaced"
    return 0
  fi
  if _swift_grep_any "${RAC_MARKER_STT_UI_READY}" "Ready to transcribe"; then
    printf '%s\n' "limited:stt_ui_ready_log"
    return 0
  fi
  local shot="${RAC_SESSION_ROOT:-}/screenshots/013_transcribe.png"
  if [[ -f "${shot}" ]]; then
    if xcrun simctl ui "$(_swift_sim_target)" describe 2>/dev/null \
      | grep -Eiq 'Ready to transcribe|"Ready"'; then
      printf '%s\n' "limited:stt_ui_ready_simctl"
      return 0
    fi
    printf '%s\n' "limited:screenshot_only"
    return 0
  fi
  return 1
}

_swift_tc07_status_from_evidence() {
  local evidence="$1"
  case "${evidence}" in
    pass:*) printf '%s\t%s\n' "PASS" "${evidence#pass:}" ;;
    limited:download_error_surfaced)
      printf '%s\t%s\n' "LIMITED" "download error surfaced in logs (CLUSTER-08 evidence)"
      ;;
    limited:*)
      printf '%s\t%s\n' "LIMITED" "transcribe UI evidence (${evidence#limited:}); log marker missing"
      ;;
    *) return 1 ;;
  esac
}
