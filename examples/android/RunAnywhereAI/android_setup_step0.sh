#!/bin/bash

# RunAnywhere Android Setup - Step 0: Emulator Setup and Basic App Launch
# This script sets up Android development environment and launches a basic app

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
EMULATOR_NAME="RunAnywhere_API35"
ANDROID_API="35"
ANDROID_IMAGE="google_apis_playstore"
DEVICE_TYPE="pixel_7"

echo -e "${BLUE}🚀 RunAnywhere Android Setup - Step 0${NC}"
echo -e "${BLUE}================================================${NC}"

# Function to check command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to print status
print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Check prerequisites
echo -e "\n${BLUE}1. Checking Prerequisites${NC}"
echo "================================"

# Check Android SDK
if [ -z "$ANDROID_HOME" ]; then
    print_error "ANDROID_HOME not set. Please install Android Studio and set ANDROID_HOME"
    echo "Example: export ANDROID_HOME=~/Library/Android/sdk"
    exit 1
fi
print_status "ANDROID_HOME: $ANDROID_HOME"

# Check SDK tools
if ! command_exists "sdkmanager"; then
    print_error "sdkmanager not found. Please ensure Android SDK command line tools are installed"
    exit 1
fi
print_status "sdkmanager found"

if ! command_exists "avdmanager"; then
    print_error "avdmanager not found. Please ensure Android SDK command line tools are installed"
    exit 1
fi
print_status "avdmanager found"

if ! command_exists "emulator"; then
    print_error "emulator not found. Please ensure Android Emulator is installed"
    exit 1
fi
print_status "emulator found"

if ! command_exists "adb"; then
    print_error "adb not found. Please ensure Android Debug Bridge is installed"
    exit 1
fi
print_status "adb found"

# Check Java
if ! command_exists "java"; then
    print_error "Java not found. Please install JDK 17 or higher"
    exit 1
fi
print_status "Java found: $(java -version 2>&1 | head -n 1)"

# Install required SDK components
echo -e "\n${BLUE}2. Installing Required SDK Components${NC}"
echo "=========================================="

print_info "Installing Android API $ANDROID_API system image..."
yes | sdkmanager "system-images;android-$ANDROID_API;$ANDROID_IMAGE;arm64-v8a" 2>/dev/null || {
    print_warning "Failed to install system image, it might already be installed"
}

print_info "Installing platform tools..."
yes | sdkmanager "platform-tools" 2>/dev/null || {
    print_warning "Failed to install platform tools, they might already be installed"
}

print_info "Installing build tools..."
yes | sdkmanager "build-tools;35.0.0" 2>/dev/null || {
    print_warning "Failed to install build tools, they might already be installed"
}

print_status "SDK components installation completed"

# Create or start emulator
echo -e "\n${BLUE}3. Emulator Setup${NC}"
echo "======================"

# Check if emulator already exists
if avdmanager list avd | grep -q "$EMULATOR_NAME"; then
    print_status "Emulator '$EMULATOR_NAME' already exists"
else
    print_info "Creating new emulator '$EMULATOR_NAME'..."
    echo "no" | avdmanager create avd \
        -n "$EMULATOR_NAME" \
        -k "system-images;android-$ANDROID_API;$ANDROID_IMAGE;arm64-v8a" \
        -d "$DEVICE_TYPE" \
        --force
    print_status "Emulator '$EMULATOR_NAME' created successfully"
fi

# Check if emulator is already running
if adb devices | grep -q "emulator"; then
    print_status "Emulator is already running"
    EMULATOR_DEVICE=$(adb devices | grep emulator | cut -f1)
    print_info "Using running emulator: $EMULATOR_DEVICE"
else
    print_info "Starting emulator '$EMULATOR_NAME'..."
    print_warning "This may take a few minutes on first boot..."

    # Start emulator in background
    emulator -avd "$EMULATOR_NAME" -no-snapshot-save -wipe-data &
    EMULATOR_PID=$!

    print_info "Waiting for emulator to boot..."
    adb wait-for-device

    # Wait for system to be ready
    print_info "Waiting for Android system to be ready..."
    while [ "$(adb shell getprop sys.boot_completed 2>/dev/null)" != "1" ]; do
        sleep 2
        echo -n "."
    done
    echo ""

    print_status "Emulator is ready!"
fi

# Verify device connection
echo -e "\n${BLUE}4. Device Verification${NC}"
echo "========================="

DEVICE_INFO=$(adb shell getprop ro.product.model 2>/dev/null || echo "Unknown")
ANDROID_VERSION=$(adb shell getprop ro.build.version.release 2>/dev/null || echo "Unknown")
API_LEVEL=$(adb shell getprop ro.build.version.sdk 2>/dev/null || echo "Unknown")

print_status "Connected Device: $DEVICE_INFO"
print_status "Android Version: $ANDROID_VERSION (API $API_LEVEL)"

# Build and install basic Android app
echo -e "\n${BLUE}5. Building and Installing Android App${NC}"
echo "========================================="

# Already in the Android app directory

print_info "Cleaning project..."
./gradlew clean

print_info "Building debug APK..."
./gradlew :app:assembleDebug

if [ -f "app/build/outputs/apk/debug/app-debug.apk" ]; then
    print_status "Build successful!"

    print_info "Installing app on device..."
    adb install -r app/build/outputs/apk/debug/app-debug.apk

    print_info "Launching app..."

    # Launch the app on the device
    adb shell am start -n com.runanywhere.runanywhereai.debug/com.runanywhere.runanywhereai.MainActivity

    print_status "App launched successfully on device!"
    print_status "Setup complete - ready for Phase 1 implementation!"
else
    print_error "Build failed! APK not found."
    exit 1
fi

# Final status
echo -e "\n${GREEN}🎉 Step 0 Setup Complete!${NC}"
echo "=========================="
print_status "Android emulator is running"
print_status "RunAnywhereAI app is installed and launched"
print_info "You can now proceed with development phases"

echo -e "\n${BLUE}Quick Commands:${NC}"
echo "==============="
echo "• View logs: adb logcat | grep RunAnywhere"
echo "• Restart app: adb shell am start -n com.runanywhere.runanywhereai.debug/com.runanywhere.runanywhereai.MainActivity"
echo "• Stop emulator: adb emu kill"
echo "• List devices: adb devices"

echo -e "\n${BLUE}Next Steps:${NC}"
echo "============"
echo "1. Verify the app UI matches iOS equivalent"
echo "2. Test basic functionality"
echo "3. Proceed with Phase 1: Core SDK Implementation"

print_status "Step 0 setup completed successfully! 🚀"
