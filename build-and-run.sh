#!/bin/bash

# Build and Run Script for RunAnywhere AI Android App
# Usage: ./build-and-run.sh

set -e  # Exit on error

echo "================================================"
echo "RunAnywhere AI - Android Build & Deploy Script"
echo "================================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Check if we're in the right directory
if [ ! -f "settings.gradle.kts" ]; then
    print_error "Not in the project root directory!"
    echo "Please run this script from the android_init directory"
    exit 1
fi

# Check for connected device
print_status "Checking for connected Android devices..."
DEVICE_COUNT=$(adb devices | grep -c "device$" || true)

if [ "$DEVICE_COUNT" -eq 0 ]; then
    print_error "No Android device connected!"
    echo "Please connect your Pixel 8 Pro and enable USB debugging"
    exit 1
else
    print_status "Found $DEVICE_COUNT connected device(s)"
    adb devices
fi

# Navigate to the sample app directory
cd examples/android/RunAnywhereAI

# Clean previous builds
print_status "Cleaning previous builds..."
./gradlew clean

# Build the SDK modules first
print_status "Building SDK modules..."
./gradlew :sdk-core:build :sdk-jni:build

# Build the app
print_status "Building the RunAnywhereAI app..."
./gradlew assembleDebug

# Check if APK was built successfully
APK_PATH="app/build/outputs/apk/debug/app-debug.apk"
if [ ! -f "$APK_PATH" ]; then
    print_error "APK not found at $APK_PATH"
    exit 1
fi

APK_SIZE=$(du -h "$APK_PATH" | cut -f1)
print_status "APK built successfully (Size: $APK_SIZE)"

# Get device information
DEVICE_MODEL=$(adb shell getprop ro.product.model | tr -d '\r')
ANDROID_VERSION=$(adb shell getprop ro.build.version.release | tr -d '\r')
print_status "Target device: $DEVICE_MODEL (Android $ANDROID_VERSION)"

# Uninstall previous version if exists
print_status "Checking for previous installation..."
if adb shell pm list packages | grep -q "com.runanywhere.runanywhereai"; then
    print_warning "Previous version found. Uninstalling..."
    adb uninstall com.runanywhere.runanywhereai
fi

# Install the app
print_status "Installing app on device..."
adb install -r "$APK_PATH"

# Grant permissions
print_status "Granting necessary permissions..."
adb shell pm grant com.runanywhere.runanywhereai android.permission.RECORD_AUDIO || true
adb shell pm grant com.runanywhere.runanywhereai android.permission.WRITE_EXTERNAL_STORAGE || true
adb shell pm grant com.runanywhere.runanywhereai android.permission.READ_EXTERNAL_STORAGE || true

# Create model directory on device
print_status "Creating model directory on device..."
adb shell mkdir -p /sdcard/Android/data/com.runanywhere.runanywhereai/files/models/

# Check if we should download the Whisper model
echo ""
print_warning "Note: The app requires a Whisper model to function."
echo "Would you like to download and install the Whisper Base model (74MB)? (y/n)"
read -r response

if [[ "$response" =~ ^[Yy]$ ]]; then
    print_status "Downloading Whisper Base model..."
    MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"
    MODEL_FILE="ggml-base.bin"

    if [ ! -f "$MODEL_FILE" ]; then
        curl -L -o "$MODEL_FILE" "$MODEL_URL" || {
            print_error "Failed to download model"
            print_warning "You'll need to manually download the model later"
        }
    fi

    if [ -f "$MODEL_FILE" ]; then
        print_status "Pushing model to device..."
        adb push "$MODEL_FILE" /sdcard/Android/data/com.runanywhere.runanywhereai/files/models/
        print_status "Model installed successfully"
    fi
fi

# Launch the app
print_status "Launching RunAnywhereAI app..."
adb shell am start -n com.runanywhere.runanywhereai/.MainActivity

# Show logs
echo ""
echo "================================================"
print_status "App launched successfully!"
echo "================================================"
echo ""
echo "To view logs, run:"
echo "  adb logcat | grep -E 'RunAnywhereAI|WhisperSTT|WebRTCVAD'"
echo ""
echo "To stop logging, press Ctrl+C"
echo ""
echo "Would you like to view logs now? (y/n)"
read -r response

if [[ "$response" =~ ^[Yy]$ ]]; then
    print_status "Showing app logs (Press Ctrl+C to stop)..."
    adb logcat -c  # Clear old logs
    adb logcat | grep -E "RunAnywhereAI|WhisperSTT|WebRTCVAD|MainActivity"
fi
