#!/bin/bash

# =============================================================================
# download-models.sh
# Download pre-configured models for the Linux Voice Assistant
#
# Usage: ./download-models.sh [options]
#
# Options:
#   --force        Re-download all models even if they exist
#   --wakeword     Also download wake word detection models
#   --llm <model>  Specify which LLM to download (default: qwen3-1.7b)
#   --all-llms     Download all available LLM models
#   --list-llms    List available LLM models
#
# Voice Pipeline Models (always downloaded):
#   - Silero VAD (~2MB) - Voice Activity Detection
#   - Whisper Tiny English (~150MB) - Speech-to-Text
#   - VITS Piper English US Lessac (~65MB) - Text-to-Speech
#
# LLM Models (choose one or more):
#   - qwen3-0.6b     (~639MB)  - Smallest, fastest, basic quality
#   - lfm-1.2b       (~1.25GB) - Liquid AI, efficient architecture
#   - qwen3-1.7b     (~1.83GB) - Good balance (DEFAULT)
#   - llama-3.2-3b   (~2.0GB)  - Meta's efficient model
#   - qwen3-4b       (~2.5GB)  - Best quality, needs 8GB Pi
#
# Optional Wake Word Models:
#   - openWakeWord Embedding (~15MB) - Feature extraction
#   - Hey Jarvis Model (~5MB) - Wake word detection
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
# LLM Model Definitions
# =============================================================================

declare -A LLM_MODELS
declare -A LLM_URLS
declare -A LLM_SIZES
declare -A LLM_DESCRIPTIONS

# Qwen3 0.6B Q8 (Alibaba) - Smallest
LLM_MODELS["qwen3-0.6b"]="Qwen3-0.6B-Q8_0.gguf"
LLM_URLS["qwen3-0.6b"]="https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q8_0.gguf"
LLM_SIZES["qwen3-0.6b"]="~639MB"
LLM_DESCRIPTIONS["qwen3-0.6b"]="Smallest, fastest, 32K context"

# Liquid AI LFM 1.2B Q8 - Efficient architecture
LLM_MODELS["lfm-1.2b"]="LFM2.5-1.2B-Instruct-Q8_0.gguf"
LLM_URLS["lfm-1.2b"]="https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/main/LFM2.5-1.2B-Instruct-Q8_0.gguf"
LLM_SIZES["lfm-1.2b"]="~1.25GB"
LLM_DESCRIPTIONS["lfm-1.2b"]="Liquid AI, efficient new architecture"

# Qwen3 1.7B Q8 (Alibaba) - Good balance
LLM_MODELS["qwen3-1.7b"]="Qwen3-1.7B-Q8_0.gguf"
LLM_URLS["qwen3-1.7b"]="https://huggingface.co/Qwen/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q8_0.gguf"
LLM_SIZES["qwen3-1.7b"]="~1.83GB"
LLM_DESCRIPTIONS["qwen3-1.7b"]="Good balance, 32K context (RECOMMENDED)"

# Llama 3.2 3B Q4 (Meta) - Efficient
LLM_MODELS["llama-3.2-3b"]="Llama-3.2-3B-Instruct-Q4_K_M.gguf"
LLM_URLS["llama-3.2-3b"]="https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf"
LLM_SIZES["llama-3.2-3b"]="~2.0GB"
LLM_DESCRIPTIONS["llama-3.2-3b"]="Meta's efficient 3B model"

# Qwen3 4B Q4 (Alibaba) - Best quality
LLM_MODELS["qwen3-4b"]="Qwen3-4B-Q4_K_M.gguf"
LLM_URLS["qwen3-4b"]="https://huggingface.co/Qwen/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf"
LLM_SIZES["qwen3-4b"]="~2.5GB"
LLM_DESCRIPTIONS["qwen3-4b"]="Best quality, 32K context, needs 8GB Pi"

# Default LLM - Qwen3 1.7B is the best balance for Pi 5
DEFAULT_LLM="qwen3-1.7b"

# Model order (recommended first)
MODEL_ORDER="qwen3-0.6b lfm-1.2b qwen3-1.7b llama-3.2-3b qwen3-4b"

# =============================================================================
# Configuration
# =============================================================================

MODEL_DIR="${HOME}/.local/share/runanywhere/Models"
FORCE_DOWNLOAD=false
DOWNLOAD_WAKEWORD=false
SELECTED_LLM="${DEFAULT_LLM}"
DOWNLOAD_ALL_LLMS=false

