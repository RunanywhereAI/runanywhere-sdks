#!/bin/bash
#
# download-core.sh - Download runanywhere-core source from runanywhere-binaries
#
# This script downloads the runanywhere-core source tarball and iOS/macOS dependencies
# from the public runanywhere-binaries repository for REMOTE build mode.
#
# Usage:
#   ./scripts/download-core.sh [version]
#   ./scripts/download-core.sh              # Uses LATEST_CORE_VERSION
#   ./scripts/download-core.sh 0.1.0        # Specific version
#
# Environment variables:
#   RUNANYWHERE_CORE_VERSION - Override core version to download
#   SKIP_DEPS                - Set to "true" to skip downloading dependencies
#
# After running this script, use BUILD_MODE=remote ./scripts/build-ios.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
THIRD_PARTY_DIR="${PROJECT_ROOT}/third_party"
CORE_DIR="${THIRD_PARTY_DIR}/runanywhere-core"
DEPS_DIR="${CORE_DIR}/third_party"

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
echo -e "${GREEN}RunAnywhere Core Download Script${NC}"
echo -e "${GREEN}========================================${NC}"
echo "This script prepares REMOTE build mode."
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
            echo -e "${YELLOW}Please specify a version: ./scripts/download-core.sh 0.1.0${NC}" >&2
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

# =============================================================================
# Download runanywhere-core source
# =============================================================================
download_core_source() {
    local TARBALL_NAME="runanywhere-core-source-v${VERSION}.tar.gz"
    local DOWNLOAD_URL="${BINARIES_URL}/releases/download/core-v${VERSION}/${TARBALL_NAME}"
    local TARBALL_PATH="${THIRD_PARTY_DIR}/${TARBALL_NAME}"

    echo -e "${GREEN}Downloading runanywhere-core source...${NC}"
    echo "URL: ${DOWNLOAD_URL}"

    # Remove existing core directory
    if [[ -d "${CORE_DIR}" ]]; then
        echo "Removing existing core directory..."
        rm -rf "${CORE_DIR}"
    fi

    # Download tarball
    curl -L -o "${TARBALL_PATH}" "${DOWNLOAD_URL}"

    if [[ ! -f "${TARBALL_PATH}" ]]; then
        echo -e "${RED}Failed to download ${TARBALL_NAME}${NC}"
        exit 1
    fi

    # Extract
    echo "Extracting..."
    mkdir -p "${CORE_DIR}"
    tar -xzf "${TARBALL_PATH}" -C "${CORE_DIR}"
    rm "${TARBALL_PATH}"

    echo -e "${GREEN}✓ runanywhere-core source downloaded to ${CORE_DIR}${NC}"
}

# =============================================================================
# Download iOS dependencies (ONNX Runtime, Sherpa-ONNX)
# =============================================================================
download_ios_deps() {
    if [[ "${SKIP_DEPS}" == "true" ]]; then
        echo -e "${YELLOW}Skipping iOS dependencies (SKIP_DEPS=true)${NC}"
        return
    fi

    mkdir -p "${DEPS_DIR}"

    # ONNX Runtime for iOS
    echo -e "${GREEN}Downloading ONNX Runtime for iOS...${NC}"
    local ONNX_ZIP="onnxruntime-ios-v${VERSION}.zip"
    local ONNX_URL="${BINARIES_URL}/releases/download/core-v${VERSION}/${ONNX_ZIP}"
    echo "  URL: ${ONNX_URL}"

    if curl -L --fail -o "${DEPS_DIR}/${ONNX_ZIP}" "${ONNX_URL}" 2>/dev/null; then
        cd "${DEPS_DIR}"
        unzip -q -o "${ONNX_ZIP}"
        rm "${ONNX_ZIP}"
        echo -e "${GREEN}✓ ONNX Runtime for iOS downloaded${NC}"
        # List what was extracted
        ls -la *.xcframework 2>/dev/null || true
    else
        echo -e "${YELLOW}⚠ ONNX Runtime for iOS not found in release${NC}"
    fi

    # Sherpa-ONNX for iOS
    echo -e "${GREEN}Downloading Sherpa-ONNX for iOS...${NC}"
    local SHERPA_ZIP="sherpa-onnx-ios-v${VERSION}.zip"
    local SHERPA_URL="${BINARIES_URL}/releases/download/core-v${VERSION}/${SHERPA_ZIP}"
    echo "  URL: ${SHERPA_URL}"

    if curl -L --fail -o "${DEPS_DIR}/${SHERPA_ZIP}" "${SHERPA_URL}" 2>/dev/null; then
        cd "${DEPS_DIR}"
        unzip -q -o "${SHERPA_ZIP}"
        rm "${SHERPA_ZIP}"
        echo -e "${GREEN}✓ Sherpa-ONNX for iOS downloaded${NC}"
        # List what was extracted
        ls -la *.xcframework 2>/dev/null || true
    else
        echo -e "${YELLOW}⚠ Sherpa-ONNX for iOS not found in release${NC}"
    fi

    cd "${PROJECT_ROOT}"
}

