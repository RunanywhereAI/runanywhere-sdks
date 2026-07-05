#!/bin/bash
# =============================================================================
# run-tests.sh - Build and run integration tests for runanywhere-commons
# =============================================================================
#
# Usage:
#   ./run-tests.sh                  # Build + run all
#   ./run-tests.sh --build-only     # Build only
#   ./run-tests.sh --core           # Core tests only (no models needed)
#   ./run-tests.sh --onnx           # ONNX backend tests (VAD, STT, TTS, WakeWord)
#   ./run-tests.sh --llm            # LLM tests only
#   ./run-tests.sh --agent          # Voice agent tests only
#   ./run-tests.sh --download       # Download models first, then run all
#
# Environment:
#   RAC_TEST_MODEL_DIR   Override model directory for tests
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
BUILD_DIR="${RAC_ROOT}/build/test"
TEST_BIN_DIR="${BUILD_DIR}/tests"

# Detect CPU count
if command -v sysctl &> /dev/null; then
    NPROC=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
else
    NPROC=$(nproc 2>/dev/null || echo 4)
fi

# =============================================================================
# Parse arguments
# =============================================================================

BUILD_ONLY=false
DOWNLOAD_FIRST=false
RUN_CORE=false
RUN_ONNX=false
RUN_LLM=false
RUN_AGENT=false
RUN_ALL=true

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
            RUN_CORE=true
            RUN_ALL=false
            shift
            ;;
        --onnx)
            RUN_ONNX=true
            RUN_ALL=false
            shift
            ;;
        --llm)
            RUN_LLM=true
            RUN_ALL=false
            shift
            ;;
        --agent)
            RUN_AGENT=true
            RUN_ALL=false
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --build-only   Build tests without running them"
            echo "  --download     Download models first, then run all tests"
            echo "  --core         Run core tests only (no models needed)"
            echo "  --onnx         Run ONNX backend tests (VAD, STT, TTS, WakeWord)"
            echo "  --llm          Run LLM tests only"
            echo "  --agent        Run voice agent tests only"
            echo "  --help         Show this help"
            echo ""
            echo "Environment:"
            echo "  RAC_TEST_MODEL_DIR   Override model directory for tests"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

print_header "runanywhere-commons Integration Tests"

echo "RAC root:    ${RAC_ROOT}"
echo "Build dir:   ${BUILD_DIR}"
echo "Parallelism: ${NPROC} jobs"
echo ""

# =============================================================================
# Download models (optional)
# =============================================================================

if [ "${DOWNLOAD_FIRST}" = true ]; then
    print_step "Downloading test models..."
    "${SCRIPT_DIR}/download-test-models.sh"
    echo ""
fi

# =============================================================================
# Build
# =============================================================================

print_header "Building Tests"

print_step "Configuring CMake..."
cmake -B "${BUILD_DIR}" -S "${RAC_ROOT}" \
    -DRAC_BUILD_TESTS=ON \
    -DRAC_BUILD_BACKENDS=ON \
    -DCMAKE_BUILD_TYPE=Debug

print_step "Building (${NPROC} jobs)..."
cmake --build "${BUILD_DIR}" -j"${NPROC}"

print_ok "Build complete"

if [ "${BUILD_ONLY}" = true ]; then
    echo ""
    echo "Build-only mode. Test binaries are in: ${TEST_BIN_DIR}/"
    exit 0
fi

# =============================================================================
# Run tests
# =============================================================================

print_header "Running Tests"

PASSED=0
FAILED=0
SKIPPED=0
FAILED_NAMES=""

# Run a single test binary. Args: binary_name display_name
run_test() {
    local binary="$1"
    local name="$2"
    local binary_path="${TEST_BIN_DIR}/${binary}"

    if [ ! -f "${binary_path}" ]; then
        echo -e "  ${YELLOW}[SKIP]${NC} ${name} (not built)"
        SKIPPED=$((SKIPPED + 1))
        return 0
    fi

    echo -n "  Running ${name}... "
    if "${binary_path}" --run-all > /dev/null 2>&1; then
        echo -e "${GREEN}PASS${NC}"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}FAIL${NC}"
        FAILED=$((FAILED + 1))
        FAILED_NAMES="${FAILED_NAMES} ${name}"

        # Re-run with output visible for debugging
        echo ""
        echo -e "  ${RED}--- ${name} output ---${NC}"
        "${binary_path}" --run-all 2>&1 | sed 's/^/    /' || true
        echo -e "  ${RED}--- end ${name} ---${NC}"
        echo ""
    fi
}

# Core tests (always available)
if [ "${RUN_ALL}" = true ] || [ "${RUN_CORE}" = true ]; then
    echo "Core:"
    run_test "test_core" "test_core"
fi

# ONNX backend tests
if [ "${RUN_ALL}" = true ] || [ "${RUN_ONNX}" = true ]; then
    echo ""
    echo "ONNX backend:"
    run_test "test_vad"      "test_vad"
    run_test "test_stt"      "test_stt"
    run_test "test_tts"      "test_tts"
    run_test "test_wakeword" "test_wakeword"
fi

# LLM tests
if [ "${RUN_ALL}" = true ] || [ "${RUN_LLM}" = true ]; then
    echo ""
    echo "LLM:"
    run_test "test_llm" "test_llm"
fi

# Voice agent tests
if [ "${RUN_ALL}" = true ] || [ "${RUN_AGENT}" = true ]; then
    echo ""
    echo "Voice agent:"
    run_test "test_voice_agent" "test_voice_agent"
fi

# =============================================================================
# Summary
# =============================================================================

print_header "Test Summary"

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
