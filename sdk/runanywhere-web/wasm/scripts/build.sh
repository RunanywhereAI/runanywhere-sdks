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
REPO_ROOT="$(cd "${WASM_DIR}/../../.." && pwd)"
OUTPUT_DIR="${WASM_DIR}/../packages/llamacpp/wasm"

# Defaults
BUILD_TYPE="Release"
PTHREADS="OFF"
DEBUG="OFF"
LLAMACPP="OFF"
VLM="OFF"
WHISPERCPP="OFF"
ONNX="OFF"
WEBGPU="OFF"
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
        --vlm)
            VLM="ON"
            LLAMACPP="ON"  # VLM requires llama.cpp
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
        --webgpu)
            WEBGPU="ON"
            LLAMACPP="ON"  # WebGPU accelerates llama.cpp
            shift
            ;;
        --all-backends)
            LLAMACPP="ON"
            VLM="ON"
            # WhisperCPP excluded: v1.8.2 GGML API is incompatible with llama.cpp b8011+.
            # STT is handled by sherpa-onnx (separate WASM module via --build-sherpa).
            # ONNX excluded: requires native ONNX Runtime headers (not available for WASM).
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
            echo "  --vlm            Include VLM (Vision Language Model) via llama.cpp mtmd"
            echo "  --whispercpp     Include whisper.cpp STT backend"
            echo "  --onnx           Include sherpa-onnx TTS/VAD backend"
            echo "  --webgpu         Enable WebGPU GPU acceleration (produces racommons-webgpu variant)"
            echo "  --all-backends   Enable WASM-compatible backends (llama.cpp + VLM)"
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

# Use a separate build directory for WebGPU variant to avoid cache conflicts
if [ "$WEBGPU" = "ON" ]; then
    BUILD_DIR="${WASM_DIR}/build-webgpu"
else
    BUILD_DIR="${WASM_DIR}/build"
fi

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
echo " VLM (mtmd):   ${VLM}"
echo " WebGPU:       ${WEBGPU}"
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

rm -f "${REPO_ROOT}/a.out.js" "${REPO_ROOT}/a.out.wasm"

# Create build directory
mkdir -p "${BUILD_DIR}"

# Configure the single-root CMake build with Emscripten
echo ""
echo ">>> Configuring CMake with Emscripten..."
emcmake cmake \
    -B "${BUILD_DIR}" \
    -S "${REPO_ROOT}" \
    -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
    -DCMAKE_CXX_SCAN_FOR_MODULES=OFF \
    -DRAC_ENABLE_PROTOBUF=ON \
    -DRAC_ENABLE_SOLUTIONS=OFF \
    -DRAC_STATIC_PLUGINS=ON \
    -DRAC_BUILD_PLATFORM=OFF \
    -DRAC_BUILD_SHARED=OFF \
    -DRAC_WASM_PTHREADS="${PTHREADS}" \
    -DRAC_WASM_DEBUG="${DEBUG}" \
    -DRAC_WASM_LLAMACPP="${LLAMACPP}" \
    -DRAC_WASM_VLM="${VLM}" \
    -DRAC_WASM_WHISPERCPP="${WHISPERCPP}" \
    -DRAC_WASM_ONNX="${ONNX}" \
    -DRAC_WASM_WEBGPU="${WEBGPU}"

# Build
echo ""
echo ">>> Building WASM module..."
# Force serial build (--parallel 1) to avoid an intermittent zlib static-lib
# race: zlib's CMakeLists has two targets (zlib + zlibstatic) that both
# produce libz.a in the same directory; with any concurrency, llvm-ranlib
# can read the archive while another job is still writing it. On 2-core
# GitHub Actions runners --parallel 2 == default and doesn't fix the race.
# Serial costs us ~5-10 minutes vs. parallel — acceptable for a release
# pipeline that already takes 20+ minutes total. Local devs can override
# by exporting CMAKE_BUILD_PARALLEL_LEVEL=N.
cmake --build "${BUILD_DIR}" --target runanywhere_wasm --parallel "${CMAKE_BUILD_PARALLEL_LEVEL:-1}"

# Verify outputs
echo ""
echo ">>> Verifying outputs..."

# Output file names depend on whether WebGPU variant was built
if [ "$WEBGPU" = "ON" ]; then
    OUTPUT_NAME="racommons-llamacpp-webgpu"
else
    OUTPUT_NAME="racommons-llamacpp"
fi

WASM_FILE="${OUTPUT_DIR}/${OUTPUT_NAME}.wasm"
JS_FILE="${OUTPUT_DIR}/${OUTPUT_NAME}.js"

if [ -f "${WASM_FILE}" ] && [ -f "${JS_FILE}" ]; then
    WASM_SIZE=$(du -h "${WASM_FILE}" | cut -f1)
    JS_SIZE=$(du -h "${JS_FILE}" | cut -f1)
    echo "SUCCESS: WASM build complete"
    echo "  ${OUTPUT_NAME}.wasm: ${WASM_SIZE}"
    echo "  ${OUTPUT_NAME}.js:   ${JS_SIZE}"

    if [ "$PTHREADS" = "ON" ] && [ -f "${OUTPUT_DIR}/${OUTPUT_NAME}.worker.js" ]; then
        WORKER_SIZE=$(du -h "${OUTPUT_DIR}/${OUTPUT_NAME}.worker.js" | cut -f1)
        echo "  ${OUTPUT_NAME}.worker.js: ${WORKER_SIZE}"
    fi
else
    echo "ERROR: Build outputs not found!"
    echo "  Expected: ${WASM_FILE}"
    echo "  Expected: ${JS_FILE}"
    exit 1
fi

rm -f "${REPO_ROOT}/a.out.js" "${REPO_ROOT}/a.out.wasm"

echo ""
echo "WASM module ready at: ${OUTPUT_DIR}/"
