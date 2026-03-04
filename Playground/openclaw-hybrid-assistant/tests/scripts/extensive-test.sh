#!/bin/bash

# =============================================================================
# extensive-test.sh - Run comprehensive wake word and pipeline tests
# =============================================================================
# This script generates additional edge case audio files and runs an
# extensive test suite to validate wake word detection accuracy.
# =============================================================================

# Don't exit on error - we want to run all tests even if some fail
# set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/../.."
TEST_AUDIO_DIR="${SCRIPT_DIR}/../audio"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${BOLD}================================================================${NC}"
echo -e "${BOLD}     EXTENSIVE WAKE WORD DETECTION TEST SUITE${NC}"
echo -e "${BOLD}================================================================${NC}"
echo ""

# Find TTS command
TTS_CMD=""
if command -v espeak-ng &> /dev/null; then
    TTS_CMD="espeak-ng"
elif command -v espeak &> /dev/null; then
    TTS_CMD="espeak"
fi

# Convert to 16kHz mono 16-bit WAV
convert_to_16k() {
    local input="$1"
    local output="$2"
    if command -v sox &> /dev/null; then
        sox "$input" -r 16000 -c 1 -b 16 "$output" 2>/dev/null || cp "$input" "$output"
    elif command -v ffmpeg &> /dev/null; then
        ffmpeg -i "$input" -ar 16000 -ac 1 -sample_fmt s16 -y "$output" 2>/dev/null || cp "$input" "$output"
    fi
}

# =============================================================================
# Generate additional edge case audio files
# =============================================================================

echo -e "${CYAN}Generating additional edge case audio files...${NC}"
echo ""

mkdir -p "${TEST_AUDIO_DIR}/edge-cases"

