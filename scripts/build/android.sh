#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

usage() {
    cat <<'EOF'
Usage: scripts/build/android.sh [abi]

Builds the Android CMake presets (android-arm64 / android-armv7 / android-x86_64)
from sdk/runanywhere-commons and stages the resulting native libs into the SDKs
that consume them from source:
  - Kotlin (src/main/jniLibs + backend modules)
  - React Native core/llamacpp/onnx (android/src/main/jniLibs)
  - Flutter runanywhere/runanywhere_llamacpp/runanywhere_onnx/runanywhere_genie

Arguments:
  abi           arm64-v8a | armeabi-v7a | x86_64 (default: all three)

Options:
  -h, --help    Show this help

Environment:
  ANDROID_NDK_HOME   Required. NDK install root.
  RAC_BUILD_JOBS     Parallel build jobs (default: 2).
EOF
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
esac

COMMONS_ROOT="${RAC_ROOT}/sdk/runanywhere-commons"

KOTLIN_JNI_DEST="${RAC_ROOT}/sdk/runanywhere-kotlin/src/main/jniLibs"
KOTLIN_LLAMA_JNI_DEST="${RAC_ROOT}/sdk/runanywhere-kotlin/modules/runanywhere-core-llamacpp/src/main/jniLibs"
KOTLIN_ONNX_JNI_DEST="${RAC_ROOT}/sdk/runanywhere-kotlin/modules/runanywhere-core-onnx/src/main/jniLibs"
RN_CORE_JNI_DEST="${RAC_ROOT}/sdk/runanywhere-react-native/packages/core/android/src/main/jniLibs"
RN_LLAMA_JNI_DEST="${RAC_ROOT}/sdk/runanywhere-react-native/packages/llamacpp/android/src/main/jniLibs"
RN_ONNX_JNI_DEST="${RAC_ROOT}/sdk/runanywhere-react-native/packages/onnx/android/src/main/jniLibs"
RN_CORE_INCLUDE_DEST="${RN_CORE_JNI_DEST}/include"

FLUTTER_CORE_JNI_DEST="${RAC_ROOT}/sdk/runanywhere-flutter/packages/runanywhere/android/src/main/jniLibs"
FLUTTER_LLAMA_JNI_DEST="${RAC_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_llamacpp/android/src/main/jniLibs"
FLUTTER_ONNX_JNI_DEST="${RAC_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_onnx/android/src/main/jniLibs"
FLUTTER_GENIE_JNI_DEST="${RAC_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_genie/android/src/main/jniLibs"

COMMONS_INCLUDE_SRC="${COMMONS_ROOT}/include"
SHERPA_ANDROID_JNI_SRC="${COMMONS_ROOT}/third_party/sherpa-onnx-android/jniLibs"

[ -n "${ANDROID_NDK_HOME:-}" ] || die "ANDROID_NDK_HOME is not set. Install the NDK and export it."

if [ "$#" -ge 1 ] && [[ "$1" =~ ^(arm64-v8a|armeabi-v7a|x86_64)$ ]]; then
    ABIS=("$1"); shift
else
    ABIS=("arm64-v8a" "armeabi-v7a" "x86_64")
fi

# case blocks instead of associative arrays: macOS' default bash 3.2 lacks them.
preset_for_abi() {
    case "$1" in
        arm64-v8a)   echo "android-arm64"   ;;
        armeabi-v7a) echo "android-armv7"   ;;
        x86_64)      echo "android-x86_64"  ;;
        *) die "unknown Android ABI '$1' (expected arm64-v8a|armeabi-v7a|x86_64)" ;;
    esac
}

ndk_triple_for_abi() {
    case "$1" in
        arm64-v8a)   echo "aarch64-linux-android"  ;;
        armeabi-v7a) echo "arm-linux-androideabi"  ;;
        x86_64)      echo "x86_64-linux-android"   ;;
        *) die "unknown Android ABI '$1' (cannot map to NDK triple)" ;;
    esac
}

ndk_omp_arch_for_abi() {
    case "$1" in
        arm64-v8a)   echo "aarch64" ;;
        armeabi-v7a) echo "arm"     ;;
        x86_64)      echo "x86_64"  ;;
        *) die "unknown Android ABI '$1' (cannot map to libomp arch)" ;;
    esac
}

HOST_UNAME="$(uname -s)"
case "${HOST_UNAME}" in
    Darwin) NDK_HOST_TAG="darwin-x86_64" ;;
    Linux)  NDK_HOST_TAG="linux-x86_64"  ;;
    *) die "unsupported host '${HOST_UNAME}' for NDK libc++_shared lookup" ;;
