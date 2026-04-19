#!/bin/bash
# =============================================================================
# Build RunAnywhere Server
# =============================================================================
# Builds the OpenAI-compatible HTTP server for local LLM inference.
#
# Usage:
#   ./scripts/build-server.sh [options]
#
# Options:
#   --release       Build in Release mode (default)
#   --debug         Build in Debug mode
#   --shared        Build shared libraries
#   --clean         Clean build directory first
#   --help          Show this help message
#
# Example:
#   ./scripts/build-server.sh --release
#
# Output:
#   build-server/runanywhere-server   - Server binary
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build-server"

# Default options
BUILD_TYPE="Release"
BUILD_SHARED="OFF"
CLEAN_BUILD=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --release)
            BUILD_TYPE="Release"
            shift
            ;;
        --debug)
            BUILD_TYPE="Debug"
            shift
            ;;
        --shared)
            BUILD_SHARED="ON"
            shift
            ;;
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --release    Build in Release mode (default)"
            echo "  --debug      Build in Debug mode"
            echo "  --shared     Build shared libraries"
            echo "  --clean      Clean build directory first"
            echo "  --help       Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Print banner
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              Building RunAnywhere Server                     ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Project:    $PROJECT_DIR"
echo "Build:      $BUILD_DIR"
echo "Type:       $BUILD_TYPE"
echo "Shared:     $BUILD_SHARED"
echo ""

# Clean if requested
if [ "$CLEAN_BUILD" = true ]; then
    echo "Cleaning build directory..."
    rm -rf "$BUILD_DIR"
fi

# Create build directory
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Configure
echo "Configuring..."
cmake "$PROJECT_DIR" \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DRAC_BUILD_SHARED="$BUILD_SHARED" \
    -DRAC_BUILD_SERVER=ON \
    -DRAC_BUILD_BACKENDS=ON \
    -DRAC_BACKEND_LLAMACPP=ON \
    -DRAC_BUILD_PLATFORM=OFF

# Build
echo ""
echo "Building..."
cmake --build . --config "$BUILD_TYPE" -j$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

# Check if build succeeded
if [ -f "$BUILD_DIR/tools/runanywhere-server" ]; then
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    Build Successful!                         ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Server binary: $BUILD_DIR/tools/runanywhere-server"
    echo ""
    echo "Usage:"
    echo "  $BUILD_DIR/tools/runanywhere-server --model /path/to/model.gguf"
    echo ""
elif [ -f "$BUILD_DIR/tools/Release/runanywhere-server" ]; then
    # Windows/MSVC style
    echo ""
    echo "Build successful!"
    echo "Server binary: $BUILD_DIR/tools/Release/runanywhere-server"
else
    echo ""
    echo "Build completed but server binary not found."
    echo "Check build output for errors."
    exit 1
fi
