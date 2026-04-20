#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# scripts/build-core-xcframework.sh
#
# Builds the new C++ core as an XCFramework suitable for consumption by
# sdk/runanywhere-swift — the canonical migration artifact per
# thoughts/shared/plans/v2_rearchitecture/sdk_migration/01_swift.md.
#
# Output:
#   sdk/swift/Binaries/RACommonsCore.xcframework/
#
# The XCFramework bundles static libraries for every Apple platform +
# simulator arch slice. sdk/runanywhere-swift then declares a binaryTarget
# pointing at this directory.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT}/sdk/swift/Binaries"
FRAMEWORK_NAME="RACommonsCore"
FRAMEWORK="${OUT_DIR}/${FRAMEWORK_NAME}.xcframework"
BUILD_ROOT="${ROOT}/build/xcframework"

mkdir -p "${OUT_DIR}" "${BUILD_ROOT}"
rm -rf "${FRAMEWORK}"

usage() {
    cat <<EOF
usage: scripts/build-core-xcframework.sh [--platforms=<list>] [--clean]

  --platforms=a,b  comma-separated subset of:
                   ios-device, ios-sim, macos (default: all three)
  --clean          wipe build/xcframework/ before starting

Output is written to ${FRAMEWORK}.
EOF
}

PLATFORMS="ios-device,ios-sim,macos"
CLEAN=0
for arg in "$@"; do
    case "$arg" in
        --platforms=*) PLATFORMS="${arg#--platforms=}" ;;
        --clean)       CLEAN=1 ;;
        -h|--help)     usage; exit 0 ;;
        *) echo "unknown flag: $arg" >&2; usage; exit 2 ;;
    esac
done

if [ "$CLEAN" = "1" ]; then
    rm -rf "${BUILD_ROOT}"
    mkdir -p "${BUILD_ROOT}"
fi

# -----------------------------------------------------------------------------
# build_slice <cmake_dir> <extra_cmake_args...>
#   Produces a single static archive combining ra_core_abi + ra_core_graph +
#   ra_core_registry + ra_core_router + ra_core_voice_pipeline +
#   ra_core_model_registry + ra_core_net + ra_core_util.
# -----------------------------------------------------------------------------
build_slice() {
    local slice="$1"; shift
    local build_dir="${BUILD_ROOT}/${slice}"

    # iOS slices skip libcurl / libarchive because neither is available
    # in the iOS sysroot. iOS also skips RA_BUILD_ENGINES because llama.cpp
    # uses try_run() which doesn't cross-compile; engines ship as a
    # separate iOS slice built via llama.cpp's native xcframework later.
    local extra_args=("")
    local targets_list="ra_core_abi ra_core_graph ra_core_registry ra_core_router ra_core_voice_pipeline ra_core_model_registry ra_core_net ra_core_util ra_core_pipeline_abi ra_core_llm_dispatch ra_core_state_abi ra_core_abi_ext ra_solution_voice_agent ra_solution_rag"
    case "$slice" in
        ios-device|ios-sim)
            extra_args=(
                -DRA_BUILD_HTTP_CLIENT=OFF
                -DRA_BUILD_MODEL_DOWNLOADER=OFF
                -DRA_BUILD_EXTRACTION=OFF
                -DRA_BUILD_ENGINES=OFF
            )
            ;;
        macos)
            # All Apple slices delegate HTTP + download + extraction to the
            # platform adapter (URLSession / NSFileManager / NSTask unzip).
            # Dropping the curl/libarchive deps keeps the XCFramework
            # self-contained without requiring host apps to link system
            # libraries.
            extra_args=(
                -DRA_BUILD_HTTP_CLIENT=OFF
                -DRA_BUILD_MODEL_DOWNLOADER=OFF
                -DRA_BUILD_EXTRACTION=OFF
            )
            targets_list="$targets_list llamacpp_engine onnx_engine whisperkit_engine metalrt_engine diffusion_coreml_engine"
            ;;
    esac

    echo "=== Building slice: ${slice} ==================================="
    # Build core + solutions + engines all as STATIC libs so the xcframework
    # delivers every symbol the Swift SDK links against in a single archive.
    cmake -S "${ROOT}" -B "${build_dir}" \
        -G "Unix Makefiles" \
        -DCMAKE_BUILD_TYPE=Release \
        -DRA_BUILD_TESTS=OFF \
        -DRA_BUILD_TOOLS=OFF \
        -DRA_BUILD_ENGINES=ON \
        -DRA_BUILD_SHERPA=OFF \
        -DRA_BUILD_SOLUTIONS=ON \
        -DRA_STATIC_PLUGINS=ON \
        "${extra_args[@]}" \
        "$@"
    # llamacpp_engine is pure source (FetchContent-built). sherpa_engine
    # links against pre-built dynamic libs which can't merge cleanly into
    # a static xcframework; it's shipped separately (see plan 01_swift.md).
    # Per-slice target list computed above — iOS skips llamacpp_engine.
    # shellcheck disable=SC2086
    cmake --build "${build_dir}" --target ${targets_list} --parallel

    # Collect every produced static archive for the merge step.
    local archives=()
    for f in "${build_dir}/core/libra_core_abi.a" \
             "${build_dir}/core/libra_core_graph.a" \
             "${build_dir}/core/libra_core_registry.a" \
             "${build_dir}/core/libra_core_router.a" \
             "${build_dir}/core/libra_core_voice_pipeline.a" \
             "${build_dir}/core/libra_core_model_registry.a" \
             "${build_dir}/core/libra_core_net.a" \
             "${build_dir}/core/libra_core_util.a" \
             "${build_dir}/core/libra_core_pipeline_abi.a" \
             "${build_dir}/core/libra_core_llm_dispatch.a" \
             "${build_dir}/core/libra_core_state_abi.a" \
             "${build_dir}/core/libra_core_abi_ext.a" \
             "${build_dir}/solutions/voice-agent/libra_solution_voice_agent.a" \
             "${build_dir}/solutions/rag/libra_solution_rag.a" \
             "${build_dir}/engines/llamacpp/libllamacpp_engine.a" \
             "${build_dir}/engines/onnx/librunanywhere_onnx.a" \
             "${build_dir}/engines/whisperkit/librunanywhere_whisperkit.a" \
             "${build_dir}/engines/metalrt/librunanywhere_metalrt.a" \
             "${build_dir}/engines/diffusion-coreml/librunanywhere_diffusion_coreml.a"; do
        if [ -f "$f" ]; then
            archives+=("$f")
        else
            echo "  (skipping missing: $f)"
        fi
    done

    # Merge into a single fat archive.
    local merged="${build_dir}/libRACommonsCore.a"
    libtool -static -o "${merged}" "${archives[@]}" 2>&1 | tail -1 || {
        echo "ERROR libtool merge failed"
        exit 3
    }
    echo "  → ${merged} ($(ls -l "${merged}" | awk '{print $5}') bytes, ${#archives[@]} archives)"
}

