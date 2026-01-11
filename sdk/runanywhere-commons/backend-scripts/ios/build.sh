#!/bin/bash

# =============================================================================
# build-ios-core.sh
# Builds a unified RunAnywhereCore XCFramework combining multiple backends
# Usage: ./build-ios-core.sh [--onnx] [--llamacpp] [--whispercpp] [--all]
#        Default: --all (includes all available backends)
# =============================================================================

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build/ios-core"
DIST_DIR="${ROOT_DIR}/dist"

# Load centralized versions
source "${SCRIPT_DIR}/../load-versions.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

print_step() {
    echo -e "${YELLOW}-> $1${NC}"
}

print_success() {
    echo -e "${GREEN}[OK] $1${NC}"
}

print_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[WARN] $1${NC}"
}

# =============================================================================
# Parse Arguments
# =============================================================================

BUILD_ONNX=false
BUILD_LLAMACPP=false
BUILD_WHISPERCPP=false
BUILD_ALL=false

# If no arguments, default to --all
if [ $# -eq 0 ]; then
    BUILD_ALL=true
fi

# Parse flags
while [[ $# -gt 0 ]]; do
    case $1 in
        --onnx)
            BUILD_ONNX=true
            shift
            ;;
        --llamacpp)
            BUILD_LLAMACPP=true
            shift
            ;;
        --whispercpp)
            BUILD_WHISPERCPP=true
            shift
            ;;
        --all)
            BUILD_ALL=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Usage: $0 [--onnx] [--llamacpp] [--whispercpp] [--all]"
            exit 1
            ;;
    esac
done

# If --all specified, enable all backends
if [ "$BUILD_ALL" = true ]; then
    BUILD_ONNX=true
    BUILD_LLAMACPP=true
    BUILD_WHISPERCPP=true
fi

# Validate at least one backend selected
if [ "$BUILD_ONNX" = false ] && [ "$BUILD_LLAMACPP" = false ] && [ "$BUILD_WHISPERCPP" = false ]; then
    print_error "No backends selected. Use --onnx, --llamacpp, --whispercpp, or --all"
    exit 1
fi

print_header "Building Unified RunAnywhereCore XCFramework"

echo "Backends to include:"
[ "$BUILD_ONNX" = true ] && echo "  - ONNX Runtime"
[ "$BUILD_LLAMACPP" = true ] && echo "  - LlamaCPP"
[ "$BUILD_WHISPERCPP" = true ] && echo "  - WhisperCPP (STT)"
echo ""

# Use version from VERSIONS file, allow env override
IOS_DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET:-$IOS_DEPLOYMENT_TARGET}"
echo "iOS Deployment Target: ${IOS_DEPLOYMENT_TARGET}"

# =============================================================================
# Prerequisites
# =============================================================================

print_step "Checking prerequisites..."

if ! command -v cmake &> /dev/null; then
    print_error "cmake not found. Install with: brew install cmake"
    exit 1
fi

if ! command -v xcodebuild &> /dev/null; then
    print_error "xcodebuild not found. Install Xcode from App Store."
    exit 1
fi

# Backend-specific checks
if [ "$BUILD_ONNX" = true ]; then
    if [ ! -d "${ROOT_DIR}/third_party/onnxruntime-ios/onnxruntime.xcframework" ]; then
        print_error "ONNX Runtime not found at third_party/onnxruntime-ios/"
        echo "Run: ./scripts/download-onnx-ios.sh"
        exit 1
    fi
    print_success "Found ONNX Runtime"
fi

if [ "$BUILD_LLAMACPP" = true ]; then
    print_success "LlamaCPP will be fetched via CMake FetchContent"
fi

if [ "$BUILD_WHISPERCPP" = true ]; then
    print_success "WhisperCPP will be fetched via CMake FetchContent"
fi

# =============================================================================
# Clean Previous Build
# =============================================================================

print_step "Cleaning previous build..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
mkdir -p "${DIST_DIR}"

# =============================================================================
# Build CMake Flags
# =============================================================================

CMAKE_BACKEND_FLAGS=""
if [ "$BUILD_ONNX" = true ]; then
    CMAKE_BACKEND_FLAGS="${CMAKE_BACKEND_FLAGS} -DRA_BUILD_ONNX=ON"
else
    CMAKE_BACKEND_FLAGS="${CMAKE_BACKEND_FLAGS} -DRA_BUILD_ONNX=OFF"
fi