# Generate various "Hey Jarvis" variations
if [ -n "$TTS_CMD" ]; then
    echo -e "${YELLOW}Creating variations of 'Hey Jarvis'...${NC}"

    # Slow "Hey Jarvis"
    $TTS_CMD -w "${TEST_AUDIO_DIR}/edge-cases/hey-jarvis-slow_raw.wav" -s 90 -p 50 "Hey Jarvis"
    convert_to_16k "${TEST_AUDIO_DIR}/edge-cases/hey-jarvis-slow_raw.wav" "${TEST_AUDIO_DIR}/edge-cases/hey-jarvis-slow.wav"
    rm -f "${TEST_AUDIO_DIR}/edge-cases/hey-jarvis-slow_raw.wav"
    echo "  Created: hey-jarvis-slow.wav"

    # Fast "Hey Jarvis"
    $TTS_CMD -w "${TEST_AUDIO_DIR}/edge-cases/hey-jarvis-fast_raw.wav" -s 200 -p 50 "Hey Jarvis"
    convert_to_16k "${TEST_AUDIO_DIR}/edge-cases/hey-jarvis-fast_raw.wav" "${TEST_AUDIO_DIR}/edge-cases/hey-jarvis-fast.wav"
    rm -f "${TEST_AUDIO_DIR}/edge-cases/hey-jarvis-fast_raw.wav"
    echo "  Created: hey-jarvis-fast.wav"

    # High pitch "Hey Jarvis"
    $TTS_CMD -w "${TEST_AUDIO_DIR}/edge-cases/hey-jarvis-high_raw.wav" -s 130 -p 80 "Hey Jarvis"
    convert_to_16k "${TEST_AUDIO_DIR}/edge-cases/hey-jarvis-high_raw.wav" "${TEST_AUDIO_DIR}/edge-cases/hey-jarvis-high.wav"
    rm -f "${TEST_AUDIO_DIR}/edge-cases/hey-jarvis-high_raw.wav"
    echo "  Created: hey-jarvis-high.wav"

    # Low pitch "Hey Jarvis"
    $TTS_CMD -w "${TEST_AUDIO_DIR}/edge-cases/hey-jarvis-low_raw.wav" -s 130 -p 20 "Hey Jarvis"
    convert_to_16k "${TEST_AUDIO_DIR}/edge-cases/hey-jarvis-low_raw.wav" "${TEST_AUDIO_DIR}/edge-cases/hey-jarvis-low.wav"
    rm -f "${TEST_AUDIO_DIR}/edge-cases/hey-jarvis-low_raw.wav"
    echo "  Created: hey-jarvis-low.wav"

    # "Hey Jarvis" repeated 3 times
    $TTS_CMD -w "${TEST_AUDIO_DIR}/edge-cases/hey-jarvis-repeat_raw.wav" -s 130 "Hey Jarvis. Hey Jarvis. Hey Jarvis."
    convert_to_16k "${TEST_AUDIO_DIR}/edge-cases/hey-jarvis-repeat_raw.wav" "${TEST_AUDIO_DIR}/edge-cases/hey-jarvis-repeat.wav"
    rm -f "${TEST_AUDIO_DIR}/edge-cases/hey-jarvis-repeat_raw.wav"
    echo "  Created: hey-jarvis-repeat.wav"

    # Similar sounding phrases that should NOT trigger
    echo -e "${YELLOW}Creating similar-sounding phrases (should NOT trigger)...${NC}"

    $TTS_CMD -w "${TEST_AUDIO_DIR}/edge-cases/hey-travis_raw.wav" -s 130 "Hey Travis"
    convert_to_16k "${TEST_AUDIO_DIR}/edge-cases/hey-travis_raw.wav" "${TEST_AUDIO_DIR}/edge-cases/hey-travis.wav"
    rm -f "${TEST_AUDIO_DIR}/edge-cases/hey-travis_raw.wav"
    echo "  Created: hey-travis.wav"

    $TTS_CMD -w "${TEST_AUDIO_DIR}/edge-cases/hey-service_raw.wav" -s 130 "Hey service"
    convert_to_16k "${TEST_AUDIO_DIR}/edge-cases/hey-service_raw.wav" "${TEST_AUDIO_DIR}/edge-cases/hey-service.wav"
    rm -f "${TEST_AUDIO_DIR}/edge-cases/hey-service_raw.wav"
    echo "  Created: hey-service.wav"

    $TTS_CMD -w "${TEST_AUDIO_DIR}/edge-cases/hey-marcus_raw.wav" -s 130 "Hey Marcus"
    convert_to_16k "${TEST_AUDIO_DIR}/edge-cases/hey-marcus_raw.wav" "${TEST_AUDIO_DIR}/edge-cases/hey-marcus.wav"
    rm -f "${TEST_AUDIO_DIR}/edge-cases/hey-marcus_raw.wav"
    echo "  Created: hey-marcus.wav"

    $TTS_CMD -w "${TEST_AUDIO_DIR}/edge-cases/jarvis-only_raw.wav" -s 130 "Jarvis"
    convert_to_16k "${TEST_AUDIO_DIR}/edge-cases/jarvis-only_raw.wav" "${TEST_AUDIO_DIR}/edge-cases/jarvis-only.wav"
    rm -f "${TEST_AUDIO_DIR}/edge-cases/jarvis-only_raw.wav"
    echo "  Created: jarvis-only.wav"

    $TTS_CMD -w "${TEST_AUDIO_DIR}/edge-cases/hey-only_raw.wav" -s 130 "Hey"
    convert_to_16k "${TEST_AUDIO_DIR}/edge-cases/hey-only_raw.wav" "${TEST_AUDIO_DIR}/edge-cases/hey-only.wav"
    rm -f "${TEST_AUDIO_DIR}/edge-cases/hey-only_raw.wav"
    echo "  Created: hey-only.wav"

    # Commands without wake word (should NOT trigger wake word)
    echo -e "${YELLOW}Creating commands without wake word...${NC}"

    $TTS_CMD -w "${TEST_AUDIO_DIR}/edge-cases/weather-command_raw.wav" -s 150 "What is the weather like today"
    convert_to_16k "${TEST_AUDIO_DIR}/edge-cases/weather-command_raw.wav" "${TEST_AUDIO_DIR}/edge-cases/weather-command.wav"
    rm -f "${TEST_AUDIO_DIR}/edge-cases/weather-command_raw.wav"
    echo "  Created: weather-command.wav"

    $TTS_CMD -w "${TEST_AUDIO_DIR}/edge-cases/time-command_raw.wav" -s 150 "What time is it"
    convert_to_16k "${TEST_AUDIO_DIR}/edge-cases/time-command_raw.wav" "${TEST_AUDIO_DIR}/edge-cases/time-command.wav"
    rm -f "${TEST_AUDIO_DIR}/edge-cases/time-command_raw.wav"
    echo "  Created: time-command.wav"