# =============================================================================
# Download macOS dependencies
# =============================================================================
download_macos_deps() {
    if [[ "${SKIP_DEPS}" == "true" ]]; then
        echo -e "${YELLOW}Skipping macOS dependencies (SKIP_DEPS=true)${NC}"
        return
    fi

    mkdir -p "${DEPS_DIR}"

    # ONNX Runtime for macOS
    echo -e "${GREEN}Downloading ONNX Runtime for macOS...${NC}"
    local ONNX_ZIP="onnxruntime-macos-v${VERSION}.zip"
    local ONNX_URL="${BINARIES_URL}/releases/download/core-v${VERSION}/${ONNX_ZIP}"
    echo "  URL: ${ONNX_URL}"

    if curl -L --fail -o "${DEPS_DIR}/${ONNX_ZIP}" "${ONNX_URL}" 2>/dev/null; then
        cd "${DEPS_DIR}"
        unzip -q -o "${ONNX_ZIP}"
        rm "${ONNX_ZIP}"
        echo -e "${GREEN}✓ ONNX Runtime for macOS downloaded${NC}"
    else
        echo -e "${YELLOW}⚠ ONNX Runtime for macOS not found in release${NC}"
    fi

    cd "${PROJECT_ROOT}"
}

# =============================================================================
# Save version info
# =============================================================================
save_version_info() {
    echo "${VERSION}" > "${CORE_DIR}/DOWNLOADED_VERSION"
    echo -e "${GREEN}Version ${VERSION} saved to DOWNLOADED_VERSION${NC}"
}

# =============================================================================
# Verify downloads
# =============================================================================
verify_downloads() {
    echo ""
    echo -e "${GREEN}Verifying downloads...${NC}"

    # Check core source
    if [ -f "${CORE_DIR}/CMakeLists.txt" ]; then
        echo -e "${GREEN}✓ Core source${NC}"
    else
        echo -e "${RED}✗ Core source NOT found${NC}"
    fi

    # Check sherpa-onnx
    if [ -d "${DEPS_DIR}/sherpa-onnx.xcframework" ]; then
        echo -e "${GREEN}✓ sherpa-onnx.xcframework${NC}"
    else
        echo -e "${YELLOW}⚠ sherpa-onnx.xcframework not found${NC}"
    fi

    # Check onnxruntime
    if [ -d "${DEPS_DIR}/onnxruntime.xcframework" ]; then
        echo -e "${GREEN}✓ onnxruntime.xcframework${NC}"
    else
        echo -e "${YELLOW}⚠ onnxruntime.xcframework not found${NC}"
    fi
}

# =============================================================================
# Main
# =============================================================================

download_core_source
download_ios_deps
download_macos_deps
save_version_info
verify_downloads

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Download Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Downloaded to: ${CORE_DIR}"
echo "Version: ${VERSION}"
echo ""
echo "Directory structure:"
echo "  third_party/"
echo "    runanywhere-core/           # Core source"
echo "      third_party/"
echo "        sherpa-onnx.xcframework # STT/TTS/VAD"
echo "        onnxruntime.xcframework # ONNX Runtime"
echo ""
echo "To build iOS XCFrameworks:"
echo "  BUILD_MODE=remote ./scripts/build-ios.sh"
echo ""