esac
NDK_SYSROOT_LIB="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/${NDK_HOST_TAG}/sysroot/usr/lib"
ANDROID_READELF="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/${NDK_HOST_TAG}/bin/llvm-readelf"
[ -x "${ANDROID_READELF}" ] || die "llvm-readelf not found at ${ANDROID_READELF}. Is ANDROID_NDK_HOME correct?"

mkdir -p \
    "${KOTLIN_JNI_DEST}" \
    "${KOTLIN_LLAMA_JNI_DEST}" \
    "${KOTLIN_ONNX_JNI_DEST}" \
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

# Copy $1 to every remaining argument, silently skipping missing sources
# (e.g. a backend not emitted on this configuration).
copy_if_exists() {
    local src="$1"; shift
    if [ -f "${src}" ]; then
        for dst in "$@"; do
            mkdir -p "${dst}"
            cp -v "${src}" "${dst}/"
        done
    fi
}

validate_elf_16kb_alignment() {
    local so_file="$1"
    local align_hex
    local align_dec
    local failed=0

    while IFS= read -r align_hex; do
        [ -n "${align_hex}" ] || continue
        case "${align_hex}" in
            0x*) align_dec=$((align_hex)) ;;
            *) continue ;;
        esac
        if [ "${align_dec}" -lt 16384 ]; then
            error "${so_file} has LOAD segment alignment ${align_hex}; expected >= 0x4000"
            failed=1
        fi
    done < <("${ANDROID_READELF}" -l "${so_file}" 2>/dev/null | awk '/^[[:space:]]*LOAD[[:space:]]/ {print $NF}')

    return "${failed}"
}

validate_staged_abi_16kb_alignment() {
    local abi="$1"; shift
    local dst
    local so_file
    local failed=0

    case "${abi}" in
        arm64-v8a|x86_64) ;;
        *) return 0 ;;
    esac

    for dst in "$@"; do
        [ -d "${dst}" ] || continue
        while IFS= read -r so_file; do
            validate_elf_16kb_alignment "${so_file}" || failed=1
        done < <(find "${dst}" -maxdepth 1 -type f -name "*.so" -print)
    done

    if [ "${failed}" -ne 0 ]; then
        die "staged ${abi} Android native libs are not 16KB compatible"
    fi
}

