#!/bin/bash
# Compile ALL Vulkan shaders using the official vulkan-shaders-gen tool
# This mimics what CMake would do during normal build

set -e

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

VULKAN_DIR="$PROJECT_ROOT/sdk/runanywhere-commons/build/android/unified/arm64-v8a/_deps/llamacpp-src/ggml/src/ggml-vulkan"
SHADER_DIR="$VULKAN_DIR/vulkan-shaders"
TOOL="$VULKAN_DIR/vulkan-shaders-gen-host"
# Use HOST glslc instead of NDK's outdated version (v2023.8 vs v2022.3)
HOST_GLSLC=$(which glslc)
if [ -z "$HOST_GLSLC" ]; then
    echo "Error: glslc not found in PATH. Please install Vulkan SDK."
    exit 1
fi
OUTPUT_DIR="$VULKAN_DIR"

if [ ! -f "$TOOL" ]; then
    echo "Error: vulkan-shaders-gen-host not found at: $TOOL"
    echo "Please compile it first"
    exit 1
fi

if [ ! -f "$HOST_GLSLC" ] && [ ! -x "$(command -v glslc)" ]; then
    echo "Error: glslc not found. Please install Vulkan SDK."
    exit 1
fi

echo "=========================================="
echo "Compiling ALL Vulkan Shaders"
echo "=========================================="
echo "Tool: $TOOL"
echo "glslc: $HOST_GLSLC (HOST version - newer than NDK)"
echo "Shader dir: $SHADER_DIR"
echo "Output dir: $OUTPUT_DIR"
echo ""

# Count shader files
SHADER_COUNT=$(ls "$SHADER_DIR"/*.comp 2>/dev/null | wc -l)
echo "Found $SHADER_COUNT shader files"
echo ""

# Compile each shader
COMPILED=0
FAILED=0

for shader_file in "$SHADER_DIR"/*.comp; do
    shader_name=$(basename "$shader_file")
    echo -n "Compiling $shader_name... "
    
    if "$TOOL" \
        --glslc "$HOST_GLSLC" \
        --source "$shader_file" \
        --output-dir "$OUTPUT_DIR" \
        > /dev/null 2>&1; then
        echo "✓"
        COMPILED=$((COMPILED + 1))
    else
        echo "✗"
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "=========================================="
echo "Compilation Summary"
echo "=========================================="
echo "Total shaders: $SHADER_COUNT"
echo "Compiled: $COMPILED"
echo "Failed: $FAILED"
echo ""

# Now generate the header and cpp files
echo "Generating header and cpp files..."
"$TOOL" \
    --glslc "$HOST_GLSLC" \
    --output-dir "$OUTPUT_DIR" \
    --target-hpp "$OUTPUT_DIR/ggml-vulkan-shaders.hpp" \
    --target-cpp "$OUTPUT_DIR/ggml-vulkan-shaders.cpp"

echo ""
echo "Generated files:"
ls -lh "$OUTPUT_DIR"/ggml-vulkan-shaders.*

echo ""
echo "✓ All done!"
