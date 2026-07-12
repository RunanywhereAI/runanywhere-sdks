#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Canonical Linux release build and packaging entry point.
#
# Configures/builds the `linux-release` CMake preset, stages every produced
# `.so` plus the public `include/` tree, and packs
#      them into the versioned `dist/RACommons-linux-<arch>-v<version>.tar.gz`
#      (+ .sha256) that release.yml uploads and `publish` asserts on.
set -euo pipefail

if [ "$#" -ne 0 ]; then
    echo "usage: build-linux.sh" >&2
    exit 2
fi

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
rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}/lib" "${DIST_DIR}/include"

# Stage shared libraries — release.yml tars dist/linux/ as-is.
echo "▶ Staging shared libraries → ${DIST_DIR}/lib"
duplicate_libraries="$(find "${BUILD_DIR}" -maxdepth 6 -name '*.so' -type f -exec basename {} \; \
    | LC_ALL=C sort | uniq -d)"
if [ -n "${duplicate_libraries}" ]; then
    echo "error: duplicate shared-library basenames in Linux build:" >&2
    printf '  %s\n' "${duplicate_libraries}" >&2
    exit 1
fi
find "${BUILD_DIR}" -maxdepth 6 -name "*.so" -print -exec cp {} "${DIST_DIR}/lib/" \;

if find "${DIST_DIR}/lib" -type f \( -iname '*qhexrt*' -o -iname '*qnn*' \) -print -quit \
    | grep -q .; then
    echo "error: private QHexRT/QNN library reached the public Linux staging tree" >&2
    exit 1
fi

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
case "$(uname -m)" in
    x86_64|amd64) PACKAGE_ARCH="x86_64" ;;
    aarch64|arm64) PACKAGE_ARCH="aarch64" ;;
    *)
        echo "error: unsupported Linux package architecture '$(uname -m)'" >&2
        exit 1
        ;;
esac
TARBALL="RACommons-linux-${PACKAGE_ARCH}-v${VERSION}.tar.gz"
rm -f "${COMMONS_ROOT}/dist/${TARBALL}" "${COMMONS_ROOT}/dist/${TARBALL}.sha256"
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "${REPO_ROOT}" log -1 --format=%ct 2>/dev/null || printf '0')}"
(cd "${DIST_DIR}" && \
    tar --sort=name --mtime="@${SOURCE_DATE_EPOCH}" --owner=0 --group=0 --numeric-owner -cf - . \
        | gzip -n > "../${TARBALL}")
(cd "${COMMONS_ROOT}/dist" && shasum -a 256 "${TARBALL}" > "${TARBALL}.sha256")

echo "✓ build-linux.sh complete; staged → ${COMMONS_ROOT}/dist/${TARBALL}"
