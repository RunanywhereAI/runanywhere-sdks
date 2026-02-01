#!/bin/bash
# =============================================================================
# Build ONNX Runtime 1.17.1 with QNN Execution Provider for Android
# =============================================================================
# This script builds ONNX Runtime from source with QNN EP support.
# The resulting libonnxruntime.so will:
# - Export OrtGetApiBase@@VERS_1.17.1 (compatible with sherpa-onnx)
# - Include QNN Execution Provider for NPU acceleration
# =============================================================================

set -e

# Configuration
# Use 1.19.0 which has better QNN support and is compatible with newer CMake
ONNXRUNTIME_VERSION="1.19.0"
ONNXRUNTIME_REPO="https://github.com/microsoft/onnxruntime.git"
BUILD_DIR="/tmp/onnxruntime-qnn-build"
OUTPUT_DIR="$(cd "$(dirname "$0")/../.." && pwd)/dist/onnxruntime-qnn"

# QAIRT SDK path (Qualcomm AI Runtime)
QNN_SDK_PATH="${QNN_SDK_PATH:-/Users/sanchitmonga/development/ODLM/paytm/Paytm-offline-voice/EXTERNAL/inference-engines/qairt/2.40.0.251030}"

# Android SDK/NDK paths
ANDROID_SDK="${ANDROID_SDK:-$HOME/Library/Android/sdk}"
ANDROID_NDK="${ANDROID_NDK:-$ANDROID_SDK/ndk/26.3.11579264}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}Building ONNX Runtime $ONNXRUNTIME_VERSION with QNN EP${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""
echo "QNN SDK: $QNN_SDK_PATH"
echo "Android SDK: $ANDROID_SDK"
echo "Android NDK: $ANDROID_NDK"
echo "Build Dir: $BUILD_DIR"
echo "Output Dir: $OUTPUT_DIR"
echo ""

# Verify paths
if [[ ! -d "$QNN_SDK_PATH" ]]; then
    echo -e "${RED}ERROR: QNN SDK not found at $QNN_SDK_PATH${NC}"
    echo "Set QNN_SDK_PATH environment variable to your QAIRT SDK location"
    exit 1
fi

if [[ ! -d "$ANDROID_NDK" ]]; then
    echo -e "${RED}ERROR: Android NDK not found at $ANDROID_NDK${NC}"
    exit 1
fi

# Check for QNN libraries
if [[ ! -f "$QNN_SDK_PATH/lib/aarch64-android/libQnnHtp.so" ]]; then
    echo -e "${RED}ERROR: QNN HTP library not found in SDK${NC}"
    exit 1
fi
echo -e "${GREEN}✓ QNN SDK verified${NC}"

# Clone ONNX Runtime
echo ""
echo -e "${YELLOW}Step 1: Cloning ONNX Runtime v$ONNXRUNTIME_VERSION...${NC}"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

git clone --branch "v$ONNXRUNTIME_VERSION" --depth 1 "$ONNXRUNTIME_REPO" onnxruntime
cd onnxruntime

# Apply any necessary patches for QAIRT 2.40 compatibility
echo ""
echo -e "${YELLOW}Step 2: Checking QNN compatibility...${NC}"
# Note: ONNX Runtime 1.17.1 was tested with QNN ~2.18-2.20
# QAIRT 2.40 may require minor patches - we'll try without first

# Build for Android arm64-v8a
echo ""
echo -e "${YELLOW}Step 3: Building ONNX Runtime with QNN EP...${NC}"
echo "This may take 30-60 minutes..."

./build.sh \
    --config Release \
    --android \
    --android_sdk_path "$ANDROID_SDK" \
    --android_ndk_path "$ANDROID_NDK" \
    --android_abi arm64-v8a \
    --android_api 24 \
    --use_qnn \
    --qnn_home "$QNN_SDK_PATH" \
    --build_shared_lib \
    --parallel \
    --skip_tests \
    --cmake_extra_defines \
        CMAKE_ANDROID_STL_TYPE=c++_shared \
        CMAKE_POLICY_VERSION_MINIMUM=3.5

# Check build success
if [[ ! -f "build/Android/Release/libonnxruntime.so" ]]; then
    echo -e "${RED}ERROR: Build failed - libonnxruntime.so not found${NC}"
    exit 1
fi

# Copy output
echo ""
echo -e "${YELLOW}Step 4: Copying build artifacts...${NC}"
mkdir -p "$OUTPUT_DIR/arm64-v8a"
cp build/Android/Release/libonnxruntime.so "$OUTPUT_DIR/arm64-v8a/"

# Verify symbols
echo ""
echo -e "${YELLOW}Step 5: Verifying symbols...${NC}"
nm -D "$OUTPUT_DIR/arm64-v8a/libonnxruntime.so" | grep OrtGetApiBase
echo ""

# Copy QNN libraries needed at runtime
echo -e "${YELLOW}Step 6: Copying QNN runtime libraries...${NC}"
mkdir -p "$OUTPUT_DIR/qnn-libs"
cp "$QNN_SDK_PATH/lib/aarch64-android/libQnnHtp.so" "$OUTPUT_DIR/qnn-libs/"
cp "$QNN_SDK_PATH/lib/aarch64-android/libQnnSystem.so" "$OUTPUT_DIR/qnn-libs/"
cp "$QNN_SDK_PATH/lib/aarch64-android/libQnnHtpV81Stub.so" "$OUTPUT_DIR/qnn-libs/"  # Snapdragon 8 Elite
cp "$QNN_SDK_PATH/lib/aarch64-android/libQnnHtpV79Stub.so" "$OUTPUT_DIR/qnn-libs/"  # Snapdragon 8 Gen 3
cp "$QNN_SDK_PATH/lib/aarch64-android/libQnnHtpV75Stub.so" "$OUTPUT_DIR/qnn-libs/"  # Snapdragon 8 Gen 2
cp "$QNN_SDK_PATH/lib/aarch64-android/libQnnHtpV73Stub.so" "$OUTPUT_DIR/qnn-libs/"  # Snapdragon 8 Gen 1
cp "$QNN_SDK_PATH/lib/aarch64-android/libQnnCpu.so" "$OUTPUT_DIR/qnn-libs/"        # CPU fallback

echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}Build Complete!${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""
echo "Output: $OUTPUT_DIR"
echo ""
echo "Files:"
ls -la "$OUTPUT_DIR/arm64-v8a/"
echo ""
echo "QNN libs:"
ls -la "$OUTPUT_DIR/qnn-libs/"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Replace sherpa-onnx libonnxruntime.so with the new one:"
echo "   cp $OUTPUT_DIR/arm64-v8a/libonnxruntime.so \\"
echo "      third_party/sherpa-onnx-android/jniLibs/arm64-v8a/"
echo ""
echo "2. Copy QNN libs to jniLibs:"
echo "   cp $OUTPUT_DIR/qnn-libs/*.so \\"
echo "      third_party/sherpa-onnx-android/jniLibs/arm64-v8a/"
echo ""
echo "3. Rebuild the SDK"
