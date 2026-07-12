#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# build-core-android.sh — wraps the android-{arm64,armv7,x86_64} CMake presets
# and stages the resulting native artifacts into the SDKs that consume them
# directly from source:
#   - Kotlin (`src/main/jniLibs`)
#   - React Native core/llamacpp/onnx (`android/src/main/jniLibs`)
#   - Flutter runanywhere/runanywhere_llamacpp/runanywhere_onnx/runanywhere_qhexrt
#     (`android/src/main/jniLibs`)
#
# Usage:
#   ./scripts/build-core-android.sh                  # build all 3 ABIs
#   ./scripts/build-core-android.sh arm64-v8a        # single ABI
#   ./scripts/build-core-android.sh --release        # forwards to ctest preset
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Anchor cwd to the repo root so CMake presets resolve correctly regardless
# of where the script is invoked from (e.g., Gradle's buildLocalJniLibs task
# runs with `workingDir = sdk/runanywhere-kotlin/`, which would otherwise
# break `cmake --preset android-arm64` because CMakePresets.json lives at
# the repo root, not in the Kotlin module dir).
cd "${REPO_ROOT}"

# Kotlin + React Native destinations (existing).
KOTLIN_JNI_DEST="${REPO_ROOT}/sdk/runanywhere-kotlin/src/main/jniLibs"
KOTLIN_LLAMA_JNI_DEST="${REPO_ROOT}/sdk/runanywhere-kotlin/modules/runanywhere-core-llamacpp/src/main/jniLibs"
KOTLIN_ONNX_JNI_DEST="${REPO_ROOT}/sdk/runanywhere-kotlin/modules/runanywhere-core-onnx/src/main/jniLibs"
KOTLIN_QHEXRT_JNI_DEST="${REPO_ROOT}/sdk/runanywhere-kotlin/modules/runanywhere-core-qhexrt/src/main/jniLibs"
KOTLIN_QHEXRT_SKEL_ASSET_DEST="${REPO_ROOT}/sdk/runanywhere-kotlin/modules/runanywhere-core-qhexrt/src/main/assets/runanywhere/qhexrt/skels"
RN_CORE_JNI_DEST="${REPO_ROOT}/sdk/runanywhere-react-native/packages/core/android/src/main/jniLibs"
RN_LLAMA_JNI_DEST="${REPO_ROOT}/sdk/runanywhere-react-native/packages/llamacpp/android/src/main/jniLibs"
RN_ONNX_JNI_DEST="${REPO_ROOT}/sdk/runanywhere-react-native/packages/onnx/android/src/main/jniLibs"
RN_QHEXRT_JNI_DEST="${REPO_ROOT}/sdk/runanywhere-react-native/packages/qhexrt/android/src/main/jniLibs"
RN_QHEXRT_SKEL_ASSET_DEST="${REPO_ROOT}/sdk/runanywhere-react-native/packages/qhexrt/android/src/main/assets/runanywhere/qhexrt/skels"
RN_CORE_INCLUDE_DEST="${RN_CORE_JNI_DEST}/include"
RN_QHEXRT_INCLUDE_DEST="${RN_QHEXRT_JNI_DEST}/include"

# Flutter destinations.
FLUTTER_CORE_JNI_DEST="${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere/android/src/main/jniLibs"
FLUTTER_LLAMA_JNI_DEST="${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_llamacpp/android/src/main/jniLibs"
FLUTTER_ONNX_JNI_DEST="${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_onnx/android/src/main/jniLibs"
FLUTTER_QHEXRT_JNI_DEST="${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_qhexrt/android/src/main/jniLibs"
FLUTTER_QHEXRT_SKEL_ASSET_DEST="${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_qhexrt/android/src/main/assets/runanywhere/qhexrt/skels"

COMMONS_INCLUDE_SRC="${REPO_ROOT}/sdk/runanywhere-commons/include"
QHEXRT_INCLUDE_SRC="${REPO_ROOT}/engines/qhexrt/include"
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

