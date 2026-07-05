#!/bin/bash
# Cross-compile and run tests on Android device via adb. See --help for options.

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

COMMONS_ROOT="${RAC_ROOT}/sdk/runanywhere-commons"

source "${RAC_ROOT}/scripts/lib/load-versions.sh"

ABI="arm64-v8a"
BUILD_DIR="${COMMONS_ROOT}/build/android-test/${ABI}"
TEST_BIN_DIR="${BUILD_DIR}/tests"
DEVICE_TEST_DIR="/data/local/tmp/rac_tests"
MODEL_DIR="${RAC_TEST_MODEL_DIR:-${HOME}/.local/share/runanywhere/Models}"

if command -v sysctl &> /dev/null; then
    NPROC=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
else
    NPROC=$(nproc 2>/dev/null || echo 4)
fi

BUILD_ONLY=false
RUN_ON_DEVICE=false
PUSH_MODELS=false
DEVICE_MODELS=""
ADB_SERIAL=""
TEST_FILTER=""

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --build-only)
            BUILD_ONLY=true
            shift
            ;;
        --run)
            RUN_ON_DEVICE=true
            shift
            ;;
        --push-models)
            PUSH_MODELS=true
            shift
            ;;
        --device-models)
            DEVICE_MODELS="$2"
            shift 2
            ;;
        --serial)
            ADB_SERIAL="$2"
            shift 2
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
            echo "  --build-only       Cross-compile only (no device needed)"
            echo "  --run              Build + push + run tests on device"
            echo "  --push-models      Push models from host to device"
            echo "  --device-models D  Use models already at path D on device"
            echo "  --serial SERIAL    Use specific device (adb -s)"
            echo "  --core             Run core tests only"
            echo "  --onnx             Run ONNX backend tests (VAD, STT, TTS, WakeWord)"
            echo "  --llm              Run LLM tests only"
            echo "  --agent            Run voice agent tests only"
            echo "  --help             Show this help"
            echo ""
            echo "Environment:"
            echo "  ANDROID_NDK_HOME     Path to Android NDK"
            echo "  RAC_TEST_MODEL_DIR   Override model directory on host"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

print_header "runanywhere-commons Android Tests"

print_step "Finding Android NDK..."

if [ -z "${ANDROID_NDK_HOME:-}" ] && [ -z "${NDK_HOME:-}" ]; then
    if [ -d "$HOME/Library/Android/sdk/ndk" ]; then
        ANDROID_NDK_HOME=$(ls -d "$HOME/Library/Android/sdk/ndk"/*/ 2>/dev/null | sort -V | tail -1 || true)
    elif [ -d "$HOME/Android/Sdk/ndk" ]; then
        ANDROID_NDK_HOME=$(ls -d "$HOME/Android/Sdk/ndk"/*/ 2>/dev/null | sort -V | tail -1 || true)
    elif [ -d "${ANDROID_HOME:-}/ndk" ]; then
        ANDROID_NDK_HOME=$(ls -d "${ANDROID_HOME}/ndk"/*/ 2>/dev/null | sort -V | tail -1 || true)
    elif [ -d "${ANDROID_SDK_ROOT:-}/ndk" ]; then
        ANDROID_NDK_HOME=$(ls -d "${ANDROID_SDK_ROOT}/ndk"/*/ 2>/dev/null | sort -V | tail -1 || true)
    fi
fi

NDK_PATH="${ANDROID_NDK_HOME:-${NDK_HOME:-}}"
if [ -z "$NDK_PATH" ] || [ ! -d "$NDK_PATH" ]; then
    print_error "Android NDK not found. Set ANDROID_NDK_HOME environment variable."
    exit 1
fi

TOOLCHAIN_FILE="$NDK_PATH/build/cmake/android.toolchain.cmake"
if [ ! -f "$TOOLCHAIN_FILE" ]; then
    print_error "Android toolchain file not found at: $TOOLCHAIN_FILE"
    exit 1
fi

print_ok "Found Android NDK: $NDK_PATH"

ANDROID_API_LEVEL="${ANDROID_MIN_SDK:-24}"

