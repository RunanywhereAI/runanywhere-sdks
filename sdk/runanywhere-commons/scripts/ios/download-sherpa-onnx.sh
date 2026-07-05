#!/bin/bash
# Download Sherpa-ONNX iOS xcframework
#
# Since Sherpa-ONNX doesn't provide pre-built iOS binaries, we host our own
# built version on the runanywhere-binaries releases.
#
# To update: Build locally with build-sherpa-onnx-ios.sh and upload to releases

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SHERPA_DIR="${ROOT_DIR}/third_party/sherpa-onnx-ios"

# Load versions from centralized VERSIONS file (SINGLE SOURCE OF TRUTH)
source "${SCRIPT_DIR}/../load-versions.sh"

# Use version from VERSIONS file - no hardcoded fallbacks
if [ -z "${SHERPA_ONNX_VERSION_IOS:-}" ]; then
    echo "ERROR: SHERPA_ONNX_VERSION_IOS not loaded from VERSIONS file" >&2
    exit 1
fi
SHERPA_VERSION="${SHERPA_ONNX_VERSION_IOS}"
# Try runanywhere-sdks first, fallback to runanywhere-binaries
DOWNLOAD_URL="https://github.com/RunanywhereAI/runanywhere-binaries/releases/download/sherpa-onnx-v${SHERPA_VERSION}/sherpa-onnx.xcframework.zip"

# Alternative: Build from source if download fails
BUILD_FROM_SOURCE=false

echo "======================================="
echo "📦 Sherpa-ONNX iOS XCFramework Downloader"
echo "======================================="
echo ""
echo "Version: ${SHERPA_VERSION}"

# Check if already exists and is valid
if [ -d "${SHERPA_DIR}/sherpa-onnx.xcframework" ]; then
    # Verify it has the static libraries
    if [ -f "${SHERPA_DIR}/sherpa-onnx.xcframework/ios-arm64/libsherpa-onnx.a" ] && \
       [ -f "${SHERPA_DIR}/sherpa-onnx.xcframework/ios-arm64_x86_64-simulator/libsherpa-onnx.a" ]; then
        echo "✅ Sherpa-ONNX xcframework already exists and appears valid"
        echo "   Location: ${SHERPA_DIR}/sherpa-onnx.xcframework"
        echo ""
        echo "To force re-download, remove the directory first:"
        echo "   rm -rf ${SHERPA_DIR}/sherpa-onnx.xcframework"
        exit 0
    else
        echo "⚠️  Existing xcframework appears incomplete, re-downloading..."
        rm -rf "${SHERPA_DIR}/sherpa-onnx.xcframework"
    fi
fi

# Create temp directory for download
TEMP_DIR=$(mktemp -d)
TEMP_ZIP="${TEMP_DIR}/sherpa-onnx.xcframework.zip"

echo ""
echo "Downloading from ${DOWNLOAD_URL}..."

# Try to download pre-built version
HTTP_CODE=$(curl -L -w "%{http_code}" -o "${TEMP_ZIP}" "${DOWNLOAD_URL}" 2>/dev/null) || true

if [ "${HTTP_CODE}" = "200" ] && [ -f "${TEMP_ZIP}" ] && [ -s "${TEMP_ZIP}" ]; then
    echo "Download complete. Size: $(du -h "${TEMP_ZIP}" | cut -f1)"

    # Extract the xcframework
    echo "Extracting xcframework..."
    mkdir -p "${SHERPA_DIR}"

    # Unzip to temp directory first
    unzip -q "${TEMP_ZIP}" -d "${TEMP_DIR}/extracted"

    # Find and copy the xcframework
    XCFRAMEWORK=$(find "${TEMP_DIR}/extracted" -name "sherpa-onnx.xcframework" -type d | head -1)
    if [ -z "${XCFRAMEWORK}" ]; then
        echo "Error: sherpa-onnx.xcframework not found in archive"
        ls -R "${TEMP_DIR}/extracted"
        rm -rf "${TEMP_DIR}"
        exit 1
    fi

    cp -R "${XCFRAMEWORK}" "${SHERPA_DIR}/"

    # Clean up
    rm -rf "${TEMP_DIR}"

    echo ""
    echo "✅ Sherpa-ONNX xcframework downloaded to ${SHERPA_DIR}/sherpa-onnx.xcframework"
    echo ""
    echo "Contents:"
    ls -lh "${SHERPA_DIR}/sherpa-onnx.xcframework"
else
    echo ""
    echo "⚠️  Pre-built Sherpa-ONNX not available for download (HTTP: ${HTTP_CODE})"
    echo ""

    # Clean up failed download
    rm -rf "${TEMP_DIR}"

    if [ "${BUILD_FROM_SOURCE}" = "true" ]; then
        echo "Falling back to building from source..."
        echo "This will take several minutes..."
        echo ""

        # Check if the build script exists
        BUILD_SCRIPT="${SCRIPT_DIR}/build-sherpa-onnx-ios.sh"
        if [ -f "${BUILD_SCRIPT}" ]; then
            exec "${BUILD_SCRIPT}"
        else
            echo "Error: Build script not found at ${BUILD_SCRIPT}"
            exit 1
        fi
    else
        echo "=============================================="
        echo "❌ Sherpa-ONNX download failed"
        echo "=============================================="
        echo ""
        echo "Options:"
        echo ""
        echo "1. Upload pre-built Sherpa-ONNX to runanywhere-binaries:"
        echo "   - Build locally: ./scripts/build-sherpa-onnx-ios.sh"
        echo "   - Create zip: cd third_party/sherpa-onnx-ios && zip -r sherpa-onnx.xcframework.zip sherpa-onnx.xcframework"
        echo "   - Create release: sherpa-onnx-v${SHERPA_VERSION} on runanywhere-binaries"
        echo "   - Upload the zip file"
        echo ""
        echo "2. Build from source (slow, ~10-15 minutes):"
        echo "   ./src/backends/onnx/scripts/build-sherpa-onnx-ios.sh"
        echo ""
        echo "3. Set BUILD_FROM_SOURCE=true in this script to auto-build"
        echo ""
        exit 1
    fi
fi
