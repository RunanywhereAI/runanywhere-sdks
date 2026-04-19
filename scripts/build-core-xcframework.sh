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
#   sdk/runanywhere-swift/Binaries/RACommonsCore.xcframework/
#
# The XCFramework bundles static libraries for every Apple platform +
# simulator arch slice. sdk/runanywhere-swift then declares a binaryTarget
# pointing at this directory.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT}/sdk/runanywhere-swift/Binaries"
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

    echo "=== Building slice: ${slice} ==================================="
    cmake -S "${ROOT}" -B "${build_dir}" \
        -G "Unix Makefiles" \
        -DCMAKE_BUILD_TYPE=Release \
        -DRA_BUILD_TESTS=OFF \
        -DRA_BUILD_TOOLS=OFF \
        -DRA_BUILD_ENGINES=OFF \
        -DRA_BUILD_SOLUTIONS=OFF \
        -DRA_STATIC_PLUGINS=ON \
        "$@"
    cmake --build "${build_dir}" --target ra_core_abi ra_core_graph \
        ra_core_registry ra_core_router ra_core_voice_pipeline \
        ra_core_model_registry ra_core_net ra_core_util \
        --parallel

    # Merge the per-target static archives into one libcore.a for the
    # xcframework. libtool is the Apple tool of choice for combining
    # static libs without losing symbols.
    local merged="${build_dir}/libRACommonsCore.a"
    libtool -static -o "${merged}" \
        "${build_dir}/core/libra_core_abi.a" \
        "${build_dir}/core/libra_core_graph.a" \
        "${build_dir}/core/libra_core_registry.a" \
        "${build_dir}/core/libra_core_router.a" \
        "${build_dir}/core/libra_core_voice_pipeline.a" \
        "${build_dir}/core/libra_core_model_registry.a" \
        "${build_dir}/core/libra_core_net.a" \
        "${build_dir}/core/libra_core_util.a" 2>/dev/null || {
        echo "WARN  libtool merge failed (likely some targets didn't build)"
        echo "      Check ${build_dir}/core/ for the per-target .a files"
        exit 3
    }
    echo "  → ${merged}"
}

# -----------------------------------------------------------------------------
# Build each requested slice.
# -----------------------------------------------------------------------------
SLICE_ARGS=()

IFS=',' read -ra REQUESTED <<< "${PLATFORMS}"
for p in "${REQUESTED[@]}"; do
    case "$p" in
        ios-device)
            build_slice ios-device \
                -DCMAKE_SYSTEM_NAME=iOS \
                -DCMAKE_OSX_ARCHITECTURES=arm64 \
                -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
                -DCMAKE_OSX_SYSROOT=iphoneos
            SLICE_ARGS+=(-library "${BUILD_ROOT}/ios-device/libRACommonsCore.a")
            ;;
        ios-sim)
            build_slice ios-sim \
                -DCMAKE_SYSTEM_NAME=iOS \
                -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
                -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
                -DCMAKE_OSX_SYSROOT=iphonesimulator
            SLICE_ARGS+=(-library "${BUILD_ROOT}/ios-sim/libRACommonsCore.a")
            ;;
        macos)
            build_slice macos \
                -DCMAKE_SYSTEM_NAME=Darwin \
                -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
                -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0
            SLICE_ARGS+=(-library "${BUILD_ROOT}/macos/libRACommonsCore.a")
            ;;
        *)
            echo "unknown platform: $p" >&2
            exit 2
            ;;
    esac
done

# Collect public headers once — the xcframework carries them per slice but
# our headers are arch-independent so a single copy suffices.
HEADERS_DIR="${BUILD_ROOT}/headers"
rm -rf "${HEADERS_DIR}"
mkdir -p "${HEADERS_DIR}"
cp "${ROOT}/core/abi/"*.h "${HEADERS_DIR}/"

# -----------------------------------------------------------------------------
# Combine slices into a single XCFramework.
# -----------------------------------------------------------------------------
echo "=== Creating XCFramework ========================================"
xcodebuild -create-xcframework \
    "${SLICE_ARGS[@]}" \
    -headers "${HEADERS_DIR}" \
    -output "${FRAMEWORK}"

echo
echo "✓ Wrote ${FRAMEWORK}"
ls -la "${FRAMEWORK}" 2>/dev/null | head
