#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# build-core-xcframework.sh — wraps the ios-device, ios-simulator, and
# macos-release CMake presets and runs `xcodebuild -create-xcframework` to
# produce the `.xcframework` bundles the Swift SDK consumes on Apple platforms:
#
#   sdk/runanywhere-swift/Binaries/RACommons.xcframework
#   sdk/runanywhere-swift/Binaries/RABackendLLAMACPP.xcframework
#   sdk/runanywhere-swift/Binaries/RABackendONNX.xcframework          (skipped if RAC_BACKEND_ONNX=OFF)
#   sdk/runanywhere-swift/Binaries/RABackendSherpa.xcframework       (skipped if RAC_BACKEND_SHERPA=OFF)
#   sdk/runanywhere-swift/Binaries/RABackendMLX.xcframework           (Apple-only, skipped if RAC_BACKEND_MLX=OFF)
#
# Engine plugins under engines/{llamacpp,onnx} use SHARED_ONLY inside
# rac_add_engine_plugin(...), so on iOS (RAC_STATIC_PLUGINS=ON) they still
# produce standalone `librac_backend_<name>.a` archives alongside
# `librac_commons.a`. All three have to be re-packaged into
# `.xcframework`s containing ios-arm64, ios-arm64-simulator, and macos-arm64
# slices. Every product in Package.swift advertises macOS, so every binary
# target in that product graph must carry the macOS slice.
#
# Environment knobs:
#   RAC_BACKEND_ONNX=OFF     skip the ONNX backend (used when the operator
#                            hasn't extracted third_party/onnxruntime-ios)
#   RAC_BACKEND_MLX=OFF      skip the MLX backend bridge
#   DRY_RUN=1                only print the planned commands, don't invoke
#                            cmake/xcodebuild. Useful in CI preflight and
#                            the `release-swift-binaries.sh DRY_RUN=1` path.
set -euo pipefail
export ZERO_AR_DATE=1
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-315532800}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DEST="${REPO_ROOT}/sdk/runanywhere-swift/Binaries"
# The source path is anchored dynamically so the script works from any cwd.
# shellcheck disable=SC1091
source "${REPO_ROOT}/sdk/runanywhere-commons/scripts/load-versions.sh"

if [ "$(uname -s)" != "Darwin" ]; then
    echo "error: build-core-xcframework.sh only runs on macOS" >&2
    exit 1
fi

DRY_RUN="${DRY_RUN:-0}"
RAC_BACKEND_ONNX="${RAC_BACKEND_ONNX:-ON}"
RAC_BACKEND_MLX="${RAC_BACKEND_MLX:-ON}"
COMMONS_HEADERS="${REPO_ROOT}/sdk/runanywhere-commons/include"
STAGING_DIR="${REPO_ROOT}/build/ios-xcframework-staging"
BUILD_JOBS="${RAC_BUILD_JOBS:-$(sysctl -n hw.logicalcpu)}"

run() {
    # Thin wrapper that either prints the command (DRY_RUN=1) or executes it.
    # Quoting is preserved via "$@" — callers must pass each argv entry as a
    # separate shell word, not a single string with shell metacharacters.
    if [ "${DRY_RUN}" = "1" ]; then
        printf '[DRY RUN] '
        printf '%q ' "$@"
        printf '\n'
    else
        "$@"
    fi
}

prepare_archive_input() {
    local input="$1"
    local arch="$2"
    local scratch_dir="$3"

    if [ "${DRY_RUN}" = "1" ]; then
        echo "${input}"
        return
    fi
    if [ ! -f "${input}" ]; then
        echo "error: required archive not found: ${input}" >&2
        exit 1
    fi
    if ! xcrun lipo "${input}" -verify_arch "${arch}" >/dev/null 2>&1; then
        echo "error: ${input} does not contain architecture ${arch}" >&2
        exit 1
    fi

    local info
    info="$(xcrun lipo -info "${input}")"
    if printf '%s' "${info}" | grep -q "^Non-fat file:"; then
        echo "${input}"
        return
    fi

    run mkdir -p "${scratch_dir}"
    local prepared
    prepared="${scratch_dir}/$(basename "${input}").${arch}.a"
    run xcrun lipo -thin "${arch}" "${input}" -output "${prepared}"
    echo "${prepared}"
}

merge_static_archives() {
    local output="$1"
    shift
    local inputs=("$@")

    if [ "${#inputs[@]}" -eq 0 ]; then
        echo "error: merge_static_archives called without input archives" >&2
        exit 1
    fi

    if [ "${DRY_RUN}" != "1" ]; then
        local input
        for input in "${inputs[@]}"; do
            if [ ! -f "${input}" ]; then
                echo "error: required archive not found: ${input}" >&2
                exit 1
            fi
        done
    fi

    run mkdir -p "$(dirname "${output}")"
    run rm -f "${output}"
    run xcrun libtool -static -o "${output}" "${inputs[@]}"
}

RAC_PROTO_STATIC_DEPS=()

collect_protobuf_static_deps() {
    local build_root="$1"
    local dep
    local absl_count=0
    local protobuf_has_absl_refs=0
    local protobuf_archives=()
    RAC_PROTO_STATIC_DEPS=()

    if [ "${DRY_RUN}" = "1" ] || [ ! -d "${build_root}/_deps" ]; then
        return
    fi

    while IFS= read -r dep; do
        RAC_PROTO_STATIC_DEPS+=("${dep}")
        case "$(basename "${dep}")" in
            libabsl*.a)
                absl_count=$((absl_count + 1))
                ;;
            libprotobuf*.a)
                protobuf_archives+=("${dep}")
                ;;
        esac
    done < <(find "${build_root}/_deps" -type f \( \
        -name "libprotobuf.a" -o \
        -name "libprotobuf-lite.a" -o \
        -name "libabsl*.a" -o \
        -name "libutf8*.a" \
    \) | sort)

    if [ "${DRY_RUN}" != "1" ] && [ "${#RAC_PROTO_STATIC_DEPS[@]}" -eq 0 ]; then
        echo "error: no vendored protobuf/abseil static archives found under ${build_root}/_deps" >&2
        echo "       RACommons.xcframework must bundle protobuf runtime objects." >&2
        exit 1
    fi

    if [ "${#protobuf_archives[@]}" -gt 0 ] && [ "${absl_count}" -eq 0 ]; then
        for dep in "${protobuf_archives[@]}"; do
            if nm -u "${dep}" 2>/dev/null | grep -q "absl"; then
                protobuf_has_absl_refs=1
                break
            fi
        done
        if [ "${protobuf_has_absl_refs}" = "1" ]; then
            echo "error: vendored protobuf archive references absl, but no static libabsl*.a archives were found under ${build_root}/_deps" >&2
            echo "       Reconfigure with RAC_VENDOR_PROTOBUF=ON and protobuf_FORCE_FETCH_DEPENDENCIES=ON before packaging RACommons.xcframework." >&2
            exit 1
        fi
    fi
}

