#!/bin/bash

# =============================================================================
# build.sh - Build script for OpenClaw Hybrid Assistant
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

print_header "OpenClaw Hybrid Assistant Build"

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
# Step 3: Download Models (NO LLM!)
# =============================================================================

print_header "Step 3: Download Models (NO LLM)"

MODEL_DIR="${HOME}/.local/share/runanywhere/Models"

# Check required models (no LLM)
MODELS_OK=true
if [ ! -d "${MODEL_DIR}/ONNX/silero-vad" ]; then
    MODELS_OK=false
fi
if [ ! -d "${MODEL_DIR}/ONNX/whisper-tiny-en" ]; then
    MODELS_OK=false
fi
if [ ! -d "${MODEL_DIR}/ONNX/vits-piper-en_US-lessac-medium" ]; then
    MODELS_OK=false
fi

if [ "$MODELS_OK" = true ] && [ "$CLEAN_BUILD" = false ]; then
    print_success "Models already downloaded"
else
    print_info "Downloading models (NO LLM)..."

    # Create model directories
    mkdir -p "${MODEL_DIR}/ONNX/silero-vad"
    mkdir -p "${MODEL_DIR}/ONNX/whisper-tiny-en"
    mkdir -p "${MODEL_DIR}/ONNX/vits-piper-en_US-lessac-medium"

    # Download Silero VAD
    print_step "Downloading Silero VAD..."
    if [ ! -f "${MODEL_DIR}/ONNX/silero-vad/silero_vad.onnx" ]; then
        curl -L -o "${MODEL_DIR}/ONNX/silero-vad/silero_vad.onnx" \
            "https://github.com/snakers4/silero-vad/raw/master/files/silero_vad.onnx"
    fi

    # Download Whisper Tiny EN (Sherpa-ONNX format)
    print_step "Downloading Whisper Tiny EN..."
    if [ ! -f "${MODEL_DIR}/ONNX/whisper-tiny-en/tiny-encoder.int8.onnx" ]; then
        WHISPER_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny.en.tar.bz2"
        curl -L "${WHISPER_URL}" | tar -xjf - -C "${MODEL_DIR}/ONNX/"
        mv "${MODEL_DIR}/ONNX/sherpa-onnx-whisper-tiny.en"/* "${MODEL_DIR}/ONNX/whisper-tiny-en/" 2>/dev/null || true
        rm -rf "${MODEL_DIR}/ONNX/sherpa-onnx-whisper-tiny.en"
    fi

    # Download Piper TTS (Lessac medium)
    print_step "Downloading Piper TTS (Lessac)..."
    if [ ! -f "${MODEL_DIR}/ONNX/vits-piper-en_US-lessac-medium/en_US-lessac-medium.onnx" ]; then
        PIPER_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-lessac-medium.tar.bz2"
        curl -L "${PIPER_URL}" | tar -xjf - -C "${MODEL_DIR}/ONNX/"
    fi

    print_success "Models downloaded"
fi

# =============================================================================
# Step 4: Build OpenClaw Hybrid Assistant
# =============================================================================

print_header "Step 4: Build OpenClaw Hybrid Assistant"

mkdir -p "${SCRIPT_DIR}/build"
cd "${SCRIPT_DIR}/build"

cmake .. \
    -DCMAKE_BUILD_TYPE=Release

cmake --build . -j$(nproc)

print_success "OpenClaw Hybrid Assistant built successfully"

# =============================================================================
# Summary
# =============================================================================

print_header "Build Complete!"

echo "Executable: ${SCRIPT_DIR}/build/openclaw-assistant"
echo ""
echo "To run:"
echo "  cd ${SCRIPT_DIR}"
echo "  ./build/openclaw-assistant"
echo ""
echo "Options:"
echo "  ./build/openclaw-assistant --help"
echo "  ./build/openclaw-assistant --wakeword"
echo "  ./build/openclaw-assistant --openclaw-url http://your-pi:8081"
echo ""

# Quick test
print_step "Verifying executable..."
if [ -f "${SCRIPT_DIR}/build/openclaw-assistant" ]; then
    print_success "Executable created: $(ls -lh ${SCRIPT_DIR}/build/openclaw-assistant | awk '{print $5}')"
else
    print_error "Executable not found!"
    exit 1
fi

echo ""
print_info "Note: This is a NO-LLM build. It sends ASR to OpenClaw and receives TTS from OpenClaw."
print_success "All done! Run ./build/openclaw-assistant to start."
