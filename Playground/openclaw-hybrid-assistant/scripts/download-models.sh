#!/bin/bash

# =============================================================================
# download-models.sh - Download models for OpenClaw Hybrid Assistant
# =============================================================================
# Downloads the required models (NO LLM):
# - Silero VAD (~2MB)
# - Parakeet TDT-CTC 110M EN int8 (~126MB) - DEFAULT ASR
# - Piper TTS Lessac Medium (~61MB) - DEFAULT TTS
#
# Alternative models (via flags):
# - Whisper Tiny EN (~150MB) - use --whisper for ASR
# - Kokoro TTS v0.19 (~330MB) - use --kokoro for TTS
# =============================================================================

set -e

MODEL_DIR="${HOME}/.local/share/runanywhere/Models"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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
USE_WHISPER_ASR=false
USE_KOKORO_TTS=false
while [[ "$1" == --* ]]; do
    case "$1" in
        --whisper)
            USE_WHISPER_ASR=true
            shift
            ;;
        --kokoro)
            USE_KOKORO_TTS=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --whisper    Use Whisper Tiny EN for ASR instead of Parakeet (larger but multilingual)"
            echo "  --kokoro     Use Kokoro TTS instead of Piper (larger but higher quality, multi-speaker)"
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
if [ "$USE_WHISPER_ASR" = true ]; then
    echo "ASR: Whisper Tiny EN (~150MB, multilingual)"
else
    echo "ASR: Parakeet TDT-CTC 110M EN int8 (~126MB, fast)"
fi
if [ "$USE_KOKORO_TTS" = true ]; then
    echo "TTS: Kokoro TTS v0.19 English (high quality, ~330MB, 11 speakers)"
else
    echo "TTS: Piper Lessac Medium (~61MB, natural male voice)"
fi
echo ""

# Create directories
mkdir -p "${MODEL_DIR}/Sherpa/silero-vad"
if [ "$USE_WHISPER_ASR" = true ]; then
    mkdir -p "${MODEL_DIR}/Sherpa/whisper-tiny-en"
else
    mkdir -p "${MODEL_DIR}/Sherpa/parakeet-tdt-ctc-110m-en-int8"
fi
if [ "$USE_KOKORO_TTS" = true ]; then
    mkdir -p "${MODEL_DIR}/Sherpa/kokoro-en-v0_19"
else
    mkdir -p "${MODEL_DIR}/Sherpa/vits-piper-en_US-lessac-medium"
fi

# =============================================================================
# Silero VAD
# =============================================================================

print_step "Downloading Silero VAD..."
VAD_FILE="${MODEL_DIR}/Sherpa/silero-vad/silero_vad.onnx"

# Check if existing file is valid (not an HTML redirect page from Git LFS)
if [ -f "${VAD_FILE}" ]; then
    FIRST_BYTES=$(head -c 10 "${VAD_FILE}" 2>/dev/null || true)
    if echo "${FIRST_BYTES}" | grep -q "DOCTYPE"; then
        echo "  Existing file is HTML (Git LFS redirect), re-downloading..."
        rm -f "${VAD_FILE}"
    fi
fi

if [ -f "${VAD_FILE}" ]; then
    print_success "Silero VAD already downloaded"
else
    # NOTE: The old path (.../files/silero_vad.onnx) returns an HTML page via Git LFS.
    # The correct path for v5+ is under src/silero_vad/data/
    curl -L -o "${VAD_FILE}" \
        "https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx"

    # Verify download is a real ONNX file, not HTML
    FIRST_BYTES=$(head -c 10 "${VAD_FILE}" 2>/dev/null || true)
    if echo "${FIRST_BYTES}" | grep -q "DOCTYPE"; then
        print_error "Downloaded file is HTML (Git LFS redirect). Trying alternative URL..."
        rm -f "${VAD_FILE}"
        # Fallback: try the HuggingFace mirror
        curl -L -o "${VAD_FILE}" \
            "https://huggingface.co/snakers4/silero-vad/resolve/main/src/silero_vad/data/silero_vad.onnx" 2>/dev/null || true
    fi

    if [ -f "${VAD_FILE}" ]; then
        print_success "Silero VAD downloaded"
    else
        print_error "Failed to download Silero VAD"
    fi
fi

# =============================================================================
# ASR Model (Parakeet or Whisper)
# =============================================================================

