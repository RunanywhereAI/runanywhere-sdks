#!/bin/bash
# =============================================================================
# Build Sherpa-ONNX static libraries for macOS
# =============================================================================
#
# Builds Sherpa-ONNX from source as static libraries for macOS arm64.
# The official releases only provide shared libraries for macOS,
# but we need static libs to bundle into xcframeworks.
#
# Output: third_party/sherpa-onnx-macos/
#   lib/libsherpa-onnx-c-api.a (and dependency .a files)
#   include/sherpa-onnx/c-api/c-api.h
#
# Prerequisites: cmake, git, clang (Xcode Command Line Tools)
# Build time: ~5-10 minutes on Apple Silicon
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SHERPA_DIR="${ROOT_DIR}/third_party/sherpa-onnx-macos"
BUILD_TEMP="${ROOT_DIR}/build/sherpa-onnx-macos-build"

# Load versions
source "${SCRIPT_DIR}/../load-versions.sh"

if [ -z "${SHERPA_ONNX_VERSION_MACOS:-}" ]; then
    echo "ERROR: SHERPA_ONNX_VERSION_MACOS not loaded from VERSIONS file" >&2
    exit 1
fi

SHERPA_VERSION="${SHERPA_ONNX_VERSION_MACOS}"

echo "======================================="
echo "📦 Sherpa-ONNX macOS Static Builder"
echo "======================================="
echo ""
echo "Version: ${SHERPA_VERSION}"
echo "Architecture: arm64 (Apple Silicon)"

# Check if already built
if [ -f "${SHERPA_DIR}/lib/libsherpa-onnx-c-api.a" ]; then
    echo "✅ Sherpa-ONNX macOS static libs already exist at ${SHERPA_DIR}"
    echo "   To force rebuild, remove: rm -rf ${SHERPA_DIR}"
    exit 0
fi

# Check prerequisites
for cmd in cmake git; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: $cmd is required but not found"
        exit 1
    fi
done

# Clone sherpa-onnx
echo ""
echo "==> Cloning sherpa-onnx v${SHERPA_VERSION}..."
rm -rf "${BUILD_TEMP}"
mkdir -p "${BUILD_TEMP}"

git clone --depth 1 --branch "v${SHERPA_VERSION}" \
    https://github.com/k2-fsa/sherpa-onnx.git \
    "${BUILD_TEMP}/sherpa-onnx"

# Build static libraries
echo ""
echo "==> Building static libraries for macOS arm64..."
echo "    This takes ~5-10 minutes..."

BUILD_DIR="${BUILD_TEMP}/sherpa-onnx/build-macos-static"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

cmake "${BUILD_TEMP}/sherpa-onnx" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES="arm64" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="14.0" \
    -DBUILD_SHARED_LIBS=OFF \
    -DSHERPA_ONNX_ENABLE_C_API=ON \
    -DSHERPA_ONNX_ENABLE_BINARY=OFF \
    -DSHERPA_ONNX_ENABLE_TESTS=OFF \
    -DSHERPA_ONNX_ENABLE_PYTHON=OFF \
    -DSHERPA_ONNX_ENABLE_PORTAUDIO=OFF \
    -DSHERPA_ONNX_ENABLE_WEBSOCKET=OFF \
    -DSHERPA_ONNX_ENABLE_GPU=OFF

cmake --build . --config Release -j$(sysctl -n hw.ncpu)

# Collect static libraries and headers
echo ""
echo "==> Collecting build artifacts..."
mkdir -p "${SHERPA_DIR}/lib"
mkdir -p "${SHERPA_DIR}/include"

# Copy the C API static library
find "${BUILD_DIR}" -name "libsherpa-onnx-c-api.a" -exec cp {} "${SHERPA_DIR}/lib/" \;

# Copy all dependency static libraries
for lib in \
    sherpa-onnx-core sherpa-onnx-fst sherpa-onnx-fstfar \
    sherpa-onnx-kaldifst-core kaldi-decoder-core kaldi-native-fbank-core \
    piper_phonemize espeak-ng ucd cppinyin_core ssentencepiece_core kissfft-float; do
    LIB_FILE=$(find "${BUILD_DIR}" -name "lib${lib}.a" 2>/dev/null | head -1)
    if [ -n "${LIB_FILE}" ]; then
        cp "${LIB_FILE}" "${SHERPA_DIR}/lib/"
    fi
done

# Copy ONNX Runtime static lib if built by sherpa-onnx
ONNX_LIB=$(find "${BUILD_DIR}" -name "libonnxruntime.a" 2>/dev/null | head -1)
if [ -n "${ONNX_LIB}" ]; then
    cp "${ONNX_LIB}" "${SHERPA_DIR}/lib/"
fi

# Copy headers
if [ -d "${BUILD_TEMP}/sherpa-onnx/sherpa-onnx/c-api" ]; then
    mkdir -p "${SHERPA_DIR}/include/sherpa-onnx/c-api"
    cp "${BUILD_TEMP}/sherpa-onnx/sherpa-onnx/c-api/"*.h "${SHERPA_DIR}/include/sherpa-onnx/c-api/" 2>/dev/null || true
fi

# Also copy from build dir if headers were generated there
GENERATED_HEADERS=$(find "${BUILD_DIR}" -path "*/sherpa-onnx/c-api/c-api.h" | head -1)
if [ -n "${GENERATED_HEADERS}" ]; then
    HEADER_DIR=$(dirname "${GENERATED_HEADERS}")
    mkdir -p "${SHERPA_DIR}/include/sherpa-onnx/c-api"
    cp "${HEADER_DIR}/"*.h "${SHERPA_DIR}/include/sherpa-onnx/c-api/" 2>/dev/null || true
fi

# Verify build
echo ""
if [ -f "${SHERPA_DIR}/lib/libsherpa-onnx-c-api.a" ]; then
    echo "✅ Sherpa-ONNX macOS static build complete!"
    echo ""
    echo "Output: ${SHERPA_DIR}"
    echo ""
    echo "Libraries:"
    ls -lh "${SHERPA_DIR}/lib/"*.a 2>/dev/null || echo "  (none found)"
    echo ""
    echo "Headers:"
    find "${SHERPA_DIR}/include" -name "*.h" 2>/dev/null || echo "  (none found)"
else
    echo "❌ Build failed - libsherpa-onnx-c-api.a not found"
    echo ""
    echo "Build directory: ${BUILD_DIR}"
    echo "Check build logs above for errors."
    exit 1
fi

# Clean up build temp (optional - keep for debugging)
echo ""
echo "Cleaning up build directory..."
rm -rf "${BUILD_TEMP}"

echo ""
echo "Done!"
