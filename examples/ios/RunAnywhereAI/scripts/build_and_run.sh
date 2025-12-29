#!/bin/bash
# build_and_run.sh - Build, install, and run the RunAnywhereAI app
# Usage: ./build_and_run.sh [simulator|device|mac] [device-name-or-id] [--add-models] [--build-sdk] [--build-cpp] [--clean] [--clean-data]
# Examples:
#   ./build_and_run.sh simulator "iPhone 16 Pro"
#   ./build_and_run.sh simulator "iPhone 16 Pro" --add-models
#   ./build_and_run.sh device "YOUR_DEVICE_ID"
#   ./build_and_run.sh device "Your Device Name" --add-models
#   ./build_and_run.sh simulator "iPhone 16 Pro" --build-sdk
#   ./build_and_run.sh simulator "iPhone 16 Pro" --build-cpp --build-sdk
#   ./build_and_run.sh simulator "iPhone 16 Pro" --build-cpp   # Builds C++ and Swift SDK
#   ./build_and_run.sh simulator "iPhone 16 Pro" --clean
#   ./build_and_run.sh simulator "iPhone 16 Pro" --clean-data
#   ./build_and_run.sh mac
#   ./build_and_run.sh mac --clean
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
BLUE='\033[0;34m'
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

print_debug() {
    if [ "${DEBUG:-0}" = "1" ]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

# Function to check required tools
check_requirements() {
    local missing_tools=()

    # Check for xcodebuild
    if ! command -v xcodebuild &> /dev/null; then
        missing_tools+=("xcodebuild (Xcode)")
    fi

    # Check for xcrun
    if ! command -v xcrun &> /dev/null; then
        missing_tools+=("xcrun (Xcode Command Line Tools)")
    fi

    # CocoaPods is no longer required - using Swift Package Manager only

    # Check if any required tools are missing
    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_error "Missing required tools:"
        for tool in "${missing_tools[@]}"; do
            print_error "  - $tool"
        done
        print_error "Please install Xcode from the App Store and run: xcode-select --install"
        exit 1
    fi

    # Check Xcode selection
    if ! xcode-select -p &> /dev/null; then
        print_error "Xcode path not set. Run: sudo xcode-select --switch /Applications/Xcode.app"
        exit 1
    fi

    print_status "All required tools are installed"
}

# Parse arguments
TARGET_TYPE="${1:-device}"
DEVICE_NAME="${2:-}"
ADD_MODELS=false
BUILD_SDK=false
BUILD_CPP=false
CLEAN_BUILD=false
CLEAN_DATA=false
FORCE_PROJECT=false
SDK_ONLY=false

# Check for help flag
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: $0 [simulator|device|mac] [device-name-or-id] [--add-models] [--build-sdk] [--build-cpp] [--clean] [--clean-data]"
    echo ""
    echo "Arguments:"
    echo "  simulator|device|mac  Target type (default: device)"
    echo "  device-name-or-id     Device name or ID (optional for simulator, not used for mac)"
    echo "  --add-models          Add model files to Xcode project (optional)"
    echo "  --build-sdk           Build the RunAnywhere Swift SDK before building the app"
    echo "  --build-cpp           Build C++ layer (runanywhere-commons), copy XCFrameworks, sync headers, and build Swift SDK"
    echo "  --sdk-only            Only build C++/SDK, skip Xcode app build (use with --build-cpp or --build-sdk)"
    echo "  --clean               Clean all build artifacts before building (optional)"
    echo "  --clean-data          Clean app data including database (optional)"
    echo ""
    echo "Examples:"
    echo "  $0 simulator \"iPhone 16 Pro\""
    echo "  $0 simulator \"iPhone 16 Pro\" --add-models"
    echo "  $0 device"
    echo "  $0 device \"My iPhone\" --add-models"
    echo "  $0 simulator \"iPhone 16 Pro\" --build-sdk"
    echo "  $0 simulator \"iPhone 16 Pro\" --build-cpp"
    echo "  $0 simulator \"iPhone 16 Pro\" --build-cpp --sdk-only"
    echo "  $0 simulator \"iPhone 16 Pro\" --clean"
    echo "  $0 simulator \"iPhone 16 Pro\" --clean-data"
    echo "  $0 mac"
    echo "  $0 mac --clean"
    exit 0
fi

# Check for flags in any position after the first two arguments
for arg in "${@:3}"; do
    if [ "$arg" = "--add-models" ]; then
        ADD_MODELS=true
    elif [ "$arg" = "--build-sdk" ]; then
        BUILD_SDK=true
    elif [ "$arg" = "--build-cpp" ]; then
        BUILD_CPP=true
        BUILD_SDK=true  # Building C++ implies building Swift SDK too
    elif [ "$arg" = "--clean" ]; then
        CLEAN_BUILD=true
    elif [ "$arg" = "--clean-data" ]; then
        CLEAN_DATA=true
        CLEAN_BUILD=true  # Clean data implies clean build
    elif [ "$arg" = "--use-project" ]; then
        FORCE_PROJECT=true
    elif [ "$arg" = "--sdk-only" ]; then
        SDK_ONLY=true
    fi
done

# Default values
PROJECT="RunAnywhereAI.xcodeproj"
SCHEME="RunAnywhereAI"
CONFIGURATION="Debug"
BUNDLE_ID="com.runanywhere.RunAnywhereAI"

# Always use project file now (no CocoaPods workspace)
USE_PROJECT=true

# Function to get device destination
get_destination() {
    if [ "$TARGET_TYPE" = "mac" ]; then
        # For macOS
        echo "platform=macOS"
    elif [ "$TARGET_TYPE" = "simulator" ]; then
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
            if [ "$USE_PROJECT" = "true" ]; then
                DEVICE_ID=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showdestinations 2>/dev/null | grep "platform:iOS" | grep -v "Simulator" | head -1 | sed -n 's/.*id:\([^,]*\).*/\1/p')
            else
                DEVICE_ID=$(xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" -showdestinations 2>/dev/null | grep "platform:iOS" | grep -v "Simulator" | head -1 | sed -n 's/.*id:\([^,]*\).*/\1/p')
            fi
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
            if [ "$USE_PROJECT" = "true" ]; then
                DEVICE_ID=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showdestinations 2>/dev/null | grep "platform:iOS" | grep -v "Simulator" | grep "$DEVICE_NAME" | head -1 | sed -n 's/.*id:\([^,]*\).*/\1/p')
            else
                DEVICE_ID=$(xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" -showdestinations 2>/dev/null | grep "platform:iOS" | grep -v "Simulator" | grep "$DEVICE_NAME" | head -1 | sed -n 's/.*id:\([^,]*\).*/\1/p')
            fi
            if [ -z "$DEVICE_ID" ]; then
                print_error "Device '$DEVICE_NAME' not found!"
                exit 1
            fi
            echo "platform=iOS,id=$DEVICE_ID"
        fi
    fi
}

# Function to clean build artifacts
clean_build_artifacts() {
    print_status "Cleaning build artifacts..."

    # Clean DerivedData
    print_status "Removing DerivedData..."
    rm -rf ~/Library/Developer/Xcode/DerivedData/RunAnywhereAI-*

    # Clean local build directory
    if [ -d "build" ]; then
        print_status "Removing local build directory..."
        rm -rf build/
    fi

    # Clean using xcodebuild
    print_status "Running xcodebuild clean..."
    if [ "$USE_PROJECT" = "true" ]; then
        xcodebuild clean -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" >/dev/null 2>&1 || true
    else
        xcodebuild clean -workspace "$WORKSPACE" -scheme "$SCHEME" -configuration "$CONFIGURATION" >/dev/null 2>&1 || true
    fi

    # Clean Swift Package Manager cache
    print_status "Cleaning Swift Package Manager cache..."
    rm -rf .build/
    rm -rf ~/Library/Caches/org.swift.swiftpm/

    # CocoaPods removed - no need to clean Pods
    print_status "CocoaPods dependencies removed - using Swift Package Manager"
}

# Function to clean app data
clean_app_data() {
    print_status "Cleaning app data including database..."

    # Remove app data from simulators
    BUNDLE_ID="com.runanywhere.RunAnywhereAI"
    LEGACY_BUNDLE_ID="com.runanywhere.ai.RunAnywhereAI"  # Also clean legacy bundle ID

    print_status "Removing simulator app data..."
    # Clean both bundle IDs
    rm -rf ~/Library/Developer/CoreSimulator/Devices/*/data/Containers/Data/Application/*/${BUNDLE_ID}/Documents/* 2>/dev/null || true
    rm -rf ~/Library/Developer/CoreSimulator/Devices/*/data/Containers/Data/Application/*/${LEGACY_BUNDLE_ID}/Documents/* 2>/dev/null || true

    # Clean app container if it exists
    find ~/Library/Developer/CoreSimulator/Devices/*/data/Containers/Data/Application -name ".com.apple.mobile_container_manager.metadata.plist" -exec grep -l "${BUNDLE_ID}\|${LEGACY_BUNDLE_ID}" {} \; | while read plist; do
        APP_DIR=$(dirname "$plist")
        if [ -d "$APP_DIR/Documents" ]; then
            print_status "Cleaning app data in: $APP_DIR"
            rm -rf "$APP_DIR/Documents"/*
        fi
    done

    print_status "App data cleaned successfully!"
}

# Function to get DerivedData path
get_derived_data_path() {
    # First try to get from xcodebuild
    if [ "$USE_PROJECT" = "true" ]; then
        local derived_data=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showBuildSettings 2>/dev/null | grep -E "^\s*BUILD_ROOT" | head -1 | awk '{print $3}' | sed 's|/Build/Products||')
    else
        local derived_data=$(xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" -showBuildSettings 2>/dev/null | grep -E "^\s*BUILD_ROOT" | head -1 | awk '{print $3}' | sed 's|/Build/Products||')
    fi

    if [ -n "$derived_data" ] && [ -d "$derived_data" ]; then
        echo "$derived_data"
        return
    fi

    # Fallback to default location
    echo "$HOME/Library/Developer/Xcode/DerivedData"
}

# Main execution
print_status "Starting build process for $TARGET_TYPE..."

# Check requirements first
check_requirements

# Clean if requested
if [ "$CLEAN_BUILD" = true ]; then
    clean_build_artifacts
fi

# Clean data if requested
if [ "$CLEAN_DATA" = true ]; then
    clean_app_data
fi

# Build C++ layer if requested
if [ "$BUILD_CPP" = true ]; then
    print_status "Building C++ layer (runanywhere-core + runanywhere-commons)..."

    CORE_PATH="../../../../runanywhere-core"
    COMMONS_PATH="../../../sdk/runanywhere-commons"
    SWIFT_SDK_PATH="../../../sdk/runanywhere-swift"

    # =========================================================================
    # Step 1: Build runanywhere-core iOS XCFramework
    # =========================================================================
    if [ -d "$CORE_PATH" ]; then
        print_status "Building runanywhere-core iOS XCFramework..."
        pushd "$CORE_PATH" > /dev/null

        if ./scripts/ios/build.sh 2>&1 | tee /tmp/core_build.log; then
            print_status "runanywhere-core built successfully!"
        else
            print_error "runanywhere-core build failed! Check /tmp/core_build.log"
            tail -30 /tmp/core_build.log
            exit 1
        fi

        # Create combined XCFramework
        if ./scripts/build-xcframework.sh --ios-only 2>&1 | tee -a /tmp/core_build.log; then
            print_status "RunAnywhereCore.xcframework created!"
        else
            print_warning "XCFramework creation had issues, continuing..."
        fi

        popd > /dev/null

        # Copy RunAnywhereCore.xcframework to Swift SDK
        if [ -d "$CORE_PATH/dist/RunAnywhereCore.xcframework" ]; then
            print_status "Copying RunAnywhereCore.xcframework to Swift SDK..."
            rm -rf "$SWIFT_SDK_PATH/Binaries/RunAnywhereCore.xcframework"
            cp -r "$CORE_PATH/dist/RunAnywhereCore.xcframework" "$SWIFT_SDK_PATH/Binaries/"
        fi
    else
        print_warning "runanywhere-core not found at $CORE_PATH, skipping..."
    fi

    # =========================================================================
    # Step 2: Build runanywhere-commons iOS XCFrameworks
    # =========================================================================
    if [ ! -d "$COMMONS_PATH" ]; then
        print_error "runanywhere-commons not found at $COMMONS_PATH"
        exit 1
    fi

    print_status "Building runanywhere-commons iOS XCFrameworks..."
    pushd "$COMMONS_PATH" > /dev/null

    if ./scripts/build-ios.sh 2>&1 | tee /tmp/commons_build.log; then
        print_status "runanywhere-commons XCFrameworks built successfully!"
    else
        print_error "runanywhere-commons build failed! Check /tmp/commons_build.log"
        tail -30 /tmp/commons_build.log
        exit 1
    fi

    popd > /dev/null

    # =========================================================================
    # Step 3: Clean existing XCFrameworks (full clean before fresh install)
    # =========================================================================
    print_status "Cleaning existing XCFrameworks from Swift SDK..."
    BINARIES_DIR="$SWIFT_SDK_PATH/Binaries"
    DIST_DIR="$COMMONS_PATH/dist"

    # Remove all existing XCFrameworks to ensure fresh install
    for framework in RACommons RABackendLlamaCPP RABackendONNX RunAnywhereCore onnxruntime; do
        if [ -d "$BINARIES_DIR/${framework}.xcframework" ]; then
            print_status "  Removing old ${framework}.xcframework..."
            rm -rf "$BINARIES_DIR/${framework}.xcframework"
        fi
    done

    # =========================================================================
    # Step 4: Copy ALL fresh XCFrameworks to Swift SDK Binaries
    # =========================================================================
    print_status "Installing fresh XCFrameworks to Swift SDK..."

    # Copy runanywhere-commons frameworks
    for framework in RACommons RABackendLlamaCPP RABackendONNX; do
        if [ -d "$DIST_DIR/${framework}.xcframework" ]; then
            print_status "  Installing ${framework}.xcframework..."
            cp -r "$DIST_DIR/${framework}.xcframework" "$BINARIES_DIR/"
        else
            print_warning "  ${framework}.xcframework not found in dist!"
        fi
    done

    # Copy runanywhere-core framework (if built)
    if [ -d "$CORE_PATH/dist/RunAnywhereCore.xcframework" ]; then
        print_status "  Installing RunAnywhereCore.xcframework..."
        cp -r "$CORE_PATH/dist/RunAnywhereCore.xcframework" "$BINARIES_DIR/"
    else
        print_warning "  RunAnywhereCore.xcframework not found!"
    fi

    # Copy vendored onnxruntime.xcframework (third-party dependency)
    ONNX_RUNTIME_SRC="$CORE_PATH/third_party/onnxruntime-ios/onnxruntime.xcframework"
    if [ -d "$ONNX_RUNTIME_SRC" ]; then
        print_status "  Installing onnxruntime.xcframework (vendored)..."
        cp -r "$ONNX_RUNTIME_SRC" "$BINARIES_DIR/"
    else
        print_warning "  onnxruntime.xcframework not found in third_party!"
    fi

    # =========================================================================
    # Step 5: Sync headers to CRACommons
    # =========================================================================
    print_status "Syncing headers to CRACommons..."
    HEADERS_SRC="$COMMONS_PATH/include/rac"
    HEADERS_DST="$SWIFT_SDK_PATH/Sources/CRACommons/include"

    # Copy all headers with flat structure for Swift compatibility
    for header in $(find "$HEADERS_SRC" -name "*.h" -type f); do
        header_name=$(basename "$header")
        # Convert nested includes (with subdirectories) to flat includes
        # Pattern: rac/.*/filename.h -> filename.h
        # Only matches paths with at least one subdirectory level after rac/
        # Leaves flat includes like "rac_types.h" unchanged
        sed 's|#include "rac/.*/\([^/"]*\)"|#include "\1"|g' "$header" > "$HEADERS_DST/$header_name"
    done

    print_status "C++ layer build complete!"
    print_status "Framework sizes:"
    du -sh "$BINARIES_DIR"/*.xcframework 2>/dev/null | while read size path; do
        echo "    $(basename "$path"): $size"
    done
fi

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

# Exit early if --sdk-only flag is set
if [ "$SDK_ONLY" = true ]; then
    print_status "SDK-only build complete! Skipping Xcode app build."
    print_status "You can now open Xcode and build the app manually."
    exit 0
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

# Get destination
DESTINATION=$(get_destination)
print_status "Building for destination: $DESTINATION"

# Build the app
print_status "Building the app..."
# Removed debug output
if [ "$USE_PROJECT" = "true" ]; then
    BUILD_CMD="xcodebuild -project \"$PROJECT\""
else
    BUILD_CMD="xcodebuild -workspace \"$WORKSPACE\""
fi

if eval "$BUILD_CMD" \
    -scheme \"$SCHEME\" \
    -configuration \"$CONFIGURATION\" \
    -destination \"$DESTINATION\" \
    -allowProvisioningUpdates \
    build > /tmp/xcodebuild.log 2>&1; then
    print_status "Build succeeded!"
else
    print_error "Build failed! Check /tmp/xcodebuild.log for details"
    tail -50 /tmp/xcodebuild.log
    exit 1
fi

# Install and run
if [ "$TARGET_TYPE" = "mac" ]; then
    # For macOS
    print_status "Running on macOS..."

    # Get the app path
    if [ "$USE_PROJECT" = "true" ]; then
        BUILD_DIR=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" -destination "$DESTINATION" -showBuildSettings 2>/dev/null | grep -E "^\s*BUILT_PRODUCTS_DIR" | head -1 | awk '{print $3}')
    else
        BUILD_DIR=$(xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" -configuration "$CONFIGURATION" -destination "$DESTINATION" -showBuildSettings 2>/dev/null | grep -E "^\s*BUILT_PRODUCTS_DIR" | head -1 | awk '{print $3}')
    fi

    if [ -n "$BUILD_DIR" ]; then
        APP_PATH="$BUILD_DIR/$SCHEME.app"
    fi

    # Verify the app exists
    if [ ! -d "$APP_PATH" ]; then
        print_warning "App not found at expected path, searching for built app..."

        # Search in DerivedData
        DERIVED_DATA=$(get_derived_data_path)
        APP_PATH=$(find "$DERIVED_DATA" -name "${SCHEME}.app" -path "*/Debug/*" -not -path "*/Index.noindex/*" -not -path "*-iphonesimulator/*" -not -path "*-iphoneos/*" 2>/dev/null | head -1)

        if [ ! -d "$APP_PATH" ]; then
            print_error "Could not find built app!"
            print_error "You may need to clean and rebuild. Try: $0 mac --clean"
            exit 1
        fi
    fi

    print_status "Found app at: $APP_PATH"

    # Launch the macOS app
    print_status "Launching macOS app..."
    open "$APP_PATH"

elif [ "$TARGET_TYPE" = "simulator" ]; then
    # For simulator
    print_status "Installing on simulator..."

    # Get the app path - use xcodebuild to get the exact build location
    print_debug "Getting build directory from xcodebuild..."
    if [ "$USE_PROJECT" = "true" ]; then
        BUILD_DIR=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" -destination "$DESTINATION" -showBuildSettings 2>/dev/null | grep -E "^\s*BUILT_PRODUCTS_DIR" | head -1 | awk '{print $3}')
    else
        BUILD_DIR=$(xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" -configuration "$CONFIGURATION" -destination "$DESTINATION" -showBuildSettings 2>/dev/null | grep -E "^\s*BUILT_PRODUCTS_DIR" | head -1 | awk '{print $3}')
    fi

    if [ -n "$BUILD_DIR" ]; then
        APP_PATH="$BUILD_DIR/$SCHEME.app"
        print_debug "Expected app path: $APP_PATH"
    fi

    # Verify the app exists, if not try multiple strategies
    if [ ! -d "$APP_PATH" ]; then
        print_warning "App not found at expected path, searching for built app..."

        # Strategy 1: Search in DerivedData with multiple patterns
        DERIVED_DATA=$(get_derived_data_path)
        print_debug "Searching in DerivedData: $DERIVED_DATA"

        # Try to find the app with various search patterns
        APP_PATH=$(find "$DERIVED_DATA" -name "${SCHEME}.app" -path "*/Debug-iphonesimulator/*" -not -path "*/Index.noindex/*" 2>/dev/null | head -1)

        # Strategy 2: If still not found, try without the Debug requirement
        if [ ! -d "$APP_PATH" ]; then
            APP_PATH=$(find "$DERIVED_DATA" -name "${SCHEME}.app" -path "*-iphonesimulator/*" -not -path "*/Index.noindex/*" 2>/dev/null | head -1)
        fi

        # Strategy 3: Last resort - any .app file for our scheme
        if [ ! -d "$APP_PATH" ]; then
            APP_PATH=$(find "$DERIVED_DATA" -name "${SCHEME}.app" -not -path "*/Index.noindex/*" 2>/dev/null | grep -i simulator | head -1)
        fi

        if [ ! -d "$APP_PATH" ]; then
            print_error "Could not find built app!"
            print_error "Searched in: $DERIVED_DATA"
            print_error "You may need to clean and rebuild. Try: $0 $TARGET_TYPE \"$DEVICE_NAME\" --clean"
            exit 1
        fi
    fi

    print_status "Found app at: $APP_PATH"

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
    if [ "$USE_PROJECT" = "true" ]; then
        DEVICE_NAME_FOR_INSTALL=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showdestinations 2>/dev/null | grep "platform:iOS" | grep -v "Simulator" | grep "$XCODE_DEVICE_ID" | sed -n 's/.*name:\([^}]*\).*/\1/p' | sed 's/  *$//')
    else
        DEVICE_NAME_FOR_INSTALL=$(xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" -showdestinations 2>/dev/null | grep "platform:iOS" | grep -v "Simulator" | grep "$XCODE_DEVICE_ID" | sed -n 's/.*name:\([^}]*\).*/\1/p' | sed 's/  *$//')
    fi

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

    # Get the built app path - use xcodebuild to get the exact build location
    print_debug "Getting build directory from xcodebuild..."
    if [ "$USE_PROJECT" = "true" ]; then
        BUILD_DIR=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" -destination "$DESTINATION" -showBuildSettings 2>/dev/null | grep -E "^\s*BUILT_PRODUCTS_DIR" | head -1 | awk '{print $3}')
    else
        BUILD_DIR=$(xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" -configuration "$CONFIGURATION" -destination "$DESTINATION" -showBuildSettings 2>/dev/null | grep -E "^\s*BUILT_PRODUCTS_DIR" | head -1 | awk '{print $3}')
    fi

    if [ -n "$BUILD_DIR" ]; then
        APP_PATH="$BUILD_DIR/$SCHEME.app"
        print_debug "Expected app path: $APP_PATH"
    fi

    # Verify the app exists, if not try multiple strategies
    if [ ! -d "$APP_PATH" ]; then
        print_warning "App not found at expected path, searching for built app..."

        # Strategy 1: Search in DerivedData with multiple patterns
        DERIVED_DATA=$(get_derived_data_path)
        print_debug "Searching in DerivedData: $DERIVED_DATA"

        # Try to find the app with various search patterns
        APP_PATH=$(find "$DERIVED_DATA" -name "${SCHEME}.app" -path "*/Debug-iphoneos/*" -not -path "*/Index.noindex/*" 2>/dev/null | head -1)

        # Strategy 2: If still not found, try without the Debug requirement
        if [ ! -d "$APP_PATH" ]; then
            APP_PATH=$(find "$DERIVED_DATA" -name "${SCHEME}.app" -path "*-iphoneos/*" -not -path "*/Index.noindex/*" 2>/dev/null | head -1)
        fi

        # Strategy 3: Last resort - any .app file for our scheme
        if [ ! -d "$APP_PATH" ]; then
            APP_PATH=$(find "$DERIVED_DATA" -name "${SCHEME}.app" -not -path "*/Index.noindex/*" 2>/dev/null | grep -v simulator | head -1)
        fi

        if [ ! -d "$APP_PATH" ]; then
            print_error "Could not find built app!"
            print_error "Searched in: $DERIVED_DATA"
            print_error "You may need to clean and rebuild. Try: $0 $TARGET_TYPE \"$DEVICE_NAME\" --clean"
            exit 1
        fi
    fi

    print_status "Found app at: $APP_PATH"

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
