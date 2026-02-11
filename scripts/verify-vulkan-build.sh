#!/bin/bash
# Verify Vulkan GPU Support Build
# This script verifies that Vulkan is properly compiled and linked

set -e

echo "=========================================="
echo "VULKAN BUILD VERIFICATION"
echo "=========================================="

LIB_PATH="sdk/runanywhere-commons/build/android/unified/arm64-v8a/src/backends/llamacpp/librac_backend_llamacpp.so"

if [ ! -f "$LIB_PATH" ]; then
    echo "❌ ERROR: Library not found at $LIB_PATH"
    exit 1
fi

echo ""
echo "1. Checking library size..."
SIZE=$(du -h "$LIB_PATH" | cut -f1)
echo "   Library size: $SIZE"
if [ "${SIZE%M}" -lt 50 ]; then
    echo "   ❌ FAIL: Library too small (expected >50MB with Vulkan)"
    exit 1
fi
echo "   ✅ PASS: Library size indicates Vulkan included"

echo ""
echo "2. Checking Vulkan symbols..."
VULKAN_SYMBOLS=$(readelf -s "$LIB_PATH" 2>/dev/null | grep -i "ggml_vk\|vulkan" | wc -l)
echo "   Found $VULKAN_SYMBOLS Vulkan symbols"
if [ "$VULKAN_SYMBOLS" -lt 100 ]; then
    echo "   ❌ FAIL: Too few Vulkan symbols (expected >100)"
    exit 1
fi
echo "   ✅ PASS: Vulkan symbols present"

echo ""
echo "3. Checking critical Vulkan functions..."
CRITICAL_FUNCS=("ggml_vk" "vulkan" "vk_")
for func in "${CRITICAL_FUNCS[@]}"; do
    COUNT=$(readelf -s "$LIB_PATH" 2>/dev/null | grep -i "$func" | wc -l)
    if [ "$COUNT" -gt 0 ]; then
        echo "   ✅ $func* - FOUND ($COUNT symbols)"
    else
        echo "   ❌ $func* - MISSING"
        exit 1
    fi
done

echo ""
echo "4. Checking CMake configuration..."
CMAKE_CACHE="sdk/runanywhere-commons/build/android/unified/arm64-v8a/CMakeCache.txt"
if grep -q "GGML_VULKAN:BOOL=ON" "$CMAKE_CACHE"; then
    echo "   ✅ GGML_VULKAN=ON in CMake"
else
    echo "   ❌ GGML_VULKAN not enabled in CMake"
    exit 1
fi

echo ""
echo "5. Checking Vulkan shaders..."
SHADER_COUNT=$(find sdk/runanywhere-commons/build/android/unified/arm64-v8a/_deps/llamacpp-src/ggml/src/ggml-vulkan -name "*.spv" 2>/dev/null | wc -l)
echo "   Found $SHADER_COUNT compiled shaders"
if [ "$SHADER_COUNT" -lt 1000 ]; then
    echo "   ❌ FAIL: Too few shaders (expected >1000)"
    exit 1
fi
echo "   ✅ PASS: Vulkan shaders compiled"

echo ""
echo "=========================================="
echo "✅ ALL CHECKS PASSED"
echo "=========================================="
echo ""
echo "SUMMARY:"
echo "  - Library size: $SIZE"
echo "  - Vulkan symbols: $VULKAN_SYMBOLS"
echo "  - Compiled shaders: $SHADER_COUNT"
echo "  - Build: VERIFIED"
echo ""
