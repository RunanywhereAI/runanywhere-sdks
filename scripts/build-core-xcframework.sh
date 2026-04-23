#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# build-core-xcframework.sh — wraps the ios-device + ios-simulator CMake
# presets and runs `xcodebuild -create-xcframework` to produce the three
# `.xcframework` bundles the Swift SDK consumes on iOS:
#
#   sdk/runanywhere-swift/Binaries/RACommons.xcframework
#   sdk/runanywhere-swift/Binaries/RABackendLLAMACPP.xcframework
#   sdk/runanywhere-swift/Binaries/RABackendONNX.xcframework          (skipped if RAC_BACKEND_ONNX=OFF)
#
# Engine plugins under engines/{llamacpp,onnx} use SHARED_ONLY inside
# rac_add_engine_plugin(...), so on iOS (RAC_STATIC_PLUGINS=ON) they still
# produce standalone `librac_backend_<name>.a` archives alongside
# `librac_commons.a`. All three have to be re-packaged into
# `.xcframework`s containing an ios-arm64 slice AND an
# ios-arm64_x86_64-simulator slice, which is what this script does.
#
# Environment knobs:
#   RAC_BACKEND_ONNX=OFF     skip the ONNX backend (used when the operator
#                            hasn't extracted third_party/onnxruntime-ios)
#   DRY_RUN=1                only print the planned commands, don't invoke
#                            cmake/xcodebuild. Useful in CI preflight and
#                            the `release-swift-binaries.sh DRY_RUN=1` path.
#
# GAP 07 Phase 6 / v2 close-out Phase J-1.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${REPO_ROOT}/sdk/runanywhere-swift/Binaries"

if [ "$(uname -s)" != "Darwin" ]; then
    echo "error: build-core-xcframework.sh only runs on macOS" >&2
    exit 1
fi

DRY_RUN="${DRY_RUN:-0}"
RAC_BACKEND_ONNX="${RAC_BACKEND_ONNX:-ON}"
COMMONS_HEADERS="${REPO_ROOT}/sdk/runanywhere-commons/include"

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

mkdir -p "${DEST}"

# ────────────────────────────────────────────────────────────────────────────
# 1 & 2. Configure + build both iOS slices (device + simulator).
# ────────────────────────────────────────────────────────────────────────────
cmake_extra=""
if [ "${RAC_BACKEND_ONNX}" = "OFF" ]; then
    cmake_extra="-DRAC_BACKEND_ONNX=OFF"
fi

echo "▶ Configure ios-device"
if [ -n "${cmake_extra}" ]; then
    run cmake --preset ios-device "${cmake_extra}"
else
    run cmake --preset ios-device
fi
echo "▶ Build ios-device (Release)"
run cmake --build --preset ios-device --config Release

echo "▶ Configure ios-simulator"
if [ -n "${cmake_extra}" ]; then
    run cmake --preset ios-simulator "${cmake_extra}"
else
    run cmake --preset ios-simulator
fi
echo "▶ Build ios-simulator (Release)"
run cmake --build --preset ios-simulator --config Release

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

# build_xcframework <lib-subdir> <libname> <xcframework-name> [--with-headers]
#
# Only the first (RACommons) xcframework ships the commons C header tree via
# `-headers`. Backend xcframeworks share the same canonical commons headers,
# but bundling the same tree into every `.xcframework`'s `Headers/` directory
# causes `error: Multiple commands produce .../include/rac/.../*.h` when Xcode's
# SPM binary-target integration processes all three bundles in the same build
# graph. Downstream Swift modules import the commons headers via
# `RACommonsBinary` anyway, so the backend xcframeworks only need to carry
# their `.a` archives — the headers come from RACommons.xcframework.
build_xcframework() {
    local subdir="$1"
    local libname="$2"
    local xcf_name="$3"
    local mode="${4:-}"

    local paths
    paths="$(find_lib "${subdir}" "${libname}")"
    local dev_lib="${paths%|*}"
    local sim_lib="${paths#*|}"

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

build_xcframework "sdk/runanywhere-commons" "librac_commons.a"          "RACommons.xcframework"          --with-headers
build_xcframework "engines/llamacpp"        "librac_backend_llamacpp.a" "RABackendLLAMACPP.xcframework"
if [ "${RAC_BACKEND_ONNX}" = "ON" ]; then
    build_xcframework "engines/onnx"         "librac_backend_onnx.a"    "RABackendONNX.xcframework"
else
    echo "▶ Skipping RABackendONNX.xcframework (RAC_BACKEND_ONNX=OFF)"
fi

echo ""
echo "✓ XCFrameworks written to: ${DEST}"
