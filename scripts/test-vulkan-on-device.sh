#!/bin/bash
# Test Vulkan on Android Device
# This script tests if Vulkan actually works on connected device

set -e

echo "=========================================="
echo "VULKAN DEVICE TEST"
echo "=========================================="

# Check if device connected
if ! adb devices | grep -q "device$"; then
    echo "❌ ERROR: No Android device connected"
    exit 1
fi

echo ""
echo "1. Device Information:"
DEVICE_MODEL=$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r')
DEVICE_BRAND=$(adb shell getprop ro.product.brand 2>/dev/null | tr -d '\r')
ANDROID_VERSION=$(adb shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')
GPU_RENDERER=$(adb shell dumpsys SurfaceFlinger | grep "GLES:" | head -1 | cut -d: -f2 | xargs)

echo "   Brand: $DEVICE_BRAND"
echo "   Model: $DEVICE_MODEL"
echo "   Android: $ANDROID_VERSION"
echo "   GPU: $GPU_RENDERER"

echo ""
echo "2. Checking Vulkan support on device..."
# Check if Vulkan library exists
if adb shell "ls /system/lib64/libvulkan.so" 2>/dev/null | grep -q "libvulkan.so"; then
    echo "   ✅ libvulkan.so found"
else
    echo "   ❌ libvulkan.so NOT found - Vulkan not supported"
    exit 1
fi

echo ""
echo "3. Installing test app..."
if [ ! -f "examples/android/RunAnywhereAI/app/build/outputs/apk/debug/app-debug.apk" ]; then
    echo "   ❌ APK not found. Build first with: ./gradlew assembleDebug"
    exit 1
fi

adb install -r examples/android/RunAnywhereAI/app/build/outputs/apk/debug/app-debug.apk > /dev/null 2>&1
echo "   ✅ App installed"

echo ""
echo "4. Testing app launch..."
adb logcat -c
adb shell am start -n com.runanywhere.runanywhereai.debug/com.runanywhere.runanywhereai.MainActivity > /dev/null 2>&1
sleep 5

# Check for crash
if adb logcat -d | grep -q "Fatal signal 11"; then
    echo "   ❌ CRASH DETECTED"
    echo ""
    echo "   Crash details:"
    adb logcat -d | grep -A 5 "Fatal signal 11" | head -10
    echo ""
    echo "   ⚠️  VULKAN CAUSES CRASH ON THIS DEVICE"
    echo "   Device: $DEVICE_BRAND $DEVICE_MODEL"
    echo "   GPU: $GPU_RENDERER"
    exit 1
else
    echo "   ✅ App launched without crash"
fi

echo ""
echo "5. Checking GPU logs..."
GPU_LOGS=$(adb logcat -d | grep -E "RAC_GPU_STATUS|Android detected|GPU|Vulkan" | head -10)
if [ -z "$GPU_LOGS" ]; then
    echo "   ⚠️  No GPU logs found"
else
    echo "   GPU Logs:"
    echo "$GPU_LOGS" | sed 's/^/     /'
fi

echo ""
echo "=========================================="
echo "TEST RESULT"
echo "=========================================="
echo "Device: $DEVICE_BRAND $DEVICE_MODEL ($GPU_RENDERER)"
echo "Status: ✅ NO CRASH (but may have other issues)"
echo ""
echo "⚠️  NOTE: No crash doesn't mean Vulkan works correctly!"
echo "   - Output may be gibberish (like Adreno 732 issue)"
echo "   - Performance may be worse than CPU"
echo "   - Memory allocation may fail during inference"
echo ""
