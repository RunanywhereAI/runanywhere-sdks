#!/bin/bash

# =============================================================================
# build-linux.sh
# Linux build script for runanywhere-commons (x86_64 and aarch64)
#
# Usage: ./build-linux.sh [options] [backends]
#        backends: onnx | llamacpp | all (default: all)
#                  - onnx: STT/TTS/VAD (Sherpa-ONNX models)
#                  - llamacpp: LLM text generation (GGUF models)
#                  - all: onnx + llamacpp (default)
#
# Options:
#   --clean     Clean build directory before building
#   --shared    Build shared libraries (default: static)
#   --help      Show this help message
#
# Examples:
#   ./build-linux.sh                    # Build all backends (static)
#   ./build-linux.sh --shared           # Build all backends (shared)
#   ./build-linux.sh llamacpp           # Build only LlamaCPP
#   ./build-linux.sh onnx               # Build only ONNX backend
#   ./build-linux.sh --clean all        # Clean build, all backends
#
# Supported architectures:
#   - x86_64 (Intel/AMD 64-bit)
#   - aarch64 (ARM 64-bit, e.g., Raspberry Pi 5)
# =============================================================================

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Detect architecture
ARCH=$(uname -m)
BUILD_DIR="${ROOT_DIR}/build-linux-${ARCH}"
DIST_DIR="${ROOT_DIR}/dist/linux/${ARCH}"

# Load centralized versions
source "${SCRIPT_DIR}/load-versions.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

print_info() {
    echo -e "${CYAN}[INFO] $1${NC}"
}

# =============================================================================
# Parse Options
# =============================================================================

CLEAN_BUILD=false
BUILD_SHARED=OFF

while [[ "$1" == --* ]]; do
    case "$1" in
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --shared)
            BUILD_SHARED=ON
            shift
            ;;
        --help|-h)
            head -35 "$0" | tail -30
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# =============================================================================
# Parse Backend Selection
# =============================================================================

BACKENDS="${1:-all}"

BUILD_ONNX=OFF
BUILD_LLAMACPP=OFF
BUILD_WHISPERCPP=OFF

case "$BACKENDS" in
    all)
        BUILD_ONNX=ON
        BUILD_LLAMACPP=ON
        ;;
    onnx)
        BUILD_ONNX=ON
        ;;
    llamacpp)
        BUILD_LLAMACPP=ON
        ;;
    onnx,llamacpp|llamacpp,onnx)
        BUILD_ONNX=ON
        BUILD_LLAMACPP=ON
        ;;
    *)
        print_error "Unknown backend(s): $BACKENDS"
        echo "Usage: $0 [options] [backends]"
        echo "  backends: onnx | llamacpp | all"
        exit 1
        ;;
esac

print_header "RunAnywhere Linux Build"
echo "Architecture: ${ARCH}"
echo "Backends: ONNX=$BUILD_ONNX, LlamaCPP=$BUILD_LLAMACPP"
echo "Build type: $([ "$BUILD_SHARED" = "ON" ] && echo "Shared" || echo "Static")"
echo "Build dir: ${BUILD_DIR}"
echo "Dist dir: ${DIST_DIR}"

# =============================================================================
# Prerequisites
# =============================================================================

print_step "Checking prerequisites..."

if ! command -v cmake &> /dev/null; then
    print_error "cmake not found. Install with: apt install cmake"
    exit 1
fi
print_success "Found cmake $(cmake --version | head -1 | cut -d' ' -f3)"

if ! command -v g++ &> /dev/null && ! command -v clang++ &> /dev/null; then
    print_error "C++ compiler not found. Install with: apt install build-essential"
    exit 1
fi
if command -v g++ &> /dev/null; then
    print_success "Found g++ $(g++ --version | head -1)"
else
    print_success "Found clang++ $(clang++ --version | head -1)"
fi

# Backend-specific checks
if [ "$BUILD_ONNX" = "ON" ]; then
    SHERPA_DIR="${ROOT_DIR}/third_party/sherpa-onnx-linux"
    if [ ! -d "${SHERPA_DIR}" ]; then
        print_step "Sherpa-ONNX not found. Downloading..."
        "${SCRIPT_DIR}/linux/download-sherpa-onnx.sh"
    fi
    print_success "Found Sherpa-ONNX (STT/TTS/VAD)"
fi

if [ "$BUILD_LLAMACPP" = "ON" ]; then
    print_success "LlamaCPP will be fetched via CMake FetchContent"