echo "ABI:          ${ABI}"
echo "API Level:    ${ANDROID_API_LEVEL}"
echo "Build dir:    ${BUILD_DIR}"
echo "Parallelism:  ${NPROC} jobs"
echo ""

if [ ! -d "${COMMONS_ROOT}/third_party/sherpa-onnx-android/jniLibs" ]; then
    print_step "Sherpa-ONNX not found. Downloading..."
    "${RAC_ROOT}/scripts/build/deps/download-sherpa-onnx.sh"
fi
print_ok "Found Sherpa-ONNX Android prebuilts"

print_header "Cross-Compiling for ${ABI}"

echo -e "${YELLOW}NOTE: Emulator builds may encounter issues with shared library loading.${NC}"
echo -e "${YELLOW}      For reliable test execution, use --run with a real device connected.${NC}"
echo ""

print_step "Configuring CMake..."
cmake -B "${BUILD_DIR}" -S "${COMMONS_ROOT}" \
    -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN_FILE}" \
    -DANDROID_ABI="${ABI}" \
    -DANDROID_PLATFORM="android-${ANDROID_API_LEVEL}" \
    -DANDROID_STL=c++_shared \
    -DCMAKE_BUILD_TYPE=Debug \
    -DRAC_BUILD_TESTS=ON \
    -DRAC_BUILD_BACKENDS=ON \
    -DRAC_BUILD_SHARED=ON \
    -DRAC_BUILD_PLATFORM=OFF \
    -DRAC_BUILD_JNI=OFF

print_step "Building (${NPROC} jobs)..."
cmake --build "${BUILD_DIR}" -j"${NPROC}"

print_ok "Cross-compilation complete"

echo ""
echo "Test binaries:"
for binary in test_core test_vad test_stt test_tts test_wakeword test_llm test_voice_agent; do
    if [ -f "${TEST_BIN_DIR}/${binary}" ]; then
        echo -e "  ${GREEN}[OK]${NC} ${binary}"
    else
        echo -e "  ${YELLOW}[--]${NC} ${binary} (not built)"
    fi
done

if [ "${BUILD_ONLY}" = true ] || [ "${RUN_ON_DEVICE}" = false ]; then
    echo ""
    echo "Build complete. Test binaries are in: ${TEST_BIN_DIR}/"
    echo "Use --run to push and execute on a connected device."
    exit 0
fi

print_header "Pushing to Device"

ADB_CMD="adb"
if [ -n "${ADB_SERIAL}" ]; then
    ADB_CMD="adb -s ${ADB_SERIAL}"
fi

if ! command -v adb &> /dev/null; then
    print_error "adb not found. Install Android SDK platform-tools."
    exit 1
fi

if ! ${ADB_CMD} get-state &> /dev/null; then
    print_error "No device connected. Connect a device or use --serial."
    exit 1
fi
print_ok "Device connected"

${ADB_CMD} shell "rm -rf ${DEVICE_TEST_DIR} && mkdir -p ${DEVICE_TEST_DIR}/bin ${DEVICE_TEST_DIR}/lib"

print_step "Pushing test binaries..."
for binary in test_core test_vad test_stt test_tts test_wakeword test_llm test_voice_agent; do
    if [ -f "${TEST_BIN_DIR}/${binary}" ]; then
        ${ADB_CMD} push "${TEST_BIN_DIR}/${binary}" "${DEVICE_TEST_DIR}/bin/" > /dev/null
        ${ADB_CMD} shell "chmod +x ${DEVICE_TEST_DIR}/bin/${binary}"
        echo "  Pushed: ${binary}"
    fi
done

print_step "Pushing shared libraries..."

if [ -f "${BUILD_DIR}/librac_commons.so" ]; then
    ${ADB_CMD} push "${BUILD_DIR}/librac_commons.so" "${DEVICE_TEST_DIR}/lib/" > /dev/null
    echo "  Pushed: librac_commons.so"
fi