merge_commons_slice() {
    local build_root="$1"
    local slice_dir="$2"
    local output="$3"
    local arch="$4"
    local scratch_dir="${STAGING_DIR}/prepared/${slice_dir}/commons"
    local inputs=(
        "${build_root}/sdk/runanywhere-commons/${slice_dir}/librac_commons.a"
        "${build_root}/_deps/libarchive-build/libarchive/${slice_dir}/libarchive.a"
    )

    # libcurl was removed from the native HTTP transport, but older dependency
    # graphs may still produce it. Bundle it only when it exists.
    local bundled_curl="${build_root}/_deps/curl_fetched-build/lib/${slice_dir}/libcurl.a"
    if [ "${DRY_RUN}" = "1" ] || [ -f "${bundled_curl}" ]; then
        inputs+=("${bundled_curl}")
    fi
    collect_protobuf_static_deps "${build_root}"
    if [ -n "${RAC_PROTO_STATIC_DEPS[*]-}" ]; then
        inputs+=("${RAC_PROTO_STATIC_DEPS[@]}")
    fi

    local prepared=()
    local input
    for input in "${inputs[@]}"; do
        prepared+=("$(prepare_archive_input "${input}" "${arch}" "${scratch_dir}")")
    done

    merge_static_archives "${output}" "${prepared[@]}"
}

merge_commons_macos_slice() {
    local build_root="$1"
    local output="$2"
    local arch="$3"
    local scratch_dir="${STAGING_DIR}/prepared/Release-macos/commons"
    local inputs=(
        "${build_root}/sdk/runanywhere-commons/librac_commons.a"
        "${build_root}/_deps/libarchive-build/libarchive/libarchive.a"
    )

    # libcurl was removed from the native HTTP transport, but older dependency
    # graphs may still produce it. Bundle it only when it exists.
    local bundled_curl="${build_root}/_deps/curl_fetched-build/lib/libcurl.a"
    if [ "${DRY_RUN}" = "1" ] || [ -f "${bundled_curl}" ]; then
        inputs+=("${bundled_curl}")
    fi
    collect_protobuf_static_deps "${build_root}"
    if [ -n "${RAC_PROTO_STATIC_DEPS[*]-}" ]; then
        inputs+=("${RAC_PROTO_STATIC_DEPS[@]}")
    fi

    local prepared=()
    local input
    for input in "${inputs[@]}"; do
        prepared+=("$(prepare_archive_input "${input}" "${arch}" "${scratch_dir}")")
    done

    merge_static_archives "${output}" "${prepared[@]}"
}

validate_isolated_protobuf_archive() {
    local archive="$1"
    local label="$2"

    if [ "${DRY_RUN}" = "1" ]; then
        return
    fi

    local symbols="${STAGING_DIR}/protobuf-symbols-${label}.txt"
    if ! nm -gU "${archive}" 2>/dev/null | c++filt > "${symbols}"; then
        echo "error: could not inspect external symbols in ${archive}" >&2
        exit 1
    fi
    if grep -Fq "google::protobuf::" "${symbols}"; then
        echo "error: ${label} RACommons exports the process-global google::protobuf namespace" >&2
        echo "       Static ONNX/Sherpa consumers can carry a different protobuf runtime; rebuild with RAC_ISOLATE_PROTOBUF_NAMESPACE=ON." >&2
        exit 1
    fi
    if ! grep -Fq "runanywhere_internal::protobuf::" "${symbols}"; then
        echo "error: ${label} RACommons is missing the isolated RunAnywhere protobuf runtime" >&2
        exit 1
    fi
    echo "  ✓ ${label} protobuf symbols are namespace-isolated"
}

find_onnxruntime_ios_archive() {
    local slice_dir="$1"
    local arch_dir

    if [ "${slice_dir}" = "Release-iphoneos" ]; then
        arch_dir="ios-arm64"
    else
        arch_dir="ios-arm64_x86_64-simulator"
    fi

    local candidates=(
        "${IOS_ONNXRT}/${arch_dir}/libonnxruntime.a"
        "${IOS_ONNXRT}/${arch_dir}/onnxruntime.a"
        "${IOS_ONNXRT}/${arch_dir}/onnxruntime.framework/onnxruntime"
    )
    local candidate
    for candidate in "${candidates[@]}"; do
        if [ "${DRY_RUN}" = "1" ] || [ -f "${candidate}" ]; then
            echo "${candidate}"
            return
        fi
    done

    echo "error: could not locate ONNX Runtime iOS archive for ${slice_dir}" >&2
    exit 1
}

