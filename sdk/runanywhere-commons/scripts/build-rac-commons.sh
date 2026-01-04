#!/bin/bash
# =============================================================================
# RunAnywhere Commons - Unified Build Script
# =============================================================================
#
# Builds RACommons for iOS (xcframework) and Android (JNI shared libraries).
#
# Outputs:
#   iOS:     dist/RACommons.xcframework
#   Android: dist/android/jniLibs/{abi}/librac_commons.so
#            dist/android/include/
#
# Usage:
#   ./scripts/build-rac-commons.sh [options]
#
# Options:
#   --ios          Build iOS xcframework only
#   --android      Build Android libraries only
#   --all          Build for all platforms (default)
#   --clean        Clean build directories first
#   --release      Release build (default)
#   --debug        Debug build
#   --package      Create release packages (ZIP files)
#   --abi ABI      Android: specific ABI (arm64-v8a, armeabi-v7a, x86_64, x86)
#   --help         Show this help
#
# Examples:
#   ./scripts/build-rac-commons.sh --ios --release
#   ./scripts/build-rac-commons.sh --android --abi arm64-v8a
#   ./scripts/build-rac-commons.sh --all --clean --package
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build"
DIST_DIR="${PROJECT_ROOT}/dist"

# Load versions
source "${SCRIPT_DIR}/load-versions.sh"

# Get version from VERSION file
VERSION=$(cat "${PROJECT_ROOT}/VERSION" 2>/dev/null | head -1 || echo "0.1.0")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_header() { echo -e "\n${BLUE}═══════════════════════════════════════════${NC}"; echo -e "${BLUE} $1${NC}"; echo -e "${BLUE}═══════════════════════════════════════════${NC}"; }
log_step()   { echo -e "${YELLOW}-> $1${NC}"; }
log_info()   { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn()   { echo -e "${YELLOW}[!]${NC} $1"; }
log_error()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# =============================================================================
# Parse Arguments
# =============================================================================

BUILD_IOS=false
BUILD_ANDROID=false
BUILD_ALL=true
CLEAN_BUILD=false
BUILD_TYPE="Release"
CREATE_PACKAGE=false
ANDROID_ABIS=("arm64-v8a" "armeabi-v7a" "x86_64")

show_help() {
    head -30 "$0" | tail -25
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --ios)
            BUILD_IOS=true
            BUILD_ALL=false
            shift
            ;;
        --android)
            BUILD_ANDROID=true
            BUILD_ALL=false
            shift
            ;;
        --all)
            BUILD_ALL=true
            shift
            ;;
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --release)
            BUILD_TYPE="Release"
            shift
            ;;
        --debug)
            BUILD_TYPE="Debug"
            shift
            ;;
        --package)
            CREATE_PACKAGE=true
            shift
            ;;
        --abi)
            ANDROID_ABIS=("$2")
            shift 2
            ;;
        --help|-h)
            show_help
            ;;
        *)
            log_error "Unknown option: $1"
            ;;
    esac
done

if [ "$BUILD_ALL" = true ]; then
    BUILD_IOS=true
    BUILD_ANDROID=true
fi

# =============================================================================
# Configuration
# =============================================================================

IOS_DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET:-14.0}"
ANDROID_MIN_SDK="${ANDROID_MIN_SDK:-24}"
ANDROID_NDK="${ANDROID_NDK_HOME:-$ANDROID_NDK}"

