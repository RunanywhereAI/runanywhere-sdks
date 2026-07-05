#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

usage() {
    cat <<'EOF'
Usage: scripts/release/package-rcli.sh <build-dir> <platform-tag>

Stages bin/rcli + the shared libraries it actually links (discovered via
otool/ldd, fail-closed) into a relocatable layout, sanity-runs the staged
binary, and packs rcli-<platform>-v<version>.tar.gz + .sha256 under
sdk/runanywhere-cli/dist/.

Arguments:
  build-dir       CMake build dir containing rcli/rcli (relative paths are
                  resolved against the repo root)
  platform-tag    macos-arm64 | linux-x86_64

Environment:
  RAC_RELEASE_VERSION   Version override (default: sdk/runanywhere-commons/VERSION)

Tarball layout (matches the binary's INSTALL_RPATH
@loader_path/../lib | $ORIGIN/../lib):
  rcli-<platform>/bin/rcli
  rcli-<platform>/lib/*.dylib|*.so*
  rcli-<platform>/README.md
EOF
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
esac

CLI_ROOT="${RAC_ROOT}/sdk/runanywhere-cli"

BUILD_DIR="${1:?usage: package-rcli.sh <build-dir> <platform-tag>}"
PLATFORM="${2:?usage: package-rcli.sh <build-dir> <platform-tag>}"
[[ "${BUILD_DIR}" = /* ]] || BUILD_DIR="${RAC_ROOT}/${BUILD_DIR}"

VERSION="${RAC_RELEASE_VERSION:-$(tr -d '[:space:]' < "${RAC_ROOT}/sdk/runanywhere-commons/VERSION")}"
BINARY="${BUILD_DIR}/rcli/rcli"
DIST_DIR="${CLI_ROOT}/dist"
STAGE_ROOT="${DIST_DIR}/stage"
STAGE="${STAGE_ROOT}/rcli-${PLATFORM}"
TARBALL="${DIST_DIR}/rcli-${PLATFORM}-v${VERSION}.tar.gz"

[ -x "${BINARY}" ] || die "rcli binary not found at ${BINARY}"

rm -rf "${STAGE}"
mkdir -p "${STAGE}/bin" "${STAGE}/lib"
cp "${BINARY}" "${STAGE}/bin/rcli"
cp "${CLI_ROOT}/README.md" "${STAGE}/README.md"

# Bundle every non-system shared library the binary links. Discovering from
# the binary (instead of hardcoding libonnxruntime/sherpa names) keeps the
# package correct when backend link sets change.
case "${PLATFORM}" in
    macos-*)
        deps=$(otool -L "${STAGE}/bin/rcli" | awk 'NR>1 {print $1}' \
               | grep -vE '^(/usr/lib|/System)' || true)
        for dep in ${deps}; do
            # @rpath/libfoo.dylib → find the real file in the build tree.
            local_name="$(basename "${dep}")"
            src="${dep}"
            if [[ "${dep}" == @rpath/* || ! -f "${dep}" ]]; then
                src="$(find "${BUILD_DIR}" -name "${local_name}" -type f 2>/dev/null | head -1)"
            fi
            if [ -z "${src}" ] || [ ! -f "${src}" ]; then
                die "cannot locate linked library ${dep}"
            fi
            cp "${src}" "${STAGE}/lib/${local_name}"
            install_name_tool -change "${dep}" "@rpath/${local_name}" "${STAGE}/bin/rcli"
        done
        # Ad-hoc signature so Gatekeeper accepts the modified binary locally.
        codesign --force -s - "${STAGE}/bin/rcli"
        find "${STAGE}/lib" -name "*.dylib" -exec codesign --force -s - {} \;
        ;;
    linux-*)
        deps=$(ldd "${STAGE}/bin/rcli" | awk '/=>/ {print $3}' \
               | grep -vE '^(/lib|/usr/lib|/lib64)' || true)
        for src in ${deps}; do
            [ -f "${src}" ] && cp -L "${src}" "${STAGE}/lib/$(basename "${src}")"
        done
        ;;
    *)
        die "unknown platform tag '${PLATFORM}'"
        ;;
esac

# Fail-closed sanity run from the staged layout.
case "${PLATFORM}" in
    macos-*) DYLD_LIBRARY_PATH="${STAGE}/lib" "${STAGE}/bin/rcli" version >/dev/null ;;
    linux-*) LD_LIBRARY_PATH="${STAGE}/lib" "${STAGE}/bin/rcli" version >/dev/null ;;
esac

mkdir -p "${DIST_DIR}"
rm -f "${TARBALL}" "${TARBALL}.sha256"
tar -czf "${TARBALL}" -C "${STAGE_ROOT}" "rcli-${PLATFORM}"
(cd "${DIST_DIR}" && shasum -a 256 "$(basename "${TARBALL}")" > "$(basename "${TARBALL}").sha256")

ok "Packaged: ${TARBALL}"
log "Contents:"
tar -tzf "${TARBALL}" | head -20
