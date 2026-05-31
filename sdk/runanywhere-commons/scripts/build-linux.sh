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
#   2. Staging every produced `.so` + the public `include/` tree and packing
#      them into the versioned `dist/RACommons-linux-x86_64-v<version>.tar.gz`
#      (+ .sha256) that release.yml uploads and `publish` asserts on.
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

# Refuse to package an empty tarball — `find ... -exec cp` exits 0 even with
# zero matches, and `tar czf .` would still produce a valid archive of just
# directory entries. The symmetric upload `if-no-files-found: error` + the
# `== 'success'` publish gate rely on a present, non-empty archive.
SO_COUNT=$(find "${DIST_DIR}/lib" -name '*.so' -type f | wc -l | tr -d ' ')
if [ "${SO_COUNT}" -lt 1 ]; then
    echo "error: no .so files in linux-release build — refusing to package empty tarball" >&2
    exit 1
fi

# Pack the staged tree into the versioned release tarball + .sha256 under dist/.
# Version: RAC_RELEASE_VERSION (the release tag) or PROJECT_VERSION standalone.
source "${SCRIPT_DIR}/load-versions.sh" >/dev/null
VERSION="${RAC_RELEASE_VERSION:-${PROJECT_VERSION}}"
TARBALL="RACommons-linux-x86_64-v${VERSION}.tar.gz"
rm -f "${COMMONS_ROOT}/dist/${TARBALL}" "${COMMONS_ROOT}/dist/${TARBALL}.sha256"
(cd "${DIST_DIR}" && tar czf "../${TARBALL}" .)
(cd "${COMMONS_ROOT}/dist" && shasum -a 256 "${TARBALL}" > "${TARBALL}.sha256")

echo "✓ build-linux.sh complete; staged → ${COMMONS_ROOT}/dist/${TARBALL}"
