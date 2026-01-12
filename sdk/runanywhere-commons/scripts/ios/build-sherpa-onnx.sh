#!/usr/bin/env bash
# Build sherpa-onnx for iOS and create XCFramework
# This script builds sherpa-onnx library for iOS devices and simulators

set -e

echo "======================================="
echo "🚀 Building Sherpa-ONNX for iOS"
echo "======================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
SHERPA_DIR="$PROJECT_ROOT/third_party/sherpa-onnx"
BUILD_DIR="$SHERPA_DIR/build-ios"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if sherpa-onnx is cloned
if [ ! -d "$SHERPA_DIR" ]; then
    echo -e "${RED}❌ Sherpa-ONNX not found. Please run: cd $PROJECT_ROOT/third_party && git clone https://github.com/k2-fsa/sherpa-onnx.git${NC}"
    exit 1
fi

cd "$SHERPA_DIR"

echo -e "${YELLOW}Building sherpa-onnx using official build script...${NC}"

# Use the official sherpa-onnx build script
./build-ios.sh

echo -e "${YELLOW}Copying XCFramework to project...${NC}"

# Create destination directory
DEST_DIR="$PROJECT_ROOT/third_party/sherpa-onnx-ios"
mkdir -p "$DEST_DIR"

# Copy the built XCFramework
if [ -d "$BUILD_DIR/sherpa-onnx.xcframework" ]; then
    rm -rf "$DEST_DIR/sherpa-onnx.xcframework"
    cp -r "$BUILD_DIR/sherpa-onnx.xcframework" "$DEST_DIR/"
    echo -e "${GREEN}✅ Sherpa-ONNX XCFramework copied to: $DEST_DIR/sherpa-onnx.xcframework${NC}"
else
    echo -e "${RED}❌ Failed to build sherpa-onnx.xcframework${NC}"
    exit 1
fi

# Get framework size
FRAMEWORK_SIZE=$(du -sh "$DEST_DIR/sherpa-onnx.xcframework" | awk '{print $1}')

echo ""
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}✅ Sherpa-ONNX iOS build successful!${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""
echo "XCFramework location:"
echo "  $DEST_DIR/sherpa-onnx.xcframework"
echo ""
echo "Size: $FRAMEWORK_SIZE"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Update CMakeLists.txt to link sherpa-onnx"
echo "2. Implement C bridge functions"
echo "3. Update Swift integration"
echo ""
