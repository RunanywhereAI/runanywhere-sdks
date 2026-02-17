#!/usr/bin/env bash
# =============================================================================
# RunAnywhere Web SDK - Sherpa-ONNX WASM Build Script
# =============================================================================
#
# Builds sherpa-onnx from source for browser WASM with ASR + TTS + VAD support.
# Produces a single WASM module alongside the sherpa-onnx JS wrapper files.
#
# Usage:
#   ./scripts/build-sherpa-onnx.sh              # Build all (ASR+TTS+VAD)
#   ./scripts/build-sherpa-onnx.sh --clean      # Clean before building
#   ./scripts/build-sherpa-onnx.sh --help       # Show help
#
# Prerequisites:
#   - Emscripten SDK (emsdk) installed and activated (3.1.51-3.1.53 recommended)
#   - CMake 3.22+
#   - git (to clone sherpa-onnx)
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WASM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${WASM_DIR}/build-sherpa-onnx"
SHERPA_SRC="${WASM_DIR}/third_party/sherpa-onnx"
OUTPUT_DIR="${WASM_DIR}/../packages/onnx/wasm/sherpa"

SHERPA_VERSION="v1.12.20"
CLEAN=false
JOBS=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --clean)
            CLEAN=true
            shift
            ;;
        --version)
            SHERPA_VERSION="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Builds sherpa-onnx from source for browser WASM (ASR+TTS+VAD)."
            echo ""
            echo "Options:"
            echo "  --clean          Clean build directory before building"
            echo "  --version TAG    Sherpa-onnx git tag (default: ${SHERPA_VERSION})"
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
if [ -z "${EMSCRIPTEN:-}" ]; then
    if ! command -v emcc &> /dev/null; then
        echo "ERROR: Emscripten not found. Please install and activate emsdk:"
        echo "  ./scripts/setup-emsdk.sh"
        echo "  source <emsdk-path>/emsdk_env.sh"
        exit 1
    else
        EMSCRIPTEN=$(dirname "$(command -v emcc)")
    fi
fi

if [ ! -f "${EMSCRIPTEN}/cmake/Modules/Platform/Emscripten.cmake" ]; then
    echo "ERROR: Cannot find Emscripten CMake toolchain at:"
    echo "  ${EMSCRIPTEN}/cmake/Modules/Platform/Emscripten.cmake"
    echo "Hint: emsdk 3.1.51-3.1.53 is known to work."
    exit 1
fi

echo "======================================"
echo " RunAnywhere - Sherpa-ONNX WASM Build"
echo "======================================"
echo " Version:      ${SHERPA_VERSION}"
echo " Emscripten:   ${EMSCRIPTEN}"
echo " Build dir:    ${BUILD_DIR}"
echo " Output dir:   ${OUTPUT_DIR}"
echo " Parallel:     ${JOBS} jobs"
echo "======================================"

# Clean if requested
if [ "$CLEAN" = true ]; then
    echo "Cleaning build directory..."
    rm -rf "${BUILD_DIR}"
fi

# =============================================================================
# Step 1: Clone/update sherpa-onnx source
# =============================================================================

if [ ! -d "${SHERPA_SRC}" ]; then
    echo ""
    echo ">>> Cloning sherpa-onnx ${SHERPA_VERSION}..."
    mkdir -p "$(dirname "${SHERPA_SRC}")"
    git clone --depth 1 --branch "${SHERPA_VERSION}" \
        https://github.com/k2-fsa/sherpa-onnx.git "${SHERPA_SRC}"
else
    echo ""
    echo ">>> Using existing sherpa-onnx source at ${SHERPA_SRC}"
    echo "    (delete to re-clone, or use --clean to rebuild)"
fi

# =============================================================================
# Step 2: Build with Emscripten (browser-compatible, all features)
# =============================================================================

mkdir -p "${BUILD_DIR}"

echo ""
echo ">>> Configuring sherpa-onnx for browser WASM (ASR+TTS+VAD)..."

export SHERPA_ONNX_IS_USING_BUILD_WASM_SH=ON

cmake \
    -B "${BUILD_DIR}" \
    -S "${SHERPA_SRC}" \
    -DCMAKE_INSTALL_PREFIX="${BUILD_DIR}/install" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="${EMSCRIPTEN}/cmake/Modules/Platform/Emscripten.cmake" \
    \
    -DSHERPA_ONNX_ENABLE_PYTHON=OFF \
    -DSHERPA_ONNX_ENABLE_TESTS=OFF \
    -DSHERPA_ONNX_ENABLE_CHECK=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DSHERPA_ONNX_ENABLE_PORTAUDIO=OFF \
    -DSHERPA_ONNX_ENABLE_JNI=OFF \
    -DSHERPA_ONNX_ENABLE_C_API=ON \
    -DSHERPA_ONNX_ENABLE_WEBSOCKET=OFF \
    -DSHERPA_ONNX_ENABLE_GPU=OFF \
    -DSHERPA_ONNX_ENABLE_BINARY=OFF \
    -DSHERPA_ONNX_LINK_LIBSTDCPP_STATICALLY=OFF \
    \
    -DSHERPA_ONNX_ENABLE_WASM=ON \
    -DSHERPA_ONNX_ENABLE_WASM_NODEJS=ON \
    -DSHERPA_ONNX_ENABLE_WASM_ASR=OFF \
    -DSHERPA_ONNX_ENABLE_WASM_TTS=OFF \
    -DSHERPA_ONNX_ENABLE_WASM_VAD=OFF \
    -DSHERPA_ONNX_ENABLE_TTS=ON

