#!/bin/bash
# Download and verify the pinned upstream Sherpa-ONNX iOS XCFramework.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SHERPA_DIR="${ROOT_DIR}/third_party/sherpa-onnx-ios"

# Load versions from centralized VERSIONS file (SINGLE SOURCE OF TRUTH)
# The path is resolved from this script at runtime.
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../load-versions.sh"

# Use version from VERSIONS file - no hardcoded fallbacks
if [ -z "${SHERPA_ONNX_VERSION_IOS:-}" ]; then
    echo "ERROR: SHERPA_ONNX_VERSION_IOS not loaded from VERSIONS file" >&2
    exit 1
fi
if [ -z "${SHERPA_ONNX_IOS_SHA256:-}" ]; then
    echo "ERROR: SHERPA_ONNX_IOS_SHA256 not loaded from VERSIONS file" >&2
    exit 1
fi
SHERPA_VERSION="${SHERPA_ONNX_VERSION_IOS}"
DOWNLOAD_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/xcframework/sherpa-onnx-v${SHERPA_VERSION}-ios-static.xcframework.zip"
VERSION_MARKER="${SHERPA_DIR}/.sherpa-version"

echo "======================================="
echo "📦 Sherpa-ONNX iOS XCFramework Downloader"
echo "======================================="
echo ""
echo "Version: ${SHERPA_VERSION}"

# Check if already exists and is valid
if [ -d "${SHERPA_DIR}/sherpa-onnx.xcframework" ]; then
    if [ "$(cat "${VERSION_MARKER}" 2>/dev/null || true)" = "${SHERPA_VERSION}" ] && \
       [ -f "${SHERPA_DIR}/sherpa-onnx.xcframework/ios-arm64/libsherpa-onnx.a" ] && \
       [ -f "${SHERPA_DIR}/sherpa-onnx.xcframework/ios-arm64_x86_64-simulator/libsherpa-onnx.a" ] && \
       grep -q 'SherpaOnnxOfflineTtsGenerateWithConfig' \
         "${SHERPA_DIR}/sherpa-onnx.xcframework/ios-arm64/Headers/sherpa-onnx/c-api/c-api.h"; then
        echo "✅ Sherpa-ONNX xcframework already exists and appears valid"
        echo "   Location: ${SHERPA_DIR}/sherpa-onnx.xcframework"
        echo ""
        echo "To force re-download, remove the directory first:"
        echo "   rm -rf ${SHERPA_DIR}/sherpa-onnx.xcframework"
        exit 0
    else
        echo "⚠️  Existing XCFramework is stale or incomplete; replacing it..."
        rm -rf "${SHERPA_DIR}"
    fi
fi

# Create temp directory for download
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "${TEMP_DIR}"' EXIT
TEMP_ARCHIVE="${TEMP_DIR}/sherpa-onnx-ios.xcframework.zip"

echo ""
echo "Downloading from ${DOWNLOAD_URL}..."

curl --fail --show-error --location --http1.1 \
    --retry 5 --retry-all-errors --retry-delay 2 \
    --output "${TEMP_ARCHIVE}" "${DOWNLOAD_URL}"

ACTUAL_SHA256="$(shasum -a 256 "${TEMP_ARCHIVE}" | awk '{print $1}')"
if [ "${ACTUAL_SHA256}" != "${SHERPA_ONNX_IOS_SHA256}" ]; then
    echo "ERROR: Sherpa-ONNX iOS archive checksum mismatch" >&2
    echo "  expected: ${SHERPA_ONNX_IOS_SHA256}" >&2
    echo "  actual:   ${ACTUAL_SHA256}" >&2
    exit 1
fi

mkdir -p "${TEMP_DIR}/extracted"
unzip -q "${TEMP_ARCHIVE}" -d "${TEMP_DIR}/extracted"
XCFRAMEWORK="$(find "${TEMP_DIR}/extracted" -type d -name 'sherpa-onnx.xcframework' -print -quit)"
if [ -z "${XCFRAMEWORK}" ]; then
    echo "ERROR: sherpa-onnx.xcframework not found in verified archive" >&2
    exit 1
fi

DEVICE_FRAMEWORK="${XCFRAMEWORK}/ios-arm64/SherpaOnnxC.framework"
SIMULATOR_FRAMEWORK="${XCFRAMEWORK}/ios-arm64_x86_64-simulator/SherpaOnnxC.framework"
HEADER="${DEVICE_FRAMEWORK}/Headers/sherpa-onnx/c-api/c-api.h"
if [ ! -f "${DEVICE_FRAMEWORK}/SherpaOnnxC" ] || \
   [ ! -f "${SIMULATOR_FRAMEWORK}/SherpaOnnxC" ] || \
   [ ! -f "${HEADER}" ] || \
   ! grep -q 'SherpaOnnxOfflineTtsGenerateWithConfig' "${HEADER}"; then
    echo "ERROR: downloaded Sherpa-ONNX headers do not expose the required current TTS API" >&2
    exit 1
fi

rm -rf "${SHERPA_DIR}"
NORMALIZED_XCFRAMEWORK="${SHERPA_DIR}/sherpa-onnx.xcframework"
for slice in ios-arm64 ios-arm64_x86_64-simulator; do
    source_framework="${XCFRAMEWORK}/${slice}/SherpaOnnxC.framework"
    destination_slice="${NORMALIZED_XCFRAMEWORK}/${slice}"
    mkdir -p "${destination_slice}"
    cp "${source_framework}/SherpaOnnxC" "${destination_slice}/libsherpa-onnx.a"
    cp -R "${source_framework}/Headers" "${destination_slice}/Headers"
done
printf '%s\n' "${SHERPA_VERSION}" > "${VERSION_MARKER}"

echo ""
echo "✅ Sherpa-ONNX ${SHERPA_VERSION} XCFramework installed at ${SHERPA_DIR}/sherpa-onnx.xcframework"
