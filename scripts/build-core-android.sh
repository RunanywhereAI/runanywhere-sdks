#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# build-core-android.sh — wraps the android-{arm64,armv7,x86_64} CMake presets
# and stages the resulting native artifacts into the SDKs that consume them
# directly from source:
#   - Kotlin (`src/androidMain/jniLibs`)
#   - React Native core/llamacpp/onnx (`android/src/main/jniLibs`)
#   - Flutter runanywhere/runanywhere_llamacpp/runanywhere_onnx/runanywhere_genie
#     (`android/src/main/jniLibs`)
#
# GAP 07 Phase 6 — see v2_gap_specs/GAP_07_SINGLE_ROOT_CMAKE.md.
#
# Usage:
#   ./scripts/build-core-android.sh                  # build all 3 ABIs
#   ./scripts/build-core-android.sh arm64-v8a        # single ABI
#   ./scripts/build-core-android.sh --release        # forwards to ctest preset
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Kotlin + React Native destinations (existing).
KOTLIN_JNI_DEST="${REPO_ROOT}/sdk/runanywhere-kotlin/src/androidMain/jniLibs"
RN_CORE_JNI_DEST="${REPO_ROOT}/sdk/runanywhere-react-native/packages/core/android/src/main/jniLibs"
RN_LLAMA_JNI_DEST="${REPO_ROOT}/sdk/runanywhere-react-native/packages/llamacpp/android/src/main/jniLibs"
RN_ONNX_JNI_DEST="${REPO_ROOT}/sdk/runanywhere-react-native/packages/onnx/android/src/main/jniLibs"
RN_CORE_INCLUDE_DEST="${RN_CORE_JNI_DEST}/include"

# Flutter destinations (new — T0.1).
FLUTTER_CORE_JNI_DEST="${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere/android/src/main/jniLibs"
FLUTTER_LLAMA_JNI_DEST="${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_llamacpp/android/src/main/jniLibs"
FLUTTER_ONNX_JNI_DEST="${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_onnx/android/src/main/jniLibs"
FLUTTER_GENIE_JNI_DEST="${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_genie/android/src/main/jniLibs"

COMMONS_INCLUDE_SRC="${REPO_ROOT}/sdk/runanywhere-commons/include"
SHERPA_ANDROID_JNI_SRC="${REPO_ROOT}/sdk/runanywhere-commons/third_party/sherpa-onnx-android/jniLibs"

if [ -z "${ANDROID_NDK_HOME:-}" ]; then
    echo "error: ANDROID_NDK_HOME is not set. Install the NDK and export it." >&2
    exit 1
fi

# ABI selection
if [ "$#" -ge 1 ] && [[ "$1" =~ ^(arm64-v8a|armeabi-v7a|x86_64)$ ]]; then
    ABIS=("$1"); shift
else
    ABIS=("arm64-v8a" "armeabi-v7a" "x86_64")
fi

# ABI → preset mapping. Written as a `case` block instead of an associative
# array (`declare -A`) so this script works on macOS' default /bin/bash 3.2,
# which predates bash 4's associative-array support.
preset_for_abi() {
    case "$1" in
        arm64-v8a)   echo "android-arm64"   ;;
        armeabi-v7a) echo "android-armv7"   ;;
        x86_64)      echo "android-x86_64"  ;;
        *)
            echo "error: unknown Android ABI '$1' (expected arm64-v8a|armeabi-v7a|x86_64)" >&2
            exit 1
            ;;
    esac
}

# Map ABI → NDK sysroot triple directory (for locating libc++_shared.so).
ndk_triple_for_abi() {
    case "$1" in
        arm64-v8a)   echo "aarch64-linux-android"  ;;
        armeabi-v7a) echo "arm-linux-androideabi"  ;;
        x86_64)      echo "x86_64-linux-android"   ;;
        *)
            echo "error: unknown Android ABI '$1' (cannot map to NDK triple)" >&2
            exit 1
            ;;
    esac
}

# Detect NDK host tag so we can locate libc++_shared.so in the prebuilt sysroot.
HOST_UNAME="$(uname -s)"
case "${HOST_UNAME}" in
    Darwin) NDK_HOST_TAG="darwin-x86_64" ;;
    Linux)  NDK_HOST_TAG="linux-x86_64"  ;;
    *)
        echo "error: unsupported host '${HOST_UNAME}' for NDK libc++_shared lookup" >&2
        exit 1
        ;;
esac
NDK_SYSROOT_LIB="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/${NDK_HOST_TAG}/sysroot/usr/lib"

