#!/bin/bash

# =============================================================================
# download-models.sh
# Download pre-configured models for the Linux Voice Assistant
#
# Usage: ./download-models.sh [--force]
#
# Options:
#   --force    Re-download all models even if they exist
#
# Models downloaded:
#   - Silero VAD (~2MB) - Voice Activity Detection
#   - Whisper Tiny English (~150MB) - Speech-to-Text
#   - Qwen2.5 0.5B Instruct Q4 (~400MB) - Language Model
#   - VITS Piper English US Lessac (~65MB) - Text-to-Speech
# =============================================================================

set -e

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
# Configuration
# =============================================================================

MODEL_DIR="${HOME}/.local/share/runanywhere/Models"
FORCE_DOWNLOAD=false

# Parse arguments
while [[ "$1" == --* ]]; do
    case "$1" in
        --force)
            FORCE_DOWNLOAD=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--force]"
            echo "  --force    Re-download all models even if they exist"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

print_header "Downloading Voice Assistant Models"
echo "Model directory: ${MODEL_DIR}"
echo "Force download: ${FORCE_DOWNLOAD}"

# Create base directories
mkdir -p "${MODEL_DIR}/ONNX"
mkdir -p "${MODEL_DIR}/LlamaCpp"

# =============================================================================
# 1. Silero VAD (~2MB)
# =============================================================================

VAD_DIR="${MODEL_DIR}/ONNX/silero-vad"
VAD_FILE="${VAD_DIR}/silero_vad.onnx"

print_step "Downloading Silero VAD..."

if [ -f "${VAD_FILE}" ] && [ "${FORCE_DOWNLOAD}" = false ]; then
    print_success "Silero VAD already exists, skipping"
else
    mkdir -p "${VAD_DIR}"
    curl -L -o "${VAD_FILE}" \
        "https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx"
    print_success "Silero VAD downloaded"
fi

# =============================================================================
# 2. Whisper Tiny English (~150MB via Sherpa-ONNX)
# =============================================================================

STT_DIR="${MODEL_DIR}/ONNX/whisper-tiny-en"
STT_FILE="${STT_DIR}/whisper-tiny.en-encoder.onnx"

print_step "Downloading Whisper Tiny English..."

if [ -f "${STT_FILE}" ] && [ "${FORCE_DOWNLOAD}" = false ]; then
    print_success "Whisper Tiny English already exists, skipping"
else
    mkdir -p "${STT_DIR}"
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf ${TEMP_DIR}" EXIT

    # Download Sherpa-ONNX whisper model
    curl -L -o "${TEMP_DIR}/whisper.tar.bz2" \
        "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny.en.tar.bz2"

    # Extract to temp directory
    tar -xjf "${TEMP_DIR}/whisper.tar.bz2" -C "${TEMP_DIR}"

    # Copy model files to destination
    cp -r "${TEMP_DIR}/sherpa-onnx-whisper-tiny.en/"* "${STT_DIR}/"

    print_success "Whisper Tiny English downloaded"
fi

# =============================================================================
# 3. Qwen2.5 0.5B Instruct Q4 (~400MB)
# =============================================================================

LLM_DIR="${MODEL_DIR}/LlamaCpp/qwen2.5-0.5b-instruct-q4"
LLM_FILE="${LLM_DIR}/qwen2.5-0.5b-instruct-q4_k_m.gguf"

print_step "Downloading Qwen2.5 0.5B Instruct Q4..."

if [ -f "${LLM_FILE}" ] && [ "${FORCE_DOWNLOAD}" = false ]; then
    print_success "Qwen2.5 0.5B already exists, skipping"
else
    mkdir -p "${LLM_DIR}"
    curl -L -o "${LLM_FILE}" \
        "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf"
    print_success "Qwen2.5 0.5B downloaded"
fi

# =============================================================================
# 4. VITS Piper English US Amy (~50MB)
# =============================================================================

TTS_DIR="${MODEL_DIR}/ONNX/vits-piper-en_US-lessac-medium"
TTS_FILE="${TTS_DIR}/en_US-lessac-medium.onnx"

print_step "Downloading VITS Piper English US (Lessac)..."

if [ -f "${TTS_FILE}" ] && [ "${FORCE_DOWNLOAD}" = false ]; then
    print_success "VITS Piper English already exists, skipping"
else
    mkdir -p "${TTS_DIR}"
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf ${TEMP_DIR}" EXIT

    # Download from RunanywhereAI hosted models
    curl -L -o "${TEMP_DIR}/piper.tar.gz" \
        "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz"

    # Extract to temp directory
    tar -xzf "${TEMP_DIR}/piper.tar.gz" -C "${TEMP_DIR}"

    # Copy model files to destination
    cp -r "${TEMP_DIR}/vits-piper-en_US-lessac-medium/"* "${TTS_DIR}/"

    print_success "VITS Piper English downloaded"
fi

# =============================================================================
# Summary
# =============================================================================

print_header "Download Complete!"

echo "Model locations:"
echo ""

echo "VAD (Silero):"
ls -lh "${VAD_DIR}"/*.onnx 2>/dev/null | awk '{print "  " $9 ": " $5}' || echo "  (missing)"

echo ""
echo "STT (Whisper Tiny English):"
ls -lh "${STT_DIR}"/*.onnx 2>/dev/null | head -3 | awk '{print "  " $9 ": " $5}' || echo "  (missing)"

echo ""
echo "LLM (Qwen2.5 0.5B):"
ls -lh "${LLM_DIR}"/*.gguf 2>/dev/null | awk '{print "  " $9 ": " $5}' || echo "  (missing)"

echo ""
echo "TTS (VITS Piper):"
ls -lh "${TTS_DIR}"/*.onnx 2>/dev/null | awk '{print "  " $9 ": " $5}' || echo "  (missing)"

echo ""

# Calculate total size
TOTAL_SIZE=$(du -sh "${MODEL_DIR}" 2>/dev/null | cut -f1)
echo "Total model size: ${TOTAL_SIZE}"

echo ""
print_success "All models downloaded successfully!"
echo ""
echo "To verify models, run:"
echo "  ls -la ${MODEL_DIR}/ONNX/"
echo "  ls -la ${MODEL_DIR}/LlamaCpp/"
