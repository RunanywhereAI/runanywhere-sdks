#!/bin/bash
# Download the pinned ONNX Runtime iOS XCFramework, falling back to NuGet.

set -euo pipefail

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
if [ -z "${ONNX_IOS_SHA256:-}" ]; then
    echo "ERROR: ONNX_IOS_SHA256 not loaded from VERSIONS file" >&2
    exit 1
fi
if [ -z "${ONNX_NUGET_SHA256:-}" ] || [ -z "${ONNX_NUGET_IOS_SHA256:-}" ]; then
    echo "ERROR: ONNX Runtime NuGet checksums not loaded from VERSIONS file" >&2
    exit 1
fi
ONNX_VERSION="${ONNX_VERSION_IOS}"
DOWNLOAD_URL="https://download.onnxruntime.ai/pod-archive-onnxruntime-c-${ONNX_VERSION}.zip"
NUGET_URL="https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime/${ONNX_VERSION}/microsoft.ml.onnxruntime.${ONNX_VERSION}.nupkg"

echo "Downloading ONNX Runtime iOS xcframework v${ONNX_VERSION}..."

# Create temp directory for download
TEMP_DIR=$(mktemp -d)
TEMP_ZIP="${TEMP_DIR}/onnxruntime.zip"
trap 'rm -rf "${TEMP_DIR}"' EXIT

# Prefer the existing Apple pod archive when available.
echo "Downloading from ${DOWNLOAD_URL}..."
if curl --fail --location --show-error --silent --connect-timeout 20 \
    --max-time 180 --output "${TEMP_ZIP}" "${DOWNLOAD_URL}"; then
    ACTUAL_SHA256="$(shasum -a 256 "${TEMP_ZIP}" | awk '{print $1}')"
    if [ "${ACTUAL_SHA256}" != "${ONNX_IOS_SHA256}" ]; then
        echo "ERROR: ONNX Runtime iOS archive checksum mismatch" >&2
        echo "  expected: ${ONNX_IOS_SHA256}" >&2
        echo "  actual:   ${ACTUAL_SHA256}" >&2
        exit 1
    fi
else
    echo "Apple pod archive unavailable; downloading verified NuGet fallback..."
    NUGET_FILE="${TEMP_DIR}/onnxruntime.nupkg"
    curl --fail --location --show-error --silent --retry 3 --connect-timeout 20 \
        --output "${NUGET_FILE}" "${NUGET_URL}"
    ACTUAL_SHA256="$(shasum -a 256 "${NUGET_FILE}" | awk '{print $1}')"
    if [ "${ACTUAL_SHA256}" != "${ONNX_NUGET_SHA256}" ]; then
        echo "ERROR: ONNX Runtime NuGet archive checksum mismatch" >&2
        exit 1
    fi
    unzip -p "${NUGET_FILE}" \
        runtimes/ios/native/onnxruntime.xcframework.zip > "${TEMP_ZIP}"
    ACTUAL_SHA256="$(shasum -a 256 "${TEMP_ZIP}" | awk '{print $1}')"
    if [ "${ACTUAL_SHA256}" != "${ONNX_NUGET_IOS_SHA256}" ]; then
        echo "ERROR: ONNX Runtime NuGet XCFramework checksum mismatch" >&2
        exit 1
    fi
fi

echo "Download complete. Size: $(du -h "${TEMP_ZIP}" | cut -f1)"

# Extract and validate before replacing an existing inventory.
echo "Extracting xcframework..."
unzip -q "${TEMP_ZIP}" -d "${TEMP_DIR}/extracted"

# Find and copy the xcframework
XCFRAMEWORK=$(find "${TEMP_DIR}/extracted" -name "onnxruntime.xcframework" -type d | head -1)
if [ -z "${XCFRAMEWORK}" ]; then
    echo "Error: onnxruntime.xcframework not found in archive"
    ls -R "${TEMP_DIR}/extracted"
    exit 1
fi

if [ ! -f "${XCFRAMEWORK}/ios-arm64/onnxruntime.framework/onnxruntime" ] || \
   [ ! -f "${XCFRAMEWORK}/ios-arm64/onnxruntime.framework/Headers/onnxruntime_c_api.h" ] || \
   [ ! -f "${XCFRAMEWORK}/ios-arm64_x86_64-simulator/onnxruntime.framework/onnxruntime" ]; then
    echo "Error: verified ONNX Runtime XCFramework is missing a required iOS slice or header" >&2
    exit 1
fi

STAGED_DIR="${TEMP_DIR}/staged"
mkdir -p "${STAGED_DIR}"
cp -R "${XCFRAMEWORK}" "${STAGED_DIR}/"

# Also copy headers if they exist at the top level
if [ -d "${TEMP_DIR}/extracted/Headers" ]; then
    cp -R "${TEMP_DIR}/extracted/Headers" "${STAGED_DIR}/"
else
    cp -R "${XCFRAMEWORK}/ios-arm64/onnxruntime.framework/Headers" "${STAGED_DIR}/"
fi

mkdir -p "$(dirname "${ONNX_DIR}")"
rm -rf "${ONNX_DIR}"
mv "${STAGED_DIR}" "${ONNX_DIR}"

echo ""
echo "✅ ONNX Runtime xcframework downloaded to ${ONNX_DIR}/onnxruntime.xcframework"
echo ""
echo "Contents:"
ls -lh "${ONNX_DIR}/onnxruntime.xcframework"
