#!/bin/bash
# RunAnywhere Commons - Android Build Script
#
# Builds shared libraries for Android:
# - libracommons.so (core commons library)
# - librac_backend_llamacpp.so (LlamaCpp backend)
# - librac_backend_onnx.so (ONNX backend)
# - librac_backend_whispercpp.so (WhisperCpp backend)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build/android"
DIST_DIR="${PROJECT_ROOT}/dist/android"

# Load versions from VERSIONS file (single source of truth)
source "${SCRIPT_DIR}/load-versions.sh"

# Configuration
ANDROID_MIN_SDK="${ANDROID_MIN_SDK:-24}"
BUILD_TYPE="${BUILD_TYPE:-Release}"

# NDK path (try to find automatically)
if [ -z "${ANDROID_NDK_HOME}" ]; then
    if [ -d "${HOME}/Library/Android/sdk/ndk" ]; then
        # Find latest NDK version
        ANDROID_NDK_HOME=$(ls -d "${HOME}/Library/Android/sdk/ndk/"* 2>/dev/null | sort -V | tail -1)
    elif [ -d "${ANDROID_HOME}/ndk" ]; then
        ANDROID_NDK_HOME=$(ls -d "${ANDROID_HOME}/ndk/"* 2>/dev/null | sort -V | tail -1)
    fi
fi

if [ -z "${ANDROID_NDK_HOME}" ] || [ ! -d "${ANDROID_NDK_HOME}" ]; then
    echo "Error: ANDROID_NDK_HOME not set or NDK not found"
    echo "Please set ANDROID_NDK_HOME to your NDK installation path"
    exit 1
fi

# ABIs to build
ABIS="${ABIS:-arm64-v8a armeabi-v7a x86_64}"

# Backends to build
BUILD_LLAMACPP="${BUILD_LLAMACPP:-ON}"
BUILD_ONNX="${BUILD_ONNX:-ON}"
BUILD_WHISPERCPP="${BUILD_WHISPERCPP:-OFF}"
BUILD_JNI="${BUILD_JNI:-ON}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}RunAnywhere Commons - Android Build${NC}"
echo -e "${GREEN}========================================${NC}"
echo "NDK: ${ANDROID_NDK_HOME}"
echo "Min SDK: ${ANDROID_MIN_SDK}"
echo "ABIs: ${ABIS}"
echo "Build type: ${BUILD_TYPE}"
echo "LlamaCpp: ${BUILD_LLAMACPP}"
echo "ONNX: ${BUILD_ONNX}"
echo "WhisperCpp: ${BUILD_WHISPERCPP}"
echo "JNI: ${BUILD_JNI}"
echo ""

# Clean previous build
clean_build() {
    echo -e "${YELLOW}Cleaning previous build...${NC}"
    rm -rf "${BUILD_DIR}"
    rm -rf "${DIST_DIR}"
    mkdir -p "${BUILD_DIR}"
    mkdir -p "${DIST_DIR}"
}

# Build for a specific ABI
build_abi() {
    local ABI=$1
    local ABI_DIR="${BUILD_DIR}/${ABI}"

    echo -e "${GREEN}Building for ${ABI}...${NC}"
    mkdir -p "${ABI_DIR}"
    cd "${ABI_DIR}"

    cmake "${PROJECT_ROOT}" \
        -DCMAKE_TOOLCHAIN_FILE="${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI="${ABI}" \
        -DANDROID_PLATFORM="android-${ANDROID_MIN_SDK}" \
        -DANDROID_STL=c++_shared \
        -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
        -DRAC_BUILD_LLAMACPP="${BUILD_LLAMACPP}" \
        -DRAC_BUILD_ONNX="${BUILD_ONNX}" \
        -DRAC_BUILD_WHISPERCPP="${BUILD_WHISPERCPP}" \
        -DRAC_BUILD_JNI="${BUILD_JNI}" \
        -DRAC_BUILD_SHARED=ON

    cmake --build . --config "${BUILD_TYPE}" -j$(nproc 2>/dev/null || sysctl -n hw.ncpu)

    cd "${PROJECT_ROOT}"
}

