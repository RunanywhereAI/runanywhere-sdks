#!/bin/bash
#
# download-core-prebuilt.sh - Download pre-built runanywhere-core static libraries
#
# This script downloads pre-built runanywhere-core static libraries (.a files)
# from the public runanywhere-binaries repository for REMOTE consumption.
#
# Unlike download-core.sh which downloads SOURCE, this downloads PRE-BUILT binaries.
#
# Usage:
#   ./scripts/download-core-prebuilt.sh [version]
#   ./scripts/download-core-prebuilt.sh              # Uses LATEST_CORE_VERSION
#   ./scripts/download-core-prebuilt.sh 0.1.0        # Specific version
#
# Environment variables:
#   RUNANYWHERE_CORE_VERSION - Override core version to download
#
# After running this script, commons will link against pre-built libraries
# instead of compiling core from source.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
THIRD_PARTY_DIR="${PROJECT_ROOT}/third_party"
PREBUILT_DIR="${THIRD_PARTY_DIR}/runanywhere-core-prebuilt"

# GitHub repository for published binaries
BINARIES_REPO="RunanywhereAI/runanywhere-binaries"
BINARIES_URL="https://github.com/${BINARIES_REPO}"
RAW_URL="https://raw.githubusercontent.com/${BINARIES_REPO}/main"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}RunAnywhere Core Pre-built Download${NC}"
echo -e "${GREEN}========================================${NC}"
echo "This script downloads PRE-BUILT core libraries (not source)."
echo ""

# Determine version to download
get_version() {
    if [[ -n "${RUNANYWHERE_CORE_VERSION}" ]]; then
        echo "${RUNANYWHERE_CORE_VERSION}"
    elif [[ -n "$1" ]]; then
        echo "$1"
    else
        # Fetch latest version from runanywhere-binaries
        echo -e "${YELLOW}Fetching latest core version...${NC}" >&2
        LATEST=$(curl -sL "${RAW_URL}/LATEST_CORE_VERSION" 2>/dev/null || echo "")
        if [[ -z "${LATEST}" ]]; then
            echo -e "${RED}Failed to fetch LATEST_CORE_VERSION${NC}" >&2
            echo -e "${YELLOW}Please specify a version: ./scripts/download-core-prebuilt.sh 0.1.0${NC}" >&2
            exit 1
        fi
        echo "${LATEST}"
    fi
}

VERSION=$(get_version "$1")
echo "Core Version: ${VERSION}"
echo ""

# Create directories
mkdir -p "${THIRD_PARTY_DIR}"
mkdir -p "${PREBUILT_DIR}"

# =============================================================================
# Download pre-built core static libraries
# =============================================================================
download_core_prebuilt() {
    # Try to download pre-built static libraries archive
    # Format: runanywhere-core-static-libs-v{VERSION}.zip
    local ZIP_NAME="runanywhere-core-static-libs-v${VERSION}.zip"
    local DOWNLOAD_URL="${BINARIES_URL}/releases/download/core-v${VERSION}/${ZIP_NAME}"
    local ZIP_PATH="${THIRD_PARTY_DIR}/${ZIP_NAME}"

    echo -e "${GREEN}Downloading pre-built core static libraries...${NC}"
    echo "URL: ${DOWNLOAD_URL}"

    # Remove existing pre-built directory
    if [[ -d "${PREBUILT_DIR}" ]]; then
        echo "Removing existing pre-built core directory..."
        rm -rf "${PREBUILT_DIR}"
        mkdir -p "${PREBUILT_DIR}"
    fi

    # Download archive
    echo "Downloading..."
    if ! curl -L --fail --progress-bar -o "${ZIP_PATH}" "${DOWNLOAD_URL}"; then
        echo -e "${YELLOW}Pre-built static libraries not found, trying XCFramework extraction...${NC}"
        rm -f "${ZIP_PATH}"
        
        # Fallback: Download XCFramework and extract libraries
        download_and_extract_xcframework "${VERSION}"
        return
    fi

    # Extract
    echo "Extracting..."
    cd "${PREBUILT_DIR}"
    if ! unzip -q -o "${ZIP_PATH}"; then
        echo -e "${RED}Failed to extract archive${NC}"
        rm -f "${ZIP_PATH}"
        exit 1
    fi
    rm "${ZIP_PATH}"

    echo -e "${GREEN}✓ Pre-built core libraries downloaded to ${PREBUILT_DIR}${NC}"
}