echo ""
echo ">>> Building sherpa-onnx WASM (this may take 10-20 minutes)..."
cmake --build "${BUILD_DIR}" --parallel "${JOBS}" --target sherpa-onnx-wasm-nodejs

echo ""
echo ">>> Installing..."
cmake --build "${BUILD_DIR}" --target install

# =============================================================================
# Step 3: Copy outputs to SDK packages directory
# =============================================================================

echo ""
echo ">>> Copying outputs to ${OUTPUT_DIR}..."
mkdir -p "${OUTPUT_DIR}"

NODEJS_DIR="${BUILD_DIR}/install/bin/wasm/nodejs"

if [ ! -f "${NODEJS_DIR}/sherpa-onnx-wasm-nodejs.wasm" ]; then
    echo "ERROR: WASM binary not found at ${NODEJS_DIR}/"
    echo "Build may have failed. Check logs above."
    exit 1
fi

# Copy the WASM binary and Emscripten glue
cp "${NODEJS_DIR}/sherpa-onnx-wasm-nodejs.wasm" "${OUTPUT_DIR}/sherpa-onnx.wasm"
cp "${NODEJS_DIR}/sherpa-onnx-wasm-nodejs.js" "${OUTPUT_DIR}/sherpa-onnx-glue.js"

# Copy the JS wrapper files for each capability
for wrapper in sherpa-onnx-asr.js sherpa-onnx-tts.js sherpa-onnx-vad.js sherpa-onnx-wave.js; do
    if [ -f "${NODEJS_DIR}/${wrapper}" ]; then
        cp "${NODEJS_DIR}/${wrapper}" "${OUTPUT_DIR}/${wrapper}"
    fi
done

# =============================================================================
# Step 3.5: Post-compile patches for browser compatibility
# =============================================================================
#
# The nodejs WASM target produces Emscripten glue code with Node.js assumptions
# that break in browsers. We run a Node.js patch script to fix:
#
#   1. Force ENVIRONMENT_IS_NODE = false  (use browser code paths)
#   2. require("node:path") → browser shim (provides isAbsolute/normalize/join)
#   3. NODERAWFS error throw → skip        (avoid "not supported" crash)
#   4. NODERAWFS FS patching → skip        (use MEMFS instead)
#   5. ESM default export appended         (for dynamic import() in browser)
#
# See packages/onnx/src/Foundation/SherpaONNXBridge.ts for the loader that
# consumes this patched file.
# =============================================================================

echo ""
echo ">>> Applying browser compatibility patches to sherpa-onnx-glue.js..."

PATCH_SCRIPT="${SCRIPT_DIR}/patch-sherpa-glue.js"
GLUE_FILE="${OUTPUT_DIR}/sherpa-onnx-glue.js"

if [ ! -f "$PATCH_SCRIPT" ]; then
    echo "ERROR: Patch script not found at ${PATCH_SCRIPT}"
    exit 1
fi

node "$PATCH_SCRIPT" "$GLUE_FILE"

# =============================================================================
# Step 4: Verify outputs
# =============================================================================

echo ""
echo ">>> Verifying outputs..."

WASM_FILE="${OUTPUT_DIR}/sherpa-onnx.wasm"
JS_FILE="${OUTPUT_DIR}/sherpa-onnx-glue.js"

if [ -f "${WASM_FILE}" ] && [ -f "${JS_FILE}" ]; then
    WASM_SIZE=$(du -h "${WASM_FILE}" | cut -f1)
    JS_SIZE=$(du -h "${JS_FILE}" | cut -f1)
    echo "SUCCESS: Sherpa-ONNX WASM build complete (with browser patches)"
    echo "  sherpa-onnx.wasm:       ${WASM_SIZE}"
    echo "  sherpa-onnx-glue.js:    ${JS_SIZE}"

    for wrapper in sherpa-onnx-asr.js sherpa-onnx-tts.js sherpa-onnx-vad.js; do
        if [ -f "${OUTPUT_DIR}/${wrapper}" ]; then
            SZ=$(du -h "${OUTPUT_DIR}/${wrapper}" | cut -f1)
            echo "  ${wrapper}: ${SZ}"
        fi
    done
else
    echo "ERROR: Build outputs not found!"
    exit 1
fi

echo ""
echo "Sherpa-ONNX WASM ready at: ${OUTPUT_DIR}/"