# Copy and strip libraries
copy_libraries() {
    local ABI=$1
    local ABI_BUILD_DIR="${BUILD_DIR}/${ABI}"
    local ABI_DIST_DIR="${DIST_DIR}/jniLibs/${ABI}"

    echo "Copying libraries for ${ABI}..."
    mkdir -p "${ABI_DIST_DIR}"

    # Find the strip tool
    local STRIP="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/*/bin/llvm-strip"
    STRIP=$(echo ${STRIP})  # Expand glob

    if [ ! -f "${STRIP}" ]; then
        echo -e "${YELLOW}Warning: strip tool not found, libraries won't be stripped${NC}"
        STRIP=""
    fi

    # Copy commons library
    if [ -f "${ABI_BUILD_DIR}/libracommons.so" ]; then
        cp "${ABI_BUILD_DIR}/libracommons.so" "${ABI_DIST_DIR}/"
        [ -n "${STRIP}" ] && "${STRIP}" "${ABI_DIST_DIR}/libracommons.so"
    fi

    # Copy backend libraries
    for lib in rac_backend_llamacpp rac_backend_onnx rac_backend_whispercpp; do
        if [ -f "${ABI_BUILD_DIR}/backends/${lib}/lib${lib}.so" ]; then
            cp "${ABI_BUILD_DIR}/backends/${lib}/lib${lib}.so" "${ABI_DIST_DIR}/"
            [ -n "${STRIP}" ] && "${STRIP}" "${ABI_DIST_DIR}/lib${lib}.so"
        elif [ -f "${ABI_BUILD_DIR}/lib${lib}.so" ]; then
            cp "${ABI_BUILD_DIR}/lib${lib}.so" "${ABI_DIST_DIR}/"
            [ -n "${STRIP}" ] && "${STRIP}" "${ABI_DIST_DIR}/lib${lib}.so"
        fi
    done

    # Copy JNI library (runanywhere_jni.so)
    if [ -f "${ABI_BUILD_DIR}/src/jni/librunanywhere_jni.so" ]; then
        cp "${ABI_BUILD_DIR}/src/jni/librunanywhere_jni.so" "${ABI_DIST_DIR}/"
        [ -n "${STRIP}" ] && "${STRIP}" "${ABI_DIST_DIR}/librunanywhere_jni.so"
    elif [ -f "${ABI_BUILD_DIR}/librunanywhere_jni.so" ]; then
        cp "${ABI_BUILD_DIR}/librunanywhere_jni.so" "${ABI_DIST_DIR}/"
        [ -n "${STRIP}" ] && "${STRIP}" "${ABI_DIST_DIR}/librunanywhere_jni.so"
    fi

    # Copy STL library (required for c++_shared)
    local STL_DIR="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/*/sysroot/usr/lib"
    case "${ABI}" in
        arm64-v8a)
            STL_DIR="${STL_DIR}/aarch64-linux-android"
            ;;
        armeabi-v7a)
            STL_DIR="${STL_DIR}/arm-linux-androideabi"
            ;;
        x86_64)
            STL_DIR="${STL_DIR}/x86_64-linux-android"
            ;;
        x86)
            STL_DIR="${STL_DIR}/i686-linux-android"
            ;;
    esac
    STL_DIR=$(echo ${STL_DIR})  # Expand glob

    if [ -f "${STL_DIR}/libc++_shared.so" ]; then
        cp "${STL_DIR}/libc++_shared.so" "${ABI_DIST_DIR}/"
    fi
}

# Create AAR structure
create_aar_structure() {
    echo -e "${GREEN}Creating AAR structure...${NC}"

    local AAR_DIR="${DIST_DIR}/aar"
    mkdir -p "${AAR_DIR}"

    # Move jniLibs to AAR structure
    mv "${DIST_DIR}/jniLibs" "${AAR_DIR}/"

    # Create AndroidManifest.xml
    cat > "${AAR_DIR}/AndroidManifest.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="ai.runanywhere.commons">
    <uses-sdk android:minSdkVersion="${ANDROID_MIN_SDK}" />
</manifest>
EOF

    # Create proguard rules
    cat > "${AAR_DIR}/proguard.txt" << EOF
# RunAnywhere Commons ProGuard Rules
-keep class ai.runanywhere.** { *; }
-keepclasseswithmembernames class * {
    native <methods>;
}
EOF
}

# Main build process
main() {
    clean_build

    # Build for each ABI
    for ABI in ${ABIS}; do
        build_abi "${ABI}"
        copy_libraries "${ABI}"
    done

    # Create AAR structure
    create_aar_structure

    # Print sizes
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Build Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo "Output: ${DIST_DIR}"
    echo ""
    echo "Library sizes:"
    for abi_dir in "${DIST_DIR}/aar/jniLibs/"*; do
        if [ -d "$abi_dir" ]; then
            abi=$(basename "$abi_dir")
            echo "  ${abi}:"
            for lib in "$abi_dir"/*.so; do
                if [ -f "$lib" ]; then
                    size=$(ls -lh "$lib" | awk '{print $5}')
                    echo "    $(basename "$lib"): $size"
                fi
            done
        fi
    done
}

main "$@"
