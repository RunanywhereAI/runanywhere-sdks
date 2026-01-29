#!/bin/bash

# =============================================================================
# download-sherpa-onnx.sh
# Download Sherpa-ONNX pre-built binaries for Linux
#
# Usage: ./download-sherpa-onnx.sh [--force]
#
# Options:
#   --force    Re-download even if already present
#
# Supported architectures:
#   - x86_64 (Intel/AMD 64-bit)
#   - aarch64 (ARM 64-bit, e.g., Raspberry Pi 5)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DEST_DIR="${ROOT_DIR}/third_party/sherpa-onnx-linux"

# Load versions from centralized VERSIONS file
source "${ROOT_DIR}/scripts/load-versions.sh"

VERSION="${SHERPA_ONNX_VERSION_LINUX:-1.12.18}"
ARCH=$(uname -m)

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
# Parse Options
# =============================================================================

FORCE_DOWNLOAD=false

while [[ "$1" == --* ]]; do
    case "$1" in
        --force)
            FORCE_DOWNLOAD=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--force]"
            echo "  --force    Re-download even if already present"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# =============================================================================
# Check if already downloaded
# =============================================================================

if [ -d "${DEST_DIR}/lib" ] && [ "$FORCE_DOWNLOAD" = false ]; then
    print_success "Sherpa-ONNX already downloaded at ${DEST_DIR}"
    echo "Use --force to re-download"
    exit 0
fi

# =============================================================================
# Determine Download URL
# =============================================================================

if [ "$ARCH" = "aarch64" ]; then
    URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/v${VERSION}/sherpa-onnx-v${VERSION}-linux-aarch64-shared-cpu.tar.bz2"
    ARCHIVE_NAME="sherpa-onnx-v${VERSION}-linux-aarch64-shared-cpu"
elif [ "$ARCH" = "x86_64" ]; then
    URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/v${VERSION}/sherpa-onnx-v${VERSION}-linux-x64-shared-cpu.tar.bz2"
    ARCHIVE_NAME="sherpa-onnx-v${VERSION}-linux-x64-shared-cpu"
else
    print_error "Unsupported architecture: $ARCH"
    echo "Supported architectures: x86_64, aarch64"
    exit 1
fi

# =============================================================================
# Download and Extract
# =============================================================================

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Downloading Sherpa-ONNX for Linux${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Version: ${VERSION}"
echo "Architecture: ${ARCH}"
echo "URL: ${URL}"
echo "Destination: ${DEST_DIR}"
echo ""

# Clean existing directory
if [ -d "${DEST_DIR}" ]; then
    print_step "Removing existing Sherpa-ONNX directory..."
    rm -rf "${DEST_DIR}"
fi

# Create temp directory for download
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

print_step "Downloading Sherpa-ONNX v${VERSION}..."
curl -L -o "${TEMP_DIR}/sherpa-onnx.tar.bz2" "${URL}"

print_step "Extracting archive..."
mkdir -p "${DEST_DIR}"
tar -xjf "${TEMP_DIR}/sherpa-onnx.tar.bz2" -C "${TEMP_DIR}"

# Move contents to destination (strip the top-level directory)
mv "${TEMP_DIR}/${ARCHIVE_NAME}"/* "${DEST_DIR}/"

# Download C API headers (not included in pre-built binaries since v1.12.23+)
if [ ! -d "${DEST_DIR}/include/sherpa-onnx/c-api" ]; then
    print_step "Downloading C API headers..."
    mkdir -p "${DEST_DIR}/include/sherpa-onnx/c-api"
    curl -sL "https://raw.githubusercontent.com/k2-fsa/sherpa-onnx/v${VERSION}/sherpa-onnx/c-api/c-api.h" \
        -o "${DEST_DIR}/include/sherpa-onnx/c-api/c-api.h"
fi

# =============================================================================
# Verify Installation
# =============================================================================

print_step "Verifying installation..."

if [ ! -f "${DEST_DIR}/lib/libsherpa-onnx-c-api.so" ]; then
    print_error "libsherpa-onnx-c-api.so not found!"
    exit 1
fi

if [ ! -f "${DEST_DIR}/include/sherpa-onnx/c-api/c-api.h" ]; then
    print_error "C API header not found!"
    exit 1
fi

# =============================================================================
# Summary
# =============================================================================

echo ""
print_success "Sherpa-ONNX v${VERSION} downloaded successfully!"
echo ""
echo "Contents:"
echo "  Libraries: ${DEST_DIR}/lib/"
ls -la "${DEST_DIR}/lib/"*.so* 2>/dev/null | head -10 | awk '{print "    " $9 ": " $5}'
echo ""
echo "  Headers: ${DEST_DIR}/include/"
ls "${DEST_DIR}/include/" 2>/dev/null | head -5 | awk '{print "    " $1}'
echo ""

# Show library sizes
echo "Library sizes:"
ls -lh "${DEST_DIR}/lib/"*.so 2>/dev/null | awk '{print "  " $9 ": " $5}' | head -5

echo ""
print_success "Done!"
