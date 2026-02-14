#!/bin/bash
# =============================================================================
# Build iOS Static Libraries for RAG Package
# =============================================================================
# This script builds the C++ libraries for iOS (arm64 + simulator)
# and creates static libraries (.a) in the package's ios directory.
#
# Prerequisites:
# - Xcode Command Line Tools
# - CMake 3.22+
#
# Usage:
#   ./build-ios-libs.sh [--clean]
#
# =============================================================================

set -e

# Check for clean flag
CLEAN_BUILD=false
if [[ "$1" == "--clean" ]]; then
    CLEAN_BUILD=true
fi

# Paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_DIR="$(dirname "$SCRIPT_DIR")"
COMMONS_DIR="$PACKAGE_DIR/../../../runanywhere-commons"
BUILD_BASE_DIR="$COMMONS_DIR/build/ios"

echo "Package directory: $PACKAGE_DIR"
echo "Commons directory: $COMMONS_DIR"

# Create output directories
mkdir -p "$PACKAGE_DIR/ios/Libraries"
mkdir -p "$PACKAGE_DIR/ios/Headers"

# Clean if requested
if [[ "$CLEAN_BUILD" == true ]]; then
    echo "Cleaning build directories..."
    rm -rf "$BUILD_BASE_DIR"
fi

# Always clean to avoid generator mismatch
echo "Cleaning previous build..."
rm -rf "$BUILD_BASE_DIR/DEVICE"
rm -rf "$BUILD_BASE_DIR/SIMULATOR"

# Clean commons build cache to ensure fresh CMake configuration
echo "Cleaning commons build cache..."
rm -rf "$COMMONS_DIR/build/ios"

# =============================================================================
# Build for iOS Device (arm64)
# =============================================================================

echo ""
echo "========================================"
echo "Building for iOS Device (arm64)"
echo "========================================"

BUILD_DIR="$BUILD_BASE_DIR/DEVICE"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

cmake "$COMMONS_DIR" \
    -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_BUILD_TYPE=Release \
    -DRAC_BUILD_SHARED=OFF \
    -DRAC_BUILD_BACKENDS=ON \
    -DRAC_BACKEND_LLAMACPP=OFF \
    -DRAC_BACKEND_ONNX=ON \
    -DRAC_BACKEND_RAG=ON \
    -DRAC_BACKEND_WHISPERCPP=OFF

cmake --build . --config Release --target rac_backend_rag --parallel 4

# =============================================================================
# Build for iOS Simulator (arm64 + x86_64)
# =============================================================================

echo ""
echo "========================================"
echo "Building for iOS Simulator"
echo "========================================"

BUILD_DIR="$BUILD_BASE_DIR/SIMULATOR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

cmake "$COMMONS_DIR" \
    -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DCMAKE_OSX_SYSROOT=iphonesimulator \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_COMPILER=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++ \
    -DRAC_BUILD_SHARED=OFF \
    -DRAC_BUILD_BACKENDS=ON \
    -DRAC_BACKEND_LLAMACPP=OFF \
    -DRAC_BACKEND_ONNX=ON \
    -DRAC_BACKEND_RAG=ON \
    -DRAC_BACKEND_WHISPERCPP=OFF

cmake --build . --config Release --target rac_backend_rag --parallel 4

# =============================================================================
# Create XCFrameworks (supports same arch for device/simulator)
# =============================================================================

echo ""
echo "========================================"
echo "Creating XCFrameworks"
echo "========================================"

DEVICE_LIB_DIR="$BUILD_BASE_DIR/DEVICE/src/backends/rag/Release-iphoneos"
SIMULATOR_LIB_DIR="$BUILD_BASE_DIR/SIMULATOR/src/backends/rag/Release-iphonesimulator"
DEVICE_ONNX_DIR="$BUILD_BASE_DIR/DEVICE/src/backends/onnx/Release-iphoneos"
SIMULATOR_ONNX_DIR="$BUILD_BASE_DIR/SIMULATOR/src/backends/onnx/Release-iphonesimulator"
OUTPUT_DIR="$PACKAGE_DIR/ios/Libraries"

# Remove old XCFrameworks if they exist
rm -rf "$OUTPUT_DIR/rac_backend_rag.xcframework"
rm -rf "$OUTPUT_DIR/rac_backend_onnx.xcframework"

# Create RAG backend XCFramework
echo "Creating rac_backend_rag.xcframework..."
xcodebuild -create-xcframework \
    -library "$DEVICE_LIB_DIR/librac_backend_rag.a" \
    -library "$SIMULATOR_LIB_DIR/librac_backend_rag.a" \
    -output "$OUTPUT_DIR/rac_backend_rag.xcframework"
echo "✓ rac_backend_rag.xcframework created"

# Create ONNX backend XCFramework (provides proven ONNX Runtime setup)
echo "Creating rac_backend_onnx.xcframework..."
xcodebuild -create-xcframework \
    -library "$DEVICE_ONNX_DIR/librac_backend_onnx.a" \
    -library "$SIMULATOR_ONNX_DIR/librac_backend_onnx.a" \
    -output "$OUTPUT_DIR/rac_backend_onnx.xcframework"
echo "✓ rac_backend_onnx.xcframework created"

# =============================================================================
# Copy Headers
# =============================================================================

echo ""
echo "========================================"
echo "Copying Headers"
echo "========================================"

HEADERS_SRC="$COMMONS_DIR/src/backends/rag"
HEADERS_DEST="$PACKAGE_DIR/ios/Headers"

# Copy RAG headers
if [[ -d "$HEADERS_SRC" ]]; then
    cp -v "$HEADERS_SRC/rag_backend.h" "$HEADERS_DEST/" || echo "⚠ rag_backend.h not found"
    cp -v "$HEADERS_SRC/inference_provider.h" "$HEADERS_DEST/" || echo "⚠ inference_provider.h not found"
    cp -v "$HEADERS_SRC/vector_store_usearch.h" "$HEADERS_DEST/" || echo "⚠ vector_store_usearch.h not found"
    cp -v "$HEADERS_SRC/rag_chunker.h" "$HEADERS_DEST/" || echo "⚠ rag_chunker.h not found"
    
    # Copy provider headers if they were built
    if [[ -f "$HEADERS_SRC/onnx_embedding_provider.h" ]]; then
        cp -v "$HEADERS_SRC/onnx_embedding_provider.h" "$HEADERS_DEST/"
    fi
fi

echo ""
echo "========================================"
echo "Build Summary"
echo "========================================"
echo "XCFrameworks:"
ls -lh "$OUTPUT_DIR"/*.xcframework 2>/dev/null || echo "  (none found)"
echo ""
echo "Headers:"
ls -lh "$HEADERS_DEST"/*.h 2>/dev/null || echo "  (no headers found)"
echo ""
echo "✅ iOS XCFrameworks built successfully!"
echo "📦 RAG Package Contents:"
echo "   - rac_backend_rag.xcframework (RAG core with embedding/generation providers)"
echo "   - rac_backend_onnx.xcframework (ONNX Runtime infrastructure)"
echo "   Note: XCFramework format supports arm64 on both device and simulator"
