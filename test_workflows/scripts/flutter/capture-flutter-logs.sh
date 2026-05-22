#!/usr/bin/env bash
# Flutter → runs/<run-id>/lanes/05_flutter_android | 06_flutter_ios/
set -euo pipefail

RAC_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/_session_lib.sh
source "${RAC_SCRIPTS}/lib/_session_lib.sh"

usage() {
  cat <<USAGE
Usage:
  capture-flutter-logs.sh start|snapshot|stop <run-id> <android|ios> [label]
USAGE
}

_flutter_pick_ios_udid() {
  if [[ -n "${RAC_FLUTTER_DEVICE_ID:-}" ]]; then
    printf '%s' "${RAC_FLUTTER_DEVICE_ID}"
    return 0
  fi
  if [[ -n "${RAC_IOS_SIM_UDID:-}" && "${RAC_IOS_SIM_UDID}" != "booted" ]]; then
    printf '%s' "${RAC_IOS_SIM_UDID}"
    return 0
  fi
  if command -v flutter >/dev/null 2>&1; then
    flutter devices --machine 2>/dev/null | python3 -c '
import json, sys
raw = sys.stdin.read().strip()
if not raw:
    raise SystemExit(1)
for d in json.loads(raw):
    if not d.get("emulator"):
        continue
    plat = str(d.get("platformType") or d.get("targetPlatform") or "").lower()
    if "ios" in plat:
        print(d.get("id", ""))
        raise SystemExit(0)
raise SystemExit(1)
' 2>/dev/null && return 0
  fi
  xcrun simctl list devices booted -j 2>/dev/null | python3 -c '
import json, sys
data = json.load(sys.stdin)
for group in data.get("devices", {}).values():
    for dev in group:
        if dev.get("state") == "Booted":
            print(dev.get("udid", ""))
            raise SystemExit(0)
raise SystemExit(1)
' 2>/dev/null || true
}

_start_flutter_console_logs() {
  local target="$1"
  local log_root="$2"
  if ! command -v flutter >/dev/null 2>&1; then
    return 0
  fi
  local -a dev_args=()
  if [[ "${target}" == "android" && -n "${RAC_ANDROID_SERIAL:-}" ]]; then
    dev_args=(-d "${RAC_ANDROID_SERIAL}")
  elif [[ "${target}" == "ios" ]]; then
    local udid
    udid="$(_flutter_pick_ios_udid || true)"
    [[ -n "${udid}" ]] && dev_args=(-d "${udid}")
  fi
  cd "$(rac_repo_root)/examples/flutter/RunAnywhereAI"
  : > "${log_root}/flutter_run_console.log"
  flutter logs "${dev_args[@]}" >> "${log_root}/flutter_run_console.log" 2>&1 &
  echo $! > "${RAC_SESSION_ROOT}/.pids/flutter_run_console.pid"
  ln -sf flutter_run_console.log "${log_root}/flutter_logs.log" 2>/dev/null || \
    cp -f "${log_root}/flutter_run_console.log" "${log_root}/flutter_logs.log" 2>/dev/null || true
}

[[ $# -lt 3 ]] && { usage; exit 2; }

cmd="$1"
run_id="$2"
target="$3"
label="${4:-}"

export RAC_RUN_ID="${RAC_RUN_ID:-$run_id}"
rac_session_init flutter "${run_id}" "${target}" "Flutter ${target} E2E"
export RAC_SESSION_ROOT
log_root="${RAC_SESSION_ROOT}/logs"
mkdir -p "${log_root}" "${RAC_SESSION_ROOT}/.pids"
rac_session_append_manifest "capture-flutter-logs.sh ${cmd} target=${target}"

case "${cmd}:${target}" in
  start:android)
    export ANDROID_PACKAGE="${ANDROID_PACKAGE:-com.runanywhere.runanywhere_ai}"
    "${RAC_SCRIPTS}/android/capture-android-logs.sh" start "${run_id}" "" "${ANDROID_PACKAGE}"
    _start_flutter_console_logs android "${log_root}"
    ;;
  snapshot:android)
    "${RAC_SCRIPTS}/android/capture-android-logs.sh" snapshot "${run_id}" "${label}" "${ANDROID_PACKAGE:-com.runanywhere.runanywhere_ai}"
    ;;
  stop:android)
    [[ -f "${RAC_SESSION_ROOT}/.pids/flutter_run_console.pid" ]] && kill "$(cat "${RAC_SESSION_ROOT}/.pids/flutter_run_console.pid")" 2>/dev/null || true
    [[ -f "${RAC_SESSION_ROOT}/.pids/flutter_logs.pid" ]] && kill "$(cat "${RAC_SESSION_ROOT}/.pids/flutter_logs.pid")" 2>/dev/null || true
    "${RAC_SCRIPTS}/android/capture-android-logs.sh" stop "${run_id}" "" "${ANDROID_PACKAGE:-com.runanywhere.runanywhere_ai}"
    rac_session_finish
    ;;
  start:ios)
    export IOS_PROCESS_FILTER="${IOS_PROCESS_FILTER:-Runner}"
    export IOS_SIM_UDID="${RAC_IOS_SIM_UDID:-booted}"
    "${RAC_SCRIPTS}/ios/capture-ios-simulator-logs.sh" start "${run_id}" "" "${IOS_PROCESS_FILTER}"
    _start_flutter_console_logs ios "${log_root}"
    ;;
  snapshot:ios)
    "${RAC_SCRIPTS}/ios/capture-ios-simulator-logs.sh" snapshot "${run_id}" "${label}" "${IOS_PROCESS_FILTER:-Runner}"
    ;;
  stop:ios)
    [[ -f "${RAC_SESSION_ROOT}/.pids/flutter_run_console.pid" ]] && kill "$(cat "${RAC_SESSION_ROOT}/.pids/flutter_run_console.pid")" 2>/dev/null || true
    [[ -f "${RAC_SESSION_ROOT}/.pids/flutter_logs.pid" ]] && kill "$(cat "${RAC_SESSION_ROOT}/.pids/flutter_logs.pid")" 2>/dev/null || true
    "${RAC_SCRIPTS}/ios/capture-ios-simulator-logs.sh" stop "${run_id}" "" "${IOS_PROCESS_FILTER:-Runner}"
    rac_session_finish
    ;;
  *) usage; exit 2 ;;
esac
