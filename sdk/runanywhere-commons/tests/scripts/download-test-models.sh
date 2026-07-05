#!/bin/bash
# =============================================================================
# download-test-models.sh - Download models for integration tests
# =============================================================================
#
# Usage:
#   ./download-test-models.sh              # Download all models
#   ./download-test-models.sh --minimal    # Skip LLM and wake word (VAD+STT+TTS only)
#   ./download-test-models.sh --skip-llm   # Skip LLM download
#   ./download-test-models.sh --skip-wakeword  # Skip wake word
#   ./download-test-models.sh --force      # Re-download everything
#
# Models downloaded:
#   - Silero VAD (~2MB)
#   - Whisper Tiny EN (~150MB, via Sherpa-ONNX tar.bz2)
#   - VITS Piper TTS Lessac Medium (~65MB, tar.bz2)
#   - Qwen3 0.6B Q8 GGUF (~639MB)
#   - openWakeWord embedding + melspec + Hey Jarvis (~20MB total)
#
# Environment:
#   RAC_TEST_MODEL_DIR  Override default model directory
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() {
    echo -e "${YELLOW}-> $1${NC}"
}

print_ok() {
    echo -e "${GREEN}[OK] $1${NC}"
}

print_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

print_header() {
    echo ""
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}==========================================${NC}"
    echo ""
}

# =============================================================================
# Configuration
# =============================================================================

MODEL_DIR="${RAC_TEST_MODEL_DIR:-${HOME}/.local/share/runanywhere/Models}"
FORCE_DOWNLOAD=false
SKIP_LLM=false
SKIP_WAKEWORD=false

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --force)
            FORCE_DOWNLOAD=true
            shift
            ;;
        --minimal)
            SKIP_LLM=true
            SKIP_WAKEWORD=true
            shift
            ;;
        --skip-llm)
            SKIP_LLM=true
            shift
            ;;
        --skip-wakeword)
            SKIP_WAKEWORD=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --force           Re-download all models even if they exist"
            echo "  --minimal         Skip LLM and wake word (VAD+STT+TTS only)"
            echo "  --skip-llm        Skip LLM download"
            echo "  --skip-wakeword   Skip wake word download"
            echo "  --help            Show this help"
            echo ""
            echo "Environment:"
            echo "  RAC_TEST_MODEL_DIR   Override model directory (default: ~/.local/share/runanywhere/Models)"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

print_header "Download Test Models"

echo "Model directory: ${MODEL_DIR}"
echo "Force download:  ${FORCE_DOWNLOAD}"
echo "Skip LLM:       ${SKIP_LLM}"
echo "Skip wake word:  ${SKIP_WAKEWORD}"
echo ""

# Create base directories
mkdir -p "${MODEL_DIR}/ONNX"
mkdir -p "${MODEL_DIR}/LlamaCpp"

# Helper: verify a downloaded file is not an HTML redirect page (Git LFS issue)
verify_not_html() {
    local file="$1"
    if [ -f "$file" ]; then
        local first_bytes
        first_bytes=$(head -c 20 "$file" 2>/dev/null || true)
        if echo "$first_bytes" | grep -qi "doctype\|<html"; then
            print_error "$(basename "$file") is an HTML page (Git LFS redirect), removing"
            rm -f "$file"
            return 1
        fi
    fi
    return 0
}

# =============================================================================
# 1. Silero VAD (~2MB)
# =============================================================================

VAD_DIR="${MODEL_DIR}/ONNX/silero-vad"
VAD_FILE="${VAD_DIR}/silero_vad.onnx"

print_step "Silero VAD..."

if [ -f "${VAD_FILE}" ] && verify_not_html "${VAD_FILE}" && [ "${FORCE_DOWNLOAD}" = false ]; then
    print_ok "Silero VAD already exists, skipping"
else
    mkdir -p "${VAD_DIR}"
    rm -f "${VAD_FILE}"
    curl -L --progress-bar -o "${VAD_FILE}" \
        "https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx"

    if ! verify_not_html "${VAD_FILE}"; then
        print_error "Silero VAD download failed (HTML redirect)"
        exit 1
    fi
    print_ok "Silero VAD downloaded"
fi

# =============================================================================
# 2. Whisper Tiny EN (~150MB, tar.bz2 via Sherpa-ONNX)
# =============================================================================

