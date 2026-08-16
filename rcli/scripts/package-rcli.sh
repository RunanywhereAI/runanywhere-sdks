#!/usr/bin/env bash
# =============================================================================
# package-rcli.sh <build-dir> <platform-tag>
#
# Stages bin/rcli + the shared libraries it actually links (discovered via
# otool/ldd, fail-closed) into a relocatable layout, sanity-runs the staged
# binary, and packs rcli-<platform>-v<version>.tar.gz + .sha256 under
# rcli/dist/.
#
# A tagged macOS release sets RCLI_MACOS_FULL_RELEASE=1 and points
# RCLI_MACOS_SWIFT_BIN_DIR at the release output of build-mlx-cli.sh. That
# product is the combined Swift/C++ host: it registers the MLX callbacks and
# then runs the same rcli command stack with llama.cpp and MLX both enabled.
# The package additionally stages mlx.metallib and the SwiftPM resource
# bundles beside the executable, where Bundle.module resolves them.
#
# Developer ID distribution is opt-in so pull-request smoke packaging remains
# credential-free. Set RCLI_CODESIGN_IDENTITY plus either a notarytool keychain
# profile (and RCLI_NOTARYTOOL_KEYCHAIN when the profile is in a non-default
# keychain) or App Store Connect API-key inputs, and RCLI_MACOS_NOTARIZE=1.
# The notarized, stapled DMG is emitted alongside the Homebrew-compatible
# tarball.
#
#   platform-tag: macos-arm64 | linux-x86_64
#   version:      $RAC_RELEASE_VERSION, else core/VERSION
#
# Layout inside the tarball (matches the binary's INSTALL_RPATH
# @loader_path/../lib | $ORIGIN/../lib):
#   rcli-<platform>/bin/rcli
#   rcli-macos-arm64/bin/mlx.metallib + *.bundle  (full macOS release)
#   rcli-<platform>/lib/*.dylib|*.so*
#   rcli-<platform>/README.md
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${CLI_ROOT}/.." && pwd)"

