#!/bin/bash

# =============================================================================
# record-wakeword.sh - Record wake word from your microphone
# =============================================================================
# Records your voice saying "Hey Jarvis" and saves it in the correct format
# for testing the wake word detection.
#
# Usage:
#   ./scripts/record-wakeword.sh              # Records for 3 seconds
#   ./scripts/record-wakeword.sh 5            # Records for 5 seconds
#   ./scripts/record-wakeword.sh 3 my-voice   # Custom filename
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_AUDIO_DIR="${SCRIPT_DIR}/../audio"
DURATION="${1:-3}"
FILENAME="${2:-hey-jarvis-real}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

mkdir -p "${TEST_AUDIO_DIR}"

OUTPUT_FILE="${TEST_AUDIO_DIR}/${FILENAME}.wav"

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Wake Word Recording Tool${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo -e "Output: ${GREEN}${OUTPUT_FILE}${NC}"
echo -e "Duration: ${YELLOW}${DURATION} seconds${NC}"
echo ""
echo -e "${YELLOW}Instructions:${NC}"
echo "  1. Make sure your microphone is working"
echo "  2. Wait for the countdown"
echo "  3. Say \"Hey Jarvis\" clearly into the microphone"
echo "  4. Speak naturally, not too loud, not too quiet"
echo ""

# Check for recording tools
RECORDER=""
if command -v sox &> /dev/null; then
    RECORDER="sox"
elif command -v rec &> /dev/null; then
    RECORDER="rec"
elif command -v ffmpeg &> /dev/null; then
    RECORDER="ffmpeg"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS - check for built-in tools
    if command -v afrecord &> /dev/null; then
        RECORDER="afrecord"
    fi
fi

if [ -z "$RECORDER" ]; then
    echo -e "${RED}ERROR: No audio recording tool found!${NC}"
    echo ""
    echo "Please install one of the following:"
    echo "  - sox: brew install sox"
    echo "  - ffmpeg: brew install ffmpeg"
    echo ""
    exit 1
fi

echo -e "Using recorder: ${GREEN}${RECORDER}${NC}"
echo ""

# Countdown
echo -e "${YELLOW}Get ready to say 'Hey Jarvis'...${NC}"
for i in 3 2 1; do
    echo -e "  ${i}..."
    sleep 1
done

echo ""
echo -e "${RED}>>> RECORDING NOW - Say 'Hey Jarvis' <<<${NC}"
echo ""

# Record based on available tool
case "$RECORDER" in
    sox|rec)
        # Sox/rec - most common
        rec -r 16000 -c 1 -b 16 "${OUTPUT_FILE}" trim 0 "${DURATION}" 2>/dev/null || \
        sox -d -r 16000 -c 1 -b 16 "${OUTPUT_FILE}" trim 0 "${DURATION}"
        ;;
    ffmpeg)
        # FFmpeg - use default audio input
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS uses avfoundation
            ffmpeg -f avfoundation -i ":0" -t "${DURATION}" -ar 16000 -ac 1 -y "${OUTPUT_FILE}" 2>/dev/null
        else
            # Linux uses pulse or alsa
            ffmpeg -f pulse -i default -t "${DURATION}" -ar 16000 -ac 1 -y "${OUTPUT_FILE}" 2>/dev/null || \
            ffmpeg -f alsa -i default -t "${DURATION}" -ar 16000 -ac 1 -y "${OUTPUT_FILE}" 2>/dev/null
        fi
        ;;
    afrecord)
        # macOS built-in (if available)
        afrecord -d 16 -c 1 -r 16000 -f 'WAVE' "${OUTPUT_FILE}" &
        sleep "${DURATION}"
        kill %1 2>/dev/null || true
        ;;
esac

echo ""
echo -e "${GREEN}>>> RECORDING COMPLETE <<<${NC}"
echo ""

# Verify the file
if [ -f "${OUTPUT_FILE}" ]; then
    SIZE=$(ls -lh "${OUTPUT_FILE}" | awk '{print $5}')
    echo -e "Saved: ${GREEN}${OUTPUT_FILE}${NC} (${SIZE})"

    # Show audio info if sox is available
    if command -v sox &> /dev/null; then
        echo ""
        echo "Audio info:"
        sox --i "${OUTPUT_FILE}" 2>/dev/null || true
    fi

    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  Next Steps${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    echo "1. Test the wake word detection:"
    echo "   docker run --rm -v \$(pwd)/test-audio:/workspace/test-audio openclaw-assistant \\"
    echo "     ./build/test-components --test-wakeword test-audio/${FILENAME}.wav"
    echo ""
    echo "2. Or run the full test suite with your recording:"
    echo "   Copy ${FILENAME}.wav to hey-jarvis.wav and rebuild Docker:"
    echo "   cp test-audio/${FILENAME}.wav test-audio/hey-jarvis.wav"
    echo "   docker build -t openclaw-assistant -f Dockerfile ."
    echo "   docker run --rm openclaw-assistant ./build/test-components --run-all"
    echo ""
else
    echo -e "${RED}ERROR: Recording failed!${NC}"
    exit 1
fi