if [ "$BUILD_LLAMACPP" = true ]; then
    CMAKE_BACKEND_FLAGS="${CMAKE_BACKEND_FLAGS} -DRA_BUILD_LLAMACPP=ON"
else
    CMAKE_BACKEND_FLAGS="${CMAKE_BACKEND_FLAGS} -DRA_BUILD_LLAMACPP=OFF"
fi

if [ "$BUILD_WHISPERCPP" = true ]; then
    CMAKE_BACKEND_FLAGS="${CMAKE_BACKEND_FLAGS} -DRA_BUILD_WHISPERCPP=ON"
else
    CMAKE_BACKEND_FLAGS="${CMAKE_BACKEND_FLAGS} -DRA_BUILD_WHISPERCPP=OFF"
fi

# Always disable other backends for now
CMAKE_BACKEND_FLAGS="${CMAKE_BACKEND_FLAGS} -DRA_BUILD_COREML=OFF -DRA_BUILD_TFLITE=OFF"

# =============================================================================
# Build for iOS Device (arm64)
# =============================================================================

print_header "Building for iOS Device (arm64)"

cmake -B "${BUILD_DIR}/ios-arm64" \
    -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=${IOS_DEPLOYMENT_TARGET} \
    -DCMAKE_BUILD_TYPE=Release \
    ${CMAKE_BACKEND_FLAGS} \
    -DRA_BUILD_TESTS=OFF \
    -DRA_BUILD_SHARED=OFF \
    "${ROOT_DIR}"

cmake --build "${BUILD_DIR}/ios-arm64" \
    --config Release \
    -- -quiet CODE_SIGNING_ALLOWED=NO

print_success "iOS device build complete"

# =============================================================================
# Build for iOS Simulator (arm64 + x86_64)
# =============================================================================

print_header "Building for iOS Simulator (arm64 + x86_64)"

cmake -B "${BUILD_DIR}/ios-simulator" \
    -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DCMAKE_OSX_SYSROOT=iphonesimulator \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=${IOS_DEPLOYMENT_TARGET} \
    -DCMAKE_BUILD_TYPE=Release \
    ${CMAKE_BACKEND_FLAGS} \
    -DRA_BUILD_TESTS=OFF \
    -DRA_BUILD_SHARED=OFF \
    "${ROOT_DIR}"

cmake --build "${BUILD_DIR}/ios-simulator" \
    --config Release \
    -- -quiet CODE_SIGNING_ALLOWED=NO

print_success "iOS simulator build complete"

# =============================================================================
# Locate and Combine Libraries
# =============================================================================

print_header "Combining Libraries"

# Arrays to hold all libraries for each platform
DEVICE_LIBS=()
SIM_LIBS=()

# Note: No separate bridge library - backends register directly with rac_commons

# =============================================================================
# ONNX Backend Libraries
# =============================================================================

