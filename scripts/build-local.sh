#!/bin/bash
# =============================================================================
# Local Build Script for RunAnywhere SDK
# =============================================================================
# This script builds everything locally and copies to the Swift SDK.
#
# Usage:
#   ./scripts/build-local.sh              # Full build (core + commons + copy)
#   ./scripts/build-local.sh --commons    # Build commons only (skip core)
#   ./scripts/build-local.sh --copy       # Copy only (no build)
#   ./scripts/build-local.sh --ios-app    # Full build + rebuild iOS sample app
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Paths
CORE_DIR="$ROOT_DIR/../runanywhere-core"
COMMONS_DIR="$ROOT_DIR/sdk/runanywhere-commons"
SWIFT_SDK_DIR="$ROOT_DIR/sdk/runanywhere-swift"
IOS_APP_DIR="$ROOT_DIR/examples/ios/RunAnywhereAI"

# Parse arguments
BUILD_CORE=true
BUILD_COMMONS=true
COPY_FRAMEWORKS=true
BUILD_IOS_APP=false
CLEAN_BUILD=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --commons)
            BUILD_CORE=false
            shift
            ;;
        --copy)
            BUILD_CORE=false
            BUILD_COMMONS=false
            shift
            ;;
        --ios-app)
            BUILD_IOS_APP=true
            shift
            ;;
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --commons    Build commons only (skip runanywhere-core)"
            echo "  --copy       Copy frameworks only (no build)"
            echo "  --ios-app    Also rebuild the iOS sample app"
            echo "  --clean      Clean build directories first"
            echo "  --help       Show this help"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo ""
echo "=========================================="
echo "  RunAnywhere Local Build"
echo "=========================================="
echo ""

# Clean if requested
if [ "$CLEAN_BUILD" = true ]; then
    log_info "Cleaning build directories..."
    rm -rf "$COMMONS_DIR/build" "$COMMONS_DIR/dist"
    rm -rf ~/Library/Developer/Xcode/DerivedData/RunAnywhereAI-*
    log_success "Clean complete"
fi

# Build runanywhere-commons (which includes runanywhere-core)
if [ "$BUILD_COMMONS" = true ]; then
    log_info "Building runanywhere-commons (includes runanywhere-core)..."
    cd "$COMMONS_DIR"

    if [ "$CLEAN_BUILD" = true ]; then
        rm -rf build dist
    fi

    ./scripts/build-ios.sh

    if [ $? -eq 0 ]; then
        log_success "runanywhere-commons build complete"
    else
        log_error "runanywhere-commons build failed"
        exit 1
    fi
fi

# Copy frameworks to Swift SDK
if [ "$COPY_FRAMEWORKS" = true ]; then
    log_info "Copying XCFrameworks to Swift SDK..."

    if [ -d "$COMMONS_DIR/dist" ]; then
        cp -R "$COMMONS_DIR/dist/"*.xcframework "$SWIFT_SDK_DIR/Binaries/"
        log_success "Frameworks copied to $SWIFT_SDK_DIR/Binaries/"

        # Show framework sizes
        echo ""
        log_info "Framework sizes:"
        du -sh "$SWIFT_SDK_DIR/Binaries/"*.xcframework 2>/dev/null || true
    else
        log_error "No frameworks found in $COMMONS_DIR/dist"
        exit 1
    fi
fi

# Build iOS sample app if requested
if [ "$BUILD_IOS_APP" = true ]; then
    log_info "Building iOS sample app..."

    # Clean Xcode derived data
    rm -rf ~/Library/Developer/Xcode/DerivedData/RunAnywhereAI-*

    cd "$IOS_APP_DIR"

    # Try to find a connected device, fall back to simulator
    DEVICE_ID=$(xcrun xctrace list devices 2>/dev/null | grep -E "iPhone|iPad" | grep -v "Simulator" | head -1 | sed 's/.*(\([A-F0-9-]*\)).*/\1/')

    if [ -n "$DEVICE_ID" ]; then
        log_info "Building for device: $DEVICE_ID"
        xcodebuild -project RunAnywhereAI.xcodeproj \
            -scheme RunAnywhereAI \
            -destination "id=$DEVICE_ID" \
            -configuration Debug \
            build 2>&1 | tail -20
    else
        log_warn "No device found, building for simulator"
        xcodebuild -project RunAnywhereAI.xcodeproj \
            -scheme RunAnywhereAI \
            -destination "platform=iOS Simulator,name=iPhone 15 Pro" \
            -configuration Debug \
            build 2>&1 | tail -20
    fi

    if [ $? -eq 0 ]; then
        log_success "iOS sample app build complete"
    else
        log_error "iOS sample app build failed"
        exit 1
    fi
fi

echo ""
echo "=========================================="
log_success "Local build complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Open Xcode and run the app on your device"
echo "  2. Or run: ./scripts/build-local.sh --ios-app"
echo ""
