#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_validation_lib.sh"

usage() {
  cat <<'USAGE'
Usage: scripts/validation/run_seven_lane_validation.sh [--with-preflight]

Creates the standard seven-lane evidence folder under test_workflows/logs/.
The shell wrapper cannot drive Mobile MCP or browser MCP by itself; target
agents should add actions.jsonl, screenshots, videos, logs, and agent reports
inside the generated lane folders.

Options:
  --with-preflight  Run global source checks and commons proto checks first.
  -h, --help        Show this help text.
USAGE
}

WITH_PREFLIGHT=0
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --with-preflight)
      WITH_PREFLIGHT=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf "error: unknown argument: %s\n" "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

VALIDATION_REPO_ROOT="$(validation_repo_root)"
VALIDATION_BUILD_ROOT="${VALIDATION_BUILD_ROOT:-${VALIDATION_REPO_ROOT}/build/validation}"
VALIDATION_STAMP="${VALIDATION_STAMP:-$(date +"%Y%m%d-%H%M%S")}"
RUN_DIR="${VALIDATION_RUN_DIR:-${VALIDATION_REPO_ROOT}/test_workflows/logs/${VALIDATION_STAMP}-seven-lane-validation}"

mkdir -p "${RUN_DIR}/global/logs" "${VALIDATION_BUILD_ROOT}"
printf "name\tstatus\texit_code\tlog\n" > "${RUN_DIR}/summary.tsv"

{
  printf "# Seven-Lane Validation Manifest\n\n"
  printf -- "- Started: %s\n" "$(date -Iseconds)"
  printf -- "- Repo root: %s\n" "${VALIDATION_REPO_ROOT}"
  printf -- "- Build root: %s\n" "${VALIDATION_BUILD_ROOT}"
  printf -- "- Instructions: ../../INSTRUCTIONS.md\n"
  printf -- "- Build organization: ../../README.md\n"
} > "${RUN_DIR}/RUN_MANIFEST.md"

while IFS='|' read -r lane title; do
  [[ -z "${lane}" ]] && continue
  mkdir -p "${RUN_DIR}/${lane}/logs" "${RUN_DIR}/${lane}/screenshots" "${RUN_DIR}/${lane}/videos"
  : > "${RUN_DIR}/${lane}/actions.jsonl"
  {
    printf "# %s\n\n" "${title}"
    printf -- "- Status: TODO\n"
    printf -- "- Evidence folder: %s\n" "${lane}"
    printf -- "- Add command logs under logs/, screenshots under screenshots/, videos under videos/.\n"
  } > "${RUN_DIR}/${lane}/agent_report.md"
done <<'LANES'
01_android_kotlin|Android Kotlin SDK
02_ios_swift|iOS Swift SDK
03_react_native_android|React Native Android Target
04_react_native_ios|React Native iOS Target
05_flutter_android|Flutter Android Target
06_flutter_ios|Flutter iOS Target
07_web|Web Target
LANES

{
  printf "# Seven-Lane Validation Report\n\n"
  printf -- "- Run dir: %s\n" "${RUN_DIR}"
  printf -- "- Build root: %s\n" "${VALIDATION_BUILD_ROOT}"
  printf -- "- Preflight: %s\n\n" "${WITH_PREFLIGHT}"
  printf "## Runtime Evidence\n\n"
  printf "Fill this report after target agents complete lanes 01 through 07.\n"
} > "${RUN_DIR}/REPORT.md"

if [[ "${WITH_PREFLIGHT}" -eq 1 ]]; then
  VALIDATION_RUN_DIR="${RUN_DIR}/global/source-checks" \
    VALIDATION_BUILD_ROOT="${VALIDATION_BUILD_ROOT}" \
    "${SCRIPT_DIR}/run_global_source_checks.sh"
  VALIDATION_RUN_DIR="${RUN_DIR}/global/commons-proto-checks" \
    VALIDATION_BUILD_ROOT="${VALIDATION_BUILD_ROOT}" \
    "${SCRIPT_DIR}/run_commons_proto_checks.sh"
fi

printf "Seven-lane scaffold: %s\n" "${RUN_DIR}"
printf "Use build root: %s\n" "${VALIDATION_BUILD_ROOT}"