if [ "$BUILD_ONNX" = true ]; then
    print_step "Collecting ONNX backend libraries..."

    # Check both possible paths (backends/ for monorepo, src/backends/ for original)
    DEVICE_ONNX_BACKEND="${BUILD_DIR}/ios-arm64/backends/onnx/Release-iphoneos/librunanywhere_onnx.a"
    SIM_ONNX_BACKEND="${BUILD_DIR}/ios-simulator/backends/onnx/Release-iphonesimulator/librunanywhere_onnx.a"

    # Fallback to src/backends/ if not found
    if [ ! -f "${DEVICE_ONNX_BACKEND}" ]; then
        DEVICE_ONNX_BACKEND="${BUILD_DIR}/ios-arm64/src/backends/onnx/Release-iphoneos/librunanywhere_onnx.a"
        SIM_ONNX_BACKEND="${BUILD_DIR}/ios-simulator/src/backends/onnx/Release-iphonesimulator/librunanywhere_onnx.a"
    fi

    if [ ! -f "${DEVICE_ONNX_BACKEND}" ]; then
        print_error "ONNX backend library not found. Checked:"
        echo "  - ${BUILD_DIR}/ios-arm64/backends/onnx/Release-iphoneos/librunanywhere_onnx.a"
        echo "  - ${BUILD_DIR}/ios-arm64/src/backends/onnx/Release-iphoneos/librunanywhere_onnx.a"
        exit 1
    fi

    DEVICE_LIBS+=("${DEVICE_ONNX_BACKEND}")
    SIM_LIBS+=("${SIM_ONNX_BACKEND}")

    # ONNX Runtime libraries
    ONNX_XCFRAMEWORK_DIR="${ROOT_DIR}/third_party/onnxruntime-ios/onnxruntime.xcframework"

    # Device library - check multiple possible locations
    if [ -f "${ONNX_XCFRAMEWORK_DIR}/ios-arm64/libonnxruntime.a" ]; then
        ONNX_DEVICE_LIB="${ONNX_XCFRAMEWORK_DIR}/ios-arm64/libonnxruntime.a"
    elif [ -f "${ONNX_XCFRAMEWORK_DIR}/ios-arm64/onnxruntime.a" ]; then
        ONNX_DEVICE_LIB="${ONNX_XCFRAMEWORK_DIR}/ios-arm64/onnxruntime.a"
    elif [ -f "${ONNX_XCFRAMEWORK_DIR}/ios-arm64/onnxruntime.framework/onnxruntime" ]; then
        ONNX_DEVICE_LIB="${ONNX_XCFRAMEWORK_DIR}/ios-arm64/onnxruntime.framework/onnxruntime"
    else
        print_error "Could not find ONNX Runtime device library"
        exit 1
    fi

    # Simulator library
    if [ -f "${ONNX_XCFRAMEWORK_DIR}/ios-arm64_x86_64-simulator/libonnxruntime.a" ]; then
        ONNX_SIM_LIB="${ONNX_XCFRAMEWORK_DIR}/ios-arm64_x86_64-simulator/libonnxruntime.a"
    elif [ -f "${ONNX_XCFRAMEWORK_DIR}/ios-arm64_x86_64-simulator/onnxruntime.a" ]; then
        ONNX_SIM_LIB="${ONNX_XCFRAMEWORK_DIR}/ios-arm64_x86_64-simulator/onnxruntime.a"
    elif [ -f "${ONNX_XCFRAMEWORK_DIR}/ios-arm64_x86_64-simulator/onnxruntime.framework/onnxruntime" ]; then
        ONNX_SIM_LIB="${ONNX_XCFRAMEWORK_DIR}/ios-arm64_x86_64-simulator/onnxruntime.framework/onnxruntime"
    else
        print_error "Could not find ONNX Runtime simulator library"
        exit 1
    fi

    DEVICE_LIBS+=("${ONNX_DEVICE_LIB}")
    SIM_LIBS+=("${ONNX_SIM_LIB}")

    print_success "Added ONNX Runtime libraries"

    # Sherpa-ONNX (if available)
    SHERPA_DEVICE_LIB="${ROOT_DIR}/third_party/sherpa-onnx-ios/sherpa-onnx.xcframework/ios-arm64/libsherpa-onnx.a"
    SHERPA_SIM_LIB="${ROOT_DIR}/third_party/sherpa-onnx-ios/sherpa-onnx.xcframework/ios-arm64_x86_64-simulator/libsherpa-onnx.a"

    if [ -f "${SHERPA_DEVICE_LIB}" ]; then
        DEVICE_LIBS+=("${SHERPA_DEVICE_LIB}")
        SIM_LIBS+=("${SHERPA_SIM_LIB}")
        print_success "Added Sherpa-ONNX libraries"
    else
        print_warning "Sherpa-ONNX not found - streaming STT/TTS disabled"
    fi
fi

# =============================================================================
# LlamaCPP Backend Libraries
# =============================================================================