fi

# =============================================================================
# Clean Build (if requested)
# =============================================================================

if [ "$CLEAN_BUILD" = true ]; then
    print_step "Cleaning previous builds..."
    rm -rf "${BUILD_DIR}"
    rm -rf "${DIST_DIR}"
fi

mkdir -p "${BUILD_DIR}"
mkdir -p "${DIST_DIR}"

# =============================================================================
# Build
# =============================================================================

print_header "Building for ${ARCH}"

cmake -B "${BUILD_DIR}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DRAC_BUILD_BACKENDS=ON \
    -DRAC_BACKEND_ONNX=${BUILD_ONNX} \
    -DRAC_BACKEND_LLAMACPP=${BUILD_LLAMACPP} \
    -DRAC_BACKEND_WHISPERCPP=OFF \
    -DRAC_BUILD_TESTS=OFF \
    -DRAC_BUILD_SHARED=${BUILD_SHARED} \
    -DRAC_BUILD_PLATFORM=OFF \
    "${ROOT_DIR}"

cmake --build "${BUILD_DIR}" \
    --config Release \
    -j$(nproc 2>/dev/null || echo 4)

print_success "Build complete"

# =============================================================================
# Copy Libraries to Distribution Directory
# =============================================================================

print_step "Copying libraries to distribution directory..."

# Determine library extension
if [ "$BUILD_SHARED" = "ON" ]; then
    LIB_EXT="so"
else
    LIB_EXT="a"
fi

# Copy RAC Commons
if [ -f "${BUILD_DIR}/librac_commons.${LIB_EXT}" ]; then
    cp "${BUILD_DIR}/librac_commons.${LIB_EXT}" "${DIST_DIR}/"
    print_success "Copied librac_commons.${LIB_EXT}"
fi

# Copy ONNX backend
if [ "$BUILD_ONNX" = "ON" ]; then
    if [ -f "${BUILD_DIR}/src/backends/onnx/librac_backend_onnx.${LIB_EXT}" ]; then
        cp "${BUILD_DIR}/src/backends/onnx/librac_backend_onnx.${LIB_EXT}" "${DIST_DIR}/"
        print_success "Copied librac_backend_onnx.${LIB_EXT}"
    fi

    # Copy Sherpa-ONNX shared libraries for runtime
    if [ "$BUILD_SHARED" = "ON" ]; then
        SHERPA_DIR="${ROOT_DIR}/third_party/sherpa-onnx-linux"
        if [ -d "${SHERPA_DIR}/lib" ]; then
            cp "${SHERPA_DIR}/lib"/*.so* "${DIST_DIR}/" 2>/dev/null || true
            print_success "Copied Sherpa-ONNX libraries"
        fi
    fi
fi

# Copy LlamaCPP backend
if [ "$BUILD_LLAMACPP" = "ON" ]; then
    if [ -f "${BUILD_DIR}/src/backends/llamacpp/librac_backend_llamacpp.${LIB_EXT}" ]; then
        cp "${BUILD_DIR}/src/backends/llamacpp/librac_backend_llamacpp.${LIB_EXT}" "${DIST_DIR}/"
        print_success "Copied librac_backend_llamacpp.${LIB_EXT}"
    fi
fi

# Copy headers
print_step "Copying headers..."
mkdir -p "${DIST_DIR}/include"
cp -r "${ROOT_DIR}/include/rac" "${DIST_DIR}/include/"
print_success "Copied headers"

# =============================================================================
# Summary
# =============================================================================

print_header "Build Complete!"

echo "Distribution structure:"
echo ""
echo "dist/linux/${ARCH}/"
ls -la "${DIST_DIR}"

echo ""
echo "Library sizes:"
ls -lh "${DIST_DIR}"/*.${LIB_EXT} 2>/dev/null | awk '{print "  " $9 ": " $5}' || echo "  (no libraries)"

echo ""
echo -e "${GREEN}Build complete!${NC}"
echo ""
echo "To use in your application:"
echo "  Include: -I${DIST_DIR}/include"
echo "  Link: -L${DIST_DIR} -lrac_commons -lrac_backend_onnx -lrac_backend_llamacpp"
if [ "$BUILD_SHARED" = "ON" ]; then
    echo "  Runtime: export LD_LIBRARY_PATH=${DIST_DIR}:\$LD_LIBRARY_PATH"
fi
