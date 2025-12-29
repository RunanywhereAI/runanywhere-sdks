#!/bin/bash
# RunAnywhere Commons - Build All Platforms
#
# Wrapper script to build for all supported platforms

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load versions from VERSIONS file (single source of truth)
source "${SCRIPT_DIR}/load-versions.sh"

# Configuration from environment or defaults
export BUILD_TYPE="${BUILD_TYPE:-Release}"
export BUILD_LLAMACPP="${BUILD_LLAMACPP:-ON}"
export BUILD_ONNX="${BUILD_ONNX:-ON}"
export BUILD_WHISPERCPP="${BUILD_WHISPERCPP:-OFF}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Parse arguments
BUILD_IOS=false
BUILD_ANDROID=false
BUILD_MACOS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --ios)
            BUILD_IOS=true
            shift
            ;;
        --android)
            BUILD_ANDROID=true
            shift
            ;;
        --macos)
            BUILD_MACOS=true
            shift
            ;;
        --all)
            BUILD_IOS=true
            BUILD_ANDROID=true
            BUILD_MACOS=true
            shift
            ;;
        --llamacpp)
            export BUILD_LLAMACPP=ON
            shift
            ;;
        --onnx)
            export BUILD_ONNX=ON
            shift
            ;;
        --whispercpp)
            export BUILD_WHISPERCPP=ON
            shift
            ;;
        --no-llamacpp)
            export BUILD_LLAMACPP=OFF
            shift
            ;;
        --no-onnx)
            export BUILD_ONNX=OFF
            shift
            ;;
        --debug)
            export BUILD_TYPE=Debug
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Platform options:"
            echo "  --ios          Build iOS XCFrameworks"
            echo "  --android      Build Android shared libraries"
            echo "  --macos        Build macOS libraries"
            echo "  --all          Build for all platforms"
            echo ""
            echo "Backend options:"
            echo "  --llamacpp     Include LlamaCpp backend (default: ON)"
            echo "  --onnx         Include ONNX backend (default: ON)"
            echo "  --whispercpp   Include WhisperCpp backend (default: OFF)"
            echo "  --no-llamacpp  Exclude LlamaCpp backend"
            echo "  --no-onnx      Exclude ONNX backend"
            echo ""
            echo "Build options:"
            echo "  --debug        Build in Debug mode (default: Release)"
            echo ""
            echo "Examples:"
            echo "  $0 --ios                    # Build iOS only"
            echo "  $0 --ios --android          # Build iOS and Android"
            echo "  $0 --all --no-onnx          # Build all platforms without ONNX"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# If no platform specified, show help
if [ "$BUILD_IOS" = false ] && [ "$BUILD_ANDROID" = false ] && [ "$BUILD_MACOS" = false ]; then
    echo -e "${YELLOW}No platform specified. Use --help for options.${NC}"
    echo ""
    # Default to iOS on macOS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "Building iOS by default..."
        BUILD_IOS=true
    else
        echo "Building Android by default..."
        BUILD_ANDROID=true
    fi
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}RunAnywhere Commons - Build All${NC}"
echo -e "${GREEN}========================================${NC}"
echo "Build type: ${BUILD_TYPE}"
echo "LlamaCpp: ${BUILD_LLAMACPP}"
echo "ONNX: ${BUILD_ONNX}"
echo "WhisperCpp: ${BUILD_WHISPERCPP}"
echo ""

# Build iOS
if [ "$BUILD_IOS" = true ]; then
    if [[ "$OSTYPE" != "darwin"* ]]; then
        echo -e "${RED}iOS builds require macOS${NC}"
    else
        echo -e "${GREEN}Building iOS...${NC}"
        "${SCRIPT_DIR}/build-ios.sh"
        echo ""
    fi
fi

# Build Android
if [ "$BUILD_ANDROID" = true ]; then
    echo -e "${GREEN}Building Android...${NC}"
    "${SCRIPT_DIR}/build-android.sh"
    echo ""
fi

# Build macOS
if [ "$BUILD_MACOS" = true ]; then
    if [[ "$OSTYPE" != "darwin"* ]]; then
        echo -e "${RED}macOS builds require macOS${NC}"
    else
        echo -e "${GREEN}Building macOS...${NC}"
        mkdir -p "${PROJECT_ROOT}/build/macos"
        cd "${PROJECT_ROOT}/build/macos"

        cmake "${PROJECT_ROOT}" \
            -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
            -DRAC_BUILD_LLAMACPP="${BUILD_LLAMACPP}" \
            -DRAC_BUILD_ONNX="${BUILD_ONNX}" \
            -DRAC_BUILD_WHISPERCPP="${BUILD_WHISPERCPP}" \
            -DRAC_BUILD_SHARED=OFF

        cmake --build . --config "${BUILD_TYPE}" -j$(sysctl -n hw.ncpu)

        cd "${PROJECT_ROOT}"
        echo ""
    fi
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}All builds complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo "Output directories:"
[ "$BUILD_IOS" = true ] && echo "  iOS: ${PROJECT_ROOT}/dist/*.xcframework"
[ "$BUILD_ANDROID" = true ] && echo "  Android: ${PROJECT_ROOT}/dist/android/"
[ "$BUILD_MACOS" = true ] && echo "  macOS: ${PROJECT_ROOT}/build/macos/"