if [ "$BUILD_LLAMACPP" = true ]; then
    print_step "Collecting LlamaCPP backend libraries..."

    # Check both possible paths (backends/ for monorepo, src/backends/ for original)
    DEVICE_LLAMACPP_BACKEND="${BUILD_DIR}/ios-arm64/backends/llamacpp/Release-iphoneos/librunanywhere_llamacpp.a"
    SIM_LLAMACPP_BACKEND="${BUILD_DIR}/ios-simulator/backends/llamacpp/Release-iphonesimulator/librunanywhere_llamacpp.a"

    # Fallback to src/backends/ if not found
    if [ ! -f "${DEVICE_LLAMACPP_BACKEND}" ]; then
        DEVICE_LLAMACPP_BACKEND="${BUILD_DIR}/ios-arm64/src/backends/llamacpp/Release-iphoneos/librunanywhere_llamacpp.a"
        SIM_LLAMACPP_BACKEND="${BUILD_DIR}/ios-simulator/src/backends/llamacpp/Release-iphonesimulator/librunanywhere_llamacpp.a"
    fi

    if [ ! -f "${DEVICE_LLAMACPP_BACKEND}" ]; then
        print_error "LlamaCPP backend library not found. Checked:"
        echo "  - ${BUILD_DIR}/ios-arm64/backends/llamacpp/Release-iphoneos/librunanywhere_llamacpp.a"
        echo "  - ${BUILD_DIR}/ios-arm64/src/backends/llamacpp/Release-iphoneos/librunanywhere_llamacpp.a"
        exit 1
    fi

    DEVICE_LIBS+=("${DEVICE_LLAMACPP_BACKEND}")
    SIM_LIBS+=("${SIM_LLAMACPP_BACKEND}")

    # llama.cpp libraries (built by FetchContent)
    LLAMA_LIBS=(
        "llama"
        "common"
        "ggml"
        "ggml-base"
        "ggml-cpu"
        "ggml-metal"
        "ggml-blas"
    )

    for lib in "${LLAMA_LIBS[@]}"; do
        DEVICE_BASE="${BUILD_DIR}/ios-arm64/_deps/llamacpp-build"
        SIM_BASE="${BUILD_DIR}/ios-simulator/_deps/llamacpp-build"

        # Different paths for different libs (llama.cpp has complex directory structure)
        if [ "$lib" = "llama" ]; then
            DEVICE_LIB="${DEVICE_BASE}/src/Release-iphoneos/lib${lib}.a"
            SIM_LIB="${SIM_BASE}/src/Release-iphonesimulator/lib${lib}.a"
        elif [ "$lib" = "common" ]; then
            DEVICE_LIB="${DEVICE_BASE}/common/Release-iphoneos/lib${lib}.a"
            SIM_LIB="${SIM_BASE}/common/Release-iphonesimulator/lib${lib}.a"
        elif [ "$lib" = "ggml-metal" ]; then
            # Metal backend is in its own subdirectory
            DEVICE_LIB="${DEVICE_BASE}/ggml/src/ggml-metal/Release-iphoneos/lib${lib}.a"
            SIM_LIB="${SIM_BASE}/ggml/src/ggml-metal/Release-iphonesimulator/lib${lib}.a"
        elif [ "$lib" = "ggml-blas" ]; then
            # BLAS backend is in its own subdirectory
            DEVICE_LIB="${DEVICE_BASE}/ggml/src/ggml-blas/Release-iphoneos/lib${lib}.a"
            SIM_LIB="${SIM_BASE}/ggml/src/ggml-blas/Release-iphonesimulator/lib${lib}.a"
        else
            # Core ggml libs (ggml, ggml-base, ggml-cpu) are in ggml/src/
            DEVICE_LIB="${DEVICE_BASE}/ggml/src/Release-iphoneos/lib${lib}.a"
            SIM_LIB="${SIM_BASE}/ggml/src/Release-iphonesimulator/lib${lib}.a"
        fi

        if [ -f "$DEVICE_LIB" ]; then
            DEVICE_LIBS+=("$DEVICE_LIB")
            SIM_LIBS+=("$SIM_LIB")
            echo "  Added: ${lib}"
        else
            echo "  Skipped (not found): ${lib} at ${DEVICE_LIB}"
        fi
    done

    print_success "Added LlamaCPP libraries"
fi

# =============================================================================
# WhisperCPP Backend Libraries
# =============================================================================

