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
    --predicate "$(_swift_log_predicate)" 2>/dev/null | grep -Fq "${pattern}" \
    || log show --style syslog --info --debug --last 5m \
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

_swift_wait_grep() {
  local pattern="$1"
  local timeout="${2:-120}"
  local elapsed=0
  while [[ "${elapsed}" -lt "${timeout}" ]]; do
    if _swift_grep "${pattern}"; then
      return 0
    fi
    sleep 3
    elapsed=$((elapsed + 3))
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
    --predicate "$(_swift_log_predicate)" 2>/dev/null | grep -Eq "${pattern}" \
    || log show --style syslog --info --debug --last 5m \
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
    "${RAC_MARKER_AI_READY}" \
    "Phase 1 complete"
}


_swift_actions_tc_field() {
  local tc="$1"
  local field="$2"
  local actions="${RAC_SESSION_ROOT:-}/actions.jsonl"
  [[ -f "${actions}" ]] || return 1
  python3 - "${tc}" "${field}" "${actions}" <<'PYJSON' 2>/dev/null || return 1
import json, sys
tc, field, path = sys.argv[1:4]
for line in open(path):
    line = line.strip()
    if not line:
        continue
    try:
        row = json.loads(line)
    except json.JSONDecodeError:
        continue
    if row.get("action") == tc:
        val = row.get(field)
        if val is not None and str(val).strip():
            print(str(val).strip())
            raise SystemExit(0)
raise SystemExit(1)
PYJSON
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
  if _swift_grep_any "${RAC_MARKER_STT_AUTO_PREPARE}"; then
    printf '%s\n' "limited:stt_auto_prepare_started"
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

  if [[ -f "${RAC_SESSION_ROOT:-}/screenshots/013b_stt_model_sheet.png" ]]; then
    printf '%s\n' "limited:stt_sheet_reached_no_logs"
    return 0
  fi

  local action_status action_notes
  if action_status="$(_swift_actions_tc_field tc07 status)"; then
    action_notes="$(_swift_actions_tc_field tc07 notes 2>/dev/null || _swift_actions_tc_field tc07 actual 2>/dev/null || true)"
    case "${action_status}" in
      PASS) printf '%s
' "pass:executor_pass"; return 0 ;;
      LIMITED) printf '%s
' "limited:executor_${action_notes:-transcribe}"; return 0 ;;
      BLOCKED) printf '%s
' "limited:executor_blocked"; return 0 ;;
    esac
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
    pass:executor_pass)
      printf '%s\t%s\n' "PASS" "transcribe surface (executor/actions)" ;;
    pass:*) printf '%s\t%s\n' "PASS" "${evidence#pass:}" ;;
    limited:stt_sheet_reached_no_logs)
      printf '%s\t%s\n' "BLOCKED" "reached STT model sheet; no download/load markers (SWIFT-IOS-001)" ;;
    limited:download_error_surfaced)
      printf '%s\t%s\n' "BLOCKED" "download error surfaced in logs (CLUSTER-08 evidence)"
      ;;
    limited:*)
      printf '%s\t%s\n' "LIMITED" "transcribe UI evidence (${evidence#limited:}); log marker missing"
      ;;
    *) return 1 ;;
  esac
}

_swift_app_data_container() {
  local udid bundle
  udid="$(_swift_sim_target)"
  bundle="${BUNDLE_ID:-com.runanywhere.RunAnywhere}"
  xcrun simctl get_app_container "${udid}" "${bundle}" data 2>/dev/null
}

_swift_llm_artifact_on_disk() {
  local container
  container="$(_swift_app_data_container)" || return 1
  find "${container}" -type f \( -path '*/RunAnywhere/Models/*' -o -name '*.gguf' -o -name '*.bin' -o -name 'model.safetensors' \) 2>/dev/null | grep -q .
}

_swift_benchmarks_json_path() {
  local container
  container="$(_swift_app_data_container)" || return 1
  local json="${container}/Documents/benchmarks.json"
  [[ -f "${json}" ]] || return 1
  printf '%s' "${json}"
}

_swift_tc19_history_ready() {
  local json
  json="$(_swift_benchmarks_json_path)" || return 1
  python3 - "${json}" <<'PY'
import json, sys
from datetime import datetime

path = sys.argv[1]
try:
    runs = json.loads(open(path, encoding="utf-8").read())
except Exception:
    sys.exit(1)
if not runs:
    sys.exit(1)
last = runs[-1]
results = last.get("results") or []
if not results:
    sys.exit(1)
started = last.get("startedAt")
completed = last.get("completedAt")
if not started or not completed:
    sys.exit(1)

def parse_iso(s):
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    return datetime.fromisoformat(s)

try:
    dur = (parse_iso(completed) - parse_iso(started)).total_seconds()
except Exception:
    sys.exit(1)
if dur <= 0.5:
    sys.exit(1)
sys.exit(0)
PY
}
