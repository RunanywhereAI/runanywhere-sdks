#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

usage() {
    cat <<'EOF'
Usage: scripts/build/linux.sh

Configures and builds the linux-release CMake preset from
sdk/runanywhere-commons, stages every produced .so plus the public include/
tree under sdk/runanywhere-commons/dist/linux/, and packs the versioned
dist/RACommons-linux-x86_64-v<version>.tar.gz (+ .sha256) release archive.

Options:
  -h, --help    Show this help

Environment:
  RAC_RELEASE_VERSION   Version tag override (default: PROJECT_VERSION from VERSIONS)
EOF
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
esac
# Legacy flags (e.g. --shared) are accepted and ignored: the linux-release
# preset is the single canonical configuration.
[ "$#" -eq 0 ] || warn "ignoring arguments: $*"

[ "$(uname -s)" = "Linux" ] || die "linux.sh only runs on Linux (host: $(uname -s))"

COMMONS_ROOT="${RAC_ROOT}/sdk/runanywhere-commons"
PRESET="linux-release"
BUILD_DIR="${COMMONS_ROOT}/build/${PRESET}"

# CMakePresets.json lives in sdk/runanywhere-commons.
cd "${COMMONS_ROOT}"

step "Configuring CMake preset ${PRESET}"
run_cmd cmake --preset "${PRESET}"

step "Building CMake preset ${PRESET}"
run_cmd cmake --build --preset "${PRESET}" --parallel

DIST_DIR="${COMMONS_ROOT}/dist/linux"
mkdir -p "${DIST_DIR}/lib" "${DIST_DIR}/include"

info "Staging shared libraries → ${DIST_DIR}/lib"
find "${BUILD_DIR}" -maxdepth 6 -name "*.so" -print -exec cp {} "${DIST_DIR}/lib/" \;

COMMONS_INCLUDE_SRC="${COMMONS_ROOT}/include"
if [ -d "${COMMONS_INCLUDE_SRC}" ]; then
    info "Staging headers → ${DIST_DIR}/include"
    cp -R "${COMMONS_INCLUDE_SRC}/." "${DIST_DIR}/include/"
fi

# Refuse to package an empty tarball: `find ... -exec cp` exits 0 with zero
# matches, and release.yml's `if-no-files-found: error` upload plus the
# publish gate rely on a present, non-empty archive.
SO_COUNT=$(find "${DIST_DIR}/lib" -name '*.so' -type f | wc -l | tr -d ' ')
if [ "${SO_COUNT}" -lt 1 ]; then
    die "no .so files in ${PRESET} build — refusing to package empty tarball"
fi

source "${RAC_ROOT}/scripts/lib/load-versions.sh" >/dev/null
VERSION="${RAC_RELEASE_VERSION:-${PROJECT_VERSION}}"
TARBALL="RACommons-linux-x86_64-v${VERSION}.tar.gz"
rm -f "${COMMONS_ROOT}/dist/${TARBALL}" "${COMMONS_ROOT}/dist/${TARBALL}.sha256"
(cd "${DIST_DIR}" && tar czf "../${TARBALL}" .)
(cd "${COMMONS_ROOT}/dist" && shasum -a 256 "${TARBALL}" > "${TARBALL}.sha256")

ok "staged → ${COMMONS_ROOT}/dist/${TARBALL}"
