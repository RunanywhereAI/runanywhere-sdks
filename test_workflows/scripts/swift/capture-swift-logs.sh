#!/usr/bin/env bash
# Swift iOS → runs/<run-id>/lanes/02_swift_ios/
set -euo pipefail

RAC_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/_session_lib.sh
source "${RAC_SCRIPTS}/lib/_session_lib.sh"

usage() {
  cat <<USAGE
Usage: capture-swift-logs.sh start|snapshot|stop <run-id> [label] [process-filter]
Lane: test_workflows/logs/runs/<run-id>/lanes/02_swift_ios/
USAGE
}

[[ $# -lt 2 ]] && { usage; exit 2; }

cmd="$1"
run_id="$2"
label="${3:-}"
proc="${4:-${IOS_PROCESS_FILTER:-RunAnywhereAI}}"

export RAC_RUN_ID="${RAC_RUN_ID:-$run_id}"
rac_session_init swift "${run_id}" "" "Swift iOS E2E"
export RAC_SESSION_ROOT
rac_session_append_manifest "capture-swift-logs.sh ${cmd}"
"${RAC_SCRIPTS}/ios/capture-ios-simulator-logs.sh" "${cmd}" "${run_id}" "${label}" "${proc}"
[[ "${cmd}" == "stop" ]] && rac_session_finish
