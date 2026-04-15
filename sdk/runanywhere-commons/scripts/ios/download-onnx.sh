#!/bin/bash
# Download ONNX Runtime iOS xcframework directly from onnxruntime.ai

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ONNX_DIR="${ROOT_DIR}/third_party/onnxruntime-ios"

# Load versions from centralized VERSIONS file (SINGLE SOURCE OF TRUTH)
source "${SCRIPT_DIR}/../load-versions.sh"

# Use version from VERSIONS file - no hardcoded fallbacks
if [ -z "${ONNX_VERSION_IOS:-}" ]; then
    echo "ERROR: ONNX_VERSION_IOS not loaded from VERSIONS file" >&2
    exit 1
fi
ONNX_VERSION="${ONNX_VERSION_IOS}"
DOWNLOAD_URL="https://download.onnxruntime.ai/pod-archive-onnxruntime-c-${ONNX_VERSION}.zip"
VERSION_SENTINEL="${ONNX_DIR}/.version"

# Idempotency guard: skip re-download when the on-disk xcframework already
# matches the requested version. A mismatched sentinel (or none at all
# alongside an existing framework) triggers a clean re-download so the
# ORT version can't silently drift from sherpa-onnx's expected version.
if [ -d "${ONNX_DIR}/onnxruntime.xcframework" ]; then
    EXISTING=""
    [ -f "${VERSION_SENTINEL}" ] && EXISTING=$(cat "${VERSION_SENTINEL}")
    if [ "${EXISTING}" = "${ONNX_VERSION}" ]; then
        echo "✅ ONNX Runtime iOS v${ONNX_VERSION} already present at ${ONNX_DIR}"
        echo "   To force re-download, remove: rm -rf ${ONNX_DIR}"
        exit 0
    fi
    echo "⚠️  ONNX Runtime iOS version mismatch at ${ONNX_DIR}"
    echo "   Found: ${EXISTING:-unknown}, want: ${ONNX_VERSION}"
    echo "   Clearing stale cache and re-downloading…"
fi

echo "Downloading ONNX Runtime iOS xcframework v${ONNX_VERSION}..."

# Create temp directory for download
TEMP_DIR=$(mktemp -d)
TEMP_ZIP="${TEMP_DIR}/onnxruntime.zip"

# Download the xcframework directly
echo "Downloading from ${DOWNLOAD_URL}..."
curl -L --progress-bar -o "${TEMP_ZIP}" "${DOWNLOAD_URL}"

# Verify download
if [ ! -f "${TEMP_ZIP}" ]; then
    echo "Error: Download failed"
    exit 1
fi

echo "Download complete. Size: $(du -h "${TEMP_ZIP}" | cut -f1)"

# Extract the xcframework
echo "Extracting xcframework..."
rm -rf "${ONNX_DIR}"
mkdir -p "${ONNX_DIR}"

# Unzip to temp directory first
unzip -q "${TEMP_ZIP}" -d "${TEMP_DIR}/extracted"

# Find and copy the xcframework
XCFRAMEWORK=$(find "${TEMP_DIR}/extracted" -name "onnxruntime.xcframework" -type d | head -1)
if [ -z "${XCFRAMEWORK}" ]; then
    echo "Error: onnxruntime.xcframework not found in archive"
    ls -R "${TEMP_DIR}/extracted"
    exit 1
fi

cp -R "${XCFRAMEWORK}" "${ONNX_DIR}/"

# Also copy headers if they exist at the top level
if [ -d "${TEMP_DIR}/extracted/Headers" ]; then
    cp -R "${TEMP_DIR}/extracted/Headers" "${ONNX_DIR}/"
fi

# Stamp the version so future runs can detect drift and re-download.
echo "${ONNX_VERSION}" > "${VERSION_SENTINEL}"

# Clean up
rm -rf "${TEMP_DIR}"

echo ""
echo "✅ ONNX Runtime xcframework downloaded to ${ONNX_DIR}/onnxruntime.xcframework"
echo ""
echo "Contents:"
ls -lh "${ONNX_DIR}/onnxruntime.xcframework"
