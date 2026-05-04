#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_validation_lib.sh"

validation_init "global-source-checks"

validation_run_step "git_status_short" "${VALIDATION_REPO_ROOT}" \
  git status --short --untracked-files=no
validation_run_step "diff_check" "${VALIDATION_REPO_ROOT}" \
  git diff --check

if [[ "${VALIDATION_RUN_IDL_DRIFT:-1}" == "1" ]]; then
  validation_run_step "idl_drift_check" "${VALIDATION_REPO_ROOT}" \
    "${SCRIPT_DIR}/run_idl_drift_check.sh"
fi

validation_finish
