#!/bin/bash

# =============================================================================
# generate-test-audio.sh - Generate/download test audio files
# =============================================================================
# Creates test WAV files for testing wake word, VAD, and ASR:
# 1. hey-jarvis.wav - Wake word "Hey Jarvis" only
# 2. speech.wav - Speech without wake word (command like "what's the weather")
# 3. wakeword-plus-speech.wav - Wake word followed by a command
# 4. noise.wav - Background noise (should NOT trigger)
# 5. silence.wav - Silence (should NOT trigger)
# 6. random-words.wav - Random words that are NOT wake word
# 7. music.wav - Music (should NOT trigger)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_AUDIO_DIR="${SCRIPT_DIR}/../audio"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "=========================================="
echo "  Generating Test Audio Files"
echo "=========================================="
echo ""

mkdir -p "${TEST_AUDIO_DIR}"

# =============================================================================
# Helper: Convert to 16kHz mono 16-bit WAV
# =============================================================================
convert_to_16k() {
    local input="$1"
    local output="$2"

    if command -v sox &> /dev/null; then
        sox "$input" -r 16000 -c 1 -b 16 "$output" 2>/dev/null || cp "$input" "$output"
    elif command -v ffmpeg &> /dev/null; then
        ffmpeg -i "$input" -ar 16000 -ac 1 -sample_fmt s16 -y "$output" 2>/dev/null || cp "$input" "$output"
    else
        cp "$input" "$output"
    fi
}

# =============================================================================
# Generate test files
# =============================================================================