if [ "$USE_WHISPER_ASR" = true ]; then
    # Whisper Tiny EN (alternative - larger, multilingual)
    print_step "Downloading Whisper Tiny EN..."
    if [ -f "${MODEL_DIR}/Sherpa/whisper-tiny-en/tiny-encoder.int8.onnx" ]; then
        print_success "Whisper Tiny EN already downloaded"
    else
        WHISPER_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny.en.tar.bz2"
        curl -L "${WHISPER_URL}" | tar -xjf - -C "${MODEL_DIR}/Sherpa/"

        # Move files to expected location
        if [ -d "${MODEL_DIR}/Sherpa/sherpa-onnx-whisper-tiny.en" ]; then
            mv "${MODEL_DIR}/Sherpa/sherpa-onnx-whisper-tiny.en"/* "${MODEL_DIR}/Sherpa/whisper-tiny-en/" 2>/dev/null || true
            rm -rf "${MODEL_DIR}/Sherpa/sherpa-onnx-whisper-tiny.en"
        fi
        print_success "Whisper Tiny EN downloaded"
    fi
else
    # Parakeet TDT-CTC 110M EN int8 (DEFAULT - faster, smaller, supports punctuation + capitalization)
    PARAKEET_DIR="${MODEL_DIR}/Sherpa/parakeet-tdt-ctc-110m-en-int8"
    print_step "Downloading Parakeet TDT-CTC 110M EN (int8)..."
    if [ -f "${PARAKEET_DIR}/model.int8.onnx" ]; then
        print_success "Parakeet TDT-CTC already downloaded"
    else
        PARAKEET_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-parakeet_tdt_ctc_110m-en-36000-int8.tar.bz2"
        curl -L "${PARAKEET_URL}" | tar -xjf - -C "${MODEL_DIR}/Sherpa/"

        # Move files to expected location
        EXTRACTED_DIR="${MODEL_DIR}/Sherpa/sherpa-onnx-nemo-parakeet_tdt_ctc_110m-en-36000-int8"
        if [ -d "${EXTRACTED_DIR}" ]; then
            mv "${EXTRACTED_DIR}"/* "${PARAKEET_DIR}/" 2>/dev/null || true
            rm -rf "${EXTRACTED_DIR}"
        fi

        if [ -f "${PARAKEET_DIR}/model.int8.onnx" ]; then
            print_success "Parakeet TDT-CTC downloaded"
            echo "  Model: $(ls -lh "${PARAKEET_DIR}/model.int8.onnx" | awk '{print $5}')"
            echo "  Features: Punctuation + capitalization, English-only"
            echo "  Architecture: FastConformer 110M params (int8 quantized)"
        else
            print_error "Parakeet download failed!"
            echo "  Consider using Whisper instead: $0 --whisper"
            exit 1
        fi
    fi
fi

# =============================================================================
# TTS Model (Piper or Kokoro)
# =============================================================================

if [ "$USE_KOKORO_TTS" = true ]; then
    # Kokoro TTS v0.19 English (alternative - larger, multi-speaker, higher quality)
    print_step "Downloading Kokoro TTS English (v0.19)..."
    KOKORO_DIR="${MODEL_DIR}/Sherpa/kokoro-en-v0_19"
    KOKORO_MODEL="${KOKORO_DIR}/model.onnx"

    if [ -f "${KOKORO_MODEL}" ] && [ -f "${KOKORO_DIR}/voices.bin" ]; then
        VOICES_SIZE=$(stat -c%s "${KOKORO_DIR}/voices.bin" 2>/dev/null || stat -f%z "${KOKORO_DIR}/voices.bin" 2>/dev/null || echo 0)
        if [ "$VOICES_SIZE" -gt 1000000 ]; then
            print_success "Kokoro TTS English already downloaded (with voices.bin)"
        else
            echo "  voices.bin is too small ($VOICES_SIZE bytes) - re-downloading..."
            rm -rf "${KOKORO_DIR}"
            mkdir -p "${KOKORO_DIR}"
        fi
    else
        if [ -f "${KOKORO_MODEL}" ] && [ ! -f "${KOKORO_DIR}/voices.bin" ]; then
            echo "  Found model but missing voices.bin - removing incomplete download..."
            rm -rf "${KOKORO_DIR}"
            mkdir -p "${KOKORO_DIR}"
        fi
    fi

    if [ ! -f "${KOKORO_MODEL}" ] || [ ! -f "${KOKORO_DIR}/voices.bin" ]; then
        echo "  Downloading Kokoro TTS English model (~330MB)..."
        KOKORO_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-en-v0_19.tar.bz2"
        curl -L "${KOKORO_URL}" | tar -xjf - -C "${MODEL_DIR}/Sherpa/"

        if [ -f "${KOKORO_MODEL}" ] && [ -f "${KOKORO_DIR}/voices.bin" ]; then
            print_success "Kokoro TTS English downloaded"
            echo "  Speakers: 11 (English only)"
            echo "  Sample rate: 24kHz"
        else
            print_error "Kokoro TTS download failed!"
            echo "  Consider using Piper TTS instead (default, no --kokoro flag)"
            exit 1
        fi
    fi
else
    # Piper TTS Lessac Medium (DEFAULT - smaller, fast, natural voice)
    print_step "Downloading Piper TTS (Lessac Medium)..."
    if [ -f "${MODEL_DIR}/Sherpa/vits-piper-en_US-lessac-medium/en_US-lessac-medium.onnx" ]; then
        print_success "Piper TTS already downloaded"
    else
        PIPER_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-lessac-medium.tar.bz2"
        curl -L "${PIPER_URL}" | tar -xjf - -C "${MODEL_DIR}/Sherpa/"
        print_success "Piper TTS downloaded"
        echo "  Voice: Natural American male"
        echo "  Sample rate: 22050Hz"
        echo "  Size: ~61MB"
    fi
fi

# =============================================================================
# Earcon (acknowledgment sound for waiting feedback)
# =============================================================================

EARCON_DIR="${MODEL_DIR}/ONNX/earcon"
mkdir -p "${EARCON_DIR}"
EARCON_FILE="${EARCON_DIR}/acknowledgment.wav"

if [ -f "${EARCON_FILE}" ]; then
    print_success "Earcon already generated"
else
    print_step "Generating acknowledgment earcon..."
    if command -v sox &> /dev/null; then
        # Two-note ascending pluck chime (C5 + E5) - sounds like a real glockenspiel
        sox -n -r 22050 -c 1 -b 16 "${EARCON_FILE}" \
            synth 0.4 pluck C5 fade l 0 0.4 0.3 : \
            synth 0.4 pluck E5 fade l 0 0.4 0.3 \
            norm -3 2>/dev/null
        if [ -f "${EARCON_FILE}" ]; then
            print_success "Earcon generated ($(ls -lh "${EARCON_FILE}" | awk '{print $5}'))"
        else
            echo -e "${YELLOW}  sox command failed, trying simpler syntax...${NC}"
            # Fallback: single pluck note
            sox -n -r 22050 -c 1 -b 16 "${EARCON_FILE}" \
                synth 0.5 pluck C5 fade l 0 0.5 0.4 norm -3 2>/dev/null || true
            if [ -f "${EARCON_FILE}" ]; then
                print_success "Earcon generated (single note fallback)"
            else
                echo -e "${YELLOW}  Could not generate earcon - waiting feedback will be silent${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}  sox not installed - skipping earcon generation${NC}"
        echo "  Install with: sudo apt-get install sox"
        echo "  Waiting feedback will be silent until earcon is generated"
    fi
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
ls -la "${MODEL_DIR}/Sherpa/silero-vad/"
echo ""

if [ "$USE_WHISPER_ASR" = true ]; then
    echo "ASR (Whisper Tiny EN):"
    ls -la "${MODEL_DIR}/Sherpa/whisper-tiny-en/" | head -5
else
    echo "ASR (Parakeet TDT-CTC 110M EN int8):"
    ls -la "${MODEL_DIR}/Sherpa/parakeet-tdt-ctc-110m-en-int8/" | head -5
fi

echo ""
if [ "$USE_KOKORO_TTS" = true ]; then
    echo "TTS (Kokoro English v0.19):"
    ls -la "${MODEL_DIR}/Sherpa/kokoro-en-v0_19/" | head -8
else
    echo "TTS (Piper Lessac Medium):"
    ls -la "${MODEL_DIR}/Sherpa/vits-piper-en_US-lessac-medium/" | head -5
fi

echo ""
print_success "All models downloaded successfully!"
echo ""
if [ "$USE_WHISPER_ASR" != true ]; then
    echo "ASR: Parakeet TDT-CTC 110M (NeMo CTC, int8, supports punctuation + capitalization)"
fi
if [ "$USE_KOKORO_TTS" != true ]; then
    echo "TTS: Piper Lessac Medium (22050Hz, natural American male voice)"
fi