fi

# Generate noise variants
echo -e "${YELLOW}Creating noise variants...${NC}"

if command -v sox &> /dev/null; then
    # Very loud noise
    sox -n -r 16000 -c 1 -b 16 "${TEST_AUDIO_DIR}/edge-cases/loud-noise.wav" synth 3.0 pinknoise vol 0.8
    echo "  Created: loud-noise.wav"

    # Very quiet noise
    sox -n -r 16000 -c 1 -b 16 "${TEST_AUDIO_DIR}/edge-cases/quiet-noise.wav" synth 3.0 pinknoise vol 0.05
    echo "  Created: quiet-noise.wav"

    # Brown noise
    sox -n -r 16000 -c 1 -b 16 "${TEST_AUDIO_DIR}/edge-cases/brown-noise.wav" synth 3.0 brownnoise vol 0.3
    echo "  Created: brown-noise.wav"

    # Tone (pure sine wave)
    sox -n -r 16000 -c 1 -b 16 "${TEST_AUDIO_DIR}/edge-cases/tone-1khz.wav" synth 3.0 sine 1000 vol 0.3
    echo "  Created: tone-1khz.wav"
fi

echo ""
echo -e "${CYAN}Running comprehensive test suite...${NC}"
echo ""

# =============================================================================
# Run Tests
# =============================================================================

PASS_COUNT=0
FAIL_COUNT=0