BUILD_DIR="${1:?usage: package-rcli.sh <build-dir> <platform-tag>}"
PLATFORM="${2:?usage: package-rcli.sh <build-dir> <platform-tag>}"
[[ "${BUILD_DIR}" = /* ]] || BUILD_DIR="${REPO_ROOT}/${BUILD_DIR}"

VERSION="${RAC_RELEASE_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/core/VERSION")}"
MACOS_FULL_RELEASE="${RCLI_MACOS_FULL_RELEASE:-0}"
MACOS_NOTARIZE="${RCLI_MACOS_NOTARIZE:-0}"
SWIFT_BIN_DIR="${RCLI_MACOS_SWIFT_BIN_DIR:-}"
CODESIGN_IDENTITY="${RCLI_CODESIGN_IDENTITY:-}"
CODESIGN_KEYCHAIN="${RCLI_CODESIGN_KEYCHAIN:-}"
BINARY="${BUILD_DIR}/rcli/rcli"
DIST_DIR="${CLI_ROOT}/dist"
STAGE_ROOT="${DIST_DIR}/stage"
STAGE="${STAGE_ROOT}/rcli-${PLATFORM}"
TARBALL="${DIST_DIR}/rcli-${PLATFORM}-v${VERSION}.tar.gz"
DMG="${DIST_DIR}/rcli-${PLATFORM}-v${VERSION}.dmg"

case "${MACOS_FULL_RELEASE}:${MACOS_NOTARIZE}" in
    0:0|0:1|1:0|1:1) ;;
    *) echo "ERROR: RCLI_MACOS_FULL_RELEASE and RCLI_MACOS_NOTARIZE must be 0 or 1" >&2; exit 2 ;;
esac

if [[ "${PLATFORM}" == macos-* && "${MACOS_FULL_RELEASE}" == "1" ]]; then
    [ -n "${SWIFT_BIN_DIR}" ] || {
        echo "ERROR: RCLI_MACOS_SWIFT_BIN_DIR is required for a full macOS release" >&2
        exit 1
    }
    BINARY="${SWIFT_BIN_DIR}/RunAnywhereMLXCLI"
fi

if [[ "${MACOS_NOTARIZE}" == "1" ]]; then
    [[ "${PLATFORM}" == macos-* && "${MACOS_FULL_RELEASE}" == "1" ]] || {
        echo "ERROR: notarization is supported only for a full macOS release" >&2
        exit 1
    }
    [ -n "${CODESIGN_IDENTITY}" ] || {
        echo "ERROR: RCLI_CODESIGN_IDENTITY is required for notarization" >&2
        exit 1
    }
fi

[ -x "${BINARY}" ] || { echo "ERROR: rcli binary not found at ${BINARY}" >&2; exit 1; }

sanitize_macho_host_prefix() {
    local artifact="$1"
    local source_prefix="$2"
    local stable_prefix="$3"
    local label="$4"

    python3 - "${artifact}" "${source_prefix}" "${stable_prefix}" "${label}" <<'PY'
from pathlib import Path
import sys

artifact = Path(sys.argv[1])
source = sys.argv[2].encode()
stable_prefix = sys.argv[3].encode()
label = sys.argv[4]
payload = artifact.read_bytes()
count = payload.count(source)
if count == 0:
    raise SystemExit(f"ERROR: full macOS host contains no reviewed {label} prefix")

if len(stable_prefix) > len(source):
    stable_prefix = b"/"
replacement = stable_prefix + (b"_" * (len(source) - len(stable_prefix)))
payload = payload.replace(source, replacement)
if source in payload or len(payload) != artifact.stat().st_size:
    raise SystemExit(f"ERROR: {label} sanitization was incomplete")
artifact.write_bytes(payload)
PY
}

rm -rf "${STAGE}"
mkdir -p "${STAGE}/bin" "${STAGE}/lib"
cp "${BINARY}" "${STAGE}/bin/rcli"
cp "${CLI_ROOT}/README.md" "${STAGE}/README.md"

if [[ "${PLATFORM}" == macos-* && "${MACOS_FULL_RELEASE}" == "1" ]]; then
    [ -s "${SWIFT_BIN_DIR}/mlx.metallib" ] || {
        echo "ERROR: full macOS release is missing ${SWIFT_BIN_DIR}/mlx.metallib" >&2
        exit 1
    }
    cp "${SWIFT_BIN_DIR}/mlx.metallib" "${STAGE}/bin/mlx.metallib"

    resource_count=0
    while IFS= read -r -d '' bundle; do
        cp -R "${bundle}" "${STAGE}/bin/$(basename "${bundle}")"
        resource_count=$((resource_count + 1))
    done < <(find "${SWIFT_BIN_DIR}" -maxdepth 1 -type d -name '*.bundle' \
        ! -name '*-tool.bundle' -print0)
    [ "${resource_count}" -gt 0 ] || {
        echo "ERROR: full macOS release contains no SwiftPM resource bundles" >&2
        exit 1
    }
    [ -d "${STAGE}/bin/swift-transformers_Hub.bundle" ] || {
        echo "ERROR: full macOS release is missing swift-transformers_Hub.bundle" >&2
        exit 1
    }

    # SwiftPM resource accessors contain a build-tree fallback after their
    # relocatable Bundle.main lookup. Replace only that known prefix, keeping
    # Mach-O offsets stable, before the package privacy scan and final signing.
    sanitize_macho_host_prefix \
        "${STAGE}/bin/rcli" \
        "${SWIFT_BIN_DIR}/" \
        "/runanywhere/swiftpm-resources/" \
        "SwiftPM resource path"
    sanitize_macho_host_prefix \
        "${STAGE}/bin/rcli" \
        "${REPO_ROOT}/" \
        "/runanywhere/source/" \
        "source checkout path"

    # Copy any Swift compatibility runtime required by the deployment target.
    # Current macOS provides the standard Swift runtime; this normally stages
    # only compatibility shims such as libswiftCompatibilitySpan.dylib.
    # Xcode 26.6's swift-stdlib-tool resolves --unsigned-destination to `/`
    # for this standalone executable layout. --destination preserves the
    # requested directory; every copied dylib is signed explicitly below.
    xcrun swift-stdlib-tool --copy \
        --scan-executable "${STAGE}/bin/rcli" \
        --platform macosx \
        --destination "${STAGE}/lib"
fi

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
                if [ -f "${STAGE}/lib/${local_name}" ]; then
                    src="${STAGE}/lib/${local_name}"
                else
                # Release archives may contain a dSYM DWARF file with the same
                # basename as the linked dylib. Search only library entries
                # so filesystem traversal order cannot select debug symbols.
                    # Versioned runtime archives use symlink chains such as
                    # libonnxruntime.1.dylib -> libonnxruntime.1.28.0.dylib.
                    # -type f drops the linked name that Mach-O records, so
                    # accept both regular files and symlinks here. The -f
                    # validation below still rejects broken links.
                    src="$(find "${BUILD_DIR}" -path "*/lib/${local_name}" \
                        \( -type f -o -type l \) \
                        ! -path "*/.dSYM/*" 2>/dev/null | LC_ALL=C sort | head -1)"
                fi
            fi
            if [ -z "${src}" ] || [ ! -f "${src}" ]; then
                echo "ERROR: cannot locate linked library ${dep}" >&2
                exit 1
            fi
            if [ "${src}" != "${STAGE}/lib/${local_name}" ]; then
                cp "${src}" "${STAGE}/lib/${local_name}"
            fi
            install_name_tool -change "${dep}" "@rpath/${local_name}" "${STAGE}/bin/rcli"
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

        if [ -n "${CODESIGN_IDENTITY}" ]; then
            codesign_args=(--force --sign "${CODESIGN_IDENTITY}" --options runtime --timestamp)
            if [ -n "${CODESIGN_KEYCHAIN}" ]; then
                codesign_args+=(--keychain "${CODESIGN_KEYCHAIN}")
            fi
            while IFS= read -r -d '' library; do
                codesign "${codesign_args[@]}" "${library}"
            done < <(find "${STAGE}/lib" -name '*.dylib' -type f -print0)
            codesign "${codesign_args[@]}" "${STAGE}/bin/rcli"
            codesign --verify --strict --verbose=2 "${STAGE}/bin/rcli"
            codesign_metadata="$(codesign -dvvv "${STAGE}/bin/rcli" 2>&1)"
            [[ "${codesign_metadata}" == *'Authority=Developer ID Application:'* ]] || {
                echo "ERROR: rcli is not signed by a Developer ID Application certificate" >&2
                exit 1
            }
            [[ "${codesign_metadata}" =~ flags=.*runtime ]] || {
                echo "ERROR: rcli signature does not enable the hardened runtime" >&2
                exit 1
            }
        else
            # Credential-free smoke packages remain ad-hoc signed. Tagged
            # production releases set RCLI_CODESIGN_IDENTITY and notarize.
            codesign --force -s - "${STAGE}/bin/rcli"
            find "${STAGE}/lib" -name "*.dylib" -exec codesign --force -s - {} \;
        fi
        ;;
    linux-*)
        deps=$(ldd "${STAGE}/bin/rcli" | awk '/=>/ {print $3}' \
               | grep -vE '^(/lib|/usr/lib|/lib64)' || true)
        for src in ${deps}; do
            [ -f "${src}" ] && cp -L "${src}" "${STAGE}/lib/$(basename "${src}")"
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
rm -f "${TARBALL}" "${TARBALL}.sha256" "${DMG}" "${DMG}.sha256"
tar -czf "${TARBALL}" -C "${STAGE_ROOT}" "rcli-${PLATFORM}"
(cd "${DIST_DIR}" && shasum -a 256 "$(basename "${TARBALL}")" > "$(basename "${TARBALL}").sha256")

if [[ "${PLATFORM}" == macos-* && "${MACOS_NOTARIZE}" == "1" ]]; then
    notary_args=()
    if [ -n "${RCLI_NOTARYTOOL_PROFILE:-}" ]; then
        notary_args+=(--keychain-profile "${RCLI_NOTARYTOOL_PROFILE}")
        if [ -n "${RCLI_NOTARYTOOL_KEYCHAIN:-}" ]; then
            [ -f "${RCLI_NOTARYTOOL_KEYCHAIN}" ] || {
                echo "ERROR: RCLI_NOTARYTOOL_KEYCHAIN does not exist" >&2
                exit 1
            }
            notary_args+=(--keychain "${RCLI_NOTARYTOOL_KEYCHAIN}")
        fi
    elif [ -n "${RCLI_NOTARY_KEY_PATH:-}" ] \
        && [ -n "${RCLI_NOTARY_KEY_ID:-}" ] \
        && [ -n "${RCLI_NOTARY_ISSUER_ID:-}" ]; then
        [ -f "${RCLI_NOTARY_KEY_PATH}" ] || {
            echo "ERROR: RCLI_NOTARY_KEY_PATH does not exist" >&2
            exit 1
        }
        notary_args+=(
            --key "${RCLI_NOTARY_KEY_PATH}"
            --key-id "${RCLI_NOTARY_KEY_ID}"
            --issuer "${RCLI_NOTARY_ISSUER_ID}"
        )
    else
        echo "ERROR: provide RCLI_NOTARYTOOL_PROFILE or the complete App Store Connect API-key inputs" >&2
        exit 1
    fi

    hdiutil create -quiet -fs HFS+ -format UDZO \
        -volname "rcli ${VERSION}" \
        -srcfolder "${STAGE}" \
        "${DMG}"
    dmg_codesign_args=(--force --sign "${CODESIGN_IDENTITY}" --timestamp)
    if [ -n "${CODESIGN_KEYCHAIN}" ]; then
        dmg_codesign_args+=(--keychain "${CODESIGN_KEYCHAIN}")
    fi
    codesign "${dmg_codesign_args[@]}" "${DMG}"
    xcrun notarytool submit "${DMG}" "${notary_args[@]}" --wait
    xcrun stapler staple "${DMG}"
    xcrun stapler validate "${DMG}"
    (cd "${DIST_DIR}" && shasum -a 256 "$(basename "${DMG}")" > "$(basename "${DMG}").sha256")
fi

echo "Packaged: ${TARBALL}"
if [ -f "${DMG}" ]; then
    echo "Notarized + stapled: ${DMG}"
fi
echo "Contents:"
tar -tzf "${TARBALL}" | head -20
