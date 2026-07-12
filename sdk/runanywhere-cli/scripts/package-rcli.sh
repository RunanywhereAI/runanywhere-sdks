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

sanitize_pinned_host_path() {
    local artifact="$1"
    local source="$2"
    local replacement="$3"
    local expected_count="$4"
    local raw_digest="$5"
    local transformed_digest="$6"
    local label="$7"

    python3 - "${artifact}" "${source}" "${replacement}" "${expected_count}" \
        "${raw_digest}" "${transformed_digest}" "${label}" <<'PY'
from hashlib import sha256
from pathlib import Path
import sys

artifact = Path(sys.argv[1])
source = sys.argv[2].encode()
replacement = sys.argv[3].encode()
expected_count = int(sys.argv[4])
raw_digest, transformed_digest, label = sys.argv[5:8]
payload = artifact.read_bytes()

if len(source) != len(replacement):
    raise SystemExit(f"ERROR: {label} replacement changes binary offsets")

digest = sha256(payload).hexdigest()
if digest == raw_digest:
    if payload.count(source) != expected_count or replacement in payload:
        raise SystemExit(f"ERROR: {label} embedded-path inventory drifted")
    payload = payload.replace(source, replacement)
    if sha256(payload).hexdigest() != transformed_digest:
        raise SystemExit(f"ERROR: {label} sanitized digest mismatch")
    artifact.write_bytes(payload)
elif digest != transformed_digest:
    raise SystemExit(f"ERROR: unreviewed {label} bytes")

if payload.count(source) or payload.count(replacement) != expected_count:
    raise SystemExit(f"ERROR: {label} path sanitization was incomplete")
PY
}

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

        # The pinned ONNX Runtime 1.24.4 arm64 dylib embeds its upstream CI
        # checkout prefix in __FILE__ strings. Rewrite only that reviewed
        # byte prefix, with raw/transformed digests and occurrence count
        # pinned so an upstream artifact change fails closed.
        for library in "${STAGE}"/lib/libonnxruntime*.dylib; do
            [ -e "${library}" ] || continue
            sanitize_pinned_host_path \
                "${library}" \
                "/Users/cloudtest/vss/_work/" \
                "/runanywhere/vendor/onnxrt/" \
                843 \
                "872533f130f1839a5bc01788ddb4f75c83a189763441ba1178788ed965449289" \
                "3e4f1ac4cef99693c95532f38b436bd106156504c4dd51595af2e51d3c3d00ee" \
                "ONNX Runtime 1.24.4 arm64 dylib"
        done

        # A copied Homebrew dylib may retain an absolute install ID or refer
        # to another copied dylib through its Cellar path. Make the complete
        # staged set self-contained before validating the executable.
        for library in "${STAGE}"/lib/*.dylib; do
            [ -e "${library}" ] || continue
            library_name="$(basename "${library}")"
            library_id="$(otool -D "${library}" | tail -1)"
            if [[ "${library_id}" != @rpath/* && "${library_id}" != @loader_path/* ]]; then
                install_name_tool -id "@rpath/${library_name}" "${library}"
            fi
            library_deps=$(otool -L "${library}" | awk 'NR>1 {print $1}')
            for library_dep in ${library_deps}; do
                dep_name="$(basename "${library_dep}")"
                if [ "${dep_name}" != "${library_name}" ] \
                    && [ "${library_dep}" != "@loader_path/${dep_name}" ] \
                    && [ -f "${STAGE}/lib/${dep_name}" ]; then
                    install_name_tool -change "${library_dep}" "@loader_path/${dep_name}" "${library}"
                fi
            done
            while IFS= read -r rpath; do
                if [[ "${rpath}" != @loader_path* && "${rpath}" != @rpath* ]]; then
                    install_name_tool -delete_rpath "${rpath}" "${library}"
                fi
            done < <(otool -l "${library}" | awk '
                $1 == "cmd" && $2 == "LC_RPATH" { in_rpath = 1; next }
                in_rpath && $1 == "path" { print $2; in_rpath = 0 }
            ')
        done

        # The build-tree executable carries absolute LC_RPATH entries so it
        # can locate fetched dylibs before packaging. Retire every non-package
        # entry and install exactly one relocatable package rpath before the
        # privacy scan and ad-hoc signature.
        has_package_rpath=0
        while IFS= read -r rpath; do
            if [ "${rpath}" = "@loader_path/../lib" ]; then
                has_package_rpath=1
            else
                install_name_tool -delete_rpath "${rpath}" "${STAGE}/bin/rcli"
            fi
        done < <(otool -l "${STAGE}/bin/rcli" | awk '
            $1 == "cmd" && $2 == "LC_RPATH" { in_rpath = 1; next }
            in_rpath && $1 == "path" { print $2; in_rpath = 0 }
        ')
        if [ "${has_package_rpath}" -eq 0 ]; then
            install_name_tool -add_rpath "@loader_path/../lib" "${STAGE}/bin/rcli"
        fi

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
        # The pinned Sherpa-ONNX 1.13.2 x64 C API library carries its
        # upstream GitHub Actions source root. Apply the same exact,
        # byte-preserving fail-closed policy as the macOS runtime input.
        for library in "${STAGE}"/lib/libsherpa-onnx-c-api.so*; do
            [ -e "${library}" ] || continue
            sanitize_pinned_host_path \
                "${library}" \
                "/home/runner/work/sherpa-onnx/sherpa-onnx" \
                "/runanywhere/vendor/sherpa-onnx/src/root0" \
                250 \
                "744cabaf8bdc079414e3f07d3cdf3550a5c74798a4b50c789468e7b038b7907f" \
                "b6fecd4a48bea06c50bf6bfd69e08ff241071b47251f90b8549491a120af0498" \
                "Sherpa-ONNX 1.13.2 x64 C API library"
        done
        command -v patchelf >/dev/null 2>&1 || {
            echo "ERROR: patchelf is required to make the Linux package relocatable" >&2
            exit 1
        }
        patchelf --set-rpath "\$ORIGIN/../lib" "${STAGE}/bin/rcli"
        while IFS= read -r -d '' library; do
            patchelf --set-rpath "\$ORIGIN" "${library}"
        done < <(find "${STAGE}/lib" -type f -print0)
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
    macos-*|linux-*) "${STAGE}/bin/rcli" version >/dev/null ;;
esac

# Release artifacts must not disclose the packager's checkout location. Keep
# this gate here so both CI smoke packages and tagged releases fail closed.
while IFS= read -r -d '' artifact; do
    if LC_ALL=C grep -aF -q -- "${REPO_ROOT}" "${artifact}"; then
        echo "ERROR: packaged artifact embeds the local checkout path: ${artifact#"${STAGE}/"}" >&2
        exit 1
    fi
    if LC_ALL=C grep -aE -q -- '/Users/[^/]+/|/home/[^/]+/|/var/folders/' "${artifact}" \
        || LC_ALL=C grep -aE -q -- "[A-Za-z]:\\\\Users\\\\" "${artifact}"; then
        echo "ERROR: packaged artifact embeds a developer home path: ${artifact#"${STAGE}/"}" >&2
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
