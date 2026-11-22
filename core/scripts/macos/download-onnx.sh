#!/bin/bash
# Download the pinned macOS ONNX Runtime dylib and headers.
# The official per-arch release is preferred; a verified NuGet package keeps
# Apple Silicon builds working when GitHub release assets are unavailable.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ONNX_DIR="${ROOT_DIR}/third_party/onnxruntime-macos"

source "${SCRIPT_DIR}/../load-versions.sh"

if [ -z "${ONNX_VERSION_MACOS:-}" ] || \
   [ -z "${ONNX_NUGET_SHA256:-}" ] || \
   [ -z "${ONNX_NUGET_IOS_SHA256:-}" ]; then
    echo "ERROR: macOS ONNX Runtime version/checksums not loaded from VERSIONS" >&2
    exit 1
fi

if [ -f "${ONNX_DIR}/lib/libonnxruntime.dylib" ] && \
   [ -e "${ONNX_DIR}/lib/libonnxruntime.1.dylib" ] && \
   [ -f "${ONNX_DIR}/include/onnxruntime_c_api.h" ] && \
   [ -f "${ONNX_DIR}/include/coreml_provider_factory.h" ]; then
    echo "ONNX Runtime macOS already exists at ${ONNX_DIR}"
    exit 0
fi

case "$(uname -m)" in
    arm64|aarch64) ONNX_ARCH="arm64" ;;
    x86_64) ONNX_ARCH="x86_64" ;;
    *) echo "ERROR: unsupported macOS architecture: $(uname -m)" >&2; exit 1 ;;
esac

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_DIR}"' EXIT
STAGED_DIR="${TEMP_DIR}/staged"
mkdir -p "${STAGED_DIR}/lib" "${STAGED_DIR}/include"

RELEASE_URL="https://github.com/microsoft/onnxruntime/releases/download/v${ONNX_VERSION_MACOS}/onnxruntime-osx-${ONNX_ARCH}-${ONNX_VERSION_MACOS}.tgz"
RELEASE_ARCHIVE="${TEMP_DIR}/onnxruntime.tgz"
echo "Downloading ONNX Runtime macOS v${ONNX_VERSION_MACOS} from ${RELEASE_URL}..."
if curl --fail --location --show-error --silent --connect-timeout 20 \
    --max-time 180 --output "${RELEASE_ARCHIVE}" "${RELEASE_URL}"; then
    tar -xzf "${RELEASE_ARCHIVE}" -C "${TEMP_DIR}"
    EXTRACTED_DIR="${TEMP_DIR}/onnxruntime-osx-${ONNX_ARCH}-${ONNX_VERSION_MACOS}"
    if [ ! -f "${EXTRACTED_DIR}/lib/libonnxruntime.dylib" ]; then
        echo "ERROR: ONNX Runtime release has an unexpected layout" >&2
        exit 1
    fi
    cp -R "${EXTRACTED_DIR}/lib/." "${STAGED_DIR}/lib/"
    cp -R "${EXTRACTED_DIR}/include/." "${STAGED_DIR}/include/"
else
    if [ "${ONNX_ARCH}" != "arm64" ]; then
        echo "ERROR: ONNX Runtime ${ONNX_VERSION_MACOS} NuGet has no macOS x64 payload; the GitHub release is required" >&2
        exit 1
    fi
    NUGET_URL="https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime/${ONNX_VERSION_MACOS}/microsoft.ml.onnxruntime.${ONNX_VERSION_MACOS}.nupkg"
    NUGET_FILE="${TEMP_DIR}/onnxruntime.nupkg"
    echo "GitHub release unavailable; downloading verified NuGet fallback..."
    curl --fail --location --show-error --silent --retry 3 --connect-timeout 20 \
        --output "${NUGET_FILE}" "${NUGET_URL}"
    ACTUAL_SHA256="$(shasum -a 256 "${NUGET_FILE}" | awk '{print $1}')"
    if [ "${ACTUAL_SHA256}" != "${ONNX_NUGET_SHA256}" ]; then
        echo "ERROR: ONNX Runtime NuGet archive checksum mismatch" >&2
        exit 1
    fi
    unzip -p "${NUGET_FILE}" \
        runtimes/osx-arm64/native/libonnxruntime.dylib > \
        "${STAGED_DIR}/lib/libonnxruntime.dylib"
    unzip -j -q "${NUGET_FILE}" 'build/native/include/*' -d "${STAGED_DIR}/include"
    IOS_ZIP="${TEMP_DIR}/onnxruntime-ios.zip"
    unzip -p "${NUGET_FILE}" \
        runtimes/ios/native/onnxruntime.xcframework.zip > "${IOS_ZIP}"
    ACTUAL_IOS_SHA256="$(shasum -a 256 "${IOS_ZIP}" | awk '{print $1}')"
    if [ "${ACTUAL_IOS_SHA256}" != "${ONNX_NUGET_IOS_SHA256}" ]; then
        echo "ERROR: ONNX Runtime NuGet XCFramework checksum mismatch" >&2
        exit 1
    fi
    unzip -p "${IOS_ZIP}" \
        onnxruntime.xcframework/ios-arm64/onnxruntime.framework/Headers/coreml_provider_factory.h > \
        "${STAGED_DIR}/include/coreml_provider_factory.h"
fi

if [ ! -e "${STAGED_DIR}/lib/libonnxruntime.1.dylib" ]; then
    ln -s libonnxruntime.dylib "${STAGED_DIR}/lib/libonnxruntime.1.dylib"
fi
if [ ! -s "${STAGED_DIR}/lib/libonnxruntime.dylib" ] || \
   [ ! -e "${STAGED_DIR}/lib/libonnxruntime.1.dylib" ] || \
   [ ! -s "${STAGED_DIR}/include/onnxruntime_c_api.h" ] || \
   [ ! -s "${STAGED_DIR}/include/coreml_provider_factory.h" ]; then
    echo "ERROR: ONNX Runtime macOS library or required headers are missing" >&2
    exit 1
fi

mkdir -p "$(dirname "${ONNX_DIR}")"
rm -rf "${ONNX_DIR}"
mv "${STAGED_DIR}" "${ONNX_DIR}"
echo "ONNX Runtime macOS v${ONNX_VERSION_MACOS} installed to ${ONNX_DIR}"
