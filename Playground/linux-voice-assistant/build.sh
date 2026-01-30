#!/bin/bash

# =============================================================================
# build.sh - Complete build script for Linux Voice Assistant
# =============================================================================
# Run this script on your Raspberry Pi 5 (or any Linux ARM64/x86_64 system)
#
# Prerequisites:
#   sudo apt install -y build-essential cmake git curl libasound2-dev
#
# Usage:
#   ./build.sh              # Build everything
#   ./build.sh --clean      # Clean and rebuild
#   ./build.sh --models     # Download models only
#   ./build.sh --help       # Show help
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RAC_COMMONS_DIR="${ROOT_DIR}/sdk/runanywhere-commons"

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

print_info() {
    echo -e "${CYAN}[INFO] $1${NC}"
}

# =============================================================================
# Parse Arguments
# =============================================================================

CLEAN_BUILD=false
MODELS_ONLY=false

while [[ "$1" == --* ]]; do
    case "$1" in
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --models)
            MODELS_ONLY=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --clean      Clean and rebuild everything"
            echo "  --models     Download models only"
            echo "  --help       Show this help"
            echo ""
            echo "Prerequisites (install first):"
            echo "  sudo apt install -y build-essential cmake git curl libasound2-dev"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# =============================================================================
# Check Prerequisites
# =============================================================================

print_header "Linux Voice Assistant Build"

echo "System Info:"
echo "  OS: $(uname -s)"
echo "  Arch: $(uname -m)"
echo "  Host: $(hostname)"
echo ""

print_step "Checking prerequisites..."

# Check for required tools
MISSING_TOOLS=""

if ! command -v cmake &> /dev/null; then
    MISSING_TOOLS="$MISSING_TOOLS cmake"
fi

if ! command -v g++ &> /dev/null && ! command -v clang++ &> /dev/null; then
    MISSING_TOOLS="$MISSING_TOOLS g++"
fi

if ! command -v curl &> /dev/null; then
    MISSING_TOOLS="$MISSING_TOOLS curl"
fi

# Check for ALSA headers
if [ ! -f /usr/include/alsa/asoundlib.h ]; then
    MISSING_TOOLS="$MISSING_TOOLS libasound2-dev"
fi

if [ -n "$MISSING_TOOLS" ]; then
    print_error "Missing required tools:$MISSING_TOOLS"
    echo ""
    echo "Install with:"
    echo "  sudo apt update"
    echo "  sudo apt install -y build-essential cmake git curl libasound2-dev"
    exit 1
fi

print_success "All prerequisites found"

# =============================================================================
# Models Only Mode
# =============================================================================

if [ "$MODELS_ONLY" = true ]; then
    print_header "Downloading Models"
    "${SCRIPT_DIR}/scripts/download-models.sh"
    exit 0
fi

# =============================================================================
# Clean Build (if requested)
# =============================================================================

if [ "$CLEAN_BUILD" = true ]; then
    print_step "Cleaning previous builds..."
    rm -rf "${SCRIPT_DIR}/build"
    rm -rf "${RAC_COMMONS_DIR}/build-linux-"*
    rm -rf "${RAC_COMMONS_DIR}/dist/linux"
    print_success "Clean complete"
fi

# =============================================================================
# Step 1: Download Sherpa-ONNX
# =============================================================================

print_header "Step 1: Download Sherpa-ONNX"

SHERPA_DIR="${RAC_COMMONS_DIR}/third_party/sherpa-onnx-linux"
if [ -d "${SHERPA_DIR}/lib" ] && [ "$CLEAN_BUILD" = false ]; then
    print_success "Sherpa-ONNX already downloaded"
else
    "${RAC_COMMONS_DIR}/scripts/linux/download-sherpa-onnx.sh"
fi

# =============================================================================
# Step 2: Build runanywhere-commons
# =============================================================================

print_header "Step 2: Build runanywhere-commons"

ARCH=$(uname -m)
RAC_DIST="${RAC_COMMONS_DIR}/dist/linux/${ARCH}"

if [ -f "${RAC_DIST}/librac_commons.so" ] && [ "$CLEAN_BUILD" = false ]; then
    print_success "runanywhere-commons already built"
else
    "${RAC_COMMONS_DIR}/scripts/build-linux.sh" --shared
fi

# Verify libraries exist
if [ ! -f "${RAC_DIST}/librac_commons.so" ]; then
    print_error "librac_commons.so not found at ${RAC_DIST}"
    exit 1
fi
print_success "runanywhere-commons libraries ready"

# =============================================================================
# Step 3: Download Models
# =============================================================================

print_header "Step 3: Download Models"

MODEL_DIR="${HOME}/.local/share/runanywhere/Models"
if [ -d "${MODEL_DIR}/ONNX/silero-vad" ] && \
   [ -d "${MODEL_DIR}/ONNX/whisper-tiny-en" ] && \
   [ -d "${MODEL_DIR}/LlamaCpp/qwen2.5-0.5b-instruct-q4" ] && \
   [ -d "${MODEL_DIR}/ONNX/vits-piper-en-us" ] && \
   [ "$CLEAN_BUILD" = false ]; then
    print_success "Models already downloaded"
else
    "${SCRIPT_DIR}/scripts/download-models.sh"
fi

# =============================================================================
# Step 4: Build Voice Assistant
# =============================================================================

print_header "Step 4: Build Voice Assistant"

mkdir -p "${SCRIPT_DIR}/build"
cd "${SCRIPT_DIR}/build"

cmake .. \
    -DCMAKE_BUILD_TYPE=Release

cmake --build . -j$(nproc)

print_success "Voice Assistant built successfully"

# =============================================================================
# Summary
# =============================================================================

print_header "Build Complete!"

echo "Executable: ${SCRIPT_DIR}/build/voice-assistant"
echo ""
echo "To run:"
echo "  cd ${SCRIPT_DIR}"
echo "  ./build/voice-assistant"
echo ""
echo "Options:"
echo "  ./build/voice-assistant --help"
echo "  ./build/voice-assistant --list-devices"
echo ""

# Quick test
print_step "Verifying executable..."
if [ -f "${SCRIPT_DIR}/build/voice-assistant" ]; then
    print_success "Executable created: $(ls -lh ${SCRIPT_DIR}/build/voice-assistant | awk '{print $5}')"
else
    print_error "Executable not found!"
    exit 1
fi

echo ""
print_success "All done! Run ./build/voice-assistant to start."