if [ "$BUILD_WHISPERCPP" = true ]; then
    print_step "Collecting WhisperCPP backend libraries..."

    # Check both possible paths (backends/ for monorepo, src/backends/ for original)
    DEVICE_WHISPERCPP_BACKEND="${BUILD_DIR}/ios-arm64/backends/whispercpp/Release-iphoneos/librunanywhere_whispercpp.a"
    SIM_WHISPERCPP_BACKEND="${BUILD_DIR}/ios-simulator/backends/whispercpp/Release-iphonesimulator/librunanywhere_whispercpp.a"

    # Fallback to src/backends/ if not found
    if [ ! -f "${DEVICE_WHISPERCPP_BACKEND}" ]; then
        DEVICE_WHISPERCPP_BACKEND="${BUILD_DIR}/ios-arm64/src/backends/whispercpp/Release-iphoneos/librunanywhere_whispercpp.a"
        SIM_WHISPERCPP_BACKEND="${BUILD_DIR}/ios-simulator/src/backends/whispercpp/Release-iphonesimulator/librunanywhere_whispercpp.a"
    fi

    if [ ! -f "${DEVICE_WHISPERCPP_BACKEND}" ]; then
        print_error "WhisperCPP backend library not found. Checked:"
        echo "  - ${BUILD_DIR}/ios-arm64/backends/whispercpp/Release-iphoneos/librunanywhere_whispercpp.a"
        echo "  - ${BUILD_DIR}/ios-arm64/src/backends/whispercpp/Release-iphoneos/librunanywhere_whispercpp.a"
        exit 1
    fi

    DEVICE_LIBS+=("${DEVICE_WHISPERCPP_BACKEND}")
    SIM_LIBS+=("${SIM_WHISPERCPP_BACKEND}")

    # whisper.cpp libraries (built by FetchContent)
    WHISPER_LIBS=(
        "whisper"
    )

    # GGML libs - only add if not already added by llamacpp
    if [ "$BUILD_LLAMACPP" = false ]; then
        WHISPER_LIBS+=(
            "ggml"
            "ggml-base"
            "ggml-cpu"
            "ggml-metal"
            "ggml-blas"
        )
    fi

    for lib in "${WHISPER_LIBS[@]}"; do
        DEVICE_BASE="${BUILD_DIR}/ios-arm64/_deps/whispercpp-build"
        SIM_BASE="${BUILD_DIR}/ios-simulator/_deps/whispercpp-build"

        if [ "$lib" = "whisper" ]; then
            DEVICE_LIB="${DEVICE_BASE}/src/Release-iphoneos/lib${lib}.a"
            SIM_LIB="${SIM_BASE}/src/Release-iphonesimulator/lib${lib}.a"
        elif [ "$lib" = "ggml-metal" ]; then
            DEVICE_LIB="${DEVICE_BASE}/ggml/src/ggml-metal/Release-iphoneos/lib${lib}.a"
            SIM_LIB="${SIM_BASE}/ggml/src/ggml-metal/Release-iphonesimulator/lib${lib}.a"
        elif [ "$lib" = "ggml-blas" ]; then
            DEVICE_LIB="${DEVICE_BASE}/ggml/src/ggml-blas/Release-iphoneos/lib${lib}.a"
            SIM_LIB="${SIM_BASE}/ggml/src/ggml-blas/Release-iphonesimulator/lib${lib}.a"
        else
            # Core ggml libs (ggml, ggml-base, ggml-cpu)
            DEVICE_LIB="${DEVICE_BASE}/ggml/src/Release-iphoneos/lib${lib}.a"
            SIM_LIB="${SIM_BASE}/ggml/src/Release-iphonesimulator/lib${lib}.a"
        fi

        if [ -f "$DEVICE_LIB" ]; then
            DEVICE_LIBS+=("$DEVICE_LIB")
            SIM_LIBS+=("$SIM_LIB")
            echo "  Added: ${lib}"
        else
            echo "  Skipped (not found): ${lib} at ${DEVICE_LIB}"
        fi
    done

    print_success "Added WhisperCPP libraries"
fi

echo "Device libs to combine: ${#DEVICE_LIBS[@]} files"
echo "Simulator libs to combine: ${#SIM_LIBS[@]} files"

# =============================================================================
# Create Combined Static Libraries
# =============================================================================

print_step "Creating unified device library..."
libtool -static -o "${BUILD_DIR}/ios-arm64/libRunAnywhereCore.a" "${DEVICE_LIBS[@]}"
print_success "Device library created: $(du -sh ${BUILD_DIR}/ios-arm64/libRunAnywhereCore.a | cut -f1)"

print_step "Creating unified simulator library..."
libtool -static -o "${BUILD_DIR}/ios-simulator/libRunAnywhereCore.a" "${SIM_LIBS[@]}"
print_success "Simulator library created: $(du -sh ${BUILD_DIR}/ios-simulator/libRunAnywhereCore.a | cut -f1)"

# =============================================================================
# Prepare Unified Headers
# =============================================================================

print_header "Preparing Unified Headers"

HEADERS_PARENT="${BUILD_DIR}/Headers"
HEADERS_DIR="${HEADERS_PARENT}/RunAnywhereCore"
mkdir -p "${HEADERS_DIR}"

# 1. Create ra_types.h (single shared copy)
print_step "Creating shared ra_types.h..."
if [ -f "${ROOT_DIR}/backends/capabilities/types.h" ]; then
    sed -e "s/RUNANYWHERE_TYPES_H/RA_CORE_TYPES_H/g" \
        "${ROOT_DIR}/backends/capabilities/types.h" > "${HEADERS_DIR}/ra_types.h"
