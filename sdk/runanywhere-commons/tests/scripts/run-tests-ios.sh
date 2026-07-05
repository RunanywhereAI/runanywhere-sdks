#!/bin/bash
# =============================================================================
# run-tests-ios.sh - iOS build verification + macOS native test execution
# =============================================================================
#
# Usage:
#   ./run-tests-ios.sh                  # Cross-compile for iOS Simulator (verify)
#   ./run-tests-ios.sh --build-only     # Same as default (compile verification)
#   ./run-tests-ios.sh --run            # Build natively for macOS and run tests
#   ./run-tests-ios.sh --run --download # Download models first, then run
#   ./run-tests-ios.sh --run --core     # Core tests only
#   ./run-tests-ios.sh --run --onnx     # ONNX backend tests
#   ./run-tests-ios.sh --run --llm      # LLM tests only
#   ./run-tests-ios.sh --run --agent    # Voice agent tests only
#
# Notes:
#   Default mode cross-compiles for iOS Simulator arm64 to verify no
#   iOS-specific compile/link errors. iOS Simulator can't run plain C++
#   executables (requires app bundles), so --run builds and runs natively
#   on macOS, which is functionally equivalent for the C++ backend tests.
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

# Load centralized versions
source "${RAC_ROOT}/scripts/load-versions.sh"

IOS_BUILD_DIR="${RAC_ROOT}/build/ios-test"
MACOS_BUILD_DIR="${RAC_ROOT}/build/test"
TEST_BIN_DIR="${MACOS_BUILD_DIR}/tests"

# Detect CPU count
NPROC=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)

# =============================================================================
# Parse arguments
# =============================================================================

BUILD_ONLY=true
RUN_TESTS=false
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
            RUN_TESTS=false
            shift
            ;;
        --run)
            RUN_TESTS=true
            BUILD_ONLY=false
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
            echo "  --build-only   Cross-compile for iOS Simulator (default)"
            echo "  --run          Build natively for macOS and run tests"
            echo "  --download     Download models first, then run"
            echo "  --core         Run core tests only"
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

# =============================================================================
# Prerequisites
# =============================================================================

print_header "runanywhere-commons iOS Tests"

if ! command -v cmake &> /dev/null; then
    print_error "cmake not found. Install with: brew install cmake"
    exit 1
fi

if ! command -v xcodebuild &> /dev/null; then
    print_error "Xcode not found. Install Xcode from the App Store."
    exit 1
fi

echo "RAC root:       ${RAC_ROOT}"
echo "iOS build dir:  ${IOS_BUILD_DIR}"
echo "macOS build dir: ${MACOS_BUILD_DIR}"
echo "Parallelism:    ${NPROC} jobs"
echo ""

# =============================================================================
# iOS Simulator cross-compile (build verification)
# =============================================================================

print_header "iOS Simulator Build Verification"

echo -e "${YELLOW}NOTE: iOS Simulator cross-compilation is for build verification only.${NC}"
echo -e "${YELLOW}      Simulator builds may have xcframework slice issues that don't${NC}"
echo -e "${YELLOW}      affect real device builds. Use --run for macOS-native execution.${NC}"
echo ""

TOOLCHAIN_FILE="${RAC_ROOT}/cmake/ios.toolchain.cmake"
if [ ! -f "${TOOLCHAIN_FILE}" ]; then
    print_error "iOS toolchain not found at: ${TOOLCHAIN_FILE}"
    exit 1
fi

print_step "Configuring CMake for iOS Simulator arm64..."
cmake -B "${IOS_BUILD_DIR}" -S "${RAC_ROOT}" \
    -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN_FILE}" \
    -DIOS_PLATFORM=SIMULATORARM64 \
    -DIOS_DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET:-13.0}" \
    -DCMAKE_BUILD_TYPE=Debug \
    -DRAC_BUILD_TESTS=ON \
    -DRAC_BUILD_BACKENDS=ON \
    -DRAC_BUILD_PLATFORM=OFF \
    -DRAC_BUILD_SHARED=OFF \
    -DRAC_BUILD_JNI=OFF \
    -DGGML_BLAS=OFF

print_step "Building for iOS Simulator (${NPROC} jobs)..."
cmake --build "${IOS_BUILD_DIR}" -j"${NPROC}"

print_ok "iOS Simulator build verification passed"

# Report which targets compiled
# iOS toolchain may create .app bundles instead of bare executables
echo ""
echo "iOS Simulator test targets:"
for binary in test_core test_vad test_stt test_tts test_wakeword test_llm test_voice_agent; do
    if [ -f "${IOS_BUILD_DIR}/tests/${binary}" ] || [ -f "${IOS_BUILD_DIR}/tests/${binary}.app/${binary}" ]; then
        echo -e "  ${GREEN}[OK]${NC} ${binary}"
    else
        echo -e "  ${YELLOW}[--]${NC} ${binary} (not built)"
    fi
done

if [ "${BUILD_ONLY}" = true ] && [ "${RUN_TESTS}" = false ]; then
    echo ""
    echo "Build-only mode. iOS Simulator cross-compilation verified."
    echo "Use --run to also build and run tests natively on macOS."
    exit 0
fi

# =============================================================================
# macOS native build + test execution
# =============================================================================

print_header "macOS Native Build + Test Execution"

if [ "${DOWNLOAD_FIRST}" = true ]; then
    print_step "Downloading test models..."
    "${SCRIPT_DIR}/download-test-models.sh"
    echo ""
fi

print_step "Configuring CMake for macOS native..."
cmake -B "${MACOS_BUILD_DIR}" -S "${RAC_ROOT}" \
    -DRAC_BUILD_TESTS=ON \
    -DRAC_BUILD_BACKENDS=ON \
    -DCMAKE_BUILD_TYPE=Debug

print_step "Building (${NPROC} jobs)..."
cmake --build "${MACOS_BUILD_DIR}" -j"${NPROC}"

print_ok "macOS native build complete"

# =============================================================================
# Run tests
# =============================================================================

print_header "Running Tests (macOS native)"

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

# Core tests
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

print_header "Test Summary (iOS verification + macOS execution)"

TOTAL=$((PASSED + FAILED + SKIPPED))
echo "Total:   ${TOTAL}"
echo -e "Passed:  ${GREEN}${PASSED}${NC}"
echo -e "Failed:  ${RED}${FAILED}${NC}"
echo -e "Skipped: ${YELLOW}${SKIPPED}${NC}"
echo ""
echo "iOS Simulator:  cross-compile verified"
echo "macOS native:   ${PASSED} passed, ${FAILED} failed"

if [ "${FAILED}" -gt 0 ]; then
    echo ""
    print_error "Failed tests:${FAILED_NAMES}"
    exit 1
fi

echo ""
print_ok "All tests passed!"
