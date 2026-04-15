#!/bin/bash
# =============================================================================
# Download ONNX Runtime for macOS (universal2: arm64 + x86_64)
# =============================================================================
#
# Downloads pre-built ONNX Runtime from Microsoft GitHub releases.
# Used for compiling the ONNX backend on macOS.
#
# Output: third_party/onnxruntime-macos/
#   lib/libonnxruntime.dylib
#   include/onnxruntime_c_api.h
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ONNX_DIR="${ROOT_DIR}/third_party/onnxruntime-macos"

# Load versions from centralized VERSIONS file
source "${SCRIPT_DIR}/../load-versions.sh"

if [ -z "${ONNX_VERSION_MACOS:-}" ]; then
    echo "ERROR: ONNX_VERSION_MACOS not loaded from VERSIONS file" >&2
    exit 1
fi

ONNX_VERSION="${ONNX_VERSION_MACOS}"
DOWNLOAD_URL="https://github.com/microsoft/onnxruntime/releases/download/v${ONNX_VERSION}/onnxruntime-osx-universal2-${ONNX_VERSION}.tgz"

echo "======================================="
echo "📦 ONNX Runtime macOS Downloader"
echo "======================================="
echo ""
echo "Version: ${ONNX_VERSION}"

VERSION_SENTINEL="${ONNX_DIR}/.version"

# Check if already exists at the REQUESTED version. We compare against a
# sentinel written by this script rather than trusting the mere presence
# of libonnxruntime.dylib — that's how we'd silently drift ORT versions
# and miss the ABI mismatch with sherpa-onnx until the first Ort:: call.
if [ -d "${ONNX_DIR}/lib" ] && [ -f "${ONNX_DIR}/lib/libonnxruntime.dylib" ]; then
    EXISTING=""
    [ -f "${VERSION_SENTINEL}" ] && EXISTING=$(cat "${VERSION_SENTINEL}")
    if [ "${EXISTING}" = "${ONNX_VERSION}" ]; then
        echo "✅ ONNX Runtime macOS v${ONNX_VERSION} already exists at ${ONNX_DIR}"
        echo "   To force re-download, remove: rm -rf ${ONNX_DIR}"
        exit 0
    fi
    echo "⚠️  ONNX Runtime macOS version mismatch at ${ONNX_DIR}"
    echo "   Found: ${EXISTING:-unknown}, want: ${ONNX_VERSION}"
    echo "   Clearing stale cache and re-downloading…"
    rm -rf "${ONNX_DIR}"
fi

# Create temp directory for download
TEMP_DIR=$(mktemp -d)
TEMP_FILE="${TEMP_DIR}/onnxruntime.tgz"

echo ""
echo "Downloading from ${DOWNLOAD_URL}..."
curl -L --progress-bar -o "${TEMP_FILE}" "${DOWNLOAD_URL}"

if [ ! -f "${TEMP_FILE}" ] || [ ! -s "${TEMP_FILE}" ]; then
    echo "Error: Download failed"
    rm -rf "${TEMP_DIR}"
    exit 1
fi

echo "Download complete. Size: $(du -h "${TEMP_FILE}" | cut -f1)"

# Extract
echo "Extracting..."
mkdir -p "${ONNX_DIR}"
tar -xzf "${TEMP_FILE}" -C "${TEMP_DIR}"

# Find the extracted directory (e.g., onnxruntime-osx-universal2-1.23.2/)
EXTRACTED_DIR=$(find "${TEMP_DIR}" -maxdepth 1 -type d -name "onnxruntime-*" | head -1)
if [ -z "${EXTRACTED_DIR}" ]; then
    echo "Error: Could not find extracted ONNX Runtime directory"
    rm -rf "${TEMP_DIR}"
    exit 1
fi

# Copy lib and include
cp -R "${EXTRACTED_DIR}/lib" "${ONNX_DIR}/"
cp -R "${EXTRACTED_DIR}/include" "${ONNX_DIR}/"

# Stamp the version so future runs can detect drift.
echo "${ONNX_VERSION}" > "${VERSION_SENTINEL}"

# Clean up
rm -rf "${TEMP_DIR}"

echo ""
echo "✅ ONNX Runtime macOS v${ONNX_VERSION} installed to ${ONNX_DIR}"
echo ""
echo "Contents:"
ls -lh "${ONNX_DIR}/lib/"
