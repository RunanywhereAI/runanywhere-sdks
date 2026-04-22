#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# build-core-android.sh — wraps the android-{arm64,armv7,x86_64} CMake presets
# and copies the resulting `librac_commons.so` + `librunanywhere_*.so`
# artifacts into the Kotlin SDK's `jniLibs/` tree so a Gradle assemble picks
# them up.
#
# GAP 07 Phase 6 — see v2_gap_specs/GAP_07_SINGLE_ROOT_CMAKE.md.
#
# Usage:
#   ./scripts/build-core-android.sh                  # build all 3 ABIs
#   ./scripts/build-core-android.sh arm64-v8a        # single ABI
#   ./scripts/build-core-android.sh --release        # forwards to ctest preset
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JNI_DEST="${REPO_ROOT}/sdk/runanywhere-kotlin/src/androidMain/jniLibs"

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

declare -A PRESET_BY_ABI=(
    ["arm64-v8a"]="android-arm64"
    ["armeabi-v7a"]="android-armv7"
    ["x86_64"]="android-x86_64"
)

mkdir -p "${JNI_DEST}"

for ABI in "${ABIS[@]}"; do
    PRESET="${PRESET_BY_ABI[$ABI]}"
    echo "▶ ${ABI} via preset '${PRESET}'"

    cmake --preset "${PRESET}"
    cmake --build --preset "${PRESET}" -- -j

    BUILD_DIR="${REPO_ROOT}/build/${PRESET}"
    DEST="${JNI_DEST}/${ABI}"
    mkdir -p "${DEST}"

    # Copy commons + every plugin .so produced (rac_add_engine_plugin emits
    # `runanywhere_<name>` in SHARED mode).
    find "${BUILD_DIR}" -maxdepth 4 -name "librac_commons.so" -exec cp -v {} "${DEST}/" \;
    find "${BUILD_DIR}" -maxdepth 4 -name "librunanywhere_*.so" -exec cp -v {} "${DEST}/" \;
done

echo ""
echo "✓ Android native libs copied to: ${JNI_DEST}/{${ABIS[*]}}"
