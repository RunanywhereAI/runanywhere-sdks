#!/bin/bash
# build_and_run.sh - Build, install, and run the RunAnywhereAI app
# Usage: ./build_and_run.sh [simulator|device] [device-name-or-id] [--add-models] [--build-sdk]
# Examples:
#   ./build_and_run.sh simulator "iPhone 16 Pro"
#   ./build_and_run.sh simulator "iPhone 16 Pro" --add-models
#   ./build_and_run.sh device "YOUR_DEVICE_ID"
#   ./build_and_run.sh device "Your Device Name" --add-models
#   ./build_and_run.sh simulator "iPhone 16 Pro" --build-sdk
#
# IMPORTANT: Swift Macro Support Fix
# ----------------------------------
# This project uses llm.swift which requires Swift Macros support. If you encounter
# macro fingerprint validation errors or macro-related build issues, run this command:
#
#   defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES
#
# Additionally, ensure your project has "-enable-experimental-feature Macros" in
# "Other Swift Flags" under Build Settings. This is required because llm.swift
# uses Swift Macros for code generation, particularly for LLM model definitions
# and prompt handling.

set -e

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

# Parse arguments
TARGET_TYPE="${1:-device}"
DEVICE_NAME="${2:-}"
ADD_MODELS=false
BUILD_SDK=false

# Check for help flag
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: $0 [simulator|device] [device-name-or-id] [--add-models] [--build-sdk]"
    echo ""
    echo "Arguments:"
    echo "  simulator|device    Target type (default: device)"
    echo "  device-name-or-id   Device name or ID (optional for simulator)"
    echo "  --add-models        Add model files to Xcode project (optional)"
    echo "  --build-sdk         Build the RunAnywhere SDK before building the app (optional)"
    echo ""
    echo "Examples:"
    echo "  $0 simulator \"iPhone 16 Pro\""
    echo "  $0 simulator \"iPhone 16 Pro\" --add-models"
    echo "  $0 device"
    echo "  $0 device \"My iPhone\" --add-models"
    echo "  $0 simulator \"iPhone 16 Pro\" --build-sdk"
    exit 0
fi

# Check for flags in any position after the first two arguments
for arg in "${@:3}"; do
    if [ "$arg" = "--add-models" ]; then
        ADD_MODELS=true
    elif [ "$arg" = "--build-sdk" ]; then
        BUILD_SDK=true
    fi
done

# Default values
WORKSPACE="RunAnywhereAI.xcworkspace"
SCHEME="RunAnywhereAI"
CONFIGURATION="Debug"
BUNDLE_ID="com.runanywhere.RunAnywhereAI"

# Function to fix Pods scripts for Xcode 16
fix_pods_script() {
    # Simply call the external fix script
    if [ -x "scripts/fix_pods_sandbox.sh" ]; then
        print_status "Fixing Pods scripts for Xcode 16 sandbox compatibility..."
        ./scripts/fix_pods_sandbox.sh
    else
        print_warning "fix_pods_sandbox.sh not found or not executable"
    fi
}

