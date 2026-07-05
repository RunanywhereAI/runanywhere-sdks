#!/bin/bash
# Build and run integration tests for runanywhere-commons. See --help for options.

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMONS_ROOT="${RAC_ROOT}/sdk/runanywhere-commons"
BUILD_DIR="${COMMONS_ROOT}/build/test"
TEST_BIN_DIR="${BUILD_DIR}/tests"

if command -v sysctl &> /dev/null; then
    NPROC=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
else
    NPROC=$(nproc 2>/dev/null || echo 4)
fi

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

echo "Commons root: ${COMMONS_ROOT}"
echo "Build dir:    ${BUILD_DIR}"
echo "Parallelism:  ${NPROC} jobs"
echo ""

if [ "${DOWNLOAD_FIRST}" = true ]; then
    print_step "Downloading test models..."
    "${SCRIPT_DIR}/download-test-models.sh"
    echo ""
fi

print_header "Building Tests"

print_step "Configuring CMake..."
cmake -B "${BUILD_DIR}" -S "${COMMONS_ROOT}" \
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

print_header "Running Tests"

PASSED=0
FAILED=0
SKIPPED=0
FAILED_NAMES=""

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

        echo ""
        echo -e "  ${RED}--- ${name} output ---${NC}"
        "${binary_path}" --run-all 2>&1 | sed 's/^/    /' || true
        echo -e "  ${RED}--- end ${name} ---${NC}"
        echo ""
    fi
}

if [ "${RUN_ALL}" = true ] || [ "${RUN_CORE}" = true ]; then
    echo "Core:"
    run_test "test_core" "test_core"
fi

if [ "${RUN_ALL}" = true ] || [ "${RUN_ONNX}" = true ]; then
    echo ""
    echo "ONNX backend:"
    run_test "test_vad"      "test_vad"
    run_test "test_stt"      "test_stt"
    run_test "test_tts"      "test_tts"
    run_test "test_wakeword" "test_wakeword"
fi

if [ "${RUN_ALL}" = true ] || [ "${RUN_LLM}" = true ]; then
    echo ""
    echo "LLM:"
    run_test "test_llm" "test_llm"
fi

if [ "${RUN_ALL}" = true ] || [ "${RUN_AGENT}" = true ]; then
    echo ""
    echo "Voice agent:"
    run_test "test_voice_agent" "test_voice_agent"
fi

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