merge_llamacpp_backend_slice() {
    local build_root="$1"
    local slice_dir="$2"
    local output="$3"
    local arch="$4"
    local scratch_dir="${STAGING_DIR}/prepared/${slice_dir}/llamacpp"
    local inputs=(
        "${build_root}/engines/llamacpp/${slice_dir}/librac_backend_llamacpp.a"
        "${build_root}/_deps/llamacpp-build/src/${slice_dir}/libllama.a"
        "${build_root}/_deps/llamacpp-build/common/${slice_dir}/libllama-common.a"
        "${build_root}/_deps/llamacpp-build/common/${slice_dir}/libllama-common-base.a"
        "${build_root}/_deps/llamacpp-build/ggml/src/${slice_dir}/libggml.a"
        "${build_root}/_deps/llamacpp-build/ggml/src/${slice_dir}/libggml-base.a"
        "${build_root}/_deps/llamacpp-build/ggml/src/${slice_dir}/libggml-cpu.a"
    )

    if [ "${DRY_RUN}" = "1" ] || [ -f "${build_root}/_deps/llamacpp-build/ggml/src/ggml-metal/${slice_dir}/libggml-metal.a" ]; then
        inputs+=("${build_root}/_deps/llamacpp-build/ggml/src/ggml-metal/${slice_dir}/libggml-metal.a")
    fi
    if [ "${DRY_RUN}" = "1" ] || [ -f "${build_root}/_deps/llamacpp-build/ggml/src/ggml-blas/${slice_dir}/libggml-blas.a" ]; then
        inputs+=("${build_root}/_deps/llamacpp-build/ggml/src/ggml-blas/${slice_dir}/libggml-blas.a")
    fi
    if [ "${DRY_RUN}" = "1" ] || [ -f "${build_root}/_deps/llamacpp-build/vendor/cpp-httplib/${slice_dir}/libcpp-httplib.a" ]; then
        inputs+=("${build_root}/_deps/llamacpp-build/vendor/cpp-httplib/${slice_dir}/libcpp-httplib.a")
    fi

    local prepared=()
    local input
    for input in "${inputs[@]}"; do
        prepared+=("$(prepare_archive_input "${input}" "${arch}" "${scratch_dir}")")
    done

    merge_static_archives "${output}" "${prepared[@]}"
}

merge_llamacpp_backend_macos_slice() {
    local build_root="$1"
    local output="$2"
    local arch="$3"
    local scratch_dir="${STAGING_DIR}/prepared/Release-macos/llamacpp"
    local inputs=(
        "${build_root}/engines/llamacpp/librac_backend_llamacpp.a"
        "${build_root}/_deps/llamacpp-build/src/libllama.a"
        "${build_root}/_deps/llamacpp-build/common/libllama-common.a"
        "${build_root}/_deps/llamacpp-build/common/libllama-common-base.a"
        "${build_root}/_deps/llamacpp-build/ggml/src/libggml.a"
        "${build_root}/_deps/llamacpp-build/ggml/src/libggml-base.a"
        "${build_root}/_deps/llamacpp-build/ggml/src/libggml-cpu.a"
    )

    local optional
    for optional in \
        "${build_root}/_deps/llamacpp-build/ggml/src/ggml-metal/libggml-metal.a" \
        "${build_root}/_deps/llamacpp-build/ggml/src/ggml-blas/libggml-blas.a" \
        "${build_root}/_deps/llamacpp-build/vendor/cpp-httplib/libcpp-httplib.a"; do
        if [ "${DRY_RUN}" = "1" ] || [ -f "${optional}" ]; then
            inputs+=("${optional}")
        fi
    done

    local prepared=()
    local input
    for input in "${inputs[@]}"; do
        prepared+=("$(prepare_archive_input "${input}" "${arch}" "${scratch_dir}")")
    done

    merge_static_archives "${output}" "${prepared[@]}"
}

