#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# build-linux.sh — package-local compatibility wrapper.
#
# The original per-package Linux build entry point
# was deleted, but `.github/workflows/release.yml` (native_linux job) still
# invokes this path from working-directory `sdk/runanywhere-commons` and
# expects build artifacts to land under `dist/linux/`. This shim restores
# the workflow contract by:
#
#   1. Configuring + building the canonical `linux-release` CMake preset
#      from the repo root.
#   2. Copying every produced `.so` and the public `include/` tree into
#      `sdk/runanywhere-commons/dist/linux/` so the release workflow's
#      tar/sha256/upload steps continue to find their inputs.
#
# Long-term, callers should migrate to invoking
# `cmake --preset linux-release && cmake --build --preset linux-release`
# directly with their own packaging step.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMONS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${COMMONS_ROOT}/../.." && pwd)"

if [ "$(uname -s)" != "Linux" ]; then
    echo "error: build-linux.sh only runs on Linux (host: $(uname -s))" >&2
    exit 1
fi

PRESET="linux-release"
BUILD_DIR="${REPO_ROOT}/build/${PRESET}"

cd "${REPO_ROOT}"

echo "▶ Configuring CMake preset ${PRESET}"
cmake --preset "${PRESET}"

echo "▶ Building CMake preset ${PRESET}"
cmake --build --preset "${PRESET}" --parallel

DIST_DIR="${COMMONS_ROOT}/dist/linux"
mkdir -p "${DIST_DIR}/lib" "${DIST_DIR}/include"

# Stage shared libraries — release.yml tars dist/linux/ as-is.
echo "▶ Staging shared libraries → ${DIST_DIR}/lib"
find "${BUILD_DIR}" -maxdepth 6 -name "*.so" -print -exec cp {} "${DIST_DIR}/lib/" \;

# Mirror public headers so consumers can compile against the package.
COMMONS_INCLUDE_SRC="${COMMONS_ROOT}/include"
if [ -d "${COMMONS_INCLUDE_SRC}" ]; then
    echo "▶ Staging headers → ${DIST_DIR}/include"
    cp -R "${COMMONS_INCLUDE_SRC}/." "${DIST_DIR}/include/"
fi

echo "✓ build-linux.sh wrapper complete; staged artifacts under ${DIST_DIR}"