# -----------------------------------------------------------------------------
# Build each requested slice.
# -----------------------------------------------------------------------------
SLICE_ARGS=()

# Collect public headers once. The xcframework carries them per slice
# (arch-independent), and each -library flag pairs with its own -headers.
HEADERS_DIR="${BUILD_ROOT}/headers"
rm -rf "${HEADERS_DIR}"
mkdir -p "${HEADERS_DIR}"
cp "${ROOT}/core/Public/"*.h "${HEADERS_DIR}/"

# Module map so Swift `import CRACommonsCore` resolves the C headers.
cat > "${HEADERS_DIR}/module.modulemap" <<'MAP'
module CRACommonsCore {
    header "ra_errors.h"
    header "ra_lifecycle.h"
    header "ra_pipeline.h"
    header "ra_plugin.h"
    header "ra_primitives.h"
    header "ra_version.h"
    header "ra_platform_adapter.h"
    header "ra_core_init.h"
    header "ra_state.h"
    // Phase A extensions — full ra_* parity surface
    header "ra_tool.h"
    header "ra_structured.h"
    header "ra_image.h"
    header "ra_vlm.h"
    header "ra_diffusion.h"
    header "ra_download.h"
    header "ra_file.h"
    header "ra_storage.h"
    header "ra_extract.h"
    header "ra_device.h"
    header "ra_telemetry.h"
    header "ra_event.h"
    header "ra_http.h"
    header "ra_platform_llm.h"
    header "ra_benchmark.h"
    header "ra_server.h"
    header "ra_auth.h"
    header "ra_model.h"
    header "ra_backends.h"
    header "ra_rag.h"
    link "RACommonsCore"
    export *
}
MAP

IFS=',' read -ra REQUESTED <<< "${PLATFORMS}"
for p in "${REQUESTED[@]}"; do
    case "$p" in
        ios-device)
            build_slice ios-device \
                -DCMAKE_SYSTEM_NAME=iOS \
                -DCMAKE_OSX_ARCHITECTURES=arm64 \
                -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
                -DCMAKE_OSX_SYSROOT=iphoneos
            SLICE_ARGS+=(-library "${BUILD_ROOT}/ios-device/libRACommonsCore.a" \
                         -headers "${HEADERS_DIR}")
            ;;
        ios-sim)
            build_slice ios-sim \
                -DCMAKE_SYSTEM_NAME=iOS \
                -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
                -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
                -DCMAKE_OSX_SYSROOT=iphonesimulator
            SLICE_ARGS+=(-library "${BUILD_ROOT}/ios-sim/libRACommonsCore.a" \
                         -headers "${HEADERS_DIR}")
            ;;
        macos)
            build_slice macos \
                -DCMAKE_SYSTEM_NAME=Darwin \
                -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
                -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0
            SLICE_ARGS+=(-library "${BUILD_ROOT}/macos/libRACommonsCore.a" \
                         -headers "${HEADERS_DIR}")
            ;;
        *)
            echo "unknown platform: $p" >&2
            exit 2
            ;;
    esac
done

# -----------------------------------------------------------------------------
# Combine slices into a single XCFramework.
# -----------------------------------------------------------------------------
echo "=== Creating XCFramework ========================================"
xcodebuild -create-xcframework \
    "${SLICE_ARGS[@]}" \
    -output "${FRAMEWORK}"

echo
echo "✓ Wrote ${FRAMEWORK}"
ls -la "${FRAMEWORK}" 2>/dev/null | head
