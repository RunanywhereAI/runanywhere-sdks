#!/bin/bash

# =============================================================================
# download-native-libs.sh
# Downloads pre-built native libraries for RunAnywhere ONNX Android module
#
# Usage: ./download-native-libs.sh [version]
#        version: Version to download (default: reads from VERSION file or uses latest)
#
# This script downloads the pre-built native libraries from GitHub releases
# and extracts them to the jniLibs directory for inclusion in the AAR.
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
JNILIBS_DIR="${MODULE_DIR}/src/main/jniLibs"

# Configuration - Update these for your organization
GITHUB_ORG="${GITHUB_ORG:-RunanywhereAI}"
REPO_NAME="${REPO_NAME:-runanywhere-binaries}"
ARTIFACT_NAME="RunAnywhereONNX-android.zip"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() {
    echo -e "${YELLOW}-> $1${NC}"
}

print_success() {
    echo -e "${GREEN}[OK] $1${NC}"
}

print_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

# =============================================================================
# Determine Version
# =============================================================================

VERSION="${1:-}"

if [ -z "$VERSION" ]; then
    # Try to read from VERSION file
    if [ -f "${MODULE_DIR}/VERSION" ]; then
        VERSION=$(cat "${MODULE_DIR}/VERSION")
    elif [ -f "${MODULE_DIR}/../../VERSION" ]; then
        VERSION=$(cat "${MODULE_DIR}/../../VERSION")
    fi
fi

if [ -z "$VERSION" ]; then
    # Use latest from GitHub API
    print_step "Fetching latest version from GitHub..."
    LATEST_RELEASE=$(curl -s "https://api.github.com/repos/${GITHUB_ORG}/${REPO_NAME}/releases/latest" 2>/dev/null || echo "{}")
    VERSION=$(echo "$LATEST_RELEASE" | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4 | sed 's/^v//')

    if [ -z "$VERSION" ] || [ "$VERSION" = "null" ]; then
        print_error "Could not determine version. Please specify a version: $0 <version>"
        exit 1
    fi
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Downloading RunAnywhere ONNX Libraries${NC}"
echo -e "${BLUE}Version: ${VERSION}${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# =============================================================================
# Check if Already Downloaded
# =============================================================================

MARKER_FILE="${JNILIBS_DIR}/.version"
if [ -f "$MARKER_FILE" ]; then
    CURRENT_VERSION=$(cat "$MARKER_FILE")
    if [ "$CURRENT_VERSION" = "$VERSION" ]; then
        print_success "Native libraries version ${VERSION} already downloaded"
        echo "Location: ${JNILIBS_DIR}"
        ls -la "${JNILIBS_DIR}"/*/lib*.so 2>/dev/null | head -5 || true
        exit 0
    else
        print_step "Updating from version ${CURRENT_VERSION} to ${VERSION}..."
    fi
fi

# =============================================================================
# Download
# =============================================================================

DOWNLOAD_URL="https://github.com/${GITHUB_ORG}/${REPO_NAME}/releases/download/v${VERSION}/${ARTIFACT_NAME}"
TEMP_DIR=$(mktemp -d)
TEMP_ZIP="${TEMP_DIR}/${ARTIFACT_NAME}"

print_step "Downloading from ${DOWNLOAD_URL}..."
HTTP_CODE=$(curl -L -w "%{http_code}" -o "$TEMP_ZIP" "$DOWNLOAD_URL" 2>/dev/null || echo "000")

if [ "$HTTP_CODE" != "200" ]; then
    rm -rf "$TEMP_DIR"
    print_error "Download failed with HTTP code ${HTTP_CODE}"
    echo ""
    echo "Please check:"
    echo "  1. The version ${VERSION} exists in the releases"
    echo "  2. The repository ${GITHUB_ORG}/${REPO_NAME} is accessible"
    echo "  3. The artifact ${ARTIFACT_NAME} exists in the release"
    echo ""
    echo "You can also build locally:"
    echo "  cd runanywhere-core && ./scripts/build-android-backend.sh onnx"
    exit 1
fi

print_success "Downloaded ${ARTIFACT_NAME}"

# =============================================================================
# Verify Checksum (if available)
# =============================================================================

CHECKSUM_URL="https://github.com/${GITHUB_ORG}/${REPO_NAME}/releases/download/v${VERSION}/${ARTIFACT_NAME}.sha256"
TEMP_CHECKSUM="${TEMP_DIR}/checksum.sha256"

print_step "Verifying checksum..."
if curl -sL -o "$TEMP_CHECKSUM" "$CHECKSUM_URL" 2>/dev/null; then
    EXPECTED_CHECKSUM=$(cat "$TEMP_CHECKSUM" | awk '{print $1}')
    ACTUAL_CHECKSUM=$(shasum -a 256 "$TEMP_ZIP" | awk '{print $1}')

    if [ "$EXPECTED_CHECKSUM" = "$ACTUAL_CHECKSUM" ]; then
        print_success "Checksum verified"
    else
        rm -rf "$TEMP_DIR"
        print_error "Checksum mismatch!"
        echo "Expected: ${EXPECTED_CHECKSUM}"
        echo "Actual:   ${ACTUAL_CHECKSUM}"
        exit 1
    fi
else
    print_step "Checksum file not available, skipping verification"
fi

# =============================================================================
# Extract
# =============================================================================

print_step "Extracting libraries..."
rm -rf "${JNILIBS_DIR}"
mkdir -p "${JNILIBS_DIR}"

# Extract to temp directory first
unzip -q "$TEMP_ZIP" -d "$TEMP_DIR"

# The ZIP structure is: onnx/<abi>/lib*.so
# We need to move to: jniLibs/<abi>/lib*.so
if [ -d "${TEMP_DIR}/onnx" ]; then
    for ABI_DIR in "${TEMP_DIR}/onnx"/*; do
        if [ -d "$ABI_DIR" ] && [ "$(basename "$ABI_DIR")" != "include" ]; then
            ABI=$(basename "$ABI_DIR")
            mkdir -p "${JNILIBS_DIR}/${ABI}"
            cp "${ABI_DIR}"/*.so "${JNILIBS_DIR}/${ABI}/" 2>/dev/null || true
            print_success "Extracted ${ABI} libraries"
        fi
    done
fi

# Write version marker
echo "$VERSION" > "$MARKER_FILE"

# Cleanup
rm -rf "$TEMP_DIR"

# =============================================================================
# Summary
# =============================================================================

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Download Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Version: ${VERSION}"
echo "Location: ${JNILIBS_DIR}"
echo ""
echo "Libraries:"
for ABI_DIR in "${JNILIBS_DIR}"/*; do
    if [ -d "$ABI_DIR" ] && [ "$(basename "$ABI_DIR")" != ".version" ]; then
        ABI=$(basename "$ABI_DIR")
        echo "  ${ABI}:"
        ls -1 "${ABI_DIR}"/*.so 2>/dev/null | while read -r lib; do
            echo "    - $(basename "$lib")"
        done
    fi
done
echo ""
echo -e "${GREEN}Done!${NC}"
