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

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DEST_DIR="${RAC_SHERPA_DIR:-${ROOT_DIR}/third_party/sherpa-onnx-linux}"

# Load versions from centralized VERSIONS file
source "${ROOT_DIR}/scripts/load-versions.sh"

VERSION="${SHERPA_ONNX_VERSION_LINUX:?SHERPA_ONNX_VERSION_LINUX is not set (load-versions.sh should export it from core/VERSIONS)}"
REPOSITORY="${SHERPA_ONNX_REPO_DESKTOP:?SHERPA_ONNX_REPO_DESKTOP is not set}"
RELEASE_TAG="${SHERPA_ONNX_RELEASE_TAG_DESKTOP:?SHERPA_ONNX_RELEASE_TAG_DESKTOP is not set}"
SOURCE_COMMIT="${SHERPA_ONNX_COMMIT_DESKTOP:?SHERPA_ONNX_COMMIT_DESKTOP is not set}"
ARCH="${RAC_PLATFORM_ARCH:-$(uname -m)}"

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

while [[ "${1:-}" == --* ]]; do
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

if [ -f "${DEST_DIR}/PROVENANCE.txt" ] && \
   grep -Fxq "sherpa_onnx_version=${VERSION}" "${DEST_DIR}/PROVENANCE.txt" && \
   grep -Fxq "runanywhere_source_commit=${SOURCE_COMMIT}" "${DEST_DIR}/PROVENANCE.txt" && \
   grep -Fxq "onnxruntime_version=${ONNX_VERSION_LINUX}" "${DEST_DIR}/PROVENANCE.txt" && \
   [ "$FORCE_DOWNLOAD" = false ]; then
    print_success "Sherpa-ONNX already downloaded at ${DEST_DIR}"
    echo "Use --force to re-download"
    exit 0
fi

# =============================================================================
# Determine Download URL
# =============================================================================

if [ "$ARCH" = "aarch64" ]; then
    ASSET_NAME="sherpa-onnx-v${VERSION}-linux-aarch64-shared-rac-ort${ONNX_VERSION_LINUX}.tar.bz2"
    ARCHIVE_NAME="${ASSET_NAME%.tar.bz2}"
    EXPECTED_SHA256="${SHERPA_ONNX_LINUX_AARCH64_SHA256:?SHERPA_ONNX_LINUX_AARCH64_SHA256 is not set}"
elif [ "$ARCH" = "x86_64" ]; then
    ASSET_NAME="sherpa-onnx-v${VERSION}-linux-x64-shared-rac-ort${ONNX_VERSION_LINUX}.tar.bz2"
    ARCHIVE_NAME="${ASSET_NAME%.tar.bz2}"
    EXPECTED_SHA256="${SHERPA_ONNX_LINUX_X64_SHA256:?SHERPA_ONNX_LINUX_X64_SHA256 is not set}"
else
    print_error "Unsupported architecture: $ARCH"
    echo "Supported architectures: x86_64, aarch64"
    exit 1
fi
URL="https://github.com/${REPOSITORY}/releases/download/${RELEASE_TAG}/${ASSET_NAME}"

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
# `--fail` makes curl exit non-zero on HTTP 4xx/5xx so a 404 page doesn't end
# up being passed to tar/bzip2 below as a 9-byte "Not Found" file.
curl -L --fail -o "${TEMP_DIR}/sherpa-onnx.tar.bz2" "${URL}"

ACTUAL_SHA256="$(sha256sum "${TEMP_DIR}/sherpa-onnx.tar.bz2" | awk '{print $1}')"
if [ "${ACTUAL_SHA256}" != "${EXPECTED_SHA256}" ]; then
    print_error "Archive SHA-256 mismatch: expected ${EXPECTED_SHA256}, got ${ACTUAL_SHA256}"
    exit 1
fi
print_success "Verified archive SHA-256: ${ACTUAL_SHA256}"

# Sanity-check the archive size — anything under 1 MB is almost certainly an
# error page that slipped past --fail (e.g. proxy-mediated redirect).
DL_SIZE=$(stat -c%s "${TEMP_DIR}/sherpa-onnx.tar.bz2" 2>/dev/null || stat -f%z "${TEMP_DIR}/sherpa-onnx.tar.bz2")
if [ "${DL_SIZE}" -lt 1048576 ]; then
    print_error "Downloaded file is suspiciously small (${DL_SIZE} bytes). URL may be wrong: ${URL}"
    exit 1
fi

print_step "Extracting archive..."
mkdir -p "${DEST_DIR}"
tar -xjf "${TEMP_DIR}/sherpa-onnx.tar.bz2" -C "${TEMP_DIR}"

# Move contents to destination (strip the top-level directory)
mv "${TEMP_DIR}/${ARCHIVE_NAME}"/* "${DEST_DIR}/"

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
if [ ! -f "${DEST_DIR}/PROVENANCE.txt" ] || \
   ! grep -Fxq "sherpa_onnx_version=${VERSION}" "${DEST_DIR}/PROVENANCE.txt" || \
   ! grep -Fxq "runanywhere_source_commit=${SOURCE_COMMIT}" "${DEST_DIR}/PROVENANCE.txt" || \
   ! grep -Fxq "onnxruntime_version=${ONNX_VERSION_LINUX}" "${DEST_DIR}/PROVENANCE.txt"; then
    print_error "Embedded release provenance is missing or does not match the pinned runtime stack."
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