# =============================================================================
# Fallback: Download XCFramework and extract static libraries
# =============================================================================
download_and_extract_xcframework() {
    local VERSION=$1
    local XCFW_NAME="RunAnywhereCore.xcframework"
    local ZIP_NAME="${XCFW_NAME}-v${VERSION}.zip"
    local DOWNLOAD_URL="${BINARIES_URL}/releases/download/core-v${VERSION}/${ZIP_NAME}"
    local ZIP_PATH="${THIRD_PARTY_DIR}/${ZIP_NAME}"

    echo -e "${GREEN}Downloading XCFramework to extract libraries...${NC}"
    echo "URL: ${DOWNLOAD_URL}"

    # Download XCFramework
    if ! curl -L --fail --progress-bar -o "${ZIP_PATH}" "${DOWNLOAD_URL}"; then
        echo -e "${RED}Failed to download XCFramework${NC}"
        echo -e "${RED}URL: ${DOWNLOAD_URL}${NC}"
        echo ""
        echo "Make sure the release exists at:"
        echo "  https://github.com/${BINARIES_REPO}/releases/tag/core-v${VERSION}"
        exit 1
    fi

    # Extract XCFramework
    echo "Extracting XCFramework..."
    cd "${THIRD_PARTY_DIR}"
    unzip -q -o "${ZIP_PATH}"
    rm "${ZIP_PATH}"

    # Extract static libraries from XCFramework
    echo "Extracting static libraries from XCFramework..."
    mkdir -p "${PREBUILT_DIR}/lib"
    mkdir -p "${PREBUILT_DIR}/include"

    # Extract from ios-arm64 slice
    if [[ -d "${THIRD_PARTY_DIR}/${XCFW_NAME}/ios-arm64" ]]; then
        local ARM64_DIR="${THIRD_PARTY_DIR}/${XCFW_NAME}/ios-arm64"
        if [[ -d "${ARM64_DIR}/RunAnywhereCore.framework" ]]; then
            # Copy libraries
            find "${ARM64_DIR}/RunAnywhereCore.framework" -name "*.a" -exec cp {} "${PREBUILT_DIR}/lib/" \;
            # Copy headers
            if [[ -d "${ARM64_DIR}/RunAnywhereCore.framework/Headers" ]]; then
                cp -r "${ARM64_DIR}/RunAnywhereCore.framework/Headers"/* "${PREBUILT_DIR}/include/" 2>/dev/null || true
            fi
        fi
    fi

    # Clean up XCFramework
    rm -rf "${THIRD_PARTY_DIR}/${XCFW_NAME}"

    echo -e "${GREEN}✓ Extracted libraries to ${PREBUILT_DIR}/lib${NC}"
}

# =============================================================================
# Verify downloads
# =============================================================================
verify_downloads() {
    echo ""
    echo -e "${GREEN}Verifying downloads...${NC}"

    # Check for bridge library (required)
    if [ -f "${PREBUILT_DIR}/lib/librunanywhere_bridge.a" ] || [ -f "${PREBUILT_DIR}/librunanywhere_bridge.a" ]; then
        echo -e "${GREEN}✓ Bridge library${NC}"
    else
        echo -e "${RED}✗ Bridge library NOT found${NC}"
        echo "Expected: ${PREBUILT_DIR}/lib/librunanywhere_bridge.a or ${PREBUILT_DIR}/librunanywhere_bridge.a"
        exit 1
    fi

    # Check for optional backend libraries
    if [ -f "${PREBUILT_DIR}/lib/librunanywhere_llamacpp.a" ] || [ -f "${PREBUILT_DIR}/librunanywhere_llamacpp.a" ]; then
        echo -e "${GREEN}✓ LlamaCPP library${NC}"
    fi

    if [ -f "${PREBUILT_DIR}/lib/librunanywhere_onnx.a" ] || [ -f "${PREBUILT_DIR}/librunanywhere_onnx.a" ]; then
        echo -e "${GREEN}✓ ONNX library${NC}"
    fi
}

# =============================================================================
# Main
# =============================================================================

download_core_prebuilt
verify_downloads

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Download Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Version: ${VERSION}"
echo ""
echo "Directory structure:"
echo "  third_party/runanywhere-core-prebuilt/"
echo "    lib/"
echo "      librunanywhere_bridge.a"
echo "      librunanywhere_llamacpp.a (if available)"
echo "      librunanywhere_onnx.a (if available)"
echo "    include/ (headers)"
echo ""
echo "To build iOS XCFrameworks with pre-built core:"
echo "  USE_PREBUILT_CORE=ON ./scripts/build-ios.sh"
echo ""

