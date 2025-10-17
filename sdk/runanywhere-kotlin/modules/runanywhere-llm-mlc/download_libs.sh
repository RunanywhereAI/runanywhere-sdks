#!/bin/bash
# Download MLC4J native libraries from latest release
# This script fetches the latest pre-built Android libraries from MLC-LLM releases

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/mlc-llm/android/mlc4j/output"

echo "🔍 Fetching latest MLC-LLM release..."

# Get latest release info from GitHub API
LATEST_RELEASE=$(curl -s https://api.github.com/repos/mlc-ai/mlc-llm/releases/latest)
RELEASE_TAG=$(echo "$LATEST_RELEASE" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "$RELEASE_TAG" ]; then
    echo "❌ Failed to fetch latest release tag"
    exit 1
fi

echo "✓ Latest release: $RELEASE_TAG"

# Look for Android AAR in assets
ANDROID_AAR_URL=$(echo "$LATEST_RELEASE" | grep -o 'https://github.com/mlc-ai/mlc-llm/releases/download/[^"]*mlc4j[^"]*\.aar' | head -1)

if [ -z "$ANDROID_AAR_URL" ]; then
    echo "⚠️  No pre-built AAR found in release $RELEASE_TAG"
    echo ""
    echo "You'll need to build from source using:"
    echo "  export ANDROID_NDK=\$HOME/Library/Android/sdk/ndk/26.3.11579264"
    echo "  python3 prepare_libs.py --mlc-llm-source-dir ../.."
    echo ""
    echo "Or download manually from: https://github.com/mlc-ai/mlc-llm/releases/latest"
    exit 1
fi

echo "✓ Found Android AAR: $ANDROID_AAR_URL"
echo ""
echo "📥 Downloading..."

# Create temp directory
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Download AAR
AAR_FILE="$TEMP_DIR/mlc4j.aar"
curl -L -o "$AAR_FILE" "$ANDROID_AAR_URL"

echo "✓ Downloaded"
echo ""
echo "📦 Extracting native libraries..."

# Extract AAR (it's a ZIP file)
EXTRACT_DIR="$TEMP_DIR/extracted"
mkdir -p "$EXTRACT_DIR"
unzip -q "$AAR_FILE" -d "$EXTRACT_DIR"

# Create output directory structure
mkdir -p "$OUTPUT_DIR/arm64-v8a"

# Copy tvm4j_core.jar (if present in AAR)
if [ -f "$EXTRACT_DIR/classes.jar" ]; then
    cp "$EXTRACT_DIR/classes.jar" "$OUTPUT_DIR/tvm4j_core.jar"
    echo "✓ Copied tvm4j_core.jar"
fi

# Copy native libraries
if [ -d "$EXTRACT_DIR/jni/arm64-v8a" ]; then
    cp "$EXTRACT_DIR/jni/arm64-v8a"/*.so "$OUTPUT_DIR/arm64-v8a/" 2>/dev/null || true
    echo "✓ Copied arm64-v8a libraries"
fi

# Verify files
echo ""
echo "📋 Verification:"
echo ""

if [ -f "$OUTPUT_DIR/tvm4j_core.jar" ]; then
    SIZE=$(du -h "$OUTPUT_DIR/tvm4j_core.jar" | cut -f1)
    echo "  ✓ tvm4j_core.jar ($SIZE)"
else
    echo "  ❌ tvm4j_core.jar NOT FOUND"
    echo "     You may need to build manually with prepare_libs.py"
fi

if [ -f "$OUTPUT_DIR/arm64-v8a/libtvm4j_runtime_packed.so" ]; then
    SIZE=$(du -h "$OUTPUT_DIR/arm64-v8a/libtvm4j_runtime_packed.so" | cut -f1)
    echo "  ✓ libtvm4j_runtime_packed.so ($SIZE)"
else
    echo "  ❌ libtvm4j_runtime_packed.so NOT FOUND"
    echo "     You may need to build manually with prepare_libs.py"
fi

echo ""
TOTAL_SIZE=$(du -sh "$OUTPUT_DIR" | cut -f1)
echo "✅ Total size: $TOTAL_SIZE"
echo ""
echo "📍 Libraries installed to:"
echo "  $OUTPUT_DIR"
echo ""
echo "Next: Build the module"
echo "  cd ../../.."
echo "  ./gradlew :modules:runanywhere-llm-mlc:build"