# Function to list available LLMs
list_llms() {
    echo ""
    echo "Available LLM Models for Raspberry Pi:"
    echo "======================================="
    echo ""
    printf "%-14s %-10s %s\n" "MODEL ID" "SIZE" "DESCRIPTION"
    printf "%-14s %-10s %s\n" "--------" "----" "-----------"
    for model in $MODEL_ORDER; do
        local marker=""
        if [ "$model" = "$DEFAULT_LLM" ]; then
            marker=" ★"
        fi
        printf "%-14s %-10s %s%s\n" "$model" "${LLM_SIZES[$model]}" "${LLM_DESCRIPTIONS[$model]}" "$marker"
    done
    echo ""
    echo "★ = Default/Recommended"
    echo ""
    echo "Usage examples:"
    echo "  ./download-models.sh                    # Download default (${DEFAULT_LLM})"
    echo "  ./download-models.sh --llm qwen3-4b     # Download specific model"
    echo "  ./download-models.sh --all-llms         # Download all models"
    echo ""
}

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --force)
            FORCE_DOWNLOAD=true
            shift
            ;;
        --wakeword)
            DOWNLOAD_WAKEWORD=true
            shift
            ;;
        --llm)
            if [ -z "$2" ] || [[ "$2" == --* ]]; then
                print_error "Missing model name after --llm"
                list_llms
                exit 1
            fi
            SELECTED_LLM="$2"
            if [ -z "${LLM_MODELS[$SELECTED_LLM]}" ]; then
                print_error "Unknown LLM model: $SELECTED_LLM"
                list_llms
                exit 1
            fi
            shift 2
            ;;
        --all-llms)
            DOWNLOAD_ALL_LLMS=true
            shift
            ;;
        --list-llms)
            list_llms
            exit 0
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --force        Re-download all models even if they exist"
            echo "  --wakeword     Also download wake word detection models"
            echo "  --llm <model>  Specify which LLM to download (default: ${DEFAULT_LLM})"
            echo "  --all-llms     Download all available LLM models"
            echo "  --list-llms    List available LLM models"
            echo "  --help         Show this help message"
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
echo "Wake word models: ${DOWNLOAD_WAKEWORD}"
if [ "${DOWNLOAD_ALL_LLMS}" = true ]; then
    echo "LLM models: ALL"
else
    echo "LLM model: ${SELECTED_LLM}"
fi

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
    curl -L --progress-bar -o "${VAD_FILE}" \
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
    curl -L --progress-bar -o "${TEMP_DIR}/whisper.tar.bz2" \
        "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny.en.tar.bz2"

    # Extract to temp directory
    tar -xjf "${TEMP_DIR}/whisper.tar.bz2" -C "${TEMP_DIR}"

    # Copy model files to destination
    cp -r "${TEMP_DIR}/sherpa-onnx-whisper-tiny.en/"* "${STT_DIR}/"

    print_success "Whisper Tiny English downloaded"
fi

# =============================================================================
# 3. VITS Piper English US Lessac (~65MB)
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
    curl -L --progress-bar -o "${TEMP_DIR}/piper.tar.gz" \
        "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz"

    # Extract to temp directory
    tar -xzf "${TEMP_DIR}/piper.tar.gz" -C "${TEMP_DIR}"

    # Copy model files to destination
    cp -r "${TEMP_DIR}/vits-piper-en_US-lessac-medium/"* "${TTS_DIR}/"

    print_success "VITS Piper English downloaded"
fi

# =============================================================================
# 4. LLM Model(s)
# =============================================================================

download_llm() {
    local model_id="$1"
    local model_file="${LLM_MODELS[$model_id]}"
    local model_url="${LLM_URLS[$model_id]}"
    local model_size="${LLM_SIZES[$model_id]}"
    local model_desc="${LLM_DESCRIPTIONS[$model_id]}"

    local LLM_DIR="${MODEL_DIR}/LlamaCpp/${model_id}"
    local LLM_FILE="${LLM_DIR}/${model_file}"

    print_step "Downloading ${model_id} (${model_size})..."
    print_info "${model_desc}"

    if [ -f "${LLM_FILE}" ] && [ "${FORCE_DOWNLOAD}" = false ]; then
        print_success "${model_id} already exists, skipping"
        return 0
    fi

    mkdir -p "${LLM_DIR}"

    # Download with progress
    if curl -L --progress-bar -o "${LLM_FILE}" "${model_url}"; then
        print_success "${model_id} downloaded"
    else
        print_error "Failed to download ${model_id}"
        return 1
    fi
}

if [ "${DOWNLOAD_ALL_LLMS}" = true ]; then
    print_header "Downloading All LLM Models"
    for model in $MODEL_ORDER; do
        download_llm "$model"
    done
else
    print_header "Downloading LLM Model"
    download_llm "${SELECTED_LLM}"
fi

# =============================================================================
# 5. Wake Word Models (optional)
# =============================================================================

