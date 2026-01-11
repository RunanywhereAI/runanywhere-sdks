#!/bin/bash
# =============================================================================
# RunAnywhere Core - Unified Backend Build Script
# =============================================================================
#
# Builds RAC backend libraries (LlamaCPP, ONNX) for iOS and Android.
#
# Modes:
#   LOCAL  - Uses commons from ../sdk/runanywhere-commons/ (for development)
#   REMOTE - Downloads commons from GitHub release (for CI/releases)
#
# Usage:
#   ./backend-scripts/build-backends.sh [options]
#
# Options:
#   --ios              Build iOS xcframeworks only
#   --android          Build Android JNI libraries only
#   --all              Build for all platforms (default)
#   --backend NAME     Build specific backend: llamacpp, onnx, all (default: all)
#   --mode MODE        LOCAL or REMOTE (default: LOCAL)
#   --commons-version  Commons version for remote mode (default: 0.1.1)
#   --clean            Clean build directories first
#   --package          Create release packages (ZIP files)
#   --setup-sdk        Copy built binaries to SDK directories (Swift, Kotlin, etc.)
#   --abi ABI          Android: specific ABI (default: arm64-v8a,armeabi-v7a,x86_64)
#   --help             Show this help
#
# Examples:
#   # Build and setup for local testing
#   ./backend-scripts/build-backends.sh --ios --setup-sdk
#
#   # Build specific backend
#   ./backend-scripts/build-backends.sh --ios --backend llamacpp
#
#   # CI/Release (remote commons)
#   ./backend-scripts/build-backends.sh --all --mode remote --package
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# ROOT_DIR is now runanywhere-commons (contains backends, src, include)
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# BACKENDS_DIR contains the backend implementations
BACKENDS_DIR="${ROOT_DIR}/backends"
BUILD_DIR="${ROOT_DIR}/build"
DIST_DIR="${ROOT_DIR}/dist"

# Load versions
source "${SCRIPT_DIR}/load-versions.sh"

# Get version from git tag or fallback
VERSION=$(git describe --tags --always 2>/dev/null || echo "0.1.2")

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
# Defaults
# =============================================================================

BUILD_IOS=false
BUILD_ANDROID=false
BUILD_ALL=true
CLEAN_BUILD=false
CREATE_PACKAGE=false
SETUP_SDK=false
BUILD_MODE="LOCAL"
# SDK root is 3 levels up: backend-scripts -> runanywhere-commons -> sdk -> runanywhere-sdks
SDK_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# Use version from VERSIONS file if available
COMMONS_VERSION="${RAC_COMMONS_VERSION:-0.1.1}"
BACKEND="all"
ANDROID_ABIS="arm64-v8a,armeabi-v7a,x86_64"
IOS_DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET:-14.0}"
ANDROID_MIN_SDK="${ANDROID_API_LEVEL:-24}"

# =============================================================================
# Parse Arguments
# =============================================================================

show_help() {
    head -35 "$0" | tail -30
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
        --backend)
            BACKEND="$2"
            shift 2
            ;;
        --mode)
            BUILD_MODE="$(echo "$2" | tr '[:lower:]' '[:upper:]')"
            shift 2
            ;;
        --commons-version)
            COMMONS_VERSION="$2"
            shift 2
            ;;
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --package)
            CREATE_PACKAGE=true
            shift
            ;;
        --setup-sdk)
            SETUP_SDK=true
            shift
            ;;
        --abi)
            ANDROID_ABIS="$2"
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
# Resolve Commons Path
# =============================================================================