# Auto-detect NDK on macOS
if [ -z "${ANDROID_NDK}" ] && [ "$BUILD_ANDROID" = true ]; then
    if [ -d "$HOME/Library/Android/sdk/ndk" ]; then
        ANDROID_NDK=$(ls -d "$HOME/Library/Android/sdk/ndk"/*/ 2>/dev/null | sort -V | tail -1 | sed 's:/$::')
    fi
fi

log_header "RACommons Build v${VERSION}"
echo "Build type:     ${BUILD_TYPE}"
echo "Build iOS:      ${BUILD_IOS}"
echo "Build Android:  ${BUILD_ANDROID}"
echo "Package:        ${CREATE_PACKAGE}"
if [ "$BUILD_IOS" = true ]; then
    echo "iOS target:     ${IOS_DEPLOYMENT_TARGET}"
fi
if [ "$BUILD_ANDROID" = true ]; then
    echo "Android SDK:    ${ANDROID_MIN_SDK}"
    echo "Android ABIs:   ${ANDROID_ABIS[*]}"
    echo "NDK path:       ${ANDROID_NDK:-NOT SET}"
fi
echo ""

# =============================================================================
# Clean
# =============================================================================

if [ "$CLEAN_BUILD" = true ]; then
    log_step "Cleaning previous build..."
    [ "$BUILD_IOS" = true ] && rm -rf "${BUILD_DIR}/ios"
    [ "$BUILD_ANDROID" = true ] && rm -rf "${BUILD_DIR}/android"
    rm -rf "${DIST_DIR}"
fi

mkdir -p "${DIST_DIR}"

# =============================================================================
# iOS Build
# =============================================================================

build_ios() {
    log_header "Building RACommons for iOS"

    local IOS_BUILD_DIR="${BUILD_DIR}/ios"
    mkdir -p "${IOS_BUILD_DIR}"

    # Build for each platform
    build_ios_platform() {
        local PLATFORM=$1
        local PLATFORM_DIR="${IOS_BUILD_DIR}/${PLATFORM}"

        log_step "Building for ${PLATFORM}..."
        mkdir -p "${PLATFORM_DIR}"
        cd "${PLATFORM_DIR}"

        cmake "${PROJECT_ROOT}" \
            -DCMAKE_TOOLCHAIN_FILE="${PROJECT_ROOT}/cmake/ios.toolchain.cmake" \
            -DIOS_PLATFORM="${PLATFORM}" \
            -DIOS_DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET}" \
            -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
            -DRAC_BUILD_PLATFORM=ON \
            -DRAC_BUILD_SHARED=OFF \
            -DRAC_BUILD_JNI=OFF

        cmake --build . --config "${BUILD_TYPE}" -j$(sysctl -n hw.ncpu) --target rac_commons

        cd "${PROJECT_ROOT}"
        log_info "Built ${PLATFORM}"
    }

    build_ios_platform "OS"
    build_ios_platform "SIMULATORARM64"
    build_ios_platform "SIMULATOR"

    # Create framework structure
    create_ios_framework() {
        local PLATFORM=$1
        local PLATFORM_DIR="${IOS_BUILD_DIR}/${PLATFORM}"
        local FRAMEWORK_DIR="${PLATFORM_DIR}/RACommons.framework"

        log_step "Creating RACommons.framework for ${PLATFORM}..."

        mkdir -p "${FRAMEWORK_DIR}/Headers"
        mkdir -p "${FRAMEWORK_DIR}/Modules"

        # Copy library
        local LIB_PATH="${PLATFORM_DIR}/librac_commons.a"
        [ ! -f "${LIB_PATH}" ] && log_error "Library not found: ${LIB_PATH}"
        cp "${LIB_PATH}" "${FRAMEWORK_DIR}/RACommons"

        # Copy headers (flattened)
        cd "${PROJECT_ROOT}/include"
        find rac -name "*.h" | while read -r header; do
            local filename=$(basename "$header")
            sed -e 's|#include "rac/[^"]*\/\([^"]*\)"|#include <RACommons/\1>|g' \
                -e 's|#include "rac_|#include <RACommons/rac_|g' \
                -e 's|\.h"|.h>|g' \
                "$header" > "${FRAMEWORK_DIR}/Headers/${filename}"
        done
        cd "${PROJECT_ROOT}"

        # Module map
        cat > "${FRAMEWORK_DIR}/Modules/module.modulemap" << EOF
framework module RACommons {
    umbrella header "RACommons.h"
    export *
    module * { export * }
}
EOF

        # Umbrella header
        cat > "${FRAMEWORK_DIR}/Headers/RACommons.h" << EOF
// RACommons Umbrella Header - v${VERSION}
#ifndef RACommons_h
#define RACommons_h

EOF
        for header in "${FRAMEWORK_DIR}/Headers/"*.h; do
            [ "$(basename "$header")" != "RACommons.h" ] && \
                echo "#include \"$(basename "$header")\"" >> "${FRAMEWORK_DIR}/Headers/RACommons.h"
        done
        echo -e "\n#endif /* RACommons_h */" >> "${FRAMEWORK_DIR}/Headers/RACommons.h"

        # Info.plist
        cat > "${FRAMEWORK_DIR}/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>RACommons</string>
    <key>CFBundleIdentifier</key><string>ai.runanywhere.RACommons</string>
    <key>CFBundlePackageType</key><string>FMWK</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>MinimumOSVersion</key><string>${IOS_DEPLOYMENT_TARGET}</string>
</dict>
</plist>
EOF
    }

    create_ios_framework "OS"
    create_ios_framework "SIMULATORARM64"
    create_ios_framework "SIMULATOR"

    # Create XCFramework
    log_step "Creating RACommons.xcframework..."

    local XCFW_PATH="${DIST_DIR}/RACommons.xcframework"
    rm -rf "${XCFW_PATH}"

    # Fat simulator binary
    local SIM_FAT="${IOS_BUILD_DIR}/SIMULATOR_FAT"
    mkdir -p "${SIM_FAT}"
    cp -R "${IOS_BUILD_DIR}/SIMULATORARM64/RACommons.framework" "${SIM_FAT}/"

    lipo -create \
        "${IOS_BUILD_DIR}/SIMULATORARM64/RACommons.framework/RACommons" \
        "${IOS_BUILD_DIR}/SIMULATOR/RACommons.framework/RACommons" \
        -output "${SIM_FAT}/RACommons.framework/RACommons"

    xcodebuild -create-xcframework \
        -framework "${IOS_BUILD_DIR}/OS/RACommons.framework" \
        -framework "${SIM_FAT}/RACommons.framework" \
        -output "${XCFW_PATH}"

    log_info "Created: ${XCFW_PATH}"
    echo "  Size: $(du -sh "${XCFW_PATH}" | cut -f1)"
}