# Map ABI → libomp arch directory within the NDK clang runtime tree.
ndk_omp_arch_for_abi() {
    case "$1" in
        arm64-v8a)   echo "aarch64" ;;
        armeabi-v7a) echo "arm"     ;;
        x86_64)      echo "x86_64"  ;;
        *)
            echo "error: unknown Android ABI '$1' (cannot map to libomp arch)" >&2
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
ANDROID_READELF="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/${NDK_HOST_TAG}/bin/llvm-readelf"
if [ ! -x "${ANDROID_READELF}" ]; then
    echo "error: llvm-readelf not found at ${ANDROID_READELF}. Is ANDROID_NDK_HOME correct?" >&2
    exit 1
fi

mkdir -p \
    "${KOTLIN_JNI_DEST}" \
    "${KOTLIN_LLAMA_JNI_DEST}" \
    "${KOTLIN_ONNX_JNI_DEST}" \
    "${KOTLIN_QHEXRT_JNI_DEST}" \
    "${KOTLIN_QHEXRT_SKEL_ASSET_DEST}" \
    "${RN_CORE_JNI_DEST}" \
    "${RN_LLAMA_JNI_DEST}" \
    "${RN_ONNX_JNI_DEST}" \
    "${RN_QHEXRT_JNI_DEST}" \
    "${RN_QHEXRT_SKEL_ASSET_DEST}" \
    "${FLUTTER_CORE_JNI_DEST}" \
    "${FLUTTER_LLAMA_JNI_DEST}" \
    "${FLUTTER_ONNX_JNI_DEST}" \
    "${FLUTTER_QHEXRT_JNI_DEST}" \
    "${FLUTTER_QHEXRT_SKEL_ASSET_DEST}"

rm -rf "${RN_CORE_INCLUDE_DEST}"
mkdir -p "${RN_CORE_INCLUDE_DEST}"
cp -R "${COMMONS_INCLUDE_SRC}/." "${RN_CORE_INCLUDE_DEST}/"

# The RN QHexRT Nitro bridge compiles against the engine-owned public ABI.
# Stage it with the private backend package rather than leaking QHexRT policy
# headers into the generic @runanywhere/core include bundle.
rm -rf "${RN_QHEXRT_INCLUDE_DEST}"
mkdir -p "${RN_QHEXRT_INCLUDE_DEST}"
cp -R "${QHEXRT_INCLUDE_SRC}/." "${RN_QHEXRT_INCLUDE_DEST}/"

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

qairt_identity_matches() {
    local manifest_path="$1"
    local qairt_root="$2"
    python3 - "${manifest_path}" "${qairt_root}" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

manifest_path, qairt_root = Path(sys.argv[1]), Path(sys.argv[2]).resolve(strict=True)
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
identity = manifest["build"]["qnn_sdk"]
if set(identity) != {"metadata_file", "metadata_sha256"}:
    raise SystemExit(1)
name = identity["metadata_file"]
if not isinstance(name, str) or not name or name in {".", ".."} or "/" in name or "\\" in name:
    raise SystemExit(1)
metadata = qairt_root / name
if metadata.is_symlink() or not metadata.is_file():
    raise SystemExit(1)
actual = hashlib.sha256(metadata.read_bytes()).hexdigest()
raise SystemExit(0 if actual == identity["metadata_sha256"] else 1)
PY
}

find_qairt_root() {
    local manifest_path="$1"
    local candidate

    # An explicitly selected SDK is authoritative. Fail closed instead of
    # silently staging a different installed runtime when its identity drifts.
    if [ -n "${QNN_SDK_ROOT:-}" ]; then
        candidate="${QNN_SDK_ROOT}"
        if [ -d "${candidate}/lib/aarch64-android" ] && \
           qairt_identity_matches "${manifest_path}" "${candidate}"; then
            echo "${candidate}"
            return 0
        fi
        echo "error: QNN_SDK_ROOT does not match the selected QHexRT build identity: ${candidate}" >&2
        return 2
    fi

    for candidate in \
        "${QAIRT_ROOT:-}" \
        "${QNN_ROOT:-}" ; do
        [ -n "${candidate}" ] || continue
        if [ -d "${candidate}/lib/aarch64-android" ] && \
           qairt_identity_matches "${manifest_path}" "${candidate}"; then
            echo "${candidate}"
            return 0
        fi
        echo "error: explicit QAIRT root does not match the selected QHexRT build identity: ${candidate}" >&2
        return 2
    done

    candidate="${REPO_ROOT}/../qairt/2.47.0.260601"
    if [ -d "${candidate}/lib/aarch64-android" ] && \
       qairt_identity_matches "${manifest_path}" "${candidate}"; then
        echo "${candidate}"
        return 0
    fi

    local found
    while IFS= read -r found; do
        candidate="$(dirname "$(dirname "${found}")")"
        if qairt_identity_matches "${manifest_path}" "${candidate}"; then
            echo "${candidate}"
            return 0
        fi
    done < <(find "${REPO_ROOT}/.." -maxdepth 4 -type d -path "*/qairt/*/lib/aarch64-android" -print 2>/dev/null | sort -r)

    return 1
}