resolve_commons() {
    log_header "Resolving RAC Commons ($BUILD_MODE mode)"

    if [ "$BUILD_MODE" = "LOCAL" ]; then
        # Commons is now in the same directory as backends (runanywhere-commons)
        if [ -n "$RUNANYWHERE_COMMONS_DIR" ] && [ -d "$RUNANYWHERE_COMMONS_DIR" ]; then
            COMMONS_DIR="$RUNANYWHERE_COMMONS_DIR"
        else
            # ROOT_DIR is runanywhere-commons itself
            COMMONS_DIR="${ROOT_DIR}"
        fi
        log_info "Using LOCAL commons: ${COMMONS_DIR}"
    else
        # Remote mode - download from GitHub
        log_step "Downloading commons v${COMMONS_VERSION} from GitHub..."
        
        COMMONS_DIR="${ROOT_DIR}/third_party/runanywhere-commons"
        GITHUB_REPO="RunanywhereAI/runanywhere-sdks"
        
        if [ -d "${COMMONS_DIR}" ]; then
            CURRENT_VER=$(cat "${COMMONS_DIR}/VERSION" 2>/dev/null || echo "unknown")
            if [ "$CURRENT_VER" = "$COMMONS_VERSION" ]; then
                log_info "Commons v${COMMONS_VERSION} already downloaded"
                return
            fi
            rm -rf "${COMMONS_DIR}"
        fi
        
        mkdir -p "${ROOT_DIR}/third_party"
        cd "${ROOT_DIR}/third_party"
        
        # Download source archive
        ARCHIVE_URL="https://github.com/${GITHUB_REPO}/archive/refs/tags/commons-v${COMMONS_VERSION}.tar.gz"
        log_step "Downloading ${ARCHIVE_URL}..."
        
        curl -L -o commons.tar.gz "${ARCHIVE_URL}" || log_error "Failed to download commons"
        tar -xzf commons.tar.gz
        
        # Find and move the commons directory
        EXTRACTED=$(ls -d runanywhere-sdks-* 2>/dev/null | head -1)
        if [ -d "${EXTRACTED}/sdk/runanywhere-commons" ]; then
            mv "${EXTRACTED}/sdk/runanywhere-commons" "${COMMONS_DIR}"
        else
            log_error "Could not find runanywhere-commons in archive"
        fi
        
        rm -rf "${EXTRACTED}" commons.tar.gz
        echo "${COMMONS_VERSION}" > "${COMMONS_DIR}/VERSION"
        
        cd "${ROOT_DIR}"
        log_info "Downloaded commons v${COMMONS_VERSION}"
    fi

    # Download pre-built artifacts for remote mode
    if [ "$BUILD_MODE" = "REMOTE" ]; then
        if [ "$BUILD_IOS" = true ]; then
            download_ios_commons_xcframework
        fi
        if [ "$BUILD_ANDROID" = true ]; then
            download_android_commons_libs
        fi
    fi
}

download_android_commons_libs() {
    log_step "Downloading RACommons Android libraries..."
    
    ANDROID_DIR="${ROOT_DIR}/third_party/android-commons"
    
    if [ -d "${ANDROID_DIR}/jniLibs" ]; then
        log_info "RACommons Android libraries already exist"
        return
    fi
    
    mkdir -p "${ANDROID_DIR}"
    cd "${ANDROID_DIR}"
    
    DOWNLOAD_URL="https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/commons-v${COMMONS_VERSION}/RACommons-android-v${COMMONS_VERSION}.zip"
    
    curl -L -o RACommons-android.zip "${DOWNLOAD_URL}" || log_error "Failed to download RACommons Android package"
    unzip -q RACommons-android.zip
    rm RACommons-android.zip
    
    cd "${ROOT_DIR}"
    log_info "Downloaded RACommons Android libraries"
}

download_ios_commons_xcframework() {
    log_step "Downloading RACommons.xcframework..."
    
    XCFW_DIR="${ROOT_DIR}/third_party/xcframeworks"
    XCFW_PATH="${XCFW_DIR}/RACommons.xcframework"
    
    if [ -d "${XCFW_PATH}" ]; then
        log_info "RACommons.xcframework already exists"
        return
    fi
    
    mkdir -p "${XCFW_DIR}"
    cd "${XCFW_DIR}"
    
    DOWNLOAD_URL="https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/commons-v${COMMONS_VERSION}/RACommons-ios-v${COMMONS_VERSION}.zip"
    
    curl -L -o RACommons-ios.zip "${DOWNLOAD_URL}" || log_error "Failed to download RACommons xcframework"
    unzip -q RACommons-ios.zip
    rm RACommons-ios.zip
    
    cd "${ROOT_DIR}"
    log_info "Downloaded RACommons.xcframework"
}

# =============================================================================
# Clean
# =============================================================================

if [ "$CLEAN_BUILD" = true ]; then
    log_step "Cleaning previous builds..."
    [ "$BUILD_IOS" = true ] && rm -rf "${BUILD_DIR}/ios"
    [ "$BUILD_ANDROID" = true ] && rm -rf "${BUILD_DIR}/android"
fi

# =============================================================================
# Configuration Display
# =============================================================================

log_header "Build Configuration"
echo "Version:        ${VERSION}"
echo "Mode:           ${BUILD_MODE}"
echo "Commons:        v${COMMONS_VERSION}"
echo "Build iOS:      ${BUILD_IOS}"
echo "Build Android:  ${BUILD_ANDROID}"
echo "Backend:        ${BACKEND}"
echo "Package:        ${CREATE_PACKAGE}"
if [ "$BUILD_IOS" = true ]; then
    echo "iOS target:     ${IOS_DEPLOYMENT_TARGET}"