# Function to get device destination
get_destination() {
    if [ "$TARGET_TYPE" = "simulator" ]; then
        # First, check if there's already a booted simulator matching our criteria
        if [ -n "$DEVICE_NAME" ]; then
            # Check if the requested device is already booted
            BOOTED_ID=$(xcrun simctl list devices | grep "$DEVICE_NAME" | grep "(Booted)" | sed 's/.*(\([^)]*\)) (Booted).*/\1/' | head -1)
            if [ -n "$BOOTED_ID" ]; then
                print_status "Using already booted simulator: $DEVICE_NAME ($BOOTED_ID)" >&2
                echo "platform=iOS Simulator,id=$BOOTED_ID"
                return
            fi
            echo "platform=iOS Simulator,name=$DEVICE_NAME"
        else
            # Check for any booted iPhone simulator
            BOOTED_IPHONE=$(xcrun simctl list devices | grep -E "iPhone.*\(Booted\)" | head -1)
            if [ -n "$BOOTED_IPHONE" ]; then
                BOOTED_NAME=$(echo "$BOOTED_IPHONE" | sed 's/ *(.*//')
                BOOTED_ID=$(echo "$BOOTED_IPHONE" | sed 's/.*(\([^)]*\)) (Booted).*/\1/')
                print_status "Using already booted simulator: $BOOTED_NAME ($BOOTED_ID)" >&2
                echo "platform=iOS Simulator,id=$BOOTED_ID"
                return
            fi
            # Default to iPhone 16 simulator
            echo "platform=iOS Simulator,name=iPhone 16"
        fi
    else
        # For device - use xcodebuild to get device IDs that work with build system
        if [ -z "$DEVICE_NAME" ]; then
            # Get first connected device UUID using xcodebuild destinations
            DEVICE_ID=$(xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" -showdestinations 2>/dev/null | grep "platform:iOS" | grep -v "Simulator" | head -1 | sed -n 's/.*id:\([^,]*\).*/\1/p')
            if [ -z "$DEVICE_ID" ]; then
                print_error "No connected iOS device found!"
                exit 1
            fi
            echo "platform=iOS,id=$DEVICE_ID"
        elif [[ "$DEVICE_NAME" =~ ^[0-9a-fA-F-]+$ ]]; then
            # It's a device ID
            echo "platform=iOS,id=$DEVICE_NAME"
        else
            # It's a device name, try to find its ID using xcodebuild destinations
            DEVICE_ID=$(xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" -showdestinations 2>/dev/null | grep "platform:iOS" | grep -v "Simulator" | grep "$DEVICE_NAME" | head -1 | sed -n 's/.*id:\([^,]*\).*/\1/p')
            if [ -z "$DEVICE_ID" ]; then
                print_error "Device '$DEVICE_NAME' not found!"
                exit 1
            fi
            echo "platform=iOS,id=$DEVICE_ID"
        fi
    fi
}

# Main execution
print_status "Starting build process for $TARGET_TYPE..."

# Build SDK if requested
if [ "$BUILD_SDK" = true ]; then
    print_status "Building RunAnywhere SDK..."
    SDK_PATH="../../../sdk/runanywhere-swift"
    if [ -d "$SDK_PATH" ]; then
        pushd "$SDK_PATH" > /dev/null
        if swift build -Xswiftc -suppress-warnings 2>&1 | tee /tmp/sdk_build.log; then
            print_status "SDK built successfully!"
        else
            # Check if it's just warnings
            if grep -q "Build complete!" /tmp/sdk_build.log; then
                print_status "SDK built successfully with warnings!"
            else
                print_error "SDK build failed!"
                exit 1
            fi
        fi
        popd > /dev/null
    else
        print_error "SDK directory not found at $SDK_PATH"
        exit 1
    fi
fi

# Ensure all model files are in the project (only if --add-models flag is set)
if [ "$ADD_MODELS" = true ]; then
    if [ -x "scripts/ensure_models_in_project.sh" ]; then
        print_status "Ensuring model files are added to project..."
        ./scripts/ensure_models_in_project.sh || print_warning "Failed to add models to project"
    else
        print_warning "Model addition script not found or not executable"
    fi
fi

# Fix Pods script
fix_pods_script

# Get destination
DESTINATION=$(get_destination)
print_status "Building for destination: $DESTINATION"

# Build the app
print_status "Building the app..."
# Removed debug output
if xcodebuild -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -allowProvisioningUpdates \
    build > /tmp/xcodebuild.log 2>&1; then
    print_status "Build succeeded!"
else
    print_error "Build failed! Check /tmp/xcodebuild.log for details"
    tail -50 /tmp/xcodebuild.log
    exit 1
fi

# Install and run
if [ "$TARGET_TYPE" = "simulator" ]; then
    # For simulator
    print_status "Installing on simulator..."

    # Get the app path - use correct path for simulator builds
    if [[ "$DESTINATION" == *"id="* ]]; then
        # For simulator builds, use Debug-iphonesimulator path
        APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "RunAnywhereAI.app" -path "*/Debug-iphonesimulator/*" -not -path "*/Index.noindex/*" | head -1)
    else
        # Fallback to old method
        APP_PATH=$(xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" -configuration "$CONFIGURATION" -showBuildSettings | grep "BUILT_PRODUCTS_DIR" | head -1 | awk '{print $3}')
        APP_PATH="$APP_PATH/$SCHEME.app"
    fi

    # Extract simulator ID from destination if it's an ID-based destination
    if [[ "$DESTINATION" == *"id="* ]]; then
        SIMULATOR_ID=$(echo "$DESTINATION" | sed 's/.*id=//')
        print_status "Using simulator ID from destination: $SIMULATOR_ID"
    else
        # Boot simulator if needed (name-based destination)
        SIMULATOR_ID=$(xcrun simctl list devices | grep "$DEVICE_NAME" | grep -v "unavailable" | awk -F '[()]' '{print $2}' | head -1)
        if [ -z "$SIMULATOR_ID" ]; then
            SIMULATOR_ID=$(xcrun simctl list devices | grep "iPhone 16" | grep -v "unavailable" | awk -F '[()]' '{print $2}' | head -1)
        fi
        xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true
    fi

    # Install app
    xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"

    # Launch app
    print_status "Launching app on simulator..."
    xcrun simctl launch "$SIMULATOR_ID" "$BUNDLE_ID"

    # Open simulator
    open -a Simulator

else
    # For device
    # Extract Xcode device ID from destination
    XCODE_DEVICE_ID=$(echo "$DESTINATION" | sed 's/platform=iOS,id=//')

    # Get the devicectl ID for the same device (needed for installation)
    # Map from Xcode device ID to devicectl device ID using device name
    DEVICE_NAME_FOR_INSTALL=$(xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" -showdestinations 2>/dev/null | grep "platform:iOS" | grep -v "Simulator" | grep "$XCODE_DEVICE_ID" | sed -n 's/.*name:\([^}]*\).*/\1/p' | sed 's/  *$//')

    if [ -n "$DEVICE_NAME_FOR_INSTALL" ]; then
        DEVICECTL_ID=$(xcrun devicectl list devices | grep "$DEVICE_NAME_FOR_INSTALL" | grep "connected" | head -1 | awk '{print $3}')
    else
        # Fallback: use first connected device
        DEVICECTL_ID=$(xcrun devicectl list devices | grep -E "iPhone|iPad" | grep "connected" | head -1 | awk '{print $3}')
    fi

    if [ -z "$DEVICECTL_ID" ]; then
        print_error "Could not find device for installation!"
        exit 1
    fi

    print_status "Using device: $DEVICE_NAME_FOR_INSTALL (Xcode: $XCODE_DEVICE_ID, devicectl: $DEVICECTL_ID)"

    # Get the built app path
    APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "RunAnywhereAI.app" -path "*/Debug-iphoneos/*" -not -path "*/Index.noindex/*" | head -1)

    if [ -z "$APP_PATH" ]; then
        print_error "Could not find built app!"
        exit 1
    fi

    print_status "Installing app on device..."
    if xcrun devicectl device install app --device "$DEVICECTL_ID" "$APP_PATH"; then
        print_status "App installed successfully!"
    else
        print_error "Failed to install app!"
        exit 1
    fi

    print_status "Launching app on device..."
    if xcrun devicectl device process launch --device "$DEVICECTL_ID" "$BUNDLE_ID"; then
        print_status "App launched successfully!"
    else
        print_error "Failed to launch app!"
        exit 1
    fi
fi

print_status "Done! The app is now running on your $TARGET_TYPE."