validate_linked_qhexrt_outputs() {
    local engine_lib="$1"
    local jni_lib="$2"
    if [ ! -f "${engine_lib}" ] || [ ! -f "${jni_lib}" ]; then
        echo "error: selected QHexRT prebuilt but linked engine/JNI outputs are missing" >&2
        return 1
    fi
    if ! grep -aFq "qhexrt:engine-available" "${engine_lib}"; then
        echo "error: selected QHexRT prebuilt produced a stub/unlinked engine" >&2
        return 1
    fi
}

stage_qhexrt_qnn_runtime_libs() {
    local abi="$1"; shift
    local engine_lib="$1"; shift
    local selected_prebuilt="$1"; shift

    [ "${abi}" = "arm64-v8a" ] || return 0
    [ -f "${engine_lib}" ] || return 0

    local engine_available=0
    if grep -aFq "qhexrt:engine-available" "${engine_lib}"; then
        engine_available=1
    fi
    # The shell/stub plugin is intentionally distributable without QAIRT. Do
    # not let a sibling SDK installation make a stub build accidentally ship
    # proprietary QNN host libraries or DSP skels.
    [ "${engine_available}" -eq 1 ] || return 0

    local qairt_root
    qairt_root="$(find_qairt_root "${selected_prebuilt}/qhexrt-prebuilt.json" || true)"
    if [ -z "${qairt_root}" ]; then
        if [ "${engine_available}" -eq 1 ]; then
            echo "error: QHexRT engine is linked, but QAIRT/QNN runtime libs were not found." >&2
            echo "       Set QAIRT_ROOT or QNN_SDK_ROOT to the QAIRT install root." >&2
            exit 1
        fi
        return 0
    fi

    if ! qairt_identity_matches "${selected_prebuilt}/qhexrt-prebuilt.json" "${qairt_root}"; then
        echo "error: selected QAIRT/QNN runtime changed after identity-aware discovery: ${qairt_root}" >&2
        exit 1
    fi

    local host_dir="${qairt_root}/lib/aarch64-android"
    local qnn_host_libs=(
        "${host_dir}/libQnnHtp.so"
        "${host_dir}/libQnnHtpNetRunExtensions.so"
        "${host_dir}/libQnnHtpPrepare.so"
        "${host_dir}/libQnnSystem.so"
        "${host_dir}/libQnnHtpV75CalculatorStub.so"
        "${host_dir}/libQnnHtpV75Stub.so"
        "${host_dir}/libQnnHtpV79CalculatorStub.so"
        "${host_dir}/libQnnHtpV79Stub.so"
        "${host_dir}/libQnnHtpV81CalculatorStub.so"
        "${host_dir}/libQnnHtpV81Stub.so"
    )
    local qnn_skel_libs=(
        "${qairt_root}/lib/hexagon-v75/unsigned/libQnnHtpV75Skel.so"
        "${qairt_root}/lib/hexagon-v79/unsigned/libQnnHtpV79Skel.so"
        "${qairt_root}/lib/hexagon-v81/unsigned/libQnnHtpV81Skel.so"
    )

    local src
    for src in "${qnn_host_libs[@]}" "${qnn_skel_libs[@]}"; do
        if [ ! -f "${src}" ]; then
            echo "error: required QHexRT QAIRT runtime lib is missing: ${src}" >&2
            exit 1
        fi
    done

    echo "  Staging QHexRT QAIRT runtime libs from ${qairt_root}"
    for src in "${qnn_host_libs[@]}"; do
        copy_if_exists "${src}" "$@"
    done
    local kotlin_skel_dest="${KOTLIN_QHEXRT_SKEL_ASSET_DEST}/${abi}"
    local rn_skel_dest="${RN_QHEXRT_SKEL_ASSET_DEST}/${abi}"
    local flutter_skel_dest="${FLUTTER_QHEXRT_SKEL_ASSET_DEST}/${abi}"
    mkdir -p "${kotlin_skel_dest}" "${rn_skel_dest}" "${flutter_skel_dest}"
    rm -f "${kotlin_skel_dest}"/*.so "${rn_skel_dest}"/*.so "${flutter_skel_dest}"/*.so
    for src in "${qnn_skel_libs[@]}"; do
        copy_if_exists "${src}" "${kotlin_skel_dest}" "${rn_skel_dest}" "${flutter_skel_dest}"
    done
}

validate_elf_16kb_alignment() {
    local so_file="$1"
    local headers
    local align_hex
    local align_dec
    local failed=0
    local load_count=0

    if ! headers="$("${ANDROID_READELF}" -l "${so_file}" 2>/dev/null)"; then
        echo "error: llvm-readelf could not inspect ${so_file}" >&2
        return 1
    fi
    while IFS= read -r align_hex; do
        [ -n "${align_hex}" ] || continue
        case "${align_hex}" in
            0x*)
                load_count=$((load_count + 1))
                align_dec=$((align_hex))
                ;;
            *)
                echo "error: ${so_file} has malformed LOAD alignment ${align_hex}" >&2
                failed=1
                continue
                ;;
        esac
        if [ "${align_dec}" -lt 16384 ]; then
            echo "error: ${so_file} has LOAD segment alignment ${align_hex}; expected >= 0x4000" >&2
            failed=1
        fi
    done <<< "$(printf '%s\n' "${headers}" | awk '/^[[:space:]]*LOAD[[:space:]]/ {print $NF}')"

    if [ "${load_count}" -eq 0 ]; then
        echo "error: ${so_file} has no readable ELF LOAD segments" >&2
        failed=1
    fi

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
            case "$(basename "${so_file}")" in
                libQnnHtpV*Skel.so)
                    # DSP-side skels are extracted for cDSP lookup through
                    # ADSP_LIBRARY_PATH; they are not Android host-loaded ELF.
                    continue
                    ;;
            esac
            validate_elf_16kb_alignment "${so_file}" || failed=1
        done < <(find "${dst}" -maxdepth 1 -type f -name "*.so" -print)
    done

    if [ "${failed}" -ne 0 ]; then
        echo "error: staged ${abi} Android native libs are not 16KB compatible" >&2
        exit 1
    fi
}

for ABI in "${ABIS[@]}"; do
    PRESET="$(preset_for_abi "${ABI}")"
    TRIPLE="$(ndk_triple_for_abi "${ABI}")"
    OMP_ARCH="$(ndk_omp_arch_for_abi "${ABI}")"
    echo "▶ ${ABI} via preset '${PRESET}'"

    # Make release artifacts independent of the developer/runner checkout.
    # `__FILE__`, debug tables, and assertion strings otherwise preserve the
    # absolute source root inside every AAR/npm/Flutter native payload.
    PREFIX_MAP_FLAGS="-ffile-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fmacro-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fdebug-prefix-map=${REPO_ROOT}=/runanywhere-sdks -ffile-prefix-map=${ANDROID_NDK_HOME}=/android-ndk -fmacro-prefix-map=${ANDROID_NDK_HOME}=/android-ndk -fdebug-prefix-map=${ANDROID_NDK_HOME}=/android-ndk"
    CMAKE_CONFIGURE_ARGS=(
        "--preset" "${PRESET}"
        "-DCMAKE_C_FLAGS=${PREFIX_MAP_FLAGS}"
        "-DCMAKE_CXX_FLAGS=${PREFIX_MAP_FLAGS}"
    )
    QHEXRT_ENABLED=0
    if [ "${ABI}" = "arm64-v8a" ]; then
        QHEXRT_PREFLIGHT="${REPO_ROOT}/scripts/build/validate-qhexrt-prebuilt.py"
        if QHEXRT_SELECTED="$(python3 "${QHEXRT_PREFLIGHT}" \
            --prebuilt "${REPO_ROOT}/engines/qhexrt/prebuilt" \
            --android-abi "${ABI}")"; then
            QHEXRT_ENABLED=1
            CMAKE_CONFIGURE_ARGS+=("-DRAC_BACKEND_QHEXRT=ON" "-DQHEXRT_ROOT=${QHEXRT_SELECTED}")
        else
            QHEXRT_PREFLIGHT_STATUS=$?
            if [ "${QHEXRT_PREFLIGHT_STATUS}" -ne 3 ]; then
                echo "error: refusing Android build with an invalid selected QHexRT prebuilt" >&2
                exit "${QHEXRT_PREFLIGHT_STATUS}"
            fi
            CMAKE_CONFIGURE_ARGS+=("-DRAC_BACKEND_QHEXRT=OFF" "-UQHEXRT_ROOT")
        fi
    else
        CMAKE_CONFIGURE_ARGS+=("-DRAC_BACKEND_QHEXRT=OFF" "-UQHEXRT_ROOT")
    fi
    cmake "${CMAKE_CONFIGURE_ARGS[@]}"
    # Use CMake's generator-agnostic --parallel, CAPPED (repo resource
    # discipline: a bare --parallel spawns one heavy compiler per core and
    # has OOM-crashed dev laptops). Override with RAC_BUILD_JOBS if needed.
    # (Ninja rejects a bare `-j`,
    # while Make accepts it). Lets CMake pick a sensible default job count.
    cmake --build --preset "${PRESET}" --parallel "${RAC_BUILD_JOBS:-2}"

    BUILD_DIR="${REPO_ROOT}/build/${PRESET}"
    KOTLIN_DEST="${KOTLIN_JNI_DEST}/${ABI}"
    KOTLIN_LLAMA_DEST="${KOTLIN_LLAMA_JNI_DEST}/${ABI}"
    KOTLIN_ONNX_DEST="${KOTLIN_ONNX_JNI_DEST}/${ABI}"
    KOTLIN_QHEXRT_DEST="${KOTLIN_QHEXRT_JNI_DEST}/${ABI}"
    KOTLIN_QHEXRT_SKEL_DEST="${KOTLIN_QHEXRT_SKEL_ASSET_DEST}/${ABI}"
    RN_CORE_DEST="${RN_CORE_JNI_DEST}/${ABI}"
    RN_LLAMA_DEST="${RN_LLAMA_JNI_DEST}/${ABI}"
    RN_ONNX_DEST="${RN_ONNX_JNI_DEST}/${ABI}"
    RN_QHEXRT_DEST="${RN_QHEXRT_JNI_DEST}/${ABI}"
    RN_QHEXRT_SKEL_DEST="${RN_QHEXRT_SKEL_ASSET_DEST}/${ABI}"
    FLUTTER_CORE_DEST="${FLUTTER_CORE_JNI_DEST}/${ABI}"
    FLUTTER_LLAMA_DEST="${FLUTTER_LLAMA_JNI_DEST}/${ABI}"
    FLUTTER_ONNX_DEST="${FLUTTER_ONNX_JNI_DEST}/${ABI}"
    FLUTTER_QHEXRT_DEST="${FLUTTER_QHEXRT_JNI_DEST}/${ABI}"
    FLUTTER_QHEXRT_SKEL_DEST="${FLUTTER_QHEXRT_SKEL_ASSET_DEST}/${ABI}"

    mkdir -p \
        "${KOTLIN_DEST}" "${KOTLIN_LLAMA_DEST}" "${KOTLIN_ONNX_DEST}" \
        "${RN_CORE_DEST}" "${RN_LLAMA_DEST}" "${RN_ONNX_DEST}" \
        "${FLUTTER_CORE_DEST}" "${FLUTTER_LLAMA_DEST}" "${FLUTTER_ONNX_DEST}"
    if [ "${QHEXRT_ENABLED}" -eq 1 ]; then
        mkdir -p \
            "${KOTLIN_QHEXRT_DEST}" "${RN_QHEXRT_DEST}" "${FLUTTER_QHEXRT_DEST}" \
            "${KOTLIN_QHEXRT_SKEL_DEST}" "${RN_QHEXRT_SKEL_DEST}" "${FLUTTER_QHEXRT_SKEL_DEST}"
    else
        # QHexRT is ARM64-only. Do not leave empty/private package ABI roots or
        # unrelated libc++ sidecars behind after building public non-ARM ABIs.
        rm -rf \
            "${KOTLIN_QHEXRT_DEST}" "${RN_QHEXRT_DEST}" "${FLUTTER_QHEXRT_DEST}" \
            "${KOTLIN_QHEXRT_SKEL_DEST}" "${RN_QHEXRT_SKEL_DEST}" "${FLUTTER_QHEXRT_SKEL_DEST}"
    fi

    # Clean everything we manage before re-staging so stale artifacts from a
    # previous run (e.g. a dropped backend) don't linger.
    rm -f \
        "${KOTLIN_DEST}"/*.so \
        "${KOTLIN_LLAMA_DEST}"/*.so \
        "${KOTLIN_ONNX_DEST}"/*.so \
        "${KOTLIN_QHEXRT_DEST}"/*.so \
        "${RN_CORE_DEST}"/*.so "${RN_LLAMA_DEST}"/*.so "${RN_ONNX_DEST}"/*.so "${RN_QHEXRT_DEST}"/*.so \
        "${FLUTTER_CORE_DEST}"/*.so "${FLUTTER_LLAMA_DEST}"/*.so \
        "${FLUTTER_ONNX_DEST}"/*.so "${FLUTTER_QHEXRT_DEST}"/*.so
    rm -f \
        "${KOTLIN_QHEXRT_SKEL_DEST}"/*.so \
        "${RN_QHEXRT_SKEL_DEST}"/*.so \
        "${FLUTTER_QHEXRT_SKEL_DEST}"/*.so

    # -------------------------------------------------------------------------
    # Locate artifacts produced by the CMake build.
    #
    # Depth bumped from 4 → 6 so we also catch the commons JNI bridge, which
    # lives one level deeper than the engine plugins:
    #   build/<preset>/sdk/runanywhere-commons/src/jni/librunanywhere_jni.so
    # -------------------------------------------------------------------------
    LIB_COMMONS="$(find "${BUILD_DIR}" -maxdepth 6 -name "librac_commons.so"             -print -quit || true)"
    LIB_COMMONS_JNI="$(find "${BUILD_DIR}" -maxdepth 6 -name "librunanywhere_jni.so"     -print -quit || true)"
    # Cloud STT engine plugin. librunanywhere_jni.so declares
    # `NEEDED librac_backend_cloud.so` (it imports rac_backend_cloud_register +
    # rac_stt_cloud_* for the hybrid STT router), so this lib MUST travel with
    # the JNI bridge into every core package or the dynamic linker fails to load
    # runanywhere_jni at runtime. It is bundled in core (not a separate package)
    # because the cloud provider is data-driven config, not a distinct plugin.
    LIB_CLOUD="$(find "${BUILD_DIR}" -maxdepth 6 -name "librac_backend_cloud.so"         -print -quit || true)"
    LIB_LLAMA="$(find "${BUILD_DIR}" -maxdepth 6 -name "librac_backend_llamacpp.so"      -print -quit || true)"
    LIB_LLAMA_JNI="$(find "${BUILD_DIR}" -maxdepth 6 -name "librac_backend_llamacpp_jni.so" -print -quit || true)"
    LIB_ONNX="$(find "${BUILD_DIR}"  -maxdepth 6 -name "librac_backend_onnx.so"          -print -quit || true)"
    LIB_ONNX_JNI="$(find "${BUILD_DIR}" -maxdepth 6 -name "librac_backend_onnx_jni.so"   -print -quit || true)"
    if [ "${QHEXRT_ENABLED}" -eq 1 ]; then
        LIB_QHEXRT="$(find "${BUILD_DIR}" -maxdepth 6 -name "librac_backend_qhexrt.so"       -print -quit || true)"
        LIB_QHEXRT_JNI="$(find "${BUILD_DIR}" -maxdepth 6 -name "librac_backend_qhexrt_jni.so" -print -quit || true)"
        validate_linked_qhexrt_outputs "${LIB_QHEXRT}" "${LIB_QHEXRT_JNI}"
    else
        # CMake does not delete outputs for targets disabled on reconfigure.
        # Remove stale linked plugins so a reused build directory cannot be
        # mistaken for this build's public/stub configuration.
        find "${BUILD_DIR}" -maxdepth 6 -type f \
            \( -name "librac_backend_qhexrt.so" -o -name "librac_backend_qhexrt_jni.so" \) \
            -delete
        LIB_QHEXRT=""
        LIB_QHEXRT_JNI=""
    fi
    # New Sherpa-ONNX plugin artifact, peer of librac_backend_onnx.so.
    LIB_SHERPA="$(find "${BUILD_DIR}" -maxdepth 6 -name "librac_backend_sherpa.so"       -print -quit || true)"

    # commons core + JNI go to Kotlin, RN core and Flutter core.
    copy_if_exists "${LIB_COMMONS}"     "${KOTLIN_DEST}" "${RN_CORE_DEST}" "${FLUTTER_CORE_DEST}"
    copy_if_exists "${LIB_COMMONS_JNI}" "${KOTLIN_DEST}" "${RN_CORE_DEST}" "${FLUTTER_CORE_DEST}"
    # Cloud STT engine — co-located with librunanywhere_jni.so (its NEEDED dep).
    copy_if_exists "${LIB_CLOUD}"       "${KOTLIN_DEST}" "${RN_CORE_DEST}" "${FLUTTER_CORE_DEST}"
    # Engine plugin entry-point libs (runanywhere_<engine>.so) — routed to
    # the appropriate backend module's jniLibs, NOT to core. The core module
    # only ships librac_commons.so + librunanywhere_jni.so + the libc++/libomp
    # sidecars. Each backend's entry-point lib travels with its plugin module.
    LIB_RUNANYWHERE_LLAMACPP="$(find "${BUILD_DIR}" -maxdepth 6 -name "librunanywhere_llamacpp.so"  -print -quit || true)"
    LIB_RUNANYWHERE_ONNX="$(find "${BUILD_DIR}" -maxdepth 6 -name "librunanywhere_onnx.so"          -print -quit || true)"
    LIB_RUNANYWHERE_SHERPA="$(find "${BUILD_DIR}" -maxdepth 6 -name "librunanywhere_sherpa.so"      -print -quit || true)"
    copy_if_exists "${LIB_RUNANYWHERE_LLAMACPP}" "${KOTLIN_LLAMA_DEST}"
    copy_if_exists "${LIB_RUNANYWHERE_ONNX}"     "${KOTLIN_ONNX_DEST}"
    copy_if_exists "${LIB_RUNANYWHERE_SHERPA}"   "${KOTLIN_ONNX_DEST}"

    # Per-engine backend + JNI libs. Staged to both RN and Flutter plugin
    # packages so the same jniLibs layout is shipped from every SDK.
    copy_if_exists "${LIB_LLAMA}"     "${KOTLIN_LLAMA_DEST}" "${RN_LLAMA_DEST}" "${FLUTTER_LLAMA_DEST}"
    copy_if_exists "${LIB_LLAMA_JNI}" "${KOTLIN_LLAMA_DEST}" "${RN_LLAMA_DEST}" "${FLUTTER_LLAMA_DEST}"
    copy_if_exists "${LIB_ONNX}"      "${KOTLIN_ONNX_DEST}"  "${RN_ONNX_DEST}"  "${FLUTTER_ONNX_DEST}"
    copy_if_exists "${LIB_ONNX_JNI}"  "${KOTLIN_ONNX_DEST}"  "${RN_ONNX_DEST}"  "${FLUTTER_ONNX_DEST}"
    copy_if_exists "${LIB_QHEXRT}"     "${KOTLIN_QHEXRT_DEST}" "${RN_QHEXRT_DEST}" "${FLUTTER_QHEXRT_DEST}"
    copy_if_exists "${LIB_QHEXRT_JNI}" "${KOTLIN_QHEXRT_DEST}" "${RN_QHEXRT_DEST}" "${FLUTTER_QHEXRT_DEST}"
    if [ "${QHEXRT_ENABLED}" -eq 1 ]; then
        stage_qhexrt_qnn_runtime_libs "${ABI}" "${LIB_QHEXRT}" \
            "${QHEXRT_SELECTED}" \
            "${KOTLIN_QHEXRT_DEST}" "${RN_QHEXRT_DEST}" "${FLUTTER_QHEXRT_DEST}"
    fi
    # Sherpa is the long-term owner of Sherpa-ONNX-backed STT/TTS/VAD; ship
    # it alongside the onnx plugin on every ONNX-enabled SDK package. Routed
    # to the Kotlin ONNX module (not core).
    copy_if_exists "${LIB_SHERPA}"    "${RN_ONNX_DEST}"  "${FLUTTER_ONNX_DEST}" "${KOTLIN_ONNX_DEST}"

    # Sherpa / ORT prebuilt runtime — only has arm64-v8a/armeabi-v7a/x86_64
    # sub-folders. Staged into Kotlin, RN, and Flutter ONNX plugins.
    if [ -d "${SHERPA_ANDROID_JNI_SRC}/${ABI}" ]; then
        find "${SHERPA_ANDROID_JNI_SRC}/${ABI}" -maxdepth 1 -name "*.so" \
            -exec cp -v {} "${KOTLIN_ONNX_DEST}/" \; \
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
        "${KOTLIN_DEST}" "${KOTLIN_LLAMA_DEST}" "${KOTLIN_ONNX_DEST}" \
        "${RN_CORE_DEST}" "${RN_LLAMA_DEST}" "${RN_ONNX_DEST}" \
        "${FLUTTER_CORE_DEST}" "${FLUTTER_LLAMA_DEST}" "${FLUTTER_ONNX_DEST}" ; do
        cp -v "${LIBCXX_SHARED}" "${dst}/"
    done
    if [ "${QHEXRT_ENABLED}" -eq 1 ]; then
        for dst in "${KOTLIN_QHEXRT_DEST}" "${RN_QHEXRT_DEST}" "${FLUTTER_QHEXRT_DEST}"; do
            cp -v "${LIBCXX_SHARED}" "${dst}/"
        done
    fi

    # Some engine builds (notably ORT/Sherpa variants) require libomp.so at
    # runtime. Ship a single copy from the core package so every app that
    # depends on RunAnywhere core plus backends resolves it from the merged APK.
    LIBOMP_SHARED="$(find "${ANDROID_NDK_HOME}" -path "*/linux/${OMP_ARCH}/libomp.so" | sort | tail -1 || true)"
    if [ -z "${LIBOMP_SHARED}" ] || [ ! -f "${LIBOMP_SHARED}" ]; then
        echo "error: libomp.so not found for ABI ${ABI} under ${ANDROID_NDK_HOME}" >&2
        exit 1
    fi
    for dst in "${KOTLIN_DEST}" "${RN_CORE_DEST}" "${FLUTTER_CORE_DEST}" ; do
        cp -v "${LIBOMP_SHARED}" "${dst}/"
    done

    validate_staged_abi_16kb_alignment "${ABI}" \
        "${KOTLIN_DEST}" "${KOTLIN_LLAMA_DEST}" "${KOTLIN_ONNX_DEST}" "${KOTLIN_QHEXRT_DEST}" \
        "${RN_CORE_DEST}" "${RN_LLAMA_DEST}" "${RN_ONNX_DEST}" "${RN_QHEXRT_DEST}" \
        "${FLUTTER_CORE_DEST}" "${FLUTTER_LLAMA_DEST}" "${FLUTTER_ONNX_DEST}" \
        "${FLUTTER_QHEXRT_DEST}"
done

echo ""
echo "✓ Android native libs copied to:"
echo "  - ${KOTLIN_JNI_DEST}/{${ABIS[*]}}"
echo "  - ${KOTLIN_LLAMA_JNI_DEST}/{${ABIS[*]}}"
echo "  - ${KOTLIN_ONNX_JNI_DEST}/{${ABIS[*]}}"
echo "  - ${KOTLIN_QHEXRT_JNI_DEST}/{${ABIS[*]}}"
echo "  - ${RN_CORE_JNI_DEST}/{${ABIS[*]}}"
echo "  - ${RN_LLAMA_JNI_DEST}/{${ABIS[*]}}"
echo "  - ${RN_ONNX_JNI_DEST}/{${ABIS[*]}}"
echo "  - ${RN_QHEXRT_JNI_DEST}/{${ABIS[*]}}"
echo "  - ${FLUTTER_CORE_JNI_DEST}/{${ABIS[*]}}"
echo "  - ${FLUTTER_LLAMA_JNI_DEST}/{${ABIS[*]}}"
echo "  - ${FLUTTER_ONNX_JNI_DEST}/{${ABIS[*]}}"
echo "  - ${FLUTTER_QHEXRT_JNI_DEST}/{${ABIS[*]}}"
echo "✓ React Native headers copied to: ${RN_CORE_INCLUDE_DEST}"
