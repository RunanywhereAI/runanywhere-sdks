#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_validation_lib.sh"

validation_init "commons-proto-checks"

COMMONS_DIR="${VALIDATION_REPO_ROOT}/sdk/runanywhere-commons"
COMMONS_BUILD_DIR="${COMMONS_BUILD_DIR:-${VALIDATION_BUILD_ROOT}/commons-proto}"

if [[ "$(uname -s)" == "Linux" ]]; then
  export CC="${CC:-gcc}"
  export CXX="${CXX:-g++}"
fi

validation_run_step "commons_configure" "${VALIDATION_REPO_ROOT}" \
  cmake -S "${COMMONS_DIR}" -B "${COMMONS_BUILD_DIR}" \
    -DCMAKE_BUILD_TYPE=Debug \
    -DRAC_BUILD_PLATFORM=OFF \
    -DRAC_BUILD_BACKENDS=OFF \
    -DRAC_BACKEND_RAG=OFF \
    -DRAC_BUILD_TESTS=ON \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON

validation_run_step "commons_build" "${VALIDATION_REPO_ROOT}" \
  cmake --build "${COMMONS_BUILD_DIR}" -j "$(validation_jobs)"

validation_run_step "commons_ctest" "${VALIDATION_REPO_ROOT}" \
  ctest --test-dir "${COMMONS_BUILD_DIR}" --output-on-failure

validation_finish