generate_test_files() {
    echo -e "${CYAN}Generating test audio files...${NC}"
    echo ""

    # =========================================================================
    # 1. Silence (3 seconds)
    # =========================================================================
    echo -e "${YELLOW}[1/8] Creating silence.wav (3s of silence)...${NC}"
    if command -v sox &> /dev/null; then
        sox -n -r 16000 -c 1 -b 16 "${TEST_AUDIO_DIR}/silence.wav" trim 0.0 3.0
    elif command -v ffmpeg &> /dev/null; then
        ffmpeg -f lavfi -i anullsrc=r=16000:cl=mono -t 3 -y "${TEST_AUDIO_DIR}/silence.wav" 2>/dev/null
    fi
    echo "  Created: silence.wav"

    # =========================================================================
    # 2. Pink Noise (should NOT trigger wake word)
    # =========================================================================
    echo -e "${YELLOW}[2/8] Creating noise.wav (pink noise)...${NC}"
    if command -v sox &> /dev/null; then
        sox -n -r 16000 -c 1 -b 16 "${TEST_AUDIO_DIR}/noise.wav" synth 5.0 pinknoise vol 0.3
    elif command -v ffmpeg &> /dev/null; then
        ffmpeg -f lavfi -i "anoisesrc=d=5:c=pink:r=16000:a=0.3" -y "${TEST_AUDIO_DIR}/noise.wav" 2>/dev/null
    fi
    echo "  Created: noise.wav"

    # =========================================================================
    # 3. White Noise (another noise type)
    # =========================================================================
    echo -e "${YELLOW}[3/8] Creating white-noise.wav (white noise)...${NC}"
    if command -v sox &> /dev/null; then
        sox -n -r 16000 -c 1 -b 16 "${TEST_AUDIO_DIR}/white-noise.wav" synth 5.0 whitenoise vol 0.2
    elif command -v ffmpeg &> /dev/null; then
        ffmpeg -f lavfi -i "anoisesrc=d=5:c=white:r=16000:a=0.2" -y "${TEST_AUDIO_DIR}/white-noise.wav" 2>/dev/null
    fi
    echo "  Created: white-noise.wav"

    # =========================================================================
    # 4. Hey Jarvis (wake word)
    # =========================================================================
    echo -e "${YELLOW}[4/8] Creating hey-jarvis.wav (wake word)...${NC}"
    TTS_CMD=""
    if command -v espeak-ng &> /dev/null; then
        TTS_CMD="espeak-ng"
    elif command -v espeak &> /dev/null; then
        TTS_CMD="espeak"
    fi

    if [ -n "$TTS_CMD" ]; then
        # Generate with slightly slower speed for clarity
        $TTS_CMD -w "${TEST_AUDIO_DIR}/hey-jarvis_raw.wav" -s 120 -p 50 "Hey Jarvis"
        convert_to_16k "${TEST_AUDIO_DIR}/hey-jarvis_raw.wav" "${TEST_AUDIO_DIR}/hey-jarvis.wav"
        rm -f "${TEST_AUDIO_DIR}/hey-jarvis_raw.wav"
        echo "  Created: hey-jarvis.wav"
    else
        echo -e "  ${RED}No TTS available - skipping${NC}"
    fi

    # =========================================================================
    # 5. Speech command (without wake word)
    # =========================================================================
    echo -e "${YELLOW}[5/8] Creating speech.wav (command without wake word)...${NC}"
    if [ -n "$TTS_CMD" ]; then
        $TTS_CMD -w "${TEST_AUDIO_DIR}/speech_raw.wav" -s 150 "What is the weather like today in San Francisco"
        convert_to_16k "${TEST_AUDIO_DIR}/speech_raw.wav" "${TEST_AUDIO_DIR}/speech.wav"
        rm -f "${TEST_AUDIO_DIR}/speech_raw.wav"
        echo "  Created: speech.wav"
    fi

    # =========================================================================
    # 6. Random words (NOT wake word - should not trigger)
    # =========================================================================
    echo -e "${YELLOW}[6/8] Creating random-words.wav (not wake word)...${NC}"
    if [ -n "$TTS_CMD" ]; then
        $TTS_CMD -w "${TEST_AUDIO_DIR}/random_raw.wav" -s 140 "Hello world, the quick brown fox jumps over the lazy dog"
        convert_to_16k "${TEST_AUDIO_DIR}/random_raw.wav" "${TEST_AUDIO_DIR}/random-words.wav"
        rm -f "${TEST_AUDIO_DIR}/random_raw.wav"
        echo "  Created: random-words.wav"
    fi

    # =========================================================================
    # 7. Similar sounding words (edge case - should NOT trigger)
    # =========================================================================
    echo -e "${YELLOW}[7/8] Creating similar-words.wav (similar but not wake word)...${NC}"
    if [ -n "$TTS_CMD" ]; then
        # Words that might sound similar to "Hey Jarvis" but aren't
        $TTS_CMD -w "${TEST_AUDIO_DIR}/similar_raw.wav" -s 130 "Hey Travis, Hey Marcus, Hey service, Hey nervous"
        convert_to_16k "${TEST_AUDIO_DIR}/similar_raw.wav" "${TEST_AUDIO_DIR}/similar-words.wav"
        rm -f "${TEST_AUDIO_DIR}/similar_raw.wav"
        echo "  Created: similar-words.wav"
    fi

    # =========================================================================
    # 8. Wake word + Speech combined
    # =========================================================================
    echo -e "${YELLOW}[8/8] Creating wakeword-plus-speech.wav (wake word + command)...${NC}"
    if [ -f "${TEST_AUDIO_DIR}/hey-jarvis.wav" ] && [ -f "${TEST_AUDIO_DIR}/speech.wav" ]; then
        if command -v sox &> /dev/null; then
            # Add 0.8s pause between wake word and speech (realistic pause)
            sox -n -r 16000 -c 1 -b 16 "${TEST_AUDIO_DIR}/pause.wav" trim 0.0 0.8
            sox "${TEST_AUDIO_DIR}/hey-jarvis.wav" "${TEST_AUDIO_DIR}/pause.wav" "${TEST_AUDIO_DIR}/speech.wav" "${TEST_AUDIO_DIR}/wakeword-plus-speech.wav"
            rm -f "${TEST_AUDIO_DIR}/pause.wav"
            echo "  Created: wakeword-plus-speech.wav"
        elif command -v ffmpeg &> /dev/null; then
            # Generate pause
            ffmpeg -f lavfi -i anullsrc=r=16000:cl=mono -t 0.8 -y "${TEST_AUDIO_DIR}/pause.wav" 2>/dev/null
            # Concatenate
            ffmpeg -i "concat:${TEST_AUDIO_DIR}/hey-jarvis.wav|${TEST_AUDIO_DIR}/pause.wav|${TEST_AUDIO_DIR}/speech.wav" \
                   -y "${TEST_AUDIO_DIR}/wakeword-plus-speech.wav" 2>/dev/null || true
            rm -f "${TEST_AUDIO_DIR}/pause.wav"
            echo "  Created: wakeword-plus-speech.wav"
        fi
    fi

    # =========================================================================
    # 9. Long silence + wake word (test timeout)
    # =========================================================================
    echo -e "${YELLOW}[BONUS] Creating delayed-wakeword.wav (2s silence + wake word)...${NC}"
    if [ -f "${TEST_AUDIO_DIR}/hey-jarvis.wav" ]; then
        if command -v sox &> /dev/null; then
            sox -n -r 16000 -c 1 -b 16 "${TEST_AUDIO_DIR}/long_silence.wav" trim 0.0 2.0
            sox "${TEST_AUDIO_DIR}/long_silence.wav" "${TEST_AUDIO_DIR}/hey-jarvis.wav" "${TEST_AUDIO_DIR}/delayed-wakeword.wav"
            rm -f "${TEST_AUDIO_DIR}/long_silence.wav"
            echo "  Created: delayed-wakeword.wav"
        fi
    fi

    # =========================================================================
    # 10. Multiple wake words
    # =========================================================================
    echo -e "${YELLOW}[BONUS] Creating multiple-wakewords.wav (2x wake word)...${NC}"
    if [ -f "${TEST_AUDIO_DIR}/hey-jarvis.wav" ]; then
        if command -v sox &> /dev/null; then
            sox -n -r 16000 -c 1 -b 16 "${TEST_AUDIO_DIR}/short_pause.wav" trim 0.0 1.0
            sox "${TEST_AUDIO_DIR}/hey-jarvis.wav" "${TEST_AUDIO_DIR}/short_pause.wav" "${TEST_AUDIO_DIR}/hey-jarvis.wav" "${TEST_AUDIO_DIR}/multiple-wakewords.wav"
            rm -f "${TEST_AUDIO_DIR}/short_pause.wav"
            echo "  Created: multiple-wakewords.wav"
        fi
    fi
}