mkdir -p \
    "${KOTLIN_JNI_DEST}" \
    "${RN_CORE_JNI_DEST}" \
    "${RN_LLAMA_JNI_DEST}" \
    "${RN_ONNX_JNI_DEST}" \
    "${FLUTTER_CORE_JNI_DEST}" \
    "${FLUTTER_LLAMA_JNI_DEST}" \
    "${FLUTTER_ONNX_JNI_DEST}" \
    "${FLUTTER_GENIE_JNI_DEST}"

rm -rf "${RN_CORE_INCLUDE_DEST}"
mkdir -p "${RN_CORE_INCLUDE_DEST}"
cp -R "${COMMONS_INCLUDE_SRC}/." "${RN_CORE_INCLUDE_DEST}/"

# Helper: copy `${1}` to every remaining argument, skipping the source silently
# if it does not exist. Used to make engine-specific staging tolerant of
# missing artifacts (e.g. llamacpp JNI not emitted on every configuration).
copy_if_exists() {
    local src="$1"; shift
    if [ -f "${src}" ]; then
        for dst in "$@"; do
            mkdir -p "${dst}"
            cp -v "${src}" "${dst}/"
        done
    fi
}

for ABI in "${ABIS[@]}"; do
    PRESET="$(preset_for_abi "${ABI}")"
    TRIPLE="$(ndk_triple_for_abi "${ABI}")"
    echo "▶ ${ABI} via preset '${PRESET}'"

    cmake --preset "${PRESET}"
    # Use CMake's generator-agnostic --parallel (Ninja rejects a bare `-j`,
    # while Make accepts it). Lets CMake pick a sensible default job count.
    cmake --build --preset "${PRESET}" --parallel

    BUILD_DIR="${REPO_ROOT}/build/${PRESET}"
    KOTLIN_DEST="${KOTLIN_JNI_DEST}/${ABI}"
    RN_CORE_DEST="${RN_CORE_JNI_DEST}/${ABI}"
    RN_LLAMA_DEST="${RN_LLAMA_JNI_DEST}/${ABI}"
    RN_ONNX_DEST="${RN_ONNX_JNI_DEST}/${ABI}"
    FLUTTER_CORE_DEST="${FLUTTER_CORE_JNI_DEST}/${ABI}"
    FLUTTER_LLAMA_DEST="${FLUTTER_LLAMA_JNI_DEST}/${ABI}"
    FLUTTER_ONNX_DEST="${FLUTTER_ONNX_JNI_DEST}/${ABI}"
    FLUTTER_GENIE_DEST="${FLUTTER_GENIE_JNI_DEST}/${ABI}"

    mkdir -p \
        "${KOTLIN_DEST}" \
        "${RN_CORE_DEST}" "${RN_LLAMA_DEST}" "${RN_ONNX_DEST}" \
        "${FLUTTER_CORE_DEST}" "${FLUTTER_LLAMA_DEST}" "${FLUTTER_ONNX_DEST}" "${FLUTTER_GENIE_DEST}"

    # Clean everything we manage before re-staging so stale artifacts from a
    # previous run (e.g. a dropped backend) don't linger.
    rm -f \
        "${RN_CORE_DEST}"/*.so "${RN_LLAMA_DEST}"/*.so "${RN_ONNX_DEST}"/*.so \
        "${FLUTTER_CORE_DEST}"/*.so "${FLUTTER_LLAMA_DEST}"/*.so \
        "${FLUTTER_ONNX_DEST}"/*.so "${FLUTTER_GENIE_DEST}"/*.so

    # -------------------------------------------------------------------------
    # Locate artifacts produced by the CMake build.
    #
    # Depth bumped from 4 → 6 so we also catch the commons JNI bridge, which
    # lives one level deeper than the engine plugins:
    #   build/<preset>/sdk/runanywhere-commons/src/jni/librunanywhere_jni.so
    # -------------------------------------------------------------------------
    LIB_COMMONS="$(find "${BUILD_DIR}" -maxdepth 6 -name "librac_commons.so"             -print -quit || true)"
    LIB_COMMONS_JNI="$(find "${BUILD_DIR}" -maxdepth 6 -name "librunanywhere_jni.so"     -print -quit || true)"
    LIB_LLAMA="$(find "${BUILD_DIR}" -maxdepth 6 -name "librac_backend_llamacpp.so"      -print -quit || true)"
    LIB_LLAMA_JNI="$(find "${BUILD_DIR}" -maxdepth 6 -name "librac_backend_llamacpp_jni.so" -print -quit || true)"
    LIB_ONNX="$(find "${BUILD_DIR}"  -maxdepth 6 -name "librac_backend_onnx.so"          -print -quit || true)"
    LIB_ONNX_JNI="$(find "${BUILD_DIR}" -maxdepth 6 -name "librac_backend_onnx_jni.so"   -print -quit || true)"
    # GAP 06 T5.1 — new Sherpa-ONNX plugin artifact, peer of librac_backend_onnx.so.
    LIB_SHERPA="$(find "${BUILD_DIR}" -maxdepth 6 -name "librac_backend_sherpa.so"       -print -quit || true)"

    # commons core + JNI go to Kotlin, RN core and Flutter core.
    copy_if_exists "${LIB_COMMONS}"     "${KOTLIN_DEST}" "${RN_CORE_DEST}" "${FLUTTER_CORE_DEST}"
    copy_if_exists "${LIB_COMMONS_JNI}" "${KOTLIN_DEST}" "${RN_CORE_DEST}" "${FLUTTER_CORE_DEST}"

    # Engine plugin entry-point libs (runanywhere_<engine>.so) — Kotlin loads
    # them via the dlopen registry. Keep the original glob-based collection
    # for Kotlin so every emitted plugin is packaged.
    find "${BUILD_DIR}" -maxdepth 6 -name "librunanywhere_*.so" -exec cp -v {} "${KOTLIN_DEST}/" \;

    # Per-engine backend + JNI libs. Staged to both RN and Flutter plugin
    # packages so the same jniLibs layout is shipped from every SDK.
    copy_if_exists "${LIB_LLAMA}"     "${RN_LLAMA_DEST}" "${FLUTTER_LLAMA_DEST}"
    copy_if_exists "${LIB_LLAMA_JNI}" "${RN_LLAMA_DEST}" "${FLUTTER_LLAMA_DEST}"
    copy_if_exists "${LIB_ONNX}"      "${RN_ONNX_DEST}"  "${FLUTTER_ONNX_DEST}"
    copy_if_exists "${LIB_ONNX_JNI}"  "${RN_ONNX_DEST}"  "${FLUTTER_ONNX_DEST}"
    # Sherpa is the long-term owner of Sherpa-ONNX-backed STT/TTS/VAD; ship
    # it alongside the onnx plugin on every ONNX-enabled SDK package. Also
    # stage into Kotlin so its dlopen registry picks up the plugin.
    copy_if_exists "${LIB_SHERPA}"    "${RN_ONNX_DEST}"  "${FLUTTER_ONNX_DEST}" "${KOTLIN_DEST}"

    # Sherpa / ORT prebuilt runtime — only has arm64-v8a/armeabi-v7a/x86_64
    # sub-folders. Staged into both RN and Flutter ONNX plugins.
    if [ -d "${SHERPA_ANDROID_JNI_SRC}/${ABI}" ]; then
        find "${SHERPA_ANDROID_JNI_SRC}/${ABI}" -maxdepth 1 -name "*.so" \
            -exec cp -v {} "${RN_ONNX_DEST}/" \; \
            -exec cp -v {} "${FLUTTER_ONNX_DEST}/" \;
    fi

    # libc++_shared.so is required at runtime for every package that loads
    # any .so built with ANDROID_STL=c++_shared. AGP de-duplicates it via
    # `pickFirsts` in each Flutter package's build.gradle, so shipping it in
    # every jniLibs dir is safe.
    LIBCXX_SHARED="${NDK_SYSROOT_LIB}/${TRIPLE}/libc++_shared.so"
    if [ ! -f "${LIBCXX_SHARED}" ]; then
        echo "error: libc++_shared.so not found at ${LIBCXX_SHARED}. Is ANDROID_NDK_HOME correct?" >&2
        exit 1
    fi
    for dst in \
        "${KOTLIN_DEST}" \
        "${RN_CORE_DEST}" "${RN_LLAMA_DEST}" "${RN_ONNX_DEST}" \
        "${FLUTTER_CORE_DEST}" "${FLUTTER_LLAMA_DEST}" "${FLUTTER_ONNX_DEST}" "${FLUTTER_GENIE_DEST}" ; do
        cp -v "${LIBCXX_SHARED}" "${dst}/"
    done
done

echo ""
echo "✓ Android native libs copied to:"
echo "  - ${KOTLIN_JNI_DEST}/{${ABIS[*]}}"
echo "  - ${RN_CORE_JNI_DEST}/{${ABIS[*]}}"
echo "  - ${RN_LLAMA_JNI_DEST}/{${ABIS[*]}}"
echo "  - ${RN_ONNX_JNI_DEST}/{${ABIS[*]}}"
echo "  - ${FLUTTER_CORE_JNI_DEST}/{${ABIS[*]}}"
echo "  - ${FLUTTER_LLAMA_JNI_DEST}/{${ABIS[*]}}"
echo "  - ${FLUTTER_ONNX_JNI_DEST}/{${ABIS[*]}}"
echo "  - ${FLUTTER_GENIE_JNI_DEST}/{${ABIS[*]}}"
echo "✓ React Native headers copied to: ${RN_CORE_INCLUDE_DEST}"
