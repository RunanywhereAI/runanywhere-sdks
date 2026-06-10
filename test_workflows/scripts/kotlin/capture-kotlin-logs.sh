#!/usr/bin/env bash
# Kotlin Android → runs/<run-id>/lanes/01_kotlin_android/
set -euo pipefail

RAC_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/_session_lib.sh
source "${RAC_SCRIPTS}/lib/_session_lib.sh"

usage() {
  cat <<USAGE
Usage: capture-kotlin-logs.sh start|snapshot|stop <run-id> [label] [package]
Lane: test_workflows/logs/runs/<run-id>/lanes/01_kotlin_android/
USAGE
}

[[ $# -lt 2 ]] && { usage; exit 2; }

cmd="$1"
run_id="$2"
label="${3:-}"
package="${4:-${ANDROID_PACKAGE:-com.runanywhere.runanywhereai.debug}}"

export RAC_RUN_ID="${RAC_RUN_ID:-$run_id}"
rac_session_init kotlin "${run_id}" "" "Kotlin Android E2E"
export RAC_SESSION_ROOT
rac_session_append_manifest "capture-kotlin-logs.sh ${cmd}"
"${RAC_SCRIPTS}/android/capture-android-logs.sh" "${cmd}" "${run_id}" "${label}" "${package}"
if [[ "${cmd}" == "stop" ]]; then rac_session_finish; fi