STT_DIR="${MODEL_DIR}/ONNX/whisper-tiny-en"
STT_MARKER="${STT_DIR}/whisper-tiny.en-encoder.onnx"

print_step "Whisper Tiny EN..."

if [ -f "${STT_MARKER}" ] && [ "${FORCE_DOWNLOAD}" = false ]; then
    print_ok "Whisper Tiny EN already exists, skipping"
else
    mkdir -p "${STT_DIR}"
    TEMP_DIR=$(mktemp -d)

    curl -L --progress-bar -o "${TEMP_DIR}/whisper.tar.bz2" \
        "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny.en.tar.bz2"

    tar -xjf "${TEMP_DIR}/whisper.tar.bz2" -C "${TEMP_DIR}"

    # Move extracted contents into destination
    if [ -d "${TEMP_DIR}/sherpa-onnx-whisper-tiny.en" ]; then
        cp -r "${TEMP_DIR}/sherpa-onnx-whisper-tiny.en/"* "${STT_DIR}/"
    fi

    rm -rf "${TEMP_DIR}"
    print_ok "Whisper Tiny EN downloaded"
fi

# =============================================================================
# 3. VITS Piper TTS Lessac Medium (~65MB, tar.bz2)
# =============================================================================

TTS_DIR="${MODEL_DIR}/ONNX/vits-piper-en_US-lessac-medium"
TTS_MARKER="${TTS_DIR}/en_US-lessac-medium.onnx"

print_step "VITS Piper TTS (Lessac Medium)..."

if [ -f "${TTS_MARKER}" ] && [ "${FORCE_DOWNLOAD}" = false ]; then
    print_ok "VITS Piper TTS already exists, skipping"
else
    mkdir -p "${TTS_DIR}"
    TEMP_DIR=$(mktemp -d)

    curl -L --progress-bar -o "${TEMP_DIR}/piper.tar.bz2" \
        "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-lessac-medium.tar.bz2"

    tar -xjf "${TEMP_DIR}/piper.tar.bz2" -C "${TEMP_DIR}"

    # Move extracted contents into destination
    if [ -d "${TEMP_DIR}/vits-piper-en_US-lessac-medium" ]; then
        cp -r "${TEMP_DIR}/vits-piper-en_US-lessac-medium/"* "${TTS_DIR}/"
    fi

    rm -rf "${TEMP_DIR}"
    print_ok "VITS Piper TTS downloaded"
fi

# =============================================================================
# 4. Qwen3 0.6B Q8 GGUF (~639MB)
# =============================================================================

if [ "${SKIP_LLM}" = false ]; then
    LLM_DIR="${MODEL_DIR}/LlamaCpp/qwen3-0.6b"
    LLM_FILE="${LLM_DIR}/Qwen3-0.6B-Q8_0.gguf"

    print_step "Qwen3 0.6B Q8 GGUF (~639MB)..."

    if [ -f "${LLM_FILE}" ] && [ "${FORCE_DOWNLOAD}" = false ]; then
        print_ok "Qwen3 0.6B already exists, skipping"
    else
        mkdir -p "${LLM_DIR}"
        curl -L --progress-bar -o "${LLM_FILE}" \
            "https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q8_0.gguf"
        print_ok "Qwen3 0.6B downloaded"
    fi
else
    echo "  (skipping LLM)"
fi

# =============================================================================
# 5. openWakeWord (~20MB total: embedding + melspec + hey_jarvis)
# =============================================================================

