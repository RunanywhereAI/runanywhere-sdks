#!/usr/bin/env bash
# =============================================================================
# package-rcli.sh <build-dir> <platform-tag>
#
# Stages bin/rcli + the shared libraries it actually links (discovered via
# otool/ldd, fail-closed) into a relocatable layout, sanity-runs the staged
# binary, and packs rcli-<platform>-v<version>.tar.gz + .sha256 under
# sdk/runanywhere-cli/dist/.
#
#   platform-tag: macos-arm64 | linux-x86_64
#   version:      $RAC_RELEASE_VERSION, else sdk/runanywhere-commons/VERSION
#
# Layout inside the tarball (matches the binary's INSTALL_RPATH
# @loader_path/../lib | $ORIGIN/../lib):
#   rcli-<platform>/bin/rcli
#   rcli-<platform>/lib/*.dylib|*.so*
#   rcli-<platform>/README.md
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${CLI_ROOT}/../.." && pwd)"

BUILD_DIR="${1:?usage: package-rcli.sh <build-dir> <platform-tag>}"
PLATFORM="${2:?usage: package-rcli.sh <build-dir> <platform-tag>}"
[[ "${BUILD_DIR}" = /* ]] || BUILD_DIR="${REPO_ROOT}/${BUILD_DIR}"

VERSION="${RAC_RELEASE_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/sdk/runanywhere-commons/VERSION")}"
BINARY="${BUILD_DIR}/sdk/runanywhere-cli/rcli"
DIST_DIR="${CLI_ROOT}/dist"
STAGE_ROOT="${DIST_DIR}/stage"
STAGE="${STAGE_ROOT}/rcli-${PLATFORM}"
TARBALL="${DIST_DIR}/rcli-${PLATFORM}-v${VERSION}.tar.gz"

[ -x "${BINARY}" ] || { echo "ERROR: rcli binary not found at ${BINARY}" >&2; exit 1; }

rm -rf "${STAGE}"
mkdir -p "${STAGE}/bin" "${STAGE}/lib"
cp "${BINARY}" "${STAGE}/bin/rcli"
cp "${CLI_ROOT}/README.md" "${STAGE}/README.md"

# ----------------------------------------------------------------------------
# Bundle every non-system shared library the binary links. Discovering from
# the binary (instead of hardcoding libonnxruntime/sherpa names) keeps the
# package correct when backend link sets change.
# ----------------------------------------------------------------------------
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
                echo "ERROR: cannot locate linked library ${dep}" >&2
                exit 1
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
        echo "ERROR: unknown platform tag '${PLATFORM}'" >&2
        exit 1
        ;;
esac

# ----------------------------------------------------------------------------
# Fail-closed sanity run from the staged layout.
# ----------------------------------------------------------------------------
case "${PLATFORM}" in
    macos-*) DYLD_LIBRARY_PATH="${STAGE}/lib" "${STAGE}/bin/rcli" version >/dev/null ;;
    linux-*) LD_LIBRARY_PATH="${STAGE}/lib" "${STAGE}/bin/rcli" version >/dev/null ;;
esac

# Release artifacts must not disclose the packager's checkout location. Keep
# this gate here so both CI smoke packages and tagged releases fail closed.
while IFS= read -r -d '' artifact; do
    if LC_ALL=C grep -aF -q -- "${REPO_ROOT}" "${artifact}"; then
        echo "ERROR: packaged artifact embeds the local checkout path: ${artifact#"${STAGE}/"}" >&2
        exit 1
    fi
done < <(find "${STAGE}/bin" "${STAGE}/lib" -type f -print0)

mkdir -p "${DIST_DIR}"
rm -f "${TARBALL}" "${TARBALL}.sha256"
tar -czf "${TARBALL}" -C "${STAGE_ROOT}" "rcli-${PLATFORM}"
(cd "${DIST_DIR}" && shasum -a 256 "$(basename "${TARBALL}")" > "$(basename "${TARBALL}").sha256")

echo "Packaged: ${TARBALL}"
echo "Contents:"
tar -tzf "${TARBALL}" | head -20
