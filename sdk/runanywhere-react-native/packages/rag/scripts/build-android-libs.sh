#!/bin/bash
set -e

# =============================================================================
# Build Android Native Libraries for RAG Package
# =============================================================================
# This script builds the C++ libraries for Android (arm64-v8a, armeabi-v7a, x86_64)
# and copies them to the package's jniLibs directory.
#
# Prerequisites:
# - Android NDK installed
# - ANDROID_NDK environment variable set
# - CMake 3.22+
#
# Usage:
#   ./build-android-libs.sh [arm64-v8a|armeabi-v7a|x86_64|all]
#
# =============================================================================

# Check for Android NDK
if [ -z "$ANDROID_NDK" ]; then
    echo "Error: ANDROID_NDK environment variable not set"
    echo "Please set it to your NDK path, e.g.:"
    echo "  export ANDROID_NDK=\$HOME/Library/Android/sdk/ndk/26.1.10909125"
    exit 1
fi

if [ ! -d "$ANDROID_NDK" ]; then
    echo "Error: ANDROID_NDK directory does not exist: $ANDROID_NDK"
    exit 1
fi

echo "Using Android NDK: $ANDROID_NDK"

# Determine which ABIs to build
ABI_ARG="${1:-arm64-v8a}"
case "$ABI_ARG" in
    all)
        ABIS=("arm64-v8a" "armeabi-v7a" "x86_64")
        ;;
    arm64-v8a|armeabi-v7a|x86_64)
        ABIS=("$ABI_ARG")
        ;;
    *)
        echo "Error: Unknown ABI '$ABI_ARG'"
        echo "Valid options: arm64-v8a, armeabi-v7a, x86_64, all"
        exit 1
        ;;
esac

# Paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_DIR="$(dirname "$SCRIPT_DIR")"
COMMONS_DIR="$PACKAGE_DIR/../../../runanywhere-commons"
BUILD_BASE_DIR="$COMMONS_DIR/build-android"

echo "Package directory: $PACKAGE_DIR"
echo "Commons directory: $COMMONS_DIR"

# Create jniLibs directories
mkdir -p "$PACKAGE_DIR/android/src/main/jniLibs"

# Build for each ABI
for ABI in "${ABIS[@]}"; do
    echo ""
    echo "========================================"
    echo "Building for ABI: $ABI"
    echo "========================================"
    
    BUILD_DIR="$BUILD_BASE_DIR/$ABI"
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    
    # Configure with CMake
    # Note: ONNX backend enabled for proven ONNX Runtime setup
    # LlamaCPP enabled for RAG text generation (llamacpp_generator.cpp)
    # RAG uses its own embedding/generation providers
    cmake "$COMMONS_DIR" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI="$ABI" \
        -DANDROID_NATIVE_API_LEVEL=21 \
        -DANDROID_STL=c++_shared \
        -DRAC_BUILD_SHARED=ON \
        -DRAC_BUILD_BACKENDS=ON \
        -DRAC_BACKEND_LLAMACPP=ON \
        -DRAC_BACKEND_ONNX=ON \
        -DRAC_BACKEND_RAG=ON \
        -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-z,max-page-size=16384"
    
    # Build
    cmake --build . --parallel $(nproc 2>/dev/null || echo 4)
    
    # Create target directory
    JNILIB_DIR="$PACKAGE_DIR/android/src/main/jniLibs/$ABI"
    mkdir -p "$JNILIB_DIR"
    
    # Copy .so files
    echo "Copying libraries to $JNILIB_DIR"
    
    if [ -f "src/features/rag/librac_backend_rag.so" ]; then
        cp -v "src/features/rag/librac_backend_rag.so" "$JNILIB_DIR/"
    else
        echo "Warning: librac_backend_rag.so not found"
    fi
    
    # Copy ONNX backend (provides proven ONNX Runtime infrastructure)
    if [ -f "src/backends/onnx/librac_backend_onnx.so" ]; then
        cp -v "src/backends/onnx/librac_backend_onnx.so" "$JNILIB_DIR/"
    else
        echo "Warning: librac_backend_onnx.so not found"
    fi
    
    echo "✓ Build completed for $ABI"
done

echo ""
echo "========================================"
echo "Build Summary"
echo "========================================"
echo "Libraries copied to:"
for ABI in "${ABIS[@]}"; do
    JNILIB_DIR="$PACKAGE_DIR/android/src/main/jniLibs/$ABI"
    if [ -d "$JNILIB_DIR" ]; then
        echo "  $ABI:"
        ls -lh "$JNILIB_DIR"/*.so 2>/dev/null || echo "    (no .so files found)"
    fi
done

echo ""
echo "✅ Android native libraries built successfully!"
echo ""
echo "Next steps:"
echo "  1. cd examples/react-native/RunAnywhereAI/android"
echo "  2. ./gradlew clean"
echo "  3. ./gradlew assembleDebug"
echo "  4. npm run android (from examples/react-native/RunAnywhereAI)"