if [ "${SKIP_WAKEWORD}" = false ]; then
    OWW_DIR="${MODEL_DIR}/ONNX/openwakeword"
    JARVIS_DIR="${MODEL_DIR}/ONNX/hey-jarvis"
    mkdir -p "${OWW_DIR}"
    mkdir -p "${JARVIS_DIR}"

    # 5a. Embedding model
    EMBED_FILE="${OWW_DIR}/embedding_model.onnx"
    print_step "openWakeWord embedding model..."
    if [ -f "${EMBED_FILE}" ] && verify_not_html "${EMBED_FILE}" && [ "${FORCE_DOWNLOAD}" = false ]; then
        print_ok "Embedding model already exists, skipping"
    else
        rm -f "${EMBED_FILE}"
        curl -L --progress-bar -o "${EMBED_FILE}" \
            "https://github.com/dscripka/openWakeWord/releases/download/v0.5.1/embedding_model.onnx"
        if ! verify_not_html "${EMBED_FILE}"; then
            print_error "Embedding model download failed (HTML redirect)"
            exit 1
        fi
        print_ok "Embedding model downloaded"
    fi

    # 5b. Melspectrogram model
    MELSPEC_FILE="${OWW_DIR}/melspectrogram.onnx"
    print_step "openWakeWord melspectrogram model..."
    if [ -f "${MELSPEC_FILE}" ] && verify_not_html "${MELSPEC_FILE}" && [ "${FORCE_DOWNLOAD}" = false ]; then
        print_ok "Melspectrogram model already exists, skipping"
    else
        rm -f "${MELSPEC_FILE}"
        curl -L --progress-bar -o "${MELSPEC_FILE}" \
            "https://github.com/dscripka/openWakeWord/releases/download/v0.5.1/melspectrogram.onnx"
        if ! verify_not_html "${MELSPEC_FILE}"; then
            print_error "Melspectrogram model download failed (HTML redirect)"
            exit 1
        fi
        print_ok "Melspectrogram model downloaded"
    fi

    # 5c. Hey Jarvis wake word model
    JARVIS_FILE="${JARVIS_DIR}/hey_jarvis_v0.1.onnx"
    print_step "Hey Jarvis wake word model..."
    if [ -f "${JARVIS_FILE}" ] && verify_not_html "${JARVIS_FILE}" && [ "${FORCE_DOWNLOAD}" = false ]; then
        print_ok "Hey Jarvis model already exists, skipping"
    else
        rm -f "${JARVIS_FILE}"
        curl -L --progress-bar -o "${JARVIS_FILE}" \
            "https://github.com/dscripka/openWakeWord/releases/download/v0.5.1/hey_jarvis_v0.1.onnx"
        if ! verify_not_html "${JARVIS_FILE}"; then
            print_error "Hey Jarvis model download failed (HTML redirect)"
            exit 1
        fi
        print_ok "Hey Jarvis model downloaded"
    fi
else
    echo "  (skipping wake word models)"
fi

# =============================================================================
# Summary
# =============================================================================

print_header "Download Summary"

echo "Model directory: ${MODEL_DIR}"
echo ""

# Print file sizes for each model
print_size() {
    local label="$1"
    local path="$2"
    if [ -f "$path" ]; then
        local size
        size=$(ls -lh "$path" 2>/dev/null | awk '{print $5}')
        echo -e "  ${GREEN}[OK]${NC} ${label}: ${size}"
    else
        echo -e "  ${RED}[--]${NC} ${label}: not found"
    fi
}

echo "VAD:"
print_size "silero_vad.onnx" "${MODEL_DIR}/ONNX/silero-vad/silero_vad.onnx"

echo ""
echo "STT (Whisper Tiny EN):"
print_size "encoder" "${MODEL_DIR}/ONNX/whisper-tiny-en/whisper-tiny.en-encoder.onnx"
print_size "decoder" "${MODEL_DIR}/ONNX/whisper-tiny-en/whisper-tiny.en-decoder.onnx"

echo ""
echo "TTS (Piper Lessac):"
print_size "en_US-lessac-medium.onnx" "${MODEL_DIR}/ONNX/vits-piper-en_US-lessac-medium/en_US-lessac-medium.onnx"

if [ "${SKIP_LLM}" = false ]; then
    echo ""
    echo "LLM (Qwen3 0.6B):"
    print_size "Qwen3-0.6B-Q8_0.gguf" "${MODEL_DIR}/LlamaCpp/qwen3-0.6b/Qwen3-0.6B-Q8_0.gguf"
fi

if [ "${SKIP_WAKEWORD}" = false ]; then
    echo ""
    echo "Wake Word (openWakeWord):"
    print_size "embedding_model.onnx" "${MODEL_DIR}/ONNX/openwakeword/embedding_model.onnx"
    print_size "melspectrogram.onnx"  "${MODEL_DIR}/ONNX/openwakeword/melspectrogram.onnx"
    print_size "hey_jarvis_v0.1.onnx" "${MODEL_DIR}/ONNX/hey-jarvis/hey_jarvis_v0.1.onnx"
fi

echo ""
TOTAL_SIZE=$(du -sh "${MODEL_DIR}" 2>/dev/null | cut -f1)
echo "Total model directory size: ${TOTAL_SIZE}"
echo ""
print_ok "Model download complete!"
