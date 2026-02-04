#!/bin/bash

# =============================================================================
# download-models.sh - Download models for OpenClaw Hybrid Assistant
# =============================================================================
# Downloads the required models (NO LLM):
# - Silero VAD
# - Whisper Tiny EN
# - Piper TTS (Lessac)
# - openWakeWord (optional, with --wakeword flag)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_DIR="${HOME}/.local/share/runanywhere/Models"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() {
    echo -e "${YELLOW}-> $1${NC}"
}

print_success() {
    echo -e "${GREEN}[OK] $1${NC}"
}

print_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

# Parse arguments
DOWNLOAD_WAKEWORD=false
while [[ "$1" == --* ]]; do
    case "$1" in
        --wakeword)
            DOWNLOAD_WAKEWORD=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --wakeword   Also download wake word models (Hey Jarvis)"
            echo "  --help       Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "=========================================="
echo "  Model Download (NO LLM)"
echo "=========================================="
echo ""
echo "Model directory: ${MODEL_DIR}"
echo ""

# Create directories
mkdir -p "${MODEL_DIR}/ONNX/silero-vad"
mkdir -p "${MODEL_DIR}/ONNX/whisper-tiny-en"
mkdir -p "${MODEL_DIR}/ONNX/vits-piper-en_US-lessac-medium"

# =============================================================================
# Silero VAD
# =============================================================================

print_step "Downloading Silero VAD..."
if [ -f "${MODEL_DIR}/ONNX/silero-vad/silero_vad.onnx" ]; then
    print_success "Silero VAD already downloaded"
else
    curl -L -o "${MODEL_DIR}/ONNX/silero-vad/silero_vad.onnx" \
        "https://github.com/snakers4/silero-vad/raw/master/files/silero_vad.onnx"
    print_success "Silero VAD downloaded"
fi

# =============================================================================
# Whisper Tiny EN
# =============================================================================

print_step "Downloading Whisper Tiny EN..."
if [ -f "${MODEL_DIR}/ONNX/whisper-tiny-en/tiny-encoder.int8.onnx" ]; then
    print_success "Whisper Tiny EN already downloaded"
