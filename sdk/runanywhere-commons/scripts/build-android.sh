#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# build-android.sh — package-local compatibility wrapper.
#
# The original per-package Android build entry
# point was deleted in favour of repo-root scripts/build/build-core-android.sh,
# but `.github/workflows/release.yml` (native_android matrix job) and the
# README/CLAUDE.md docs continue to invoke this path. This shim restores
# the workflow contract by:
#
#   1. Forwarding the supplied ABI (the second positional argument from
#      release.yml: `./scripts/build-android.sh all <abi>`) to the
#      repo-root build-core-android.sh script. The first positional
#      argument (e.g. `all`) is accepted but ignored — the new script
#      always builds the canonical commons + plugin set.
#   2. Staging the resulting `.so` libraries (commons + llamacpp + onnx) for
#      that ABI into the versioned release archive
#      `sdk/runanywhere-commons/dist/RACommons-android-<abi>-v<version>.zip`
#      (+ .sha256) that release.yml uploads and `publish` asserts on.
#
# Long-term, callers should migrate to invoking
# scripts/build/build-core-android.sh directly.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMONS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${COMMONS_ROOT}/../.." && pwd)"

# Argument parsing — release.yml passes `all <abi>`. We accept either
# `<abi>` or `<which> <abi>` for backward compatibility.
ABI=""
case "${#}" in
    0)
        echo "usage: build-android.sh [<which>] <abi>" >&2
        echo "       <abi> ∈ {arm64-v8a, armeabi-v7a, x86_64}" >&2
        exit 2
        ;;
    1)
        ABI="$1"
        ;;
    *)
        # Ignore the first arg (legacy `which` selector) — the new build
        # script always builds the canonical commons + plugin set.
        ABI="$2"
        ;;
esac

if [[ ! "${ABI}" =~ ^(arm64-v8a|armeabi-v7a|x86_64)$ ]]; then
    echo "error: unsupported ABI '${ABI}' (expected arm64-v8a, armeabi-v7a, or x86_64)" >&2
    exit 2
fi

CORE_SCRIPT="${REPO_ROOT}/scripts/build/build-core-android.sh"
if [ ! -x "${CORE_SCRIPT}" ]; then
    echo "error: ${CORE_SCRIPT} not found or not executable" >&2
    exit 1
fi

echo "▶ Delegating Android build to scripts/build/build-core-android.sh ${ABI}"
"${CORE_SCRIPT}" "${ABI}"

# Stage the produced .so libraries (commons + llamacpp + onnx backends) for
# this ABI into a single per-ABI release zip + .sha256 under dist/ — the layout
# the Kotlin/RN SDK jobs expect when they extract the artifact. Sources are the
# Android-library `src/main/jniLibs` trees that build-core-android.sh writes to
# (NOT the KMP `src/androidMain` layout the SDK was migrated FROM). Version:
# RAC_RELEASE_VERSION (the release tag) or PROJECT_VERSION for standalone runs.
source "${SCRIPT_DIR}/load-versions.sh" >/dev/null
VERSION="${RAC_RELEASE_VERSION:-${PROJECT_VERSION}}"

KOTLIN_BASE="${REPO_ROOT}/sdk/runanywhere-kotlin"
DIST="${COMMONS_ROOT}/dist"
STAGING="${DIST}/android-staging/${ABI}"
rm -rf "${STAGING}"
mkdir -p "${STAGING}"

# Copy a backend's per-ABI .so set into STAGING/<sub>/ if it was produced.
# A plain function (not a bash-4 associative array) keeps this portable for
# local macOS runs (bash 3.2) as well as the ubuntu CI runner.
stage_backend() {
    local sub="$1" src="$2"
    if [ -d "${src}" ]; then
        mkdir -p "${STAGING}/${sub}"
        cp -R "${src}/." "${STAGING}/${sub}/"
    fi
}
stage_backend jni      "${KOTLIN_BASE}/src/main/jniLibs/${ABI}"
stage_backend llamacpp "${KOTLIN_BASE}/modules/runanywhere-core-llamacpp/src/main/jniLibs/${ABI}"
stage_backend onnx     "${KOTLIN_BASE}/modules/runanywhere-core-onnx/src/main/jniLibs/${ABI}"
# Flat `unified/` convenience copy — every .so for this ABI in one place.
mkdir -p "${STAGING}/unified"
find "${STAGING}" -maxdepth 2 -name "*.so" -exec cp {} "${STAGING}/unified/" \; 2>/dev/null || true

ZIP="RACommons-android-${ABI}-v${VERSION}.zip"
rm -f "${DIST}/${ZIP}" "${DIST}/${ZIP}.sha256"
(cd "${DIST}/android-staging" && zip -r "../${ZIP}" "${ABI}")
(cd "${DIST}" && shasum -a 256 "${ZIP}" > "${ZIP}.sha256")

checksum_zip() {
    local zip="$1"
    (cd "${DIST}" && shasum -a 256 "${zip}" > "${zip}.sha256")
}

package_subdir_zip() {
    local subdir="$1"
    local zip="$2"
    local extra_file="${3:-}"
    local package_root="${DIST}/android-package-${subdir}-${ABI}"

    if [ -n "${extra_file}" ] && [ ! -f "${STAGING}/jni/${extra_file}" ]; then
        echo "::error::Missing required extra file '${extra_file}' for backend '${subdir}'"
        return 1
    fi

    rm -rf "${package_root}"
    mkdir -p "${package_root}/${subdir}"
    cp -R "${STAGING}/${subdir}/." "${package_root}/${subdir}/"
    if [ -n "${extra_file}" ]; then
        cp "${STAGING}/jni/${extra_file}" "${package_root}/${subdir}/"
    fi

    rm -f "${DIST}/${zip}" "${DIST}/${zip}.sha256"
    (cd "${package_root}" && zip -r "${DIST}/${zip}" "${subdir}")
    checksum_zip "${zip}"
    rm -rf "${package_root}"
}

package_subdir_zip "llamacpp" "RABackendLLAMACPP-android-${ABI}-v${VERSION}.zip" "libc++_shared.so"
package_subdir_zip "onnx" "RABackendONNX-android-${ABI}-v${VERSION}.zip"

echo "✓ build-android.sh complete; staged ABI '${ABI}' → ${DIST}/${ZIP}"