else
    sed -e "s/RUNANYWHERE_TYPES_H/RA_CORE_TYPES_H/g" \
        "${ROOT_DIR}/src/capabilities/types.h" > "${HEADERS_DIR}/ra_types.h"
fi

# 2. Copy backend-specific public headers from include/
if [ "$BUILD_ONNX" = true ]; then
    print_step "Copying ONNX headers..."
    for header in rac_stt_onnx.h rac_tts_onnx.h rac_vad_onnx.h; do
        if [ -f "${ROOT_DIR}/include/${header}" ]; then
            cp "${ROOT_DIR}/include/${header}" "${HEADERS_DIR}/"
        fi
    done
fi

if [ "$BUILD_LLAMACPP" = true ]; then
    print_step "Copying LlamaCPP headers..."
    if [ -f "${ROOT_DIR}/include/rac_llm_llamacpp.h" ]; then
        cp "${ROOT_DIR}/include/rac_llm_llamacpp.h" "${HEADERS_DIR}/"
    fi
fi

if [ "$BUILD_WHISPERCPP" = true ]; then
    print_step "Copying WhisperCPP headers..."
    if [ -f "${ROOT_DIR}/include/rac_stt_whispercpp.h" ]; then
        cp "${ROOT_DIR}/include/rac_stt_whispercpp.h" "${HEADERS_DIR}/"
    fi
fi

# 3. Create umbrella header ra_core.h
print_step "Creating umbrella header ra_core.h..."
cat > "${HEADERS_DIR}/ra_core.h" << 'EOF'
#ifndef RA_CORE_H
#define RA_CORE_H

/**
 * RunAnywhereCore - Unified ML Inference Library
 *
 * This umbrella header includes all available backend APIs.
 * Each backend provides the same capability-based C API.
 */

// Shared types used across all backends
#include "ra_types.h"

// Backend-specific APIs (same interface, different implementations)
EOF

if [ "$BUILD_ONNX" = true ]; then
    echo '#include "rac_stt_onnx.h"' >> "${HEADERS_DIR}/ra_core.h"
    echo '#include "rac_tts_onnx.h"' >> "${HEADERS_DIR}/ra_core.h"
    echo '#include "rac_vad_onnx.h"' >> "${HEADERS_DIR}/ra_core.h"
fi

if [ "$BUILD_LLAMACPP" = true ]; then
    echo '#include "rac_llm_llamacpp.h"' >> "${HEADERS_DIR}/ra_core.h"
fi

if [ "$BUILD_WHISPERCPP" = true ]; then
    echo '#include "rac_stt_whispercpp.h"' >> "${HEADERS_DIR}/ra_core.h"
fi

cat >> "${HEADERS_DIR}/ra_core.h" << 'EOF'

#endif // RA_CORE_H
EOF

print_success "Created umbrella header"

# 4. Create module.modulemap at root
print_step "Creating module.modulemap..."
cat > "${HEADERS_PARENT}/module.modulemap" << 'EOF'
module RunAnywhereCore {
    umbrella header "RunAnywhereCore/ra_core.h"

    export *
    module * { export * }
}
EOF

print_success "Headers structure created:"
echo "  Headers/"
echo "    module.modulemap"
echo "    RunAnywhereCore/"
echo "      ra_core.h (umbrella)"
echo "      ra_types.h"
[ "$BUILD_ONNX" = true ] && echo "      rac_stt_onnx.h, rac_tts_onnx.h, rac_vad_onnx.h"
[ "$BUILD_LLAMACPP" = true ] && echo "      rac_llm_llamacpp.h"
[ "$BUILD_WHISPERCPP" = true ] && echo "      rac_stt_whispercpp.h"

# =============================================================================
# Create XCFramework
# =============================================================================

print_header "Creating XCFramework"

XCFRAMEWORK_PATH="${DIST_DIR}/RunAnywhereCore.xcframework"
rm -rf "${XCFRAMEWORK_PATH}"

xcodebuild -create-xcframework \
    -library "${BUILD_DIR}/ios-arm64/libRunAnywhereCore.a" \
    -headers "${HEADERS_PARENT}" \
    -library "${BUILD_DIR}/ios-simulator/libRunAnywhereCore.a" \
    -headers "${HEADERS_PARENT}" \
    -output "${XCFRAMEWORK_PATH}"

