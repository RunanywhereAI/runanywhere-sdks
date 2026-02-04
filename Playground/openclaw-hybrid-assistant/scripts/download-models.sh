#!/bin/bash

# =============================================================================
# download-models.sh - Download models for OpenClaw Hybrid Assistant
# =============================================================================
# Downloads the required models (NO LLM):
# - Silero VAD
# - Whisper Tiny EN
# - Kokoro TTS (high quality, 24kHz) - DEFAULT
# - Piper TTS (Lessac) - optional fallback with --piper flag
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
USE_PIPER_TTS=false
while [[ "$1" == --* ]]; do
    case "$1" in
        --wakeword)
            DOWNLOAD_WAKEWORD=true
            shift
            ;;
        --piper)
            USE_PIPER_TTS=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --wakeword   Also download wake word models (Hey Jarvis)"
            echo "  --piper      Use Piper TTS instead of Kokoro TTS (smaller but lower quality)"
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
if [ "$USE_PIPER_TTS" = true ]; then
    echo "TTS: Piper TTS (smaller, ~64MB)"
else
    echo "TTS: Kokoro TTS v0.19 English (high quality, ~330MB, 11 speakers)"
fi
echo ""

# Create directories
mkdir -p "${MODEL_DIR}/ONNX/silero-vad"
mkdir -p "${MODEL_DIR}/ONNX/whisper-tiny-en"
if [ "$USE_PIPER_TTS" = true ]; then
    mkdir -p "${MODEL_DIR}/ONNX/vits-piper-en_US-lessac-medium"
else
    mkdir -p "${MODEL_DIR}/ONNX/kokoro-en-v0_19"
fi

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
# TTS Model (Kokoro or Piper)
# =============================================================================

if [ "$USE_PIPER_TTS" = true ]; then
    # Piper TTS (Lessac) - smaller but lower quality
    print_step "Downloading Piper TTS (Lessac)..."
    if [ -f "${MODEL_DIR}/ONNX/vits-piper-en_US-lessac-medium/en_US-lessac-medium.onnx" ]; then
        print_success "Piper TTS already downloaded"
    else
        PIPER_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-lessac-medium.tar.bz2"
        curl -L "${PIPER_URL}" | tar -xjf - -C "${MODEL_DIR}/ONNX/"
        print_success "Piper TTS downloaded"
    fi
