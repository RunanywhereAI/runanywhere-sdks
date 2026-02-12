#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# RunAnywhere Web SDK - WASM Build Script
# =============================================================================
#
# Builds RACommons + platform shims to WebAssembly using Emscripten.
#
# Usage:
#   ./scripts/build.sh              # Release build
#   ./scripts/build.sh --debug      # Debug build with assertions
#   ./scripts/build.sh --pthreads   # Enable multi-threading
#   ./scripts/build.sh --clean      # Clean before building
#   ./scripts/build.sh --help       # Show help
#
# Prerequisites:
#   - Emscripten SDK (emsdk) installed and activated
#   - CMake 3.22+
#
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WASM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${WASM_DIR}/build"
OUTPUT_DIR="${WASM_DIR}/../packages/core/wasm"

# Defaults
BUILD_TYPE="Release"
PTHREADS="OFF"
DEBUG="OFF"
LLAMACPP="OFF"
WHISPERCPP="OFF"
ONNX="OFF"
CLEAN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --debug)
            BUILD_TYPE="Debug"
            DEBUG="ON"
            shift
            ;;
        --pthreads)
            PTHREADS="ON"
            shift
            ;;
        --llamacpp)
            LLAMACPP="ON"
            shift
            ;;
        --whispercpp)
            WHISPERCPP="ON"
            shift
            ;;
        --onnx)
            ONNX="ON"
            shift
            ;;
        --all-backends)
            LLAMACPP="ON"
            WHISPERCPP="ON"
            ONNX="ON"
            shift
            ;;
        --clean)
            CLEAN=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --debug          Debug build with assertions and safe heap"
            echo "  --pthreads       Enable pthreads (requires Cross-Origin Isolation)"
            echo "  --llamacpp       Include llama.cpp LLM backend"
            echo "  --whispercpp     Include whisper.cpp STT backend"
            echo "  --onnx           Include sherpa-onnx TTS/VAD backend"
            echo "  --all-backends   Enable all backends (llama.cpp + whisper.cpp + onnx)"
            echo "  --clean          Clean build directory before building"
            echo "  --help           Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check Emscripten
if ! command -v emcmake &> /dev/null; then
    echo "ERROR: Emscripten not found. Please install and activate emsdk:"
    echo "  ./scripts/setup-emsdk.sh"
    echo "  source <emsdk-path>/emsdk_env.sh"
    exit 1
fi

echo "======================================"
echo " RunAnywhere Web SDK - WASM Build"
echo "======================================"
echo " Build type:   ${BUILD_TYPE}"
echo " pthreads:     ${PTHREADS}"
echo " llama.cpp:    ${LLAMACPP}"
echo " whisper.cpp:  ${WHISPERCPP}"
echo " sherpa-onnx:  ${ONNX}"
echo " Debug:        ${DEBUG}"
echo " Build dir:    ${BUILD_DIR}"
echo " Output dir:   ${OUTPUT_DIR}"
echo "======================================"

# Clean if requested
if [ "$CLEAN" = true ]; then
    echo "Cleaning build directory..."
    rm -rf "${BUILD_DIR}"
fi

# Create build directory
mkdir -p "${BUILD_DIR}"

# Configure with Emscripten
echo ""
echo ">>> Configuring CMake with Emscripten..."
emcmake cmake \
    -B "${BUILD_DIR}" \
    -S "${WASM_DIR}" \
    -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
    -DRAC_WASM_PTHREADS="${PTHREADS}" \
    -DRAC_WASM_DEBUG="${DEBUG}" \
    -DRAC_WASM_LLAMACPP="${LLAMACPP}" \
    -DRAC_WASM_WHISPERCPP="${WHISPERCPP}" \
    -DRAC_WASM_ONNX="${ONNX}"

# Build
echo ""
echo ">>> Building WASM module..."
emmake cmake --build "${BUILD_DIR}" --parallel

# Verify outputs
echo ""
echo ">>> Verifying outputs..."

WASM_FILE="${OUTPUT_DIR}/racommons.wasm"
JS_FILE="${OUTPUT_DIR}/racommons.js"

if [ -f "${WASM_FILE}" ] && [ -f "${JS_FILE}" ]; then
    WASM_SIZE=$(du -h "${WASM_FILE}" | cut -f1)
    JS_SIZE=$(du -h "${JS_FILE}" | cut -f1)
    echo "SUCCESS: WASM build complete"
    echo "  racommons.wasm: ${WASM_SIZE}"
    echo "  racommons.js:   ${JS_SIZE}"

    if [ "$PTHREADS" = "ON" ] && [ -f "${OUTPUT_DIR}/racommons.worker.js" ]; then
        WORKER_SIZE=$(du -h "${OUTPUT_DIR}/racommons.worker.js" | cut -f1)
        echo "  racommons.worker.js: ${WORKER_SIZE}"
    fi
else
    echo "ERROR: Build outputs not found!"
    echo "  Expected: ${WASM_FILE}"
    echo "  Expected: ${JS_FILE}"
    exit 1
fi

echo ""
echo "WASM module ready at: ${OUTPUT_DIR}/"
