#!/usr/bin/env bash

validation_repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
}

validation_jobs() {
  if [[ -n "${VALIDATION_JOBS:-}" ]]; then
    printf "%s\n" "${VALIDATION_JOBS}"
    return
  fi

  if command -v nproc >/dev/null 2>&1; then
    nproc
    return
  fi

  if command -v getconf >/dev/null 2>&1; then
    getconf _NPROCESSORS_ONLN
    return
  fi

  if command -v sysctl >/dev/null 2>&1; then
    sysctl -n hw.ncpu
    return
  fi

  printf "4\n"
}

validation_init() {
  local run_name="$1"
  local stamp

  VALIDATION_REPO_ROOT="$(validation_repo_root)"
  VALIDATION_BUILD_ROOT="${VALIDATION_BUILD_ROOT:-${VALIDATION_REPO_ROOT}/build/validation}"
  stamp="${VALIDATION_STAMP:-$(date +"%Y%m%d-%H%M%S")}"
  VALIDATION_RUN_DIR="${VALIDATION_RUN_DIR:-${VALIDATION_REPO_ROOT}/test_workflows/logs/${stamp}-${run_name}}"
  VALIDATION_LOG_DIR="${VALIDATION_RUN_DIR}/logs"
  VALIDATION_SUMMARY="${VALIDATION_RUN_DIR}/summary.tsv"
  VALIDATION_FAILURES=0

  mkdir -p "${VALIDATION_BUILD_ROOT}" "${VALIDATION_LOG_DIR}"
  printf "name\tstatus\texit_code\tlog\n" > "${VALIDATION_SUMMARY}"

  {
    printf "# Validation Run\n\n"
    printf -- "- Name: %s\n" "${run_name}"
    printf -- "- Started: %s\n" "$(date -Iseconds)"
    printf -- "- Repo root: %s\n" "${VALIDATION_REPO_ROOT}"
    printf -- "- Build root: %s\n" "${VALIDATION_BUILD_ROOT}"
    printf -- "- Summary: summary.tsv\n"
  } > "${VALIDATION_RUN_DIR}/RUN_MANIFEST.md"
}

validation_run_step() {
  local name="$1"
  local workdir="$2"
  local log
  local code
  local status
  shift 2

  log="${VALIDATION_LOG_DIR}/${name}.log"

  {
    printf "name: %s\n" "${name}"
    printf "workdir: %s\n" "${workdir}"
    printf "start: %s\n" "$(date -Iseconds)"
    printf "command:"
    printf " %q" "$@"
    printf "\n\n"
  } > "${log}"

  set +e
  (
    cd "${workdir}" &&
      "$@"
  ) >> "${log}" 2>&1
  code=$?
  set -e

  {
    printf "\nexit_code: %s\n" "${code}"
    printf "end: %s\n" "$(date -Iseconds)"
  } >> "${log}"

  status="PASS"
  if [[ "${code}" -ne 0 ]]; then
    status="FAIL"
    VALIDATION_FAILURES=$((VALIDATION_FAILURES + 1))
  fi

  printf "%s\t%s\t%s\t%s\n" "${name}" "${status}" "${code}" "${log}" >> "${VALIDATION_SUMMARY}"

  if [[ "${code}" -ne 0 && "${VALIDATION_FAIL_FAST:-0}" == "1" ]]; then
    return "${code}"
  fi

  return 0
}

validation_finish() {
  local report="${VALIDATION_RUN_DIR}/REPORT.md"

  {
    printf "# Validation Report\n\n"
    printf -- "- Run dir: %s\n" "${VALIDATION_RUN_DIR}"
    printf -- "- Build root: %s\n" "${VALIDATION_BUILD_ROOT}"
    printf -- "- Failures: %s\n\n" "${VALIDATION_FAILURES}"
    printf "## Command Results\n\n"
    printf "| Step | Status | Exit | Log |\n"
    printf "| --- | --- | ---: | --- |\n"
    awk -F '\t' 'NR > 1 { printf "| `%s` | %s | %s | `%s` |\n", $1, $2, $3, $4 }' "${VALIDATION_SUMMARY}"
  } > "${report}"

  printf "Logs: %s\n" "${VALIDATION_RUN_DIR}"
  printf "Summary: %s\n" "${VALIDATION_SUMMARY}"

  if [[ "${VALIDATION_FAILURES}" -ne 0 ]]; then
    return 1
  fi
}