else
    # Kokoro TTS v0.19 English (11 speakers, English only, high quality)
    print_step "Downloading Kokoro TTS English (v0.19)..."
    KOKORO_DIR="${MODEL_DIR}/ONNX/kokoro-en-v0_19"
    KOKORO_MODEL="${KOKORO_DIR}/model.onnx"

    # Check if we have a complete download (must have both model.onnx AND voices.bin)
    if [ -f "${KOKORO_MODEL}" ] && [ -f "${KOKORO_DIR}/voices.bin" ]; then
        # Verify voices.bin is not empty (at least 1MB)
        VOICES_SIZE=$(stat -c%s "${KOKORO_DIR}/voices.bin" 2>/dev/null || stat -f%z "${KOKORO_DIR}/voices.bin" 2>/dev/null || echo 0)
        if [ "$VOICES_SIZE" -gt 1000000 ]; then
            print_success "Kokoro TTS English already downloaded (with voices.bin)"
        else
            echo "  voices.bin is too small ($VOICES_SIZE bytes) - re-downloading..."
            rm -rf "${KOKORO_DIR}"
            mkdir -p "${KOKORO_DIR}"
        fi
    else
        # Missing voices.bin or model - remove and re-download
        if [ -f "${KOKORO_MODEL}" ] && [ ! -f "${KOKORO_DIR}/voices.bin" ]; then
            echo "  Found model but missing voices.bin - removing incomplete download..."
            rm -rf "${KOKORO_DIR}"
            mkdir -p "${KOKORO_DIR}"
        fi
    fi

    # Download if needed
    if [ ! -f "${KOKORO_MODEL}" ] || [ ! -f "${KOKORO_DIR}/voices.bin" ]; then
        echo "  Downloading Kokoro TTS English model (~330MB)..."
        KOKORO_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-en-v0_19.tar.bz2"
        curl -L "${KOKORO_URL}" | tar -xjf - -C "${MODEL_DIR}/ONNX/"

        # Verify the download
        if [ -f "${KOKORO_MODEL}" ] && [ -f "${KOKORO_DIR}/voices.bin" ]; then
            print_success "Kokoro TTS English downloaded"
            echo "  Model: $(ls -lh ${KOKORO_MODEL} | awk '{print $5}')"
            echo "  Voices: $(ls -lh ${KOKORO_DIR}/voices.bin | awk '{print $5}')"
            echo "  Speakers: 11 (English only)"
            echo "  Sample rate: 24kHz"
        else
            print_error "Kokoro TTS download failed or incomplete!"
            echo "  Expected files: model.onnx, voices.bin, tokens.txt, espeak-ng-data/"
            echo "  Got:"
            ls -la "${KOKORO_DIR}/"
            echo ""
            echo "  Consider using Piper TTS instead:"
            echo "    --piper    to use Piper TTS (smaller, ~64MB)"
            exit 1
        fi
    fi

    # Print available Kokoro English speakers
    echo ""
    echo "Available Kokoro English Speakers:"
    echo "  ID 0:  af (American female, default)"
    echo "  ID 1:  af_bella (American female)"
    echo "  ID 2:  af_nicole (American female)"
    echo "  ID 3:  af_sarah (American female)"
    echo "  ID 4:  af_sky (American female)"
    echo "  ID 5:  am_adam (American male)"
    echo "  ID 6:  am_michael (American male) - DEFAULT"
    echo "  ID 7:  bf_emma (British female)"
    echo "  ID 8:  bf_isabella (British female)"
    echo "  ID 9:  bm_george (British male)"
    echo "  ID 10: bm_lewis (British male)"
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

    # Verify downloads (check size and that they are not HTML pages from Git LFS redirects)
    echo "  Verifying wake word model files..."
    ALL_OK=true
    for f in "${EMBED_FILE}" "${MELSPEC_FILE}" "${JARVIS_FILE}"; do
        if [ -f "$f" ]; then
            size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo 0)
            filetype=$(file -b "$f" 2>/dev/null || echo "unknown")
            if echo "$filetype" | grep -qi "html"; then
                echo "    ERROR: $(basename $f) is an HTML page, not an ONNX model!"
                echo "           This usually means the file was downloaded from a raw.githubusercontent.com URL"
                echo "           which returns an HTML Git LFS redirect instead of the actual binary."
                echo "           Delete it and re-run this script to download from GitHub Releases."
                rm -f "$f"
                ALL_OK=false
            elif [ "$size" -lt 10000 ]; then
                echo "    WARNING: $(basename $f) seems too small ($size bytes) - may be corrupted"
                ALL_OK=false
            else
                echo "    OK: $(basename $f) ($size bytes, $filetype)"
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
echo ""
echo "VAD (Silero):"
ls -la "${MODEL_DIR}/ONNX/silero-vad/"
echo ""
echo "STT (Whisper Tiny EN):"
ls -la "${MODEL_DIR}/ONNX/whisper-tiny-en/" | head -5
echo ""
if [ "$USE_PIPER_TTS" = true ]; then
    echo "TTS (Piper Lessac):"
    ls -la "${MODEL_DIR}/ONNX/vits-piper-en_US-lessac-medium/" | head -5
else
    echo "TTS (Kokoro English v0.19):"
    ls -la "${MODEL_DIR}/ONNX/kokoro-en-v0_19/" | head -8
fi

if [ "$DOWNLOAD_WAKEWORD" = true ]; then
    echo ""
    echo "Wake word models:"
    ls -la "${MODEL_DIR}/ONNX/hey-jarvis/"
    ls -la "${MODEL_DIR}/ONNX/openwakeword-embedding/"
fi

echo ""
print_success "All models downloaded successfully!"

if [ "$USE_PIPER_TTS" != true ]; then
    echo ""
    echo "Note: Using Kokoro TTS English with 24kHz sample rate."
    echo "Default speaker: am_michael (ID 6) - American male voice"
fi
