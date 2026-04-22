#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# build-core-xcframework.sh — wraps the ios-device + ios-simulator CMake
# presets, then runs `xcodebuild -create-xcframework` to produce the
# `.xcframework` bundles the Swift SDK consumes.
#
# GAP 07 Phase 6 — see v2_gap_specs/GAP_07_SINGLE_ROOT_CMAKE.md.
#
# iOS uses RAC_STATIC_PLUGINS=ON (set by the preset), so engines link
# directly into rac_commons. The xcframework therefore contains a single
# static `RACommons.xcframework` (plus per-engine .xcframeworks if those
# build standalone for parallel iteration).
#
# Output:
#   sdk/runanywhere-swift/Binaries/RACommons.xcframework
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${REPO_ROOT}/sdk/runanywhere-swift/Binaries"

if [ "$(uname -s)" != "Darwin" ]; then
    echo "error: build-core-xcframework.sh only runs on macOS" >&2
    exit 1
fi

mkdir -p "${DEST}"

echo "▶ Configure ios-device"
cmake --preset ios-device
echo "▶ Build ios-device (Release)"
cmake --build --preset ios-device --config Release

echo "▶ Configure ios-simulator"
cmake --preset ios-simulator
echo "▶ Build ios-simulator (Release)"
cmake --build --preset ios-simulator --config Release

DEVICE_LIB="${REPO_ROOT}/build/ios-device/Release-iphoneos/librac_commons.a"
SIM_LIB="${REPO_ROOT}/build/ios-simulator/Release-iphonesimulator/librac_commons.a"

if [ ! -f "${DEVICE_LIB}" ] || [ ! -f "${SIM_LIB}" ]; then
    echo "error: expected librac_commons.a not found in build/ios-{device,simulator}/" >&2
    exit 1
fi

XCF="${DEST}/RACommons.xcframework"
echo "▶ Create-xcframework → ${XCF}"
rm -rf "${XCF}"
xcodebuild -create-xcframework \
    -library "${DEVICE_LIB}" -headers "${REPO_ROOT}/sdk/runanywhere-commons/include" \
    -library "${SIM_LIB}"    -headers "${REPO_ROOT}/sdk/runanywhere-commons/include" \
    -output  "${XCF}"

echo ""
echo "✓ XCFramework built: ${XCF}"