if [ "${DOWNLOAD_WAKEWORD}" = true ]; then
    print_header "Downloading Wake Word Models"

    WAKEWORD_DIR="${MODEL_DIR}/ONNX/openwakeword"
    mkdir -p "${WAKEWORD_DIR}"

    # Download embedding model (shared backbone)
    EMBEDDING_FILE="${WAKEWORD_DIR}/embedding_model.onnx"
    print_step "Downloading openWakeWord embedding model..."
    if [ -f "${EMBEDDING_FILE}" ] && [ "${FORCE_DOWNLOAD}" = false ]; then
        print_success "openWakeWord embedding model already exists, skipping"
    else
        curl -L --progress-bar -o "${EMBEDDING_FILE}" \
            "https://github.com/dscripka/openWakeWord/releases/download/v0.5.0/embedding_model.onnx"
        print_success "openWakeWord embedding model downloaded"
    fi

    # Download melspectrogram model
    MELSPEC_FILE="${WAKEWORD_DIR}/melspectrogram.onnx"
    print_step "Downloading melspectrogram model..."
    if [ -f "${MELSPEC_FILE}" ] && [ "${FORCE_DOWNLOAD}" = false ]; then
        print_success "Melspectrogram model already exists, skipping"
    else
        curl -L --progress-bar -o "${MELSPEC_FILE}" \
            "https://github.com/dscripka/openWakeWord/releases/download/v0.5.0/melspectrogram.onnx"
        print_success "Melspectrogram model downloaded"
    fi

    # Download Hey Jarvis model
    WAKEWORD_MODEL_DIR="${MODEL_DIR}/ONNX/hey-jarvis"
    JARVIS_FILE="${WAKEWORD_MODEL_DIR}/hey_jarvis_v0.1.onnx"
    mkdir -p "${WAKEWORD_MODEL_DIR}"

    print_step "Downloading Hey Jarvis wake word model..."
    if [ -f "${JARVIS_FILE}" ] && [ "${FORCE_DOWNLOAD}" = false ]; then
        print_success "Hey Jarvis wake word model already exists, skipping"
    else
        curl -L --progress-bar -o "${JARVIS_FILE}" \
            "https://github.com/dscripka/openWakeWord/releases/download/v0.5.0/hey_jarvis_v0.1.onnx"
        print_success "Hey Jarvis wake word model downloaded"
    fi
fi

# =============================================================================
# Summary
# =============================================================================

print_header "Download Complete!"

echo "Voice Pipeline Models (fixed):"
echo "------------------------------"
echo ""

echo "VAD (Silero):"
ls -lh "${VAD_DIR}"/*.onnx 2>/dev/null | awk '{print "  " $NF ": " $5}' || echo "  (missing)"

echo ""
echo "STT (Whisper Tiny English):"
ls -lh "${STT_DIR}"/*.onnx 2>/dev/null | head -3 | awk '{print "  " $NF ": " $5}' || echo "  (missing)"

echo ""
echo "TTS (VITS Piper):"
ls -lh "${TTS_DIR}"/*.onnx 2>/dev/null | awk '{print "  " $NF ": " $5}' || echo "  (missing)"

echo ""
echo "LLM Models (swappable):"
echo "-----------------------"
for model_dir in "${MODEL_DIR}/LlamaCpp/"*/; do
    if [ -d "$model_dir" ]; then
        model_name=$(basename "$model_dir")
        model_file=$(ls -1 "$model_dir"/*.gguf 2>/dev/null | head -1)
        if [ -n "$model_file" ]; then
            model_size=$(ls -lh "$model_file" | awk '{print $5}')
            echo "  ${model_name}: ${model_size}"
        fi
    fi
done

if [ "${DOWNLOAD_WAKEWORD}" = true ]; then
    echo ""
    echo "Wake Word (openWakeWord):"
    ls -lh "${MODEL_DIR}/ONNX/openwakeword"/*.onnx 2>/dev/null | awk '{print "  " $NF ": " $5}' || echo "  (missing)"
    ls -lh "${MODEL_DIR}/ONNX/hey-jarvis"/*.onnx 2>/dev/null | awk '{print "  " $NF ": " $5}' || echo "  (missing)"
fi

echo ""

# Calculate total size
TOTAL_SIZE=$(du -sh "${MODEL_DIR}" 2>/dev/null | cut -f1)
echo "Total model size: ${TOTAL_SIZE}"

echo ""
print_success "All models downloaded successfully!"
echo ""

# Show which LLM is the default
if [ "${DOWNLOAD_ALL_LLMS}" = true ]; then
    echo "To use a specific LLM, start the server with:"
    echo "  runanywhere-server --model ~/.local/share/runanywhere/Models/LlamaCpp/<model-id>/<model>.gguf"
    echo ""
    echo "Available models:"
    for model_dir in "${MODEL_DIR}/LlamaCpp/"*/; do
        if [ -d "$model_dir" ]; then
            echo "  - $(basename "$model_dir")"
        fi
    done
else
    echo "Default LLM configured: ${SELECTED_LLM}"
    echo ""
    echo "To download additional LLMs, run:"
    echo "  ./download-models.sh --llm <model-id>"
    echo "  ./download-models.sh --list-llms     # See available models"
fi

if [ "${DOWNLOAD_WAKEWORD}" = true ]; then
    echo ""
    echo "Wake word models downloaded. To enable, run:"
    echo "  ./voice-assistant --wakeword"
fi