print_success "XCFramework created at: ${XCFRAMEWORK_PATH}"

# =============================================================================
# Verification
# =============================================================================

print_header "Verification"

if [ "$BUILD_ONNX" = true ]; then
    print_step "Checking ONNX Runtime symbols..."
    if nm -g "${BUILD_DIR}/ios-arm64/libRunAnywhereCore.a" 2>/dev/null | grep -q "T _OrtGetApiBase"; then
        print_success "ONNX Runtime symbols found"
    else
        print_warning "ONNX Runtime symbols NOT found"
    fi
fi

if [ "$BUILD_LLAMACPP" = true ]; then
    print_step "Checking LlamaCPP symbols..."
    if nm -g "${BUILD_DIR}/ios-arm64/libRunAnywhereCore.a" 2>/dev/null | grep -q "llama_\|ggml_"; then
        print_success "LlamaCPP symbols found"
    else
        print_warning "LlamaCPP symbols not found"
    fi

    print_step "Checking Metal acceleration..."
    if nm -g "${BUILD_DIR}/ios-arm64/libRunAnywhereCore.a" 2>/dev/null | grep -q "ggml_metal"; then
        print_success "Metal acceleration enabled"
    else
        print_warning "Metal acceleration not found"
    fi
fi

if [ "$BUILD_WHISPERCPP" = true ]; then
    print_step "Checking WhisperCPP symbols..."
    if nm -g "${BUILD_DIR}/ios-arm64/libRunAnywhereCore.a" 2>/dev/null | grep -q "whisper_"; then
        print_success "WhisperCPP symbols found"
    else
        print_warning "WhisperCPP symbols not found"
    fi

    # Check Metal acceleration if llamacpp not enabled (whisper provides its own GGML)
    if [ "$BUILD_LLAMACPP" = false ]; then
        print_step "Checking Metal acceleration (from WhisperCPP)..."
        if nm -g "${BUILD_DIR}/ios-arm64/libRunAnywhereCore.a" 2>/dev/null | grep -q "ggml_metal"; then
            print_success "Metal acceleration enabled"
        else
            print_warning "Metal acceleration not found"
        fi
    fi
fi

# =============================================================================
# Summary
# =============================================================================

print_header "Build Complete!"

echo "XCFramework: ${XCFRAMEWORK_PATH}"
echo ""

echo "Sizes:"
du -sh "${XCFRAMEWORK_PATH}"
echo "  Device:    $(du -sh ${BUILD_DIR}/ios-arm64/libRunAnywhereCore.a | cut -f1)"
echo "  Simulator: $(du -sh ${BUILD_DIR}/ios-simulator/libRunAnywhereCore.a | cut -f1)"
echo ""

echo "Backends included:"
[ "$BUILD_ONNX" = true ] && echo "  - ONNX Runtime (Text Gen, Embeddings, STT batch, TTS, VAD, Diarization)"
[ "$BUILD_LLAMACPP" = true ] && echo "  - LlamaCPP (Text Gen with Metal GPU acceleration)"
[ "$BUILD_WHISPERCPP" = true ] && echo "  - WhisperCPP (STT with Metal GPU acceleration)"
echo ""

echo "Header structure:"
echo "  - RunAnywhereCore/ra_core.h (umbrella - include this)"
echo "  - RunAnywhereCore/ra_types.h (shared types)"
[ "$BUILD_ONNX" = true ] && echo "  - RunAnywhereCore/ra_onnx_bridge.h (ONNX backend API)"
[ "$BUILD_LLAMACPP" = true ] && echo "  - RunAnywhereCore/ra_llamacpp_bridge.h (LlamaCPP backend API)"
[ "$BUILD_WHISPERCPP" = true ] && echo "  - RunAnywhereCore/ra_whispercpp_bridge.h (WhisperCPP backend API)"
echo ""

echo "Required frameworks to link in your iOS app:"
echo "  - Foundation.framework"
echo "  - CoreML.framework"
echo "  - Accelerate.framework"
[ "$BUILD_LLAMACPP" = true ] || [ "$BUILD_WHISPERCPP" = true ] && echo "  - Metal.framework"
[ "$BUILD_LLAMACPP" = true ] || [ "$BUILD_WHISPERCPP" = true ] && echo "  - MetalKit.framework"
echo ""

echo -e "${GREEN}Done!${NC}"