for ABI in "${ABIS[@]}"; do
    PRESET="$(preset_for_abi "${ABI}")"
    TRIPLE="$(ndk_triple_for_abi "${ABI}")"
    OMP_ARCH="$(ndk_omp_arch_for_abi "${ABI}")"
    step "${ABI} via preset '${PRESET}'"

    # CMakePresets.json lives in sdk/runanywhere-commons, so cmake must run
    # from there regardless of the caller's cwd (e.g. Gradle's
    # buildLocalJniLibs task runs with workingDir=sdk/runanywhere-kotlin/).
    (
        cd "${COMMONS_ROOT}"
        run_cmd cmake --preset "${PRESET}"
        # Parallelism capped: a bare --parallel spawns one heavy compiler per
        # core and has OOM-crashed dev laptops. Override via RAC_BUILD_JOBS.
        run_cmd cmake --build --preset "${PRESET}" --parallel "${RAC_BUILD_JOBS:-2}"
    )

    BUILD_DIR="${COMMONS_ROOT}/build/${PRESET}"
    KOTLIN_DEST="${KOTLIN_JNI_DEST}/${ABI}"
    KOTLIN_LLAMA_DEST="${KOTLIN_LLAMA_JNI_DEST}/${ABI}"
    KOTLIN_ONNX_DEST="${KOTLIN_ONNX_JNI_DEST}/${ABI}"
    RN_CORE_DEST="${RN_CORE_JNI_DEST}/${ABI}"
    RN_LLAMA_DEST="${RN_LLAMA_JNI_DEST}/${ABI}"
    RN_ONNX_DEST="${RN_ONNX_JNI_DEST}/${ABI}"
    FLUTTER_CORE_DEST="${FLUTTER_CORE_JNI_DEST}/${ABI}"
    FLUTTER_LLAMA_DEST="${FLUTTER_LLAMA_JNI_DEST}/${ABI}"
    FLUTTER_ONNX_DEST="${FLUTTER_ONNX_JNI_DEST}/${ABI}"
    FLUTTER_GENIE_DEST="${FLUTTER_GENIE_JNI_DEST}/${ABI}"

    mkdir -p \
        "${KOTLIN_DEST}" "${KOTLIN_LLAMA_DEST}" "${KOTLIN_ONNX_DEST}" \
        "${RN_CORE_DEST}" "${RN_LLAMA_DEST}" "${RN_ONNX_DEST}" \
        "${FLUTTER_CORE_DEST}" "${FLUTTER_LLAMA_DEST}" "${FLUTTER_ONNX_DEST}" "${FLUTTER_GENIE_DEST}"

    # Clean managed destinations so stale artifacts from a previous run
    # (e.g. a dropped backend) don't linger.
    rm -f \
        "${KOTLIN_DEST}"/*.so \
        "${KOTLIN_LLAMA_DEST}"/*.so \
        "${KOTLIN_ONNX_DEST}"/*.so \
        "${RN_CORE_DEST}"/*.so "${RN_LLAMA_DEST}"/*.so "${RN_ONNX_DEST}"/*.so \
        "${FLUTTER_CORE_DEST}"/*.so "${FLUTTER_LLAMA_DEST}"/*.so \
        "${FLUTTER_ONNX_DEST}"/*.so "${FLUTTER_GENIE_DEST}"/*.so

    # Depth 6 also catches the commons JNI bridge, one level deeper than the
    # engine plugins: build/<preset>/.../src/jni/librunanywhere_jni.so
    LIB_COMMONS="$(find "${BUILD_DIR}" -maxdepth 6 -name "librac_commons.so"             -print -quit || true)"
    LIB_COMMONS_JNI="$(find "${BUILD_DIR}" -maxdepth 6 -name "librunanywhere_jni.so"     -print -quit || true)"
    # librunanywhere_jni.so declares `NEEDED librac_backend_cloud.so`, so the
    # cloud STT engine MUST travel with the JNI bridge into every core package
    # or the dynamic linker fails to load runanywhere_jni at runtime.
    LIB_CLOUD="$(find "${BUILD_DIR}" -maxdepth 6 -name "librac_backend_cloud.so"         -print -quit || true)"
    LIB_LLAMA="$(find "${BUILD_DIR}" -maxdepth 6 -name "librac_backend_llamacpp.so"      -print -quit || true)"
    LIB_LLAMA_JNI="$(find "${BUILD_DIR}" -maxdepth 6 -name "librac_backend_llamacpp_jni.so" -print -quit || true)"
    LIB_ONNX="$(find "${BUILD_DIR}"  -maxdepth 6 -name "librac_backend_onnx.so"          -print -quit || true)"
    LIB_ONNX_JNI="$(find "${BUILD_DIR}" -maxdepth 6 -name "librac_backend_onnx_jni.so"   -print -quit || true)"
    LIB_RAG_JNI="$(find "${BUILD_DIR}" -maxdepth 6 -name "librac_backend_rag_jni.so"     -print -quit || true)"
    LIB_SHERPA="$(find "${BUILD_DIR}" -maxdepth 6 -name "librac_backend_sherpa.so"       -print -quit || true)"

    copy_if_exists "${LIB_COMMONS}"     "${KOTLIN_DEST}" "${RN_CORE_DEST}" "${FLUTTER_CORE_DEST}"
    copy_if_exists "${LIB_COMMONS_JNI}" "${KOTLIN_DEST}" "${RN_CORE_DEST}" "${FLUTTER_CORE_DEST}"
    copy_if_exists "${LIB_CLOUD}"       "${KOTLIN_DEST}" "${RN_CORE_DEST}" "${FLUTTER_CORE_DEST}"
    copy_if_exists "${LIB_RAG_JNI}"     "${KOTLIN_DEST}"

    # Engine plugin entry-point libs go to the backend module's jniLibs, NOT
    # core: core ships only commons + JNI bridge + libc++/libomp sidecars.
    LIB_RUNANYWHERE_LLAMACPP="$(find "${BUILD_DIR}" -maxdepth 6 -name "librunanywhere_llamacpp.so"  -print -quit || true)"
    LIB_RUNANYWHERE_ONNX="$(find "${BUILD_DIR}" -maxdepth 6 -name "librunanywhere_onnx.so"          -print -quit || true)"
    LIB_RUNANYWHERE_SHERPA="$(find "${BUILD_DIR}" -maxdepth 6 -name "librunanywhere_sherpa.so"      -print -quit || true)"
    copy_if_exists "${LIB_RUNANYWHERE_LLAMACPP}" "${KOTLIN_LLAMA_DEST}"
    copy_if_exists "${LIB_RUNANYWHERE_ONNX}"     "${KOTLIN_ONNX_DEST}"
    copy_if_exists "${LIB_RUNANYWHERE_SHERPA}"   "${KOTLIN_ONNX_DEST}"

    copy_if_exists "${LIB_LLAMA}"     "${KOTLIN_LLAMA_DEST}" "${RN_LLAMA_DEST}" "${FLUTTER_LLAMA_DEST}"
    copy_if_exists "${LIB_LLAMA_JNI}" "${KOTLIN_LLAMA_DEST}" "${RN_LLAMA_DEST}" "${FLUTTER_LLAMA_DEST}"
    copy_if_exists "${LIB_ONNX}"      "${KOTLIN_ONNX_DEST}"  "${RN_ONNX_DEST}"  "${FLUTTER_ONNX_DEST}"
    copy_if_exists "${LIB_ONNX_JNI}"  "${KOTLIN_ONNX_DEST}"  "${RN_ONNX_DEST}"  "${FLUTTER_ONNX_DEST}"
    copy_if_exists "${LIB_SHERPA}"    "${RN_ONNX_DEST}"  "${FLUTTER_ONNX_DEST}" "${KOTLIN_ONNX_DEST}"

    # Sherpa / ORT prebuilt runtime, staged into Kotlin, RN, and Flutter ONNX plugins.
    if [ -d "${SHERPA_ANDROID_JNI_SRC}/${ABI}" ]; then
        find "${SHERPA_ANDROID_JNI_SRC}/${ABI}" -maxdepth 1 -name "*.so" \
            -exec cp -v {} "${KOTLIN_ONNX_DEST}/" \; \
            -exec cp -v {} "${RN_ONNX_DEST}/" \; \
            -exec cp -v {} "${FLUTTER_ONNX_DEST}/" \;
    fi

    # libc++_shared.so is required at runtime by every package that loads any
    # .so built with ANDROID_STL=c++_shared; AGP de-duplicates via pickFirsts.
    LIBCXX_SHARED="${NDK_SYSROOT_LIB}/${TRIPLE}/libc++_shared.so"
    [ -f "${LIBCXX_SHARED}" ] || die "libc++_shared.so not found at ${LIBCXX_SHARED}. Is ANDROID_NDK_HOME correct?"
    for dst in \
        "${KOTLIN_DEST}" "${KOTLIN_LLAMA_DEST}" "${KOTLIN_ONNX_DEST}" \
        "${RN_CORE_DEST}" "${RN_LLAMA_DEST}" "${RN_ONNX_DEST}" \
        "${FLUTTER_CORE_DEST}" "${FLUTTER_LLAMA_DEST}" "${FLUTTER_ONNX_DEST}" "${FLUTTER_GENIE_DEST}" ; do
        cp -v "${LIBCXX_SHARED}" "${dst}/"
    done

    # Some engine builds (notably ORT/Sherpa variants) require libomp.so at
    # runtime; a single copy in the core package resolves from the merged APK.
    LIBOMP_SHARED="$(find "${ANDROID_NDK_HOME}" -path "*/linux/${OMP_ARCH}/libomp.so" | sort | tail -1 || true)"
    if [ -z "${LIBOMP_SHARED}" ] || [ ! -f "${LIBOMP_SHARED}" ]; then
        die "libomp.so not found for ABI ${ABI} under ${ANDROID_NDK_HOME}"
    fi
    for dst in "${KOTLIN_DEST}" "${RN_CORE_DEST}" "${FLUTTER_CORE_DEST}" ; do
        cp -v "${LIBOMP_SHARED}" "${dst}/"
    done

    validate_staged_abi_16kb_alignment "${ABI}" \
        "${KOTLIN_DEST}" "${KOTLIN_LLAMA_DEST}" "${KOTLIN_ONNX_DEST}" \
        "${RN_CORE_DEST}" "${RN_LLAMA_DEST}" "${RN_ONNX_DEST}" \
        "${FLUTTER_CORE_DEST}" "${FLUTTER_LLAMA_DEST}" "${FLUTTER_ONNX_DEST}" "${FLUTTER_GENIE_DEST}"
done

ok "Android native libs copied to:"
log "  - ${KOTLIN_JNI_DEST}/{${ABIS[*]}}"
log "  - ${KOTLIN_LLAMA_JNI_DEST}/{${ABIS[*]}}"
log "  - ${KOTLIN_ONNX_JNI_DEST}/{${ABIS[*]}}"
log "  - ${RN_CORE_JNI_DEST}/{${ABIS[*]}}"
log "  - ${RN_LLAMA_JNI_DEST}/{${ABIS[*]}}"
log "  - ${RN_ONNX_JNI_DEST}/{${ABIS[*]}}"
log "  - ${FLUTTER_CORE_JNI_DEST}/{${ABIS[*]}}"
log "  - ${FLUTTER_LLAMA_JNI_DEST}/{${ABIS[*]}}"
log "  - ${FLUTTER_ONNX_JNI_DEST}/{${ABIS[*]}}"
log "  - ${FLUTTER_GENIE_JNI_DEST}/{${ABIS[*]}}"
ok "React Native headers copied to: ${RN_CORE_INCLUDE_DEST}"