# =============================================================================
# Main
# =============================================================================

generate_test_files

# List created files
echo ""
echo "=========================================="
echo "  Test Audio Files Summary"
echo "=========================================="
echo ""

# Show file details
for f in "${TEST_AUDIO_DIR}"/*.wav; do
    if [ -f "$f" ]; then
        filename=$(basename "$f")
        # Get duration using sox or file size
        if command -v sox &> /dev/null; then
            duration=$(sox "$f" -n stat 2>&1 | grep "Length" | awk '{print $3}')
            echo "  $filename - ${duration}s"
        else
            size=$(ls -lh "$f" | awk '{print $5}')
            echo "  $filename - $size"
        fi
    fi
done

echo ""
echo -e "${GREEN}Test audio files ready in: ${TEST_AUDIO_DIR}${NC}"
echo ""
echo "Test cases covered:"
echo "  1. silence.wav         - Should NOT trigger anything"
echo "  2. noise.wav           - Should NOT trigger wake word"
echo "  3. white-noise.wav     - Should NOT trigger wake word"
echo "  4. hey-jarvis.wav      - Should trigger wake word ONLY"
echo "  5. speech.wav          - Should NOT trigger (no wake word)"
echo "  6. random-words.wav    - Should NOT trigger wake word"
echo "  7. similar-words.wav   - Should NOT trigger (similar sounds)"
echo "  8. wakeword-plus-speech.wav - Should trigger wake word + ASR"
echo ""
echo "Usage:"
echo "  ./build/test-components --run-all"
echo ""
echo "Or test individual components:"
echo "  ./build/test-components --test-wakeword test-audio/hey-jarvis.wav"
echo "  ./build/test-components --test-no-wakeword test-audio/noise.wav"
echo "  ./build/test-components --test-vad test-audio/speech.wav"
echo "  ./build/test-components --test-stt test-audio/speech.wav"
