#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# build-android.sh — package-local compatibility wrapper.
#
# The original per-package Android build entry
# point was deleted in favour of repo-root scripts/build-core-android.sh,
# but `.github/workflows/release.yml` (native_android matrix job) and the
# README/CLAUDE.md docs continue to invoke this path. This shim restores
# the workflow contract by:
#
#   1. Forwarding the supplied ABI (the second positional argument from
#      release.yml: `./scripts/build-android.sh all <abi>`) to the
#      repo-root build-core-android.sh script. The first positional
#      argument (e.g. `all`) is accepted but ignored — the new script
#      always builds the canonical commons + plugin set.
#   2. Staging the resulting `.so` libraries from the per-SDK jniLibs
#      destinations into `sdk/runanywhere-commons/dist/android/<sub>/<abi>/`
#      so the release workflow's `dist/android-staging` packaging step
#      continues to see the expected layout.
#
# Long-term, callers should migrate to invoking
# scripts/build-core-android.sh directly.
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

CORE_SCRIPT="${REPO_ROOT}/scripts/build-core-android.sh"
if [ ! -x "${CORE_SCRIPT}" ]; then
    echo "error: ${CORE_SCRIPT} not found or not executable" >&2
    exit 1
fi

echo "▶ Delegating Android build to scripts/build-core-android.sh ${ABI}"
"${CORE_SCRIPT}" "${ABI}"

# Stage the produced .so artifacts into the legacy
# dist/android/<sub>/<abi>/ layout that the release workflow's
# dist/android-staging packaging step still references.
KOTLIN_JNI="${REPO_ROOT}/sdk/runanywhere-kotlin/src/androidMain/jniLibs/${ABI}"
KOTLIN_LLAMA_JNI="${REPO_ROOT}/sdk/runanywhere-kotlin/modules/runanywhere-core-llamacpp/src/androidMain/jniLibs/${ABI}"
KOTLIN_ONNX_JNI="${REPO_ROOT}/sdk/runanywhere-kotlin/modules/runanywhere-core-onnx/src/androidMain/jniLibs/${ABI}"

DIST_BASE="${COMMONS_ROOT}/dist/android"
mkdir -p \
    "${DIST_BASE}/jni/${ABI}" \
    "${DIST_BASE}/unified/${ABI}" \
    "${DIST_BASE}/llamacpp/${ABI}" \
    "${DIST_BASE}/onnx/${ABI}"

# `jni/` mirrors the canonical commons + JNI bridge artifacts so consumers
# can pick them up directly. `unified/` ships the same file set as a
# convenience copy for downstream packagers (parity with the prior layout).
if [ -d "${KOTLIN_JNI}" ]; then
    cp -R "${KOTLIN_JNI}/." "${DIST_BASE}/jni/${ABI}/"
    cp -R "${KOTLIN_JNI}/." "${DIST_BASE}/unified/${ABI}/"
fi
if [ -d "${KOTLIN_LLAMA_JNI}" ]; then
    cp -R "${KOTLIN_LLAMA_JNI}/." "${DIST_BASE}/llamacpp/${ABI}/"
fi
if [ -d "${KOTLIN_ONNX_JNI}" ]; then
    cp -R "${KOTLIN_ONNX_JNI}/." "${DIST_BASE}/onnx/${ABI}/"
fi

echo "✓ build-android.sh wrapper complete; staged ABI '${ABI}' artifacts under ${DIST_BASE}"