run_wakeword_test() {
    local file="$1"
    local expect_detection="$2"  # "yes" or "no"
    local description="$3"

    # Run the test - use the appropriate test flag
    if [ "$expect_detection" == "yes" ]; then
        output=$(./build/test-components --test-wakeword "$file" 2>&1)
    else
        output=$(./build/test-components --test-no-wakeword "$file" 2>&1)
    fi

    # Check if test passed (look for PASS in the TEST RESULTS section)
    confidence=$(echo "$output" | grep -o "max conf=[0-9.]*" | head -1 | cut -d= -f2)

    if echo "$output" | grep -q "✅ PASS"; then
        echo -e "${GREEN}✅ PASS${NC}: $description"
        echo "         File: $(basename $file), conf=$confidence"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${RED}❌ FAIL${NC}: $description"
        echo "         File: $(basename $file), conf=$confidence"
        # Show actual result
        actual=$(echo "$output" | grep "Actual:" | head -1)
        if [ -n "$actual" ]; then
            echo "         $actual"
        fi
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

echo -e "${BOLD}--- Wake Word Detection Tests (Should DETECT) ---${NC}"
echo ""

# Tests that SHOULD detect wake word
run_wakeword_test "tests/audio/hey-jarvis.wav" "yes" "Standard TTS 'Hey Jarvis'"

if [ -f "tests/audio/hey-jarvis-amplified.wav" ]; then
    run_wakeword_test "tests/audio/hey-jarvis-amplified.wav" "yes" "User recorded 'Hey Jarvis' (amplified)"
fi

if [ -f "tests/audio/hey-jarvis-real.wav" ]; then
    run_wakeword_test "tests/audio/hey-jarvis-real.wav" "yes" "User recorded 'Hey Jarvis' (original)"
fi

run_wakeword_test "tests/audio/edge-cases/hey-jarvis-slow.wav" "yes" "Slow 'Hey Jarvis'"
run_wakeword_test "tests/audio/edge-cases/hey-jarvis-fast.wav" "yes" "Fast 'Hey Jarvis'"
run_wakeword_test "tests/audio/edge-cases/hey-jarvis-high.wav" "yes" "High pitch 'Hey Jarvis'"
run_wakeword_test "tests/audio/edge-cases/hey-jarvis-low.wav" "yes" "Low pitch 'Hey Jarvis'"
run_wakeword_test "tests/audio/edge-cases/hey-jarvis-repeat.wav" "yes" "Repeated 'Hey Jarvis' (3x)"

if [ -f "tests/audio/delayed-wakeword.wav" ]; then
    run_wakeword_test "tests/audio/delayed-wakeword.wav" "yes" "Delayed 'Hey Jarvis' (2s silence first)"
fi

if [ -f "tests/audio/multiple-wakewords.wav" ]; then
    run_wakeword_test "tests/audio/multiple-wakewords.wav" "yes" "Multiple 'Hey Jarvis'"
fi

echo ""
echo -e "${BOLD}--- Wake Word Rejection Tests (Should NOT detect) ---${NC}"
echo ""

# Tests that should NOT detect wake word
run_wakeword_test "tests/audio/silence.wav" "no" "Silence"
run_wakeword_test "tests/audio/noise.wav" "no" "Pink noise"
run_wakeword_test "tests/audio/white-noise.wav" "no" "White noise"
run_wakeword_test "tests/audio/random-words.wav" "no" "Random words"
run_wakeword_test "tests/audio/similar-words.wav" "no" "Similar words (Travis, Marcus, etc)"
run_wakeword_test "tests/audio/speech.wav" "no" "Speech without wake word"

run_wakeword_test "tests/audio/edge-cases/hey-travis.wav" "no" "Hey Travis (similar)"
run_wakeword_test "tests/audio/edge-cases/hey-service.wav" "no" "Hey service (similar)"
run_wakeword_test "tests/audio/edge-cases/hey-marcus.wav" "no" "Hey Marcus (similar)"
run_wakeword_test "tests/audio/edge-cases/jarvis-only.wav" "no" "Just 'Jarvis' (no Hey)"
run_wakeword_test "tests/audio/edge-cases/hey-only.wav" "no" "Just 'Hey' (no Jarvis)"
run_wakeword_test "tests/audio/edge-cases/weather-command.wav" "no" "Weather command (no wake word)"
run_wakeword_test "tests/audio/edge-cases/time-command.wav" "no" "Time command (no wake word)"
run_wakeword_test "tests/audio/edge-cases/loud-noise.wav" "no" "Loud pink noise"
run_wakeword_test "tests/audio/edge-cases/quiet-noise.wav" "no" "Quiet pink noise"
run_wakeword_test "tests/audio/edge-cases/brown-noise.wav" "no" "Brown noise"
run_wakeword_test "tests/audio/edge-cases/tone-1khz.wav" "no" "1kHz tone"

# =============================================================================
# Summary
# =============================================================================

echo ""
echo -e "${BOLD}================================================================${NC}"
echo -e "${BOLD}                    TEST RESULTS SUMMARY${NC}"
echo -e "${BOLD}================================================================${NC}"
echo ""

TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}${BOLD}ALL TESTS PASSED!${NC}"
else
    echo -e "${RED}${BOLD}SOME TESTS FAILED${NC}"
fi

echo ""
echo "  Passed: ${PASS_COUNT}/${TOTAL}"
echo "  Failed: ${FAIL_COUNT}/${TOTAL}"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}Wake word detection is working correctly!${NC}"
    echo "Ready for demo."
    exit 0
else
    echo -e "${YELLOW}Review failed tests above.${NC}"
    exit 1
fi