for backend_dir in onnx llamacpp; do
    for lib in "${BUILD_DIR}/engines/${backend_dir}"/librac_backend_*.so; do
        if [ -f "$lib" ]; then
            ${ADB_CMD} push "$lib" "${DEVICE_TEST_DIR}/lib/" > /dev/null
            echo "  Pushed: $(basename "$lib")"
        fi
    done
done

SHERPA_LIBS="${COMMONS_ROOT}/third_party/sherpa-onnx-android/jniLibs/${ABI}"
if [ -d "${SHERPA_LIBS}" ]; then
    for lib in "${SHERPA_LIBS}"/*.so; do
        if [ -f "$lib" ]; then
            ${ADB_CMD} push "$lib" "${DEVICE_TEST_DIR}/lib/" > /dev/null
            echo "  Pushed: $(basename "$lib") (sherpa-onnx)"
        fi
    done
fi

PREBUILT_DIR=$(ls -d "$NDK_PATH/toolchains/llvm/prebuilt"/*/ 2>/dev/null | head -1 || true)
if [ -n "$PREBUILT_DIR" ]; then
    LIBCXX=$(find "$PREBUILT_DIR/sysroot/usr/lib" -name "libc++_shared.so" -path "*aarch64*" 2>/dev/null | head -1)
    if [ -n "$LIBCXX" ] && [ -f "$LIBCXX" ]; then
        ${ADB_CMD} push "$LIBCXX" "${DEVICE_TEST_DIR}/lib/" > /dev/null
        echo "  Pushed: libc++_shared.so"
    fi
fi

print_ok "Libraries pushed"

DEVICE_MODEL_DIR="${DEVICE_MODELS:-${DEVICE_TEST_DIR}/models}"

if [ "${PUSH_MODELS}" = true ]; then
    print_step "Pushing models to device (this may take a while)..."
    ${ADB_CMD} shell "mkdir -p ${DEVICE_MODEL_DIR}"
    ${ADB_CMD} push "${MODEL_DIR}/." "${DEVICE_MODEL_DIR}/" > /dev/null 2>&1 || {
        print_error "Failed to push models. Check ${MODEL_DIR} exists."
        exit 1
    }
    print_ok "Models pushed to ${DEVICE_MODEL_DIR}"
fi

print_header "Running Tests on Device"

PASSED=0
FAILED=0
SKIPPED=0
FAILED_NAMES=""

ALL_TESTS="test_core test_vad test_stt test_tts test_wakeword test_llm test_voice_agent"
if [ -n "${TEST_FILTER}" ]; then
    ALL_TESTS="${TEST_FILTER}"
fi

for test_name in ${ALL_TESTS}; do
    echo -n "  Running ${test_name}... "

    EXISTS=$(${ADB_CMD} shell "[ -x '${DEVICE_TEST_DIR}/bin/${test_name}' ] && echo yes || echo no" 2>/dev/null | tr -d '\r')
    if [ "${EXISTS}" != "yes" ]; then
        echo -e "${YELLOW}SKIP${NC} (not built)"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    if ${ADB_CMD} shell "cd ${DEVICE_TEST_DIR} && \
        LD_LIBRARY_PATH=${DEVICE_TEST_DIR}/lib \
        RAC_TEST_MODEL_DIR=${DEVICE_MODEL_DIR} \
        ./bin/${test_name} --run-all" > /dev/null 2>&1; then
        echo -e "${GREEN}PASS${NC}"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}FAIL${NC}"
        FAILED=$((FAILED + 1))
        FAILED_NAMES="${FAILED_NAMES} ${test_name}"

        echo ""
        echo -e "  ${RED}--- ${test_name} output ---${NC}"
        ${ADB_CMD} shell "cd ${DEVICE_TEST_DIR} && \
            LD_LIBRARY_PATH=${DEVICE_TEST_DIR}/lib \
            RAC_TEST_MODEL_DIR=${DEVICE_MODEL_DIR} \
            ./bin/${test_name} --run-all" 2>&1 | sed 's/^/    /' || true
        echo -e "  ${RED}--- end ${test_name} ---${NC}"
        echo ""
    fi
done

print_header "Test Summary (Android ${ABI})"

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