fi
if [ "$BUILD_ANDROID" = true ]; then
    echo "Android SDK:    ${ANDROID_MIN_SDK}"
    echo "Android ABIs:   ${ANDROID_ABIS}"
fi
echo ""

# Resolve commons
resolve_commons

mkdir -p "${DIST_DIR}"

# =============================================================================
# iOS Build
# =============================================================================

build_ios_backend() {
    local BACKEND_NAME=$1
    local BACKEND_UPPER=$(echo "$BACKEND_NAME" | tr '[:lower:]' '[:upper:]')
    
    log_header "Building iOS: ${BACKEND_NAME}"
    
    local IOS_BUILD="${BUILD_DIR}/ios/${BACKEND_NAME}"
    
    # Build for each platform slice
    build_ios_slice() {
        local PLATFORM=$1
        local SLICE_DIR="${IOS_BUILD}/${PLATFORM}"
        
        log_step "Building ${BACKEND_NAME} for ${PLATFORM}..."
        mkdir -p "${SLICE_DIR}"
        cd "${SLICE_DIR}"
        
        local CMAKE_ARGS=(
            "${BACKENDS_DIR}"
            -DCMAKE_TOOLCHAIN_FILE="${ROOT_DIR}/cmake/ios.toolchain.cmake"
            -DIOS_PLATFORM="${PLATFORM}"
            -DIOS_DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET}"
            -DCMAKE_BUILD_TYPE=Release
            -DRA_BUILD_MODULAR=ON
            -DRA_BUILD_SHARED=OFF
            -DRUNANYWHERE_COMMONS_DIR="${COMMONS_DIR}"
        )
        
        # Backend-specific options
        if [ "$BACKEND_NAME" = "llamacpp" ]; then
            CMAKE_ARGS+=(-DRA_BUILD_LLAMACPP=ON -DRA_BUILD_ONNX=OFF -DRA_BUILD_WHISPERCPP=OFF)
        elif [ "$BACKEND_NAME" = "onnx" ]; then
            CMAKE_ARGS+=(-DRA_BUILD_LLAMACPP=OFF -DRA_BUILD_ONNX=ON -DRA_BUILD_WHISPERCPP=OFF)
        fi
        
        cmake "${CMAKE_ARGS[@]}"
        cmake --build . --config Release -j$(sysctl -n hw.ncpu)
        
        cd "${ROOT_DIR}"
        log_info "Built ${PLATFORM}"
    }
    
    build_ios_slice "OS"
    build_ios_slice "SIMULATORARM64"
    build_ios_slice "SIMULATOR"
    
    # Create framework
    create_ios_framework() {
        local PLATFORM=$1
        local LIB_NAME="runanywhere_${BACKEND_NAME}"
        local FRAMEWORK_NAME="RABackend${BACKEND_UPPER}"
        local SLICE_DIR="${IOS_BUILD}/${PLATFORM}"
        local FRAMEWORK_DIR="${SLICE_DIR}/${FRAMEWORK_NAME}.framework"

        log_step "Creating ${FRAMEWORK_NAME}.framework for ${PLATFORM}..."

        mkdir -p "${FRAMEWORK_DIR}/Headers"
        mkdir -p "${FRAMEWORK_DIR}/Modules"

        # =================================================================
        # CRITICAL: Bundle ALL static libraries into single fat library
        # The wrapper library links to llama.cpp/sherpa-onnx but those
        # symbols are NOT embedded - we must combine all .a files
        # =================================================================

        log_step "  Bundling all static libraries for ${PLATFORM}..."

        # Collect all static libraries that need to be bundled
        local ALL_LIBS=()

        # Main backend library
        local LIB_PATH="${SLICE_DIR}/${BACKEND_NAME}/lib${LIB_NAME}.a"
        [ ! -f "${LIB_PATH}" ] && LIB_PATH="${SLICE_DIR}/backends/${BACKEND_NAME}/lib${LIB_NAME}.a"
        [ ! -f "${LIB_PATH}" ] && LIB_PATH="${SLICE_DIR}/lib${LIB_NAME}.a"
        [ ! -f "${LIB_PATH}" ] && log_error "Backend library not found for ${PLATFORM}"
        ALL_LIBS+=("${LIB_PATH}")

        # Capabilities library (header-only, no .a file)
        local CAPS_LIB="${SLICE_DIR}/capabilities/librunanywhere_capabilities.a"
        [ -f "${CAPS_LIB}" ] && ALL_LIBS+=("${CAPS_LIB}")

        if [ "$BACKEND_NAME" = "llamacpp" ]; then
            # llama.cpp libraries - find all .a files in the llamacpp build
            local LLAMACPP_BUILD="${SLICE_DIR}/_deps/llamacpp-build"

            # Core llama.cpp library
            [ -f "${LLAMACPP_BUILD}/src/libllama.a" ] && ALL_LIBS+=("${LLAMACPP_BUILD}/src/libllama.a")
            # Common utilities
            [ -f "${LLAMACPP_BUILD}/common/libcommon.a" ] && ALL_LIBS+=("${LLAMACPP_BUILD}/common/libcommon.a")

            # ggml libraries - collect all of them
            for ggml_lib in "${LLAMACPP_BUILD}/ggml/src/"libggml*.a; do
                [ -f "$ggml_lib" ] && ALL_LIBS+=("$ggml_lib")
            done

            # Also check for ggml libs in subdirectories (ggml-metal, ggml-cpu, etc.)
            for subdir in "${LLAMACPP_BUILD}/ggml/src/"*/; do
                [ -d "$subdir" ] && for lib in "$subdir"*.a; do
                    [ -f "$lib" ] && ALL_LIBS+=("$lib")
                done
            done

        elif [ "$BACKEND_NAME" = "onnx" ]; then
            # Sherpa-ONNX libraries
            local SHERPA_BUILD="${SLICE_DIR}/_deps/sherpa-onnx-build"
            local SHERPA_XCFW="${ROOT_DIR}/third_party/sherpa-onnx-ios/sherpa-onnx.xcframework"
            [ ! -d "${SHERPA_XCFW}" ] && SHERPA_XCFW="${BACKENDS_DIR}/../third_party/sherpa-onnx-ios/sherpa-onnx.xcframework"

            # Map platform to sherpa-onnx xcframework architecture AND target arch
            local SHERPA_ARCH=""
            local TARGET_ARCH=""
            case "$PLATFORM" in
                OS)
                    SHERPA_ARCH="ios-arm64"
                    TARGET_ARCH="arm64"
                    ;;
                SIMULATORARM64)
                    SHERPA_ARCH="ios-arm64_x86_64-simulator"
                    TARGET_ARCH="arm64"
                    ;;
                SIMULATOR)
                    SHERPA_ARCH="ios-arm64_x86_64-simulator"
                    TARGET_ARCH="x86_64"
                    ;;
            esac

            # Check for pre-built sherpa-onnx xcframework (downloaded from releases)
            if [ -n "$SHERPA_ARCH" ] && [ -d "${SHERPA_XCFW}/${SHERPA_ARCH}" ]; then
                log_step "    Looking for Sherpa-ONNX in ${SHERPA_XCFW}/${SHERPA_ARCH}/"

                # Find the static library in the xcframework slice
                local SHERPA_LIB="${SHERPA_XCFW}/${SHERPA_ARCH}/libsherpa-onnx.a"
                if [ -f "${SHERPA_LIB}" ]; then
                    # Check if this is a fat binary (contains multiple architectures)
                    local LIB_ARCHS=$(lipo -info "${SHERPA_LIB}" 2>/dev/null | sed 's/.*: //')
                    log_step "    Found sherpa-onnx: $(basename "${SHERPA_LIB}") ($(du -h "${SHERPA_LIB}" | cut -f1)) archs: ${LIB_ARCHS}"

                    # If fat binary and we need a specific arch, extract it
                    if echo "$LIB_ARCHS" | grep -q " " && [ -n "$TARGET_ARCH" ]; then
                        log_step "    Extracting ${TARGET_ARCH} from fat binary..."
                        local THIN_LIB="${SLICE_DIR}/libsherpa-onnx-${TARGET_ARCH}.a"
                        lipo -thin "${TARGET_ARCH}" -output "${THIN_LIB}" "${SHERPA_LIB}"
                        log_step "    Extracted: $(basename "${THIN_LIB}") ($(du -h "${THIN_LIB}" | cut -f1))"
                        ALL_LIBS+=("${THIN_LIB}")
                    else
                        # Single arch or no target specified, use as-is
                        ALL_LIBS+=("${SHERPA_LIB}")
                    fi
                else
                    # Try to find any .a file in the slice
                    for lib in $(find "${SHERPA_XCFW}/${SHERPA_ARCH}" -name "*.a" -type f 2>/dev/null); do
                        log_step "    Found: $(basename "$lib") ($(du -h "$lib" | cut -f1))"
                        ALL_LIBS+=("$lib")
                    done
                fi
            else
                log_warn "    Sherpa-ONNX xcframework not found at ${SHERPA_XCFW}"
            fi

            # Check for built sherpa libs (fallback if building from source)
            if [ -d "${SHERPA_BUILD}" ]; then
                for lib in $(find "${SHERPA_BUILD}" -name "*.a" -type f 2>/dev/null); do
                    ALL_LIBS+=("$lib")
                done
            fi

            # CRITICAL: Include rac_backend_onnx which contains registration functions
            # (_rac_backend_onnx_register, _rac_backend_onnx_unregister)
            local RAC_ONNX_LIB="${SLICE_DIR}/onnx/librac_backend_onnx.a"
            [ ! -f "${RAC_ONNX_LIB}" ] && RAC_ONNX_LIB="${SLICE_DIR}/backends/onnx/librac_backend_onnx.a"
            if [ -f "${RAC_ONNX_LIB}" ]; then
                log_step "    Adding RAC ONNX API library (contains registration functions)"
                ALL_LIBS+=("${RAC_ONNX_LIB}")
            else
                log_warn "    WARNING: librac_backend_onnx.a not found - registration functions will be missing!"
            fi
        fi

        # Log what we're bundling
        echo "    Libraries to bundle: ${#ALL_LIBS[@]}"
        for lib in "${ALL_LIBS[@]}"; do
            echo "      - $(basename "$lib") ($(du -h "$lib" 2>/dev/null | cut -f1))"
        done

        # Use libtool to create combined static library
        if [ ${#ALL_LIBS[@]} -gt 1 ]; then
            log_step "  Running libtool to combine ${#ALL_LIBS[@]} libraries..."
            libtool -static -o "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}" "${ALL_LIBS[@]}"
        else
            # Just copy if only one library
            cp "${ALL_LIBS[0]}" "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}"
        fi

        # Verify the combined library has expected symbols
        local SYMBOL_COUNT=$(nm -g "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}" 2>/dev/null | grep " T " | wc -l)
        echo "    Combined library has ${SYMBOL_COUNT} exported symbols"
        
        # Copy RAC headers from backend
        local RAC_HEADER="${BACKENDS_DIR}/${BACKEND_NAME}/rac_${BACKEND_NAME}.h"
        [ ! -f "${RAC_HEADER}" ] && RAC_HEADER="${ROOT_DIR}/include/backends/rac_${BACKEND_NAME}.h"
        [ -f "${RAC_HEADER}" ] && cp "${RAC_HEADER}" "${FRAMEWORK_DIR}/Headers/"
        
        # Copy commons headers
        if [ -d "${COMMONS_DIR}/include/rac" ]; then
            cp -r "${COMMONS_DIR}/include/rac/"*.h "${FRAMEWORK_DIR}/Headers/" 2>/dev/null || true
            find "${COMMONS_DIR}/include/rac" -name "*.h" -exec cp {} "${FRAMEWORK_DIR}/Headers/" \; 2>/dev/null || true
        fi
        
        # Module map
        cat > "${FRAMEWORK_DIR}/Modules/module.modulemap" << EOF
framework module ${FRAMEWORK_NAME} {
    umbrella header "${FRAMEWORK_NAME}.h"
    export *
    module * { export * }
}
EOF
        
        # Umbrella header
        cat > "${FRAMEWORK_DIR}/Headers/${FRAMEWORK_NAME}.h" << EOF
// ${FRAMEWORK_NAME} Umbrella Header
#ifndef ${FRAMEWORK_NAME}_h
#define ${FRAMEWORK_NAME}_h

#include "rac_${BACKEND_NAME}.h"

#endif
EOF
        
        # Info.plist
        cat > "${FRAMEWORK_DIR}/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>${FRAMEWORK_NAME}</string>
    <key>CFBundleIdentifier</key><string>ai.runanywhere.${FRAMEWORK_NAME}</string>
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
    local FRAMEWORK_NAME="RABackend${BACKEND_UPPER}"
    local XCFW_PATH="${DIST_DIR}/ios/${FRAMEWORK_NAME}.xcframework"
    
    log_step "Creating ${FRAMEWORK_NAME}.xcframework..."
    rm -rf "${XCFW_PATH}"
    mkdir -p "${DIST_DIR}/ios"
    
    # Create fat simulator
    local SIM_FAT="${IOS_BUILD}/SIMULATOR_FAT"
    mkdir -p "${SIM_FAT}"
    cp -R "${IOS_BUILD}/SIMULATORARM64/${FRAMEWORK_NAME}.framework" "${SIM_FAT}/"
    
    lipo -create \
        "${IOS_BUILD}/SIMULATORARM64/${FRAMEWORK_NAME}.framework/${FRAMEWORK_NAME}" \
        "${IOS_BUILD}/SIMULATOR/${FRAMEWORK_NAME}.framework/${FRAMEWORK_NAME}" \
        -output "${SIM_FAT}/${FRAMEWORK_NAME}.framework/${FRAMEWORK_NAME}"
    
    xcodebuild -create-xcframework \
        -framework "${IOS_BUILD}/OS/${FRAMEWORK_NAME}.framework" \
        -framework "${SIM_FAT}/${FRAMEWORK_NAME}.framework" \
        -output "${XCFW_PATH}"
    
    log_info "Created: ${XCFW_PATH}"
    echo "  Size: $(du -sh "${XCFW_PATH}" | cut -f1)"
}

build_ios() {
    if [ "$BACKEND" = "all" ] || [ "$BACKEND" = "llamacpp" ]; then
        build_ios_backend "llamacpp"
    fi
    
    if [ "$BACKEND" = "all" ] || [ "$BACKEND" = "onnx" ]; then
        build_ios_backend "onnx"
    fi
    
    # Copy RACommons.xcframework if available
    if [ "$BUILD_MODE" = "REMOTE" ] && [ -d "${ROOT_DIR}/third_party/xcframeworks/RACommons.xcframework" ]; then
        log_step "Copying RACommons.xcframework..."
        cp -R "${ROOT_DIR}/third_party/xcframeworks/RACommons.xcframework" "${DIST_DIR}/ios/"
        log_info "Copied RACommons.xcframework"
    elif [ "$BUILD_MODE" = "LOCAL" ]; then
        # Build RACommons from source
        log_step "Building RACommons.xcframework from local source..."
        cd "${COMMONS_DIR}"
        ./scripts/build-rac-commons.sh --ios --release
        cp -R "${COMMONS_DIR}/dist/RACommons.xcframework" "${DIST_DIR}/ios/"
        cd "${ROOT_DIR}"
        log_info "Built and copied RACommons.xcframework"
    fi
}

# =============================================================================
# Android Build
# =============================================================================

build_android_backend() {
    local BACKEND_NAME=$1
    
    log_header "Building Android: ${BACKEND_NAME}"
    
    # Use existing android build script
    IFS=',' read -ra ABI_ARRAY <<< "$ANDROID_ABIS"
    
    for ABI in "${ABI_ARRAY[@]}"; do
        log_step "Building ${BACKEND_NAME} for ${ABI}..."
        
        export RUNANYWHERE_COMMONS_DIR="${COMMONS_DIR}"
        
        "${SCRIPT_DIR}/android/build.sh" "${BACKEND_NAME}" "${ABI}"
    done
}

build_android() {
    # Validate NDK
    ANDROID_NDK="${ANDROID_NDK_HOME:-$ANDROID_NDK}"
    if [ -z "${ANDROID_NDK}" ]; then
        # Try to find NDK
        if [ -d "$HOME/Library/Android/sdk/ndk" ]; then
            ANDROID_NDK=$(ls -d "$HOME/Library/Android/sdk/ndk"/*/ 2>/dev/null | sort -V | tail -1 | sed 's:/$::')
        fi
    fi
    
    if [ -z "${ANDROID_NDK}" ] || [ ! -d "${ANDROID_NDK}" ]; then
        log_error "ANDROID_NDK_HOME not set. Please install Android NDK."
    fi
    
    export ANDROID_NDK_HOME="${ANDROID_NDK}"
    
    if [ "$BACKEND" = "all" ] || [ "$BACKEND" = "llamacpp" ]; then
        build_android_backend "llamacpp"
    fi
    
    if [ "$BACKEND" = "all" ] || [ "$BACKEND" = "onnx" ]; then
        build_android_backend "onnx"
    fi
}

# =============================================================================
# Package for Release
# =============================================================================

create_packages() {
    log_header "Creating Release Packages"
    
    local PKG_DIR="${DIST_DIR}/packages"
    mkdir -p "${PKG_DIR}"
    
    # iOS packages
    if [ "$BUILD_IOS" = true ] && [ -d "${DIST_DIR}/ios" ]; then
        log_step "Packaging iOS..."
        
        for xcfw in "${DIST_DIR}/ios/"*.xcframework; do
            if [ -d "$xcfw" ]; then
                local NAME=$(basename "$xcfw" .xcframework)
                local PKG_NAME="${NAME}-ios-${VERSION}.zip"
                cd "${DIST_DIR}/ios"
                zip -r "../packages/${PKG_NAME}" "$(basename "$xcfw")"
                cd "${PKG_DIR}"
                shasum -a 256 "${PKG_NAME}" > "${PKG_NAME}.sha256"
                cd "${ROOT_DIR}"
                log_info "Created: ${PKG_NAME}"
            fi
        done
    fi
    
    # Android packages
    if [ "$BUILD_ANDROID" = true ] && [ -d "${DIST_DIR}/android" ]; then
        log_step "Packaging Android..."
        
        # LlamaCPP package
        if [ -d "${DIST_DIR}/android/llamacpp" ]; then
            local PKG_NAME="RABackendLlamaCPP-android-${VERSION}.zip"
            cd "${DIST_DIR}/android/llamacpp"
            zip -r "../../packages/${PKG_NAME}" .
            cd "${PKG_DIR}"
            shasum -a 256 "${PKG_NAME}" > "${PKG_NAME}.sha256"
            log_info "Created: ${PKG_NAME}"
        fi
        
        # ONNX package
        if [ -d "${DIST_DIR}/android/onnx" ]; then
            local PKG_NAME="RABackendONNX-android-${VERSION}.zip"
            cd "${DIST_DIR}/android/onnx"
            zip -r "../../packages/${PKG_NAME}" .
            cd "${PKG_DIR}"
            shasum -a 256 "${PKG_NAME}" > "${PKG_NAME}.sha256"
            log_info "Created: ${PKG_NAME}"
        fi
        
        # Commons package (if built)
        if [ -d "${DIST_DIR}/android/commons" ]; then
            local PKG_NAME="RACommons-android-${VERSION}.zip"
            cd "${DIST_DIR}/android/commons"
            zip -r "../../packages/${PKG_NAME}" .
            cd "${PKG_DIR}"
            shasum -a 256 "${PKG_NAME}" > "${PKG_NAME}.sha256"
            log_info "Created: ${PKG_NAME}"
        fi
    fi
    
    cd "${ROOT_DIR}"
    log_info "Packages created in: ${PKG_DIR}"
    ls -la "${PKG_DIR}/"
}

# =============================================================================
# Download Dependencies (for --setup-sdk)
# =============================================================================

download_dependencies() {
    if [ "$BUILD_IOS" = true ]; then
        log_header "Downloading iOS Dependencies"
        
        # Download ONNX Runtime for iOS
        if [ ! -d "${ROOT_DIR}/third_party/onnxruntime-ios/onnxruntime.xcframework" ]; then
            log_step "Downloading ONNX Runtime for iOS..."
            "${SCRIPT_DIR}/ios/download-onnx.sh"
            log_info "ONNX Runtime downloaded"
        else
            log_info "ONNX Runtime already present"
        fi
        
        # Download Sherpa-ONNX for iOS (required for STT/TTS/VAD)
        if [ ! -d "${ROOT_DIR}/third_party/sherpa-onnx-ios/sherpa-onnx.xcframework" ]; then
            log_step "Downloading Sherpa-ONNX for iOS..."
            "${SCRIPT_DIR}/ios/download-sherpa-onnx.sh"
            log_info "Sherpa-ONNX downloaded"
        else
            log_info "Sherpa-ONNX already present"
        fi
    fi
}

# =============================================================================
# Setup SDK (copy binaries to SDK directories)
# =============================================================================

setup_sdk() {
    log_header "Setting up SDKs"
    
    if [ "$BUILD_IOS" = true ]; then
        log_step "Copying to Swift SDK..."
        SWIFT_BINARIES="${SDK_ROOT}/sdk/runanywhere-swift/Binaries"
        mkdir -p "${SWIFT_BINARIES}"
        
        # RACommons
        if [ -d "${DIST_DIR}/RACommons.xcframework" ]; then
            rm -rf "${SWIFT_BINARIES}/RACommons.xcframework"
            cp -R "${DIST_DIR}/RACommons.xcframework" "${SWIFT_BINARIES}/"
            log_info "Copied RACommons.xcframework"
        fi
        
        # RABackendLLAMACPP
        if [ -d "${DIST_DIR}/ios/RABackendLLAMACPP.xcframework" ]; then
            rm -rf "${SWIFT_BINARIES}/RABackendLLAMACPP.xcframework"
            cp -R "${DIST_DIR}/ios/RABackendLLAMACPP.xcframework" "${SWIFT_BINARIES}/"
            log_info "Copied RABackendLLAMACPP.xcframework"
        fi
        
        # RABackendONNX
        if [ -d "${DIST_DIR}/ios/RABackendONNX.xcframework" ]; then
            rm -rf "${SWIFT_BINARIES}/RABackendONNX.xcframework"
            cp -R "${DIST_DIR}/ios/RABackendONNX.xcframework" "${SWIFT_BINARIES}/"
            log_info "Copied RABackendONNX.xcframework"
        fi
        
        # ONNX Runtime
        ONNX_XCFW="${ROOT_DIR}/third_party/onnxruntime-ios/onnxruntime.xcframework"
        if [ -d "${ONNX_XCFW}" ]; then
            rm -rf "${SWIFT_BINARIES}/onnxruntime.xcframework"
            cp -R "${ONNX_XCFW}" "${SWIFT_BINARIES}/"
            log_info "Copied onnxruntime.xcframework"
        fi
        
        log_info "Swift SDK setup complete: ${SWIFT_BINARIES}"
    fi
    
    if [ "$BUILD_ANDROID" = true ]; then
        log_step "Copying to Kotlin SDK..."
        KOTLIN_JNI="${SDK_ROOT}/sdk/runanywhere-kotlin/src/androidMain/jniLibs"
        mkdir -p "${KOTLIN_JNI}"
        
        if [ -d "${DIST_DIR}/android/jniLibs" ]; then
            cp -r "${DIST_DIR}/android/jniLibs/"* "${KOTLIN_JNI}/"
            log_info "Copied JNI libs to Kotlin SDK"
        fi
        
        log_info "Kotlin SDK setup complete: ${KOTLIN_JNI}"
    fi
    
    # Print next steps
    echo ""
    log_info "SDKs are ready for local testing!"
    echo ""
    echo "Next steps:"
    if [ "$BUILD_IOS" = true ]; then
        echo "  Swift SDK:"
        echo "    1. Set testLocal = true in sdk/runanywhere-swift/Package.swift"
        echo "    2. Open examples/ios/RunAnywhereAI/RunAnywhereAI.xcodeproj"
        echo "    3. Build and run (⌘R)"
    fi
    if [ "$BUILD_ANDROID" = true ]; then
        echo "  Kotlin SDK:"
        echo "    1. Set testLocal = true in sdk/runanywhere-kotlin/build.gradle.kts"
        echo "    2. ./gradlew build"
    fi
}

# =============================================================================
# Build Commons (for --setup-sdk)
# =============================================================================

build_commons() {
    log_header "Building Commons"
    
    if [ "$BUILD_IOS" = true ]; then
        log_step "Building commons for iOS..."
        "${ROOT_DIR}/scripts/build-rac-commons.sh" --ios
        log_info "Commons iOS built"
    fi
    
    if [ "$BUILD_ANDROID" = true ]; then
        log_step "Building commons for Android..."
        "${ROOT_DIR}/scripts/build-rac-commons.sh" --android
        log_info "Commons Android built"
    fi
}

# =============================================================================
# Main
# =============================================================================

# For --setup-sdk: download deps and build commons first
if [ "$SETUP_SDK" = true ]; then
    download_dependencies
    build_commons
fi

[ "$BUILD_IOS" = true ] && build_ios
[ "$BUILD_ANDROID" = true ] && build_android
[ "$CREATE_PACKAGE" = true ] && create_packages
[ "$SETUP_SDK" = true ] && setup_sdk

# =============================================================================
# Summary
# =============================================================================

log_header "Build Complete!"

echo "Version:   ${VERSION}"
echo "Mode:      ${BUILD_MODE}"
echo "Output:    ${DIST_DIR}"
echo ""

if [ "$BUILD_IOS" = true ] && [ -d "${DIST_DIR}/ios" ]; then
    echo "iOS XCFrameworks:"
    for xcfw in "${DIST_DIR}/ios/"*.xcframework; do
        [ -d "$xcfw" ] && echo "  $(du -sh "$xcfw" | cut -f1)  $(basename "$xcfw")"
    done
    echo ""
fi

if [ "$BUILD_ANDROID" = true ] && [ -d "${DIST_DIR}/android" ]; then
    echo "Android Libraries:"
    find "${DIST_DIR}/android" -name "*.so" -type f 2>/dev/null | while read so; do
        echo "  $(du -h "$so" | cut -f1)  $(echo "$so" | sed "s|${DIST_DIR}/android/||")"
    done
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

