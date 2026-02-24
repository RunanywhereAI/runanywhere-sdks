#!/bin/bash
# =============================================================================
# run-tests-linux.sh - Build and run integration tests in a Linux Docker container
# =============================================================================
#
# Usage:
#   ./run-tests-linux.sh                  # Build Docker image + run all tests
#   ./run-tests-linux.sh --build-only     # Build image only (compile verification)
#   ./run-tests-linux.sh --download       # Download models on host first
#   ./run-tests-linux.sh --core           # Core tests only
#   ./run-tests-linux.sh --onnx           # ONNX backend tests (VAD, STT, TTS, WakeWord)
#   ./run-tests-linux.sh --llm            # LLM tests only
#   ./run-tests-linux.sh --agent          # Voice agent tests only
#
# Environment:
#   RAC_TEST_MODEL_DIR   Override model directory on host (mounted into container)
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
# Resolve paths
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAC_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DOCKER_IMAGE="rac-linux-tests"
MODEL_DIR="${RAC_TEST_MODEL_DIR:-${HOME}/.local/share/runanywhere/Models}"

# =============================================================================
# Parse arguments
# =============================================================================

BUILD_ONLY=false
DOWNLOAD_FIRST=false
TEST_FILTER=""

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --build-only)
            BUILD_ONLY=true
            shift
            ;;
        --download)
            DOWNLOAD_FIRST=true
            shift
            ;;
        --core)
            TEST_FILTER="test_core"
            shift
            ;;
        --onnx)
            TEST_FILTER="test_vad test_stt test_tts test_wakeword"
            shift
            ;;
        --llm)
            TEST_FILTER="test_llm"
            shift
            ;;
        --agent)
            TEST_FILTER="test_voice_agent"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --build-only   Build Docker image only (compile verification)"
            echo "  --download     Download models on host first, then run all tests"
            echo "  --core         Run core tests only (no models needed)"
            echo "  --onnx         Run ONNX backend tests (VAD, STT, TTS, WakeWord)"
            echo "  --llm          Run LLM tests only"
            echo "  --agent        Run voice agent tests only"
            echo "  --help         Show this help"
            echo ""
            echo "Environment:"
            echo "  RAC_TEST_MODEL_DIR   Override model directory on host"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# =============================================================================
# Prerequisites
# =============================================================================

print_header "runanywhere-commons Linux Tests (Docker)"

if ! command -v docker &> /dev/null; then
    print_error "Docker not found. Install Docker to run Linux tests."
    exit 1
fi

echo "RAC root:    ${RAC_ROOT}"
echo "Model dir:   ${MODEL_DIR}"
echo "Docker img:  ${DOCKER_IMAGE}"
echo ""

# =============================================================================
# Download models (optional)
# =============================================================================

if [ "${DOWNLOAD_FIRST}" = true ]; then
    print_step "Downloading test models on host..."
    "${SCRIPT_DIR}/download-test-models.sh"
    echo ""
fi

# =============================================================================
# Build Docker image
# =============================================================================

print_header "Building Docker Image"

print_step "Building ${DOCKER_IMAGE}..."
docker build -f "${RAC_ROOT}/tests/Dockerfile.linux-tests" -t "${DOCKER_IMAGE}" "${RAC_ROOT}"

print_ok "Docker image built"

if [ "${BUILD_ONLY}" = true ]; then
    echo ""
    echo "Build-only mode. Docker image '${DOCKER_IMAGE}' compiled successfully."
    exit 0
fi

# =============================================================================
# Run tests in container
# =============================================================================

print_header "Running Tests in Container"

# Build the test command
if [ -n "${TEST_FILTER}" ]; then
    TEST_CMD="cd /build/tests && for t in ${TEST_FILTER}; do if [ -x \"\$t\" ]; then echo \"Running \$t...\"; ./\$t --run-all; fi; done"
else
    TEST_CMD="cd /build/tests && for t in test_core test_vad test_stt test_tts test_wakeword test_llm test_voice_agent; do if [ -x \"\$t\" ]; then echo \"Running \$t...\"; ./\$t --run-all; fi; done"
fi

PASSED=0
FAILED=0
SKIPPED=0
FAILED_NAMES=""

# Run each test individually to get per-test pass/fail
ALL_TESTS="test_core test_vad test_stt test_tts test_wakeword test_llm test_voice_agent"
if [ -n "${TEST_FILTER}" ]; then
    ALL_TESTS="${TEST_FILTER}"
fi

for test_name in ${ALL_TESTS}; do
    echo -n "  Running ${test_name}... "

    if docker run --rm \
        -v "${MODEL_DIR}:/models:ro" \
        -e RAC_TEST_MODEL_DIR=/models \
        "${DOCKER_IMAGE}" \
        bash -c "cd /build/tests && [ -x '${test_name}' ] && ./${test_name} --run-all" > /dev/null 2>&1; then
        echo -e "${GREEN}PASS${NC}"
        PASSED=$((PASSED + 1))
    else
        # Check if binary exists
        EXISTS=$(docker run --rm "${DOCKER_IMAGE}" bash -c "[ -x '/build/tests/${test_name}' ] && echo yes || echo no" 2>/dev/null)
        if [ "${EXISTS}" = "no" ]; then
            echo -e "${YELLOW}SKIP${NC} (not built)"
            SKIPPED=$((SKIPPED + 1))
        else
            echo -e "${RED}FAIL${NC}"
            FAILED=$((FAILED + 1))
            FAILED_NAMES="${FAILED_NAMES} ${test_name}"

            # Re-run with output for debugging
            echo ""
            echo -e "  ${RED}--- ${test_name} output ---${NC}"
            docker run --rm \
                -v "${MODEL_DIR}:/models:ro" \
                -e RAC_TEST_MODEL_DIR=/models \
                "${DOCKER_IMAGE}" \
                bash -c "cd /build/tests && ./${test_name} --run-all" 2>&1 | sed 's/^/    /' || true
            echo -e "  ${RED}--- end ${test_name} ---${NC}"
            echo ""
        fi
    fi
done

# =============================================================================
# Summary
# =============================================================================

print_header "Test Summary (Linux Docker)"

TOTAL=$((PASSED + FAILED + SKIPPED))
echo "Total:   ${TOTAL}"
echo -e "Passed:  ${GREEN}${PASSED}${NC}"
echo -e "Failed:  ${RED}${FAILED}${NC}"
echo -e "Skipped: ${YELLOW}${SKIPPED}${NC}"

if [ "${FAILED}" -gt 0 ]; then
    echo ""
    print_error "Failed tests:${FAILED_NAMES}"
    exit 1
fi

echo ""
print_ok "All tests passed!"