else
    WHISPER_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny.en.tar.bz2"
    curl -L "${WHISPER_URL}" | tar -xjf - -C "${MODEL_DIR}/ONNX/"

    # Move files to expected location
    if [ -d "${MODEL_DIR}/ONNX/sherpa-onnx-whisper-tiny.en" ]; then
        mv "${MODEL_DIR}/ONNX/sherpa-onnx-whisper-tiny.en"/* "${MODEL_DIR}/ONNX/whisper-tiny-en/" 2>/dev/null || true
        rm -rf "${MODEL_DIR}/ONNX/sherpa-onnx-whisper-tiny.en"
    fi
    print_success "Whisper Tiny EN downloaded"
fi

# =============================================================================
# Piper TTS (Lessac)
# =============================================================================

print_step "Downloading Piper TTS (Lessac)..."
if [ -f "${MODEL_DIR}/ONNX/vits-piper-en_US-lessac-medium/en_US-lessac-medium.onnx" ]; then
    print_success "Piper TTS already downloaded"
else
    PIPER_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-lessac-medium.tar.bz2"
    curl -L "${PIPER_URL}" | tar -xjf - -C "${MODEL_DIR}/ONNX/"
    print_success "Piper TTS downloaded"
fi

# =============================================================================
# Wake Word Models (optional)
# =============================================================================

if [ "$DOWNLOAD_WAKEWORD" = true ]; then
    print_step "Downloading Wake Word models..."

    mkdir -p "${MODEL_DIR}/ONNX/hey-jarvis"
    mkdir -p "${MODEL_DIR}/ONNX/openwakeword-embedding"

    # Use HuggingFace as the source for openWakeWord models (they host the models there)
    # Alternative: Download from GitHub using media redirect

    # Download openWakeWord embedding model from GitHub releases (v0.5.1 has the ONNX models)
    EMBED_FILE="${MODEL_DIR}/ONNX/openwakeword-embedding/embedding_model.onnx"
    if [ ! -f "${EMBED_FILE}" ] || [ $(stat -c%s "${EMBED_FILE}" 2>/dev/null || stat -f%z "${EMBED_FILE}" 2>/dev/null || echo 0) -lt 1000000 ]; then
        echo "  Downloading embedding_model.onnx from GitHub releases (v0.5.1)..."
        EMBED_URL="https://github.com/dscripka/openWakeWord/releases/download/v0.5.1/embedding_model.onnx"
        rm -f "${EMBED_FILE}"
        curl -L -o "${EMBED_FILE}" "${EMBED_URL}"
        echo "  Size: $(ls -lh "${EMBED_FILE}" 2>/dev/null | awk '{print $5}' || echo 'failed')"
    fi

    # Download melspectrogram model from GitHub releases
    MELSPEC_FILE="${MODEL_DIR}/ONNX/openwakeword-embedding/melspectrogram.onnx"
    if [ ! -f "${MELSPEC_FILE}" ] || [ $(stat -c%s "${MELSPEC_FILE}" 2>/dev/null || stat -f%z "${MELSPEC_FILE}" 2>/dev/null || echo 0) -lt 100000 ]; then
        echo "  Downloading melspectrogram.onnx from GitHub releases (v0.5.1)..."
        MELSPEC_URL="https://github.com/dscripka/openWakeWord/releases/download/v0.5.1/melspectrogram.onnx"
        rm -f "${MELSPEC_FILE}"
        curl -L -o "${MELSPEC_FILE}" "${MELSPEC_URL}"
        echo "  Size: $(ls -lh "${MELSPEC_FILE}" 2>/dev/null | awk '{print $5}' || echo 'failed')"
    fi

    # Download Hey Jarvis wake word model from GitHub releases
    JARVIS_FILE="${MODEL_DIR}/ONNX/hey-jarvis/hey_jarvis_v0.1.onnx"
    if [ ! -f "${JARVIS_FILE}" ] || [ $(stat -c%s "${JARVIS_FILE}" 2>/dev/null || stat -f%z "${JARVIS_FILE}" 2>/dev/null || echo 0) -lt 10000 ]; then
        echo "  Downloading hey_jarvis_v0.1.onnx from GitHub releases (v0.5.1)..."
        JARVIS_URL="https://github.com/dscripka/openWakeWord/releases/download/v0.5.1/hey_jarvis_v0.1.onnx"
        rm -f "${JARVIS_FILE}"
        curl -L -o "${JARVIS_FILE}" "${JARVIS_URL}"
        echo "  Size: $(ls -lh "${JARVIS_FILE}" 2>/dev/null | awk '{print $5}' || echo 'failed')"
    fi

    # Verify downloads
    echo "  Verifying wake word model files..."
    ALL_OK=true
    for f in "${EMBED_FILE}" "${MELSPEC_FILE}" "${JARVIS_FILE}"; do
        if [ -f "$f" ]; then
            size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo 0)
            if [ "$size" -lt 10000 ]; then
                echo "    WARNING: $(basename $f) seems too small ($size bytes) - may be corrupted"
                ALL_OK=false
            else
                echo "    OK: $(basename $f) ($size bytes)"
            fi
        else
            echo "    MISSING: $(basename $f)"
            ALL_OK=false
        fi
    done

    if [ "$ALL_OK" = true ]; then
        print_success "Wake word models downloaded successfully"
    else
        echo -e "${YELLOW}  Some wake word models may not have downloaded correctly${NC}"
        echo "  Wake word detection may not work properly"
    fi
else
    echo ""
    echo "Skipping wake word models. To download, run:"
    echo "  $0 --wakeword"
fi

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "=========================================="
echo "  Download Complete"
echo "=========================================="
echo ""
echo "Required models (NO LLM):"
ls -la "${MODEL_DIR}/ONNX/silero-vad/"
ls -la "${MODEL_DIR}/ONNX/whisper-tiny-en/" | head -5
ls -la "${MODEL_DIR}/ONNX/vits-piper-en_US-lessac-medium/" | head -5

if [ "$DOWNLOAD_WAKEWORD" = true ]; then
    echo ""
    echo "Wake word models:"
    ls -la "${MODEL_DIR}/ONNX/hey-jarvis/"
    ls -la "${MODEL_DIR}/ONNX/openwakeword-embedding/"
fi

echo ""
print_success "All models downloaded successfully!"