merge_onnx_backend_slice() {
    local build_root="$1"
    local slice_dir="$2"
    local output="$3"
    local arch="$4"
    local scratch_dir="${STAGING_DIR}/prepared/${slice_dir}/onnx"
    # ONNX owns generic ONNX Runtime services. When RABackendSherpa is being
    # built as its own xcframework, keep sherpa's implementation objects and
    # the sherpa-onnx prebuilt archives out of this slice so consumers linking
    # both RABackendONNX + RABackendSherpa don't see duplicate symbols.
    # When RAC_BACKEND_SHERPA=OFF, fold sherpa in here to keep the ONNX
    # xcframework self-contained for consumers that want speech-capable ONNX
    # without a separate sherpa artifact.
    local inputs=(
        "${build_root}/engines/onnx/${slice_dir}/librac_backend_onnx.a"
        "${build_root}/runtimes/onnxrt/${slice_dir}/librac_runtime_onnxrt.a"
        "$(find_onnxruntime_ios_archive "${slice_dir}")"
    )

    if [ "${RAC_BACKEND_SHERPA:-ON}" = "OFF" ]; then
        if [ "${DRY_RUN}" = "1" ] || [ -f "${build_root}/engines/sherpa/${slice_dir}/librac_backend_sherpa.a" ]; then
            inputs+=("${build_root}/engines/sherpa/${slice_dir}/librac_backend_sherpa.a")
        fi
        local sherpa_dir
        if [ "${slice_dir}" = "Release-iphoneos" ]; then
            sherpa_dir="${REPO_ROOT}/sdk/runanywhere-commons/third_party/sherpa-onnx-ios/sherpa-onnx.xcframework/ios-arm64"
        else
            sherpa_dir="${REPO_ROOT}/sdk/runanywhere-commons/third_party/sherpa-onnx-ios/sherpa-onnx.xcframework/ios-arm64_x86_64-simulator"
        fi
        if [ "${DRY_RUN}" = "1" ] || [ -d "${sherpa_dir}" ]; then
            local sherpa_archive
            for sherpa_archive in "${sherpa_dir}"/*.a; do
                if [ "${DRY_RUN}" = "1" ] || [ -f "${sherpa_archive}" ]; then
                    inputs+=("${sherpa_archive}")
                fi
            done
        fi
    fi

    local prepared=()
    local input
    for input in "${inputs[@]}"; do
        prepared+=("$(prepare_archive_input "${input}" "${arch}" "${scratch_dir}")")
    done

    merge_static_archives "${output}" "${prepared[@]}"
}

merge_onnx_backend_macos_slice() {
    local build_root="$1"
    local output="$2"
    local arch="$3"
    local scratch_dir="${STAGING_DIR}/prepared/Release-macos/onnx"
    local inputs=(
        "${build_root}/engines/onnx/librac_backend_onnx.a"
        "${build_root}/runtimes/onnxrt/librac_runtime_onnxrt.a"
        "${MACOS_SHERPA_ROOT}/lib/libonnxruntime.a"
    )

    local prepared=()
    local input
    for input in "${inputs[@]}"; do
        prepared+=("$(prepare_archive_input "${input}" "${arch}" "${scratch_dir}")")
    done

    merge_static_archives "${output}" "${prepared[@]}"
}

# Sherpa engine slice. Fold in the sherpa-onnx prebuilt archives because this
# xcframework owns the speech implementation objects and their static deps.
merge_sherpa_backend_slice() {
    local build_root="$1"
    local slice_dir="$2"
    local output="$3"
    local arch="$4"
    local scratch_dir="${STAGING_DIR}/prepared/${slice_dir}/sherpa"
    local inputs=(
        "${build_root}/engines/sherpa/${slice_dir}/librac_backend_sherpa.a"
    )
    local sherpa_dir

    if [ "${slice_dir}" = "Release-iphoneos" ]; then
        sherpa_dir="${REPO_ROOT}/sdk/runanywhere-commons/third_party/sherpa-onnx-ios/sherpa-onnx.xcframework/ios-arm64"
    else
        sherpa_dir="${REPO_ROOT}/sdk/runanywhere-commons/third_party/sherpa-onnx-ios/sherpa-onnx.xcframework/ios-arm64_x86_64-simulator"
    fi

    if [ "${DRY_RUN}" = "1" ] || [ -d "${sherpa_dir}" ]; then
        local sherpa_archive
        for sherpa_archive in "${sherpa_dir}"/*.a; do
            if [ "${DRY_RUN}" = "1" ] || [ -f "${sherpa_archive}" ]; then
                inputs+=("${sherpa_archive}")
            fi
        done
    fi

    local prepared=()
    local input
    for input in "${inputs[@]}"; do
        prepared+=("$(prepare_archive_input "${input}" "${arch}" "${scratch_dir}")")
    done

    merge_static_archives "${output}" "${prepared[@]}"
}

merge_sherpa_backend_macos_slice() {
    local build_root="$1"
    local output="$2"
    local arch="$3"
    local scratch_dir="${STAGING_DIR}/prepared/Release-macos/sherpa"
    local inputs=(
        "${build_root}/engines/sherpa/librac_backend_sherpa.a"
        "${MACOS_SHERPA_STATIC_DEPS[@]}"
    )

    local prepared=()
    local input
    for input in "${inputs[@]}"; do
        prepared+=("$(prepare_archive_input "${input}" "${arch}" "${scratch_dir}")")
    done

    merge_static_archives "${output}" "${prepared[@]}"
}

merge_mlx_backend_slice() {
    local build_root="$1"
    local slice_dir="$2"
    local output="$3"
    local arch="$4"
    local scratch_dir="${STAGING_DIR}/prepared/${slice_dir}/mlx"
    local inputs=(
        "${build_root}/engines/mlx/${slice_dir}/librac_backend_mlx.a"
    )

    local prepared=()
    local input
    for input in "${inputs[@]}"; do
        prepared+=("$(prepare_archive_input "${input}" "${arch}" "${scratch_dir}")")
    done

    merge_static_archives "${output}" "${prepared[@]}"
}

merge_mlx_backend_macos_slice() {
    local build_root="$1"
    local output="$2"
    local arch="$3"
    local scratch_dir="${STAGING_DIR}/prepared/Release-macos/mlx"
    local inputs=(
        "${build_root}/engines/mlx/librac_backend_mlx.a"
    )

    local prepared=()
    local input
    for input in "${inputs[@]}"; do
        prepared+=("$(prepare_archive_input "${input}" "${arch}" "${scratch_dir}")")
    done

    merge_static_archives "${output}" "${prepared[@]}"
}

# ────────────────────────────────────────────────────────────────────────────
# Prereq: the iOS ONNX Runtime xcframework. Only when ONNX is enabled.
# ────────────────────────────────────────────────────────────────────────────
IOS_ONNXRT="${REPO_ROOT}/sdk/runanywhere-commons/third_party/onnxruntime-ios/onnxruntime.xcframework"
if [ "${RAC_BACKEND_ONNX}" = "ON" ] && [ ! -d "${IOS_ONNXRT}" ] && [ "${DRY_RUN}" != "1" ]; then
    cat >&2 <<EOF
error: ONNX Runtime iOS xcframework not found at
  ${IOS_ONNXRT}

Run this first (one-time, per checkout):
  ./sdk/runanywhere-commons/scripts/ios/download-onnx.sh

Or re-run with RAC_BACKEND_ONNX=OFF to skip the ONNX backend entirely.
EOF
    exit 1
fi

# ────────────────────────────────────────────────────────────────────────────
# Prereq: the iOS Sherpa-ONNX xcframework. Required when the sherpa backend
# is enabled (default). Without it, engines/sherpa's CMake gate sets
# SHERPA_ONNX_AVAILABLE=0 → RAC_SHERPA_ROUTABLE=0, which strips
# stt_ops/tts_ops/vad_ops from the sherpa plugin vtable. The xcframework
# still ships, but every STT/TTS/VAD load with `framework=sherpa` hits the
# "no backend route supports requested model" router rejection (FIXLOOP-TR-1).
# ────────────────────────────────────────────────────────────────────────────
IOS_SHERPA="${REPO_ROOT}/sdk/runanywhere-commons/third_party/sherpa-onnx-ios/sherpa-onnx.xcframework"
if [ "${RAC_BACKEND_SHERPA:-ON}" = "ON" ] && [ ! -d "${IOS_SHERPA}" ] && [ "${DRY_RUN}" != "1" ]; then
    cat >&2 <<EOF
error: Sherpa-ONNX iOS xcframework not found at
  ${IOS_SHERPA}

Run this first (one-time, per checkout):
  ./sdk/runanywhere-commons/scripts/ios/download-sherpa-onnx.sh

Or re-run with RAC_BACKEND_SHERPA=OFF to skip the Sherpa-ONNX backend (this
will disable STT/TTS/VAD via Whisper/Piper/Silero on iOS).
EOF
    exit 1
fi

# The macOS ONNX and Sherpa slices are fully static. Both consume the pinned
# inventory produced from the exact SHERPA_ONNX_COMMIT_MACOS revision; the
# ONNX slice folds in libonnxruntime.a and the Sherpa slice folds in the speech
# archives. Enumerate the contract instead of globbing so an incomplete
# download/build cannot produce an apparently valid but link-broken release.
MACOS_SHERPA_ROOT="${REPO_ROOT}/sdk/runanywhere-commons/third_party/sherpa-onnx-macos"
MACOS_SHERPA_STATIC_DEPS=(
    "${MACOS_SHERPA_ROOT}/lib/libsherpa-onnx-c-api.a"
    "${MACOS_SHERPA_ROOT}/lib/libsherpa-onnx-core.a"
    "${MACOS_SHERPA_ROOT}/lib/libsherpa-onnx-fst.a"
    "${MACOS_SHERPA_ROOT}/lib/libsherpa-onnx-fstfar.a"
    "${MACOS_SHERPA_ROOT}/lib/libsherpa-onnx-kaldifst-core.a"
    "${MACOS_SHERPA_ROOT}/lib/libkaldi-decoder-core.a"
    "${MACOS_SHERPA_ROOT}/lib/libkaldi-native-fbank-core.a"
    "${MACOS_SHERPA_ROOT}/lib/libpiper_phonemize.a"
    "${MACOS_SHERPA_ROOT}/lib/libespeak-ng.a"
    "${MACOS_SHERPA_ROOT}/lib/libucd.a"
    "${MACOS_SHERPA_ROOT}/lib/libssentencepiece_core.a"
    "${MACOS_SHERPA_ROOT}/lib/libkissfft-float.a"
)
if [ "${RAC_BACKEND_ONNX}" = "ON" ] && [ "${DRY_RUN}" != "1" ]; then
    macos_required=(
        "${MACOS_SHERPA_ROOT}/lib/libonnxruntime.a"
        "${MACOS_SHERPA_ROOT}/include/onnxruntime_c_api.h"
        "${MACOS_SHERPA_ROOT}/include/onnxruntime_cxx_api.h"
        "${MACOS_SHERPA_ROOT}/include/sherpa-onnx/c-api/c-api.h"
        "${MACOS_SHERPA_STATIC_DEPS[@]}"
    )
    for required in "${macos_required[@]}"; do
        if [ ! -f "${required}" ]; then
            echo "error: required pinned macOS static dependency not found: ${required}" >&2
            echo "       Run ./sdk/runanywhere-commons/scripts/macos/download-sherpa-onnx.sh" >&2
            exit 1
        fi
        if [[ "${required}" == *.a ]] && ! xcrun lipo "${required}" -verify_arch arm64 >/dev/null 2>&1; then
            echo "error: required macOS archive is not arm64: ${required}" >&2
            exit 1
        fi
    done
fi

mkdir -p "${DEST}"
run rm -rf "${STAGING_DIR}"
run mkdir -p "${STAGING_DIR}"

# ────────────────────────────────────────────────────────────────────────────
# 1 & 2. Configure + build iOS slices (device + simulator) and matching
#        macOS slices for every advertised Swift binary target.
# ────────────────────────────────────────────────────────────────────────────
cmake_extra=(
    "-DCMAKE_C_FLAGS=-ffile-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fmacro-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fdebug-prefix-map=${REPO_ROOT}=/runanywhere-sdks"
    "-DCMAKE_CXX_FLAGS=-ffile-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fmacro-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fdebug-prefix-map=${REPO_ROOT}=/runanywhere-sdks"
    "-DCMAKE_OBJC_FLAGS=-ffile-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fmacro-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fdebug-prefix-map=${REPO_ROOT}=/runanywhere-sdks"
    "-DCMAKE_OBJCXX_FLAGS=-ffile-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fmacro-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fdebug-prefix-map=${REPO_ROOT}=/runanywhere-sdks"
    "-DRAC_ENABLE_PROTOBUF=ON"
    "-DRAC_ENABLE_SOLUTIONS=${RAC_ENABLE_SOLUTIONS:-ON}"
    "-DRAC_VENDOR_PROTOBUF=ON"
    "-DCMAKE_DISABLE_FIND_PACKAGE_Protobuf=TRUE"
    "-DCMAKE_DISABLE_FIND_PACKAGE_absl=TRUE"
    "-Dprotobuf_FORCE_FETCH_DEPENDENCIES=ON"
)
ios_cmake_extra=(
    "-DRAC_BACKEND_COREML=OFF"
    "-DGGML_NATIVE=OFF"
    "-DCMAKE_OSX_DEPLOYMENT_TARGET=${IOS_DEPLOYMENT_TARGET}"
)
if [ "${RAC_BACKEND_ONNX}" = "OFF" ]; then
    cmake_extra+=("-DRAC_BACKEND_ONNX=OFF")
fi
if [ "${RAC_BACKEND_MLX}" = "OFF" ]; then
    cmake_extra+=("-DRAC_BACKEND_MLX=OFF")
fi

echo "▶ Configure ios-device"
run cmake --preset ios-device "${cmake_extra[@]}" "${ios_cmake_extra[@]}"
echo "▶ Build ios-device (Release)"
ios_build_targets=(rac_commons rac_backend_llamacpp)
if [ "${RAC_BACKEND_ONNX}" = "ON" ]; then
    ios_build_targets+=(rac_backend_onnx)
fi
if [ "${RAC_BACKEND_SHERPA:-ON}" = "ON" ]; then
    ios_build_targets+=(rac_backend_sherpa)
fi
if [ "${RAC_BACKEND_MLX}" = "ON" ]; then
    ios_build_targets+=(rac_backend_mlx)
fi
run cmake --build --preset ios-device --config Release --target "${ios_build_targets[@]}" --parallel "${BUILD_JOBS}"

echo "▶ Configure ios-simulator"
run cmake --preset ios-simulator "${cmake_extra[@]}" "${ios_cmake_extra[@]}"
echo "▶ Build ios-simulator (Release)"
run cmake --build --preset ios-simulator --config Release --target "${ios_build_targets[@]}" --parallel "${BUILD_JOBS}"

echo "▶ Configure macos-release"
macos_cmake_args=(
    "-DCMAKE_C_FLAGS=-ffile-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fmacro-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fdebug-prefix-map=${REPO_ROOT}=/runanywhere-sdks"
    "-DCMAKE_CXX_FLAGS=-ffile-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fmacro-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fdebug-prefix-map=${REPO_ROOT}=/runanywhere-sdks"
    "-DCMAKE_OBJC_FLAGS=-ffile-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fmacro-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fdebug-prefix-map=${REPO_ROOT}=/runanywhere-sdks"
    "-DCMAKE_OBJCXX_FLAGS=-ffile-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fmacro-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fdebug-prefix-map=${REPO_ROOT}=/runanywhere-sdks"
    "-DRAC_BUILD_BACKENDS=ON"
    # The macOS slice ships inside the XCFramework and is linked statically by
    # SPM consumers (swift test, macOS apps) — there is no sibling shared-lib
    # loading there, so in-tree engines (e.g. cloud) must fold into
    # rac_commons exactly like the iOS slices, or unconditionally-referenced
    # symbols (rac_backend_cloud_register) fail the consumer link.
    "-DRAC_STATIC_PLUGINS=ON"
    "-DRAC_BACKEND_RAG=ON"
    "-DRAC_BACKEND_LLAMACPP=ON"
    "-DRAC_BACKEND_ONNX=${RAC_BACKEND_ONNX}"
    "-DRAC_BACKEND_SHERPA=${RAC_BACKEND_SHERPA:-ON}"
    "-DRAC_BACKEND_COREML=OFF"
    "-DGGML_NATIVE=OFF"
    "-DCMAKE_DISABLE_FIND_PACKAGE_Protobuf=TRUE"
    "-DCMAKE_DISABLE_FIND_PACKAGE_absl=TRUE"
    "-DCMAKE_OSX_ARCHITECTURES=arm64"
    "-DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOS_DEPLOYMENT_TARGET}"
    "-DRAC_ENABLE_PROTOBUF=ON"
    "-DRAC_ENABLE_SOLUTIONS=${RAC_ENABLE_SOLUTIONS:-ON}"
    "-DRAC_VENDOR_PROTOBUF=ON"
    "-Dprotobuf_FORCE_FETCH_DEPENDENCIES=ON"
)
run cmake --preset macos-release "${macos_cmake_args[@]}"
echo "▶ Build macos-release"
macos_build_targets=(rac_commons rac_backend_llamacpp)
if [ "${RAC_BACKEND_ONNX}" = "ON" ]; then
    macos_build_targets+=(rac_backend_onnx)
fi
if [ "${RAC_BACKEND_SHERPA:-ON}" = "ON" ]; then
    macos_build_targets+=(rac_backend_sherpa)
fi
if [ "${RAC_BACKEND_MLX}" = "ON" ]; then
    macos_build_targets+=(rac_backend_mlx)
fi
run cmake --build --preset macos-release --target "${macos_build_targets[@]}" --parallel "${BUILD_JOBS}"

# ────────────────────────────────────────────────────────────────────────────
# 3. Locate archives and package each target as an xcframework with both
#    device + simulator slices.
#
# Under the Xcode generator, static-library targets land at
#   ${CMAKE_BINARY_DIR}/<source-subdir>/Release-iphoneos/lib<target>.a
# and
#   ${CMAKE_BINARY_DIR}/<source-subdir>/Release-iphonesimulator/lib<target>.a
# ────────────────────────────────────────────────────────────────────────────
DEV_BIN="${REPO_ROOT}/build/ios-device"
SIM_BIN="${REPO_ROOT}/build/ios-simulator"
MAC_BIN="${REPO_ROOT}/build/macos-release"

# find_lib <subdir-under-bin> <libname>
find_lib() {
    local dev_path="${DEV_BIN}/$1/Release-iphoneos/$2"
    local sim_path="${SIM_BIN}/$1/Release-iphonesimulator/$2"
    if [ "${DRY_RUN}" = "1" ]; then
        # In dry-run mode the files don't exist; emit placeholders so
        # downstream `run xcodebuild -create-xcframework` still prints
        # something meaningful.
        echo "${dev_path}|${sim_path}"
        return
    fi
    if [ ! -f "${dev_path}" ]; then
        echo "error: expected device archive not found: ${dev_path}" >&2
        exit 1
    fi
    if [ ! -f "${sim_path}" ]; then
        echo "error: expected simulator archive not found: ${sim_path}" >&2
        exit 1
    fi
    echo "${dev_path}|${sim_path}"
}

# build_xcframework_from_paths <device-lib> <simulator-lib> <xcframework-name> [--with-headers]
#
# Only the first (RACommons) xcframework ships the commons C header tree via
# `-headers`. Backend xcframeworks share the same canonical commons headers,
# but bundling the same tree into every `.xcframework`'s `Headers/` directory
# causes `error: Multiple commands produce .../include/rac/.../*.h` when Xcode's
# SPM binary-target integration processes all three bundles in the same build
# graph. Downstream Swift modules import the commons headers via
# `RACommonsBinary` anyway, so the backend xcframeworks only need to carry
# their `.a` archives — the headers come from RACommons.xcframework.
build_xcframework_from_paths() {
    local dev_lib="$1"
    local sim_lib="$2"
    local xcf_name="$3"
    local mode="${4:-}"

    local xcf="${DEST}/${xcf_name}"
    echo "▶ Create-xcframework → ${xcf}"
    run rm -rf "${xcf}"
    if [ "${mode}" = "--with-headers" ]; then
        run xcodebuild -create-xcframework \
            -library "${dev_lib}" -headers "${COMMONS_HEADERS}" \
            -library "${sim_lib}" -headers "${COMMONS_HEADERS}" \
            -output  "${xcf}"
    else
        run xcodebuild -create-xcframework \
            -library "${dev_lib}" \
            -library "${sim_lib}" \
            -output  "${xcf}"
    fi
}

# build_xcframework_from_paths_with_macos <device-lib> <simulator-lib> <macos-lib> <xcframework-name> [--with-headers]
build_xcframework_from_paths_with_macos() {
    local dev_lib="$1"
    local sim_lib="$2"
    local mac_lib="$3"
    local xcf_name="$4"
    local mode="${5:-}"

    local xcf="${DEST}/${xcf_name}"
    echo "▶ Create-xcframework → ${xcf}"
    run rm -rf "${xcf}"
    if [ "${mode}" = "--with-headers" ]; then
        run xcodebuild -create-xcframework \
            -library "${dev_lib}" -headers "${COMMONS_HEADERS}" \
            -library "${sim_lib}" -headers "${COMMONS_HEADERS}" \
            -library "${mac_lib}" -headers "${COMMONS_HEADERS}" \
            -output  "${xcf}"
    else
        run xcodebuild -create-xcframework \
            -library "${dev_lib}" \
            -library "${sim_lib}" \
            -library "${mac_lib}" \
            -output  "${xcf}"
    fi
}

COMMONS_DEV_LIB="${STAGING_DIR}/Release-iphoneos/librac_commons.a"
COMMONS_SIM_LIB="${STAGING_DIR}/Release-iphonesimulator/librac_commons.a"
COMMONS_MAC_LIB="${STAGING_DIR}/Release-macos/librac_commons.a"
merge_commons_slice "${DEV_BIN}" "Release-iphoneos" "${COMMONS_DEV_LIB}" "arm64"
merge_commons_slice "${SIM_BIN}" "Release-iphonesimulator" "${COMMONS_SIM_LIB}" "arm64"
merge_commons_macos_slice "${MAC_BIN}" "${COMMONS_MAC_LIB}" "arm64"
validate_isolated_protobuf_archive "${COMMONS_DEV_LIB}" "ios-device"
validate_isolated_protobuf_archive "${COMMONS_SIM_LIB}" "ios-simulator"
validate_isolated_protobuf_archive "${COMMONS_MAC_LIB}" "macos"

LLAMACPP_DEV_LIB="${STAGING_DIR}/Release-iphoneos/librac_backend_llamacpp.a"
LLAMACPP_SIM_LIB="${STAGING_DIR}/Release-iphonesimulator/librac_backend_llamacpp.a"
LLAMACPP_MAC_LIB="${STAGING_DIR}/Release-macos/librac_backend_llamacpp.a"
merge_llamacpp_backend_slice "${DEV_BIN}" "Release-iphoneos" "${LLAMACPP_DEV_LIB}" "arm64"
merge_llamacpp_backend_slice "${SIM_BIN}" "Release-iphonesimulator" "${LLAMACPP_SIM_LIB}" "arm64"
merge_llamacpp_backend_macos_slice "${MAC_BIN}" "${LLAMACPP_MAC_LIB}" "arm64"

build_xcframework_from_paths_with_macos "${COMMONS_DEV_LIB}" "${COMMONS_SIM_LIB}" "${COMMONS_MAC_LIB}" "RACommons.xcframework" --with-headers
build_xcframework_from_paths_with_macos "${LLAMACPP_DEV_LIB}" "${LLAMACPP_SIM_LIB}" "${LLAMACPP_MAC_LIB}" "RABackendLLAMACPP.xcframework"
if [ "${RAC_BACKEND_ONNX}" = "ON" ]; then
    ONNX_DEV_LIB="${STAGING_DIR}/Release-iphoneos/librac_backend_onnx.a"
    ONNX_SIM_LIB="${STAGING_DIR}/Release-iphonesimulator/librac_backend_onnx.a"
    ONNX_MAC_LIB="${STAGING_DIR}/Release-macos/librac_backend_onnx.a"
    merge_onnx_backend_slice "${DEV_BIN}" "Release-iphoneos" "${ONNX_DEV_LIB}" "arm64"
    merge_onnx_backend_slice "${SIM_BIN}" "Release-iphonesimulator" "${ONNX_SIM_LIB}" "arm64"
    merge_onnx_backend_macos_slice "${MAC_BIN}" "${ONNX_MAC_LIB}" "arm64"
    build_xcframework_from_paths_with_macos "${ONNX_DEV_LIB}" "${ONNX_SIM_LIB}" "${ONNX_MAC_LIB}" "RABackendONNX.xcframework"
else
    echo "▶ Skipping RABackendONNX.xcframework (RAC_BACKEND_ONNX=OFF)"
fi

# RABackendSherpa.xcframework as the speech peer of RABackendONNX.
if [ "${RAC_BACKEND_SHERPA:-ON}" = "ON" ]; then
    SHERPA_DEV_LIB="${STAGING_DIR}/Release-iphoneos/librac_backend_sherpa.a"
    SHERPA_SIM_LIB="${STAGING_DIR}/Release-iphonesimulator/librac_backend_sherpa.a"
    SHERPA_MAC_LIB="${STAGING_DIR}/Release-macos/librac_backend_sherpa.a"
    if [ "${DRY_RUN}" = "1" ] || [ -f "${DEV_BIN}/engines/sherpa/Release-iphoneos/librac_backend_sherpa.a" ]; then
        merge_sherpa_backend_slice "${DEV_BIN}" "Release-iphoneos" "${SHERPA_DEV_LIB}" "arm64"
        merge_sherpa_backend_slice "${SIM_BIN}" "Release-iphonesimulator" "${SHERPA_SIM_LIB}" "arm64"
        merge_sherpa_backend_macos_slice "${MAC_BIN}" "${SHERPA_MAC_LIB}" "arm64"
        build_xcframework_from_paths_with_macos "${SHERPA_DEV_LIB}" "${SHERPA_SIM_LIB}" "${SHERPA_MAC_LIB}" "RABackendSherpa.xcframework"
    else
        echo "▶ Skipping RABackendSherpa.xcframework (target not built — engines/sherpa disabled?)"
    fi
else
    echo "▶ Skipping RABackendSherpa.xcframework (RAC_BACKEND_SHERPA=OFF)"
fi

# RABackendMLX.xcframework provides the C++ callback-backed plugin shell. The
# Swift MLXRuntime target links this archive plus mlx-swift-lm.
if [ "${RAC_BACKEND_MLX}" = "ON" ]; then
    MLX_DEV_LIB="${STAGING_DIR}/Release-iphoneos/librac_backend_mlx.a"
    MLX_SIM_LIB="${STAGING_DIR}/Release-iphonesimulator/librac_backend_mlx.a"
    MLX_MAC_LIB="${STAGING_DIR}/Release-macos/librac_backend_mlx.a"
    merge_mlx_backend_slice "${DEV_BIN}" "Release-iphoneos" "${MLX_DEV_LIB}" "arm64"
    merge_mlx_backend_slice "${SIM_BIN}" "Release-iphonesimulator" "${MLX_SIM_LIB}" "arm64"
    merge_mlx_backend_macos_slice "${MAC_BIN}" "${MLX_MAC_LIB}" "arm64"
    build_xcframework_from_paths_with_macos "${MLX_DEV_LIB}" "${MLX_SIM_LIB}" "${MLX_MAC_LIB}" "RABackendMLX.xcframework"
else
    echo "▶ Skipping RABackendMLX.xcframework (RAC_BACKEND_MLX=OFF)"
fi

sync_react_native_frameworks() {
    local rn_root="${REPO_ROOT}/sdk/runanywhere-react-native/packages"
    if [ ! -d "${rn_root}" ]; then
        return
    fi

    echo "▶ Sync React Native local iOS binaries"
    run mkdir -p "${rn_root}/core/ios/Binaries"
    run rm -rf "${rn_root}/core/ios/Binaries/RACommons.xcframework"
    run cp -R "${DEST}/RACommons.xcframework" "${rn_root}/core/ios/Binaries/"

    # RN backend podspecs vendor xcframeworks from ios/Binaries (matches
    # package-sdk.sh --natives-from staging and the new podspec contract).
    # Clean up the legacy ios/Frameworks paths so the source layout cannot
    # serve a stale framework while CocoaPods looks at ios/Binaries.
    run mkdir -p "${rn_root}/llamacpp/ios/Binaries"
    run rm -rf "${rn_root}/llamacpp/ios/Binaries/RABackendLLAMACPP.xcframework"
    run rm -rf "${rn_root}/llamacpp/ios/Frameworks/RABackendLLAMACPP.xcframework"
    run cp -R "${DEST}/RABackendLLAMACPP.xcframework" "${rn_root}/llamacpp/ios/Binaries/"

    if [ -d "${DEST}/RABackendONNX.xcframework" ]; then
        run mkdir -p "${rn_root}/onnx/ios/Binaries"
        run rm -rf "${rn_root}/onnx/ios/Binaries/RABackendONNX.xcframework"
        run rm -rf "${rn_root}/onnx/ios/Frameworks/RABackendONNX.xcframework"
        run rm -rf "${rn_root}/onnx/ios/Frameworks/onnxruntime.xcframework"
        run cp -R "${DEST}/RABackendONNX.xcframework" "${rn_root}/onnx/ios/Binaries/"
    fi

    # Stage the Sherpa plugin xcframework alongside ONNX's
    # (sherpa is the long-term owner of speech primitives).
    if [ -d "${DEST}/RABackendSherpa.xcframework" ]; then
        run mkdir -p "${rn_root}/onnx/ios/Binaries"
        run rm -rf "${rn_root}/onnx/ios/Binaries/RABackendSherpa.xcframework"
        run rm -rf "${rn_root}/onnx/ios/Frameworks/RABackendSherpa.xcframework"
        run cp -R "${DEST}/RABackendSherpa.xcframework" "${rn_root}/onnx/ios/Binaries/"
    fi
}

# Copy locally built xcframeworks next to each Flutter plugin's CocoaPods and
# SwiftPM sources so both package managers resolve the same canonical binary.
# Remove the superseded ios/Frameworks copies; current podspecs and Package.swift
# manifests intentionally reference ios/<package>/Frameworks only.
#
# Plugin → xcframework mapping:
#   runanywhere             ← RACommons.xcframework
#   runanywhere_llamacpp    ← RABackendLLAMACPP.xcframework
#   runanywhere_onnx        ← RABackendONNX.xcframework
sync_flutter_frameworks() {
    local flutter_root="${REPO_ROOT}/sdk/runanywhere-flutter/packages"
    if [ ! -d "${flutter_root}" ]; then
        return
    fi

    echo "▶ Sync Flutter local iOS binaries"

    local flutter_core="${flutter_root}/runanywhere/ios/runanywhere/Frameworks"
    local flutter_llama="${flutter_root}/runanywhere_llamacpp/ios/runanywhere_llamacpp/Frameworks"
    local flutter_onnx="${flutter_root}/runanywhere_onnx/ios/runanywhere_onnx/Frameworks"

    run rm -rf \
        "${flutter_root}/runanywhere/ios/Frameworks/RACommons.xcframework" \
        "${flutter_root}/runanywhere_llamacpp/ios/Frameworks/RABackendLLAMACPP.xcframework" \
        "${flutter_root}/runanywhere_onnx/ios/Frameworks/RABackendONNX.xcframework" \
        "${flutter_root}/runanywhere_onnx/ios/Frameworks/RABackendSherpa.xcframework" \
        "${flutter_root}/runanywhere_onnx/ios/Frameworks/onnxruntime.xcframework"

    run mkdir -p "${flutter_core}" "${flutter_llama}" "${flutter_onnx}"

    if [ -d "${DEST}/RACommons.xcframework" ]; then
        run rm -rf "${flutter_core}/RACommons.xcframework"
        run cp -R "${DEST}/RACommons.xcframework" "${flutter_core}/"
    fi

    if [ -d "${DEST}/RABackendLLAMACPP.xcframework" ]; then
        run rm -rf "${flutter_llama}/RABackendLLAMACPP.xcframework"
        run cp -R "${DEST}/RABackendLLAMACPP.xcframework" "${flutter_llama}/"
    fi

    if [ -d "${DEST}/RABackendONNX.xcframework" ]; then
        run rm -rf "${flutter_onnx}/RABackendONNX.xcframework"
        run cp -R "${DEST}/RABackendONNX.xcframework" "${flutter_onnx}/"
        # Stale onnxruntime.xcframework (pre-v0.19.0) is no longer shipped —
        # ONNX Runtime is now statically linked into RABackendONNX.a.
        run rm -rf "${flutter_onnx}/onnxruntime.xcframework"
    fi

    # Ship RABackendSherpa.xcframework inside runanywhere_onnx
    # for now (sherpa peers with onnx on speech). A future runanywhere_sherpa
    # plugin can consume it directly.
    if [ -d "${DEST}/RABackendSherpa.xcframework" ]; then
        run rm -rf "${flutter_onnx}/RABackendSherpa.xcframework"
        run cp -R "${DEST}/RABackendSherpa.xcframework" "${flutter_onnx}/"
    fi
}

sync_react_native_frameworks
sync_flutter_frameworks

echo ""
echo "✓ XCFrameworks written to: ${DEST}"