# =============================================================================
# Android Build
# =============================================================================

build_android() {
    log_header "Building RACommons for Android"

    # Validate NDK
    if [ -z "${ANDROID_NDK}" ] || [ ! -d "${ANDROID_NDK}" ]; then
        log_error "ANDROID_NDK not set or not found. Set ANDROID_NDK_HOME."
    fi

    local ANDROID_BUILD_DIR="${BUILD_DIR}/android"
    local ANDROID_DIST="${DIST_DIR}/android"
    mkdir -p "${ANDROID_BUILD_DIR}"
    mkdir -p "${ANDROID_DIST}"

    # Build for each ABI
    for ABI in "${ANDROID_ABIS[@]}"; do
        log_step "Building for ${ABI}..."

        local ABI_BUILD="${ANDROID_BUILD_DIR}/${ABI}"
        mkdir -p "${ABI_BUILD}"
        cd "${ABI_BUILD}"

        cmake "${PROJECT_ROOT}" \
            -DCMAKE_TOOLCHAIN_FILE="${ANDROID_NDK}/build/cmake/android.toolchain.cmake" \
            -DANDROID_ABI="${ABI}" \
            -DANDROID_PLATFORM="android-${ANDROID_MIN_SDK}" \
            -DANDROID_STL="c++_shared" \
            -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
            -DRAC_BUILD_PLATFORM=OFF \
            -DRAC_BUILD_SHARED=ON \
            -DRAC_BUILD_JNI=ON \
            -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-z,max-page-size=16384"

        cmake --build . --config "${BUILD_TYPE}" -j$(nproc 2>/dev/null || sysctl -n hw.ncpu)

        # Copy outputs
        local ABI_DIST="${ANDROID_DIST}/jniLibs/${ABI}"
        mkdir -p "${ABI_DIST}"

        # Copy shared libraries
        [ -f "${ABI_BUILD}/librac_commons.so" ] && cp "${ABI_BUILD}/librac_commons.so" "${ABI_DIST}/"

        # Copy JNI library if built
        # CMakeLists.txt sets OUTPUT_NAME="runanywhere_jni" producing librunanywhere_jni.so
        if [ -f "${ABI_BUILD}/src/jni/librunanywhere_jni.so" ]; then
            cp "${ABI_BUILD}/src/jni/librunanywhere_jni.so" "${ABI_DIST}/"
            log_info "Copied librunanywhere_jni.so"
        elif [ -f "${ABI_BUILD}/librunanywhere_jni.so" ]; then
            cp "${ABI_BUILD}/librunanywhere_jni.so" "${ABI_DIST}/"
            log_info "Copied librunanywhere_jni.so"
        else
            log_warning "JNI library not found - was RAC_BUILD_JNI=ON set?"
        fi

        # Copy STL
        local STL_PATH=""
        case "${ABI}" in
            arm64-v8a) STL_PATH="aarch64-linux-android" ;;
            armeabi-v7a) STL_PATH="arm-linux-androideabi" ;;
            x86_64) STL_PATH="x86_64-linux-android" ;;
            x86) STL_PATH="i686-linux-android" ;;
        esac

        local STL_LIB="${ANDROID_NDK}/toolchains/llvm/prebuilt/*/sysroot/usr/lib/${STL_PATH}/libc++_shared.so"
        for stl in $STL_LIB; do
            [ -f "$stl" ] && cp "$stl" "${ABI_DIST}/" && break
        done

        cd "${PROJECT_ROOT}"
        log_info "Built ${ABI}"

        # Show library sizes
        for lib in "${ABI_DIST}"/*.so; do
            [ -f "$lib" ] && echo "    $(basename "$lib"): $(du -h "$lib" | cut -f1)"
        done
    done

    # Copy headers
    log_step "Copying headers..."
    local HEADERS_DIST="${ANDROID_DIST}/include"
    mkdir -p "${HEADERS_DIST}"
    cp -r "${PROJECT_ROOT}/include/rac" "${HEADERS_DIST}/"

    log_info "Android build complete: ${ANDROID_DIST}"
}

# =============================================================================
# Package for Release
# =============================================================================

create_packages() {
    log_header "Creating Release Packages"

    local PACKAGE_DIR="${DIST_DIR}/packages"
    mkdir -p "${PACKAGE_DIR}"

    # iOS package
    if [ -d "${DIST_DIR}/RACommons.xcframework" ]; then
        log_step "Packaging iOS..."
        local IOS_PKG="RACommons-ios-v${VERSION}.zip"
        cd "${DIST_DIR}"
        zip -r "packages/${IOS_PKG}" "RACommons.xcframework"
        cd "${PACKAGE_DIR}"
        shasum -a 256 "${IOS_PKG}" > "${IOS_PKG}.sha256"
        cd "${PROJECT_ROOT}"
        log_info "Created: ${IOS_PKG}"
    fi

    # Android package
    if [ -d "${DIST_DIR}/android/jniLibs" ]; then
        log_step "Packaging Android..."
        local ANDROID_PKG="RACommons-android-v${VERSION}.zip"
        cd "${DIST_DIR}/android"
        zip -r "../packages/${ANDROID_PKG}" jniLibs include
        cd "${PACKAGE_DIR}"
        shasum -a 256 "${ANDROID_PKG}" > "${ANDROID_PKG}.sha256"
        cd "${PROJECT_ROOT}"
        log_info "Created: ${ANDROID_PKG}"
    fi

    log_info "Packages created in: ${PACKAGE_DIR}"
    ls -la "${PACKAGE_DIR}/"
}

# =============================================================================
# Main
# =============================================================================

[ "$BUILD_IOS" = true ] && build_ios
[ "$BUILD_ANDROID" = true ] && build_android
[ "$CREATE_PACKAGE" = true ] && create_packages

# =============================================================================
# Summary
# =============================================================================

log_header "Build Complete!"

echo "Version: ${VERSION}"
echo "Output:  ${DIST_DIR}"
echo ""

if [ "$BUILD_IOS" = true ]; then
    echo "iOS:"
    [ -d "${DIST_DIR}/RACommons.xcframework" ] && \
        echo "  $(du -sh "${DIST_DIR}/RACommons.xcframework" | cut -f1)  RACommons.xcframework"
    echo ""
fi

if [ "$BUILD_ANDROID" = true ]; then
    echo "Android:"
    if [ -d "${DIST_DIR}/android/jniLibs" ]; then
        for abi_dir in "${DIST_DIR}/android/jniLibs/"*/; do
            [ -d "$abi_dir" ] && echo "  $(basename "$abi_dir"): $(ls "$abi_dir"/*.so 2>/dev/null | wc -l | tr -d ' ') libraries"
        done
    fi
    echo ""
fi

if [ "$CREATE_PACKAGE" = true ] && [ -d "${DIST_DIR}/packages" ]; then
    echo "Packages:"
    ls -1 "${DIST_DIR}/packages/"*.zip 2>/dev/null | while read pkg; do
        echo "  $(du -h "$pkg" | cut -f1)  $(basename "$pkg")"
    done
fi

echo ""
log_info "Done!"
