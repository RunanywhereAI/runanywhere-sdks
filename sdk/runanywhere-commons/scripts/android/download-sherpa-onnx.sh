#!/bin/bash
# =============================================================================
# download-sherpa-onnx.sh
# Download Sherpa-ONNX Android native libraries
#
# Sherpa-ONNX provides pre-built Android AAR/native libraries.
# This script downloads them for STT, TTS, and VAD support.
#
# 16KB Page Size Alignment (Google Play requirement)
# --------------------------------------------------
# Starting November 1, 2025, Google Play requires all apps targeting
# Android 15+ (API 35+) to have 16KB-aligned native libraries.
#
# ✅ Sherpa-ONNX v1.12.20+ pre-built binaries ARE 16KB aligned!
#    (Fixed in https://github.com/k2-fsa/sherpa-onnx/pull/2520)
#
# Usage:
#   ./download-sherpa-onnx.sh              # Download pre-built (16KB aligned)
#   ./download-sherpa-onnx.sh --check      # Verify library alignment
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SHERPA_DIR="${ROOT_DIR}/third_party/sherpa-onnx-android"

# Load versions from centralized VERSIONS file (SINGLE SOURCE OF TRUTH)
source "${SCRIPT_DIR}/../load-versions.sh"

# Use version from VERSIONS file - no hardcoded fallbacks
if [ -z "${SHERPA_ONNX_VERSION_ANDROID:-}" ]; then
    echo "ERROR: SHERPA_ONNX_VERSION_ANDROID not loaded from VERSIONS file" >&2
    exit 1
fi
SHERPA_VERSION="${SHERPA_ONNX_VERSION_ANDROID}"
# Official Sherpa-ONNX Android release
DOWNLOAD_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/v${SHERPA_VERSION}/sherpa-onnx-v${SHERPA_VERSION}-android.tar.bz2"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Parse arguments
CHECK_ONLY=false

for arg in "$@"; do
    case $arg in
        --check)
            CHECK_ONLY=true
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --check   Verify alignment of existing libraries"
            echo "  --help    Show this help message"
            echo ""
            echo "Note: Sherpa-ONNX v1.12.20+ pre-built binaries ARE 16KB aligned."
            exit 0
            ;;
    esac
done

# Function to check 16KB alignment
check_alignment() {
    local so_file="$1"
    local filename=$(basename "$so_file")

    # Find readelf
    local READELF=""
    if command -v llvm-readelf &> /dev/null; then
        READELF="llvm-readelf"
    elif [ -d "$HOME/Library/Android/sdk/ndk" ]; then
        NDK_PATH=$(ls -d "$HOME/Library/Android/sdk/ndk"/*/ 2>/dev/null | sort -V | tail -1)
        if [ -f "$NDK_PATH/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-readelf" ]; then
            READELF="$NDK_PATH/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-readelf"
        fi
    fi

    if [ -z "$READELF" ]; then
        echo "unknown"
        return
    fi

    local LOAD_OUTPUT=$("$READELF" -l "$so_file" 2>/dev/null | grep "LOAD" || true)

    local HAS_4KB=false
    local HAS_16KB=false

    while IFS= read -r line; do
        local ALIGN_VAL=$(echo "$line" | grep -oE '0x[0-9a-fA-F]+' | tail -1)
        case "$ALIGN_VAL" in
            0x1000|0x001000)
                HAS_4KB=true
                ;;
            0x4000|0x004000)
                HAS_16KB=true
                ;;
        esac
    done <<< "$LOAD_OUTPUT"

    if [ "$HAS_4KB" = true ] && [ "$HAS_16KB" = false ]; then
        echo "4KB"
    elif [ "$HAS_16KB" = true ]; then
        echo "16KB"
    else
        echo "unknown"
    fi
}

# Check alignment of existing libraries
if [ "$CHECK_ONLY" = true ]; then
    echo -e "${BLUE}=======================================${NC}"
    echo -e "${BLUE}Checking Sherpa-ONNX Library Alignment${NC}"
    echo -e "${BLUE}=======================================${NC}"
    echo ""

    if [ ! -d "${SHERPA_DIR}/jniLibs" ]; then
        echo -e "${RED}No libraries found at ${SHERPA_DIR}/jniLibs${NC}"
        exit 1
    fi

    ALL_16KB=true
    for so_file in "${SHERPA_DIR}/jniLibs"/*/*.so; do
        if [ -f "$so_file" ]; then
            alignment=$(check_alignment "$so_file")
            filename=$(basename "$so_file")
            abi=$(basename $(dirname "$so_file"))

            if [ "$alignment" = "16KB" ]; then
                echo -e "${GREEN}✅ $abi/$filename - 16KB aligned${NC}"
            elif [ "$alignment" = "4KB" ]; then
                echo -e "${RED}❌ $abi/$filename - 4KB aligned (NOT Play Store ready)${NC}"
                ALL_16KB=false
            else
                echo -e "${YELLOW}⚠️  $abi/$filename - Unknown alignment${NC}"
            fi
        fi
    done

    echo ""
    if [ "$ALL_16KB" = true ]; then
        echo -e "${GREEN}All libraries are 16KB aligned - Play Store ready!${NC}"
    else
        echo -e "${RED}Some libraries are NOT 16KB aligned.${NC}"
        echo -e "${RED}Please re-download with: rm -rf ${SHERPA_DIR} && $0${NC}"
    fi
    exit 0
fi

# Default: Download pre-built libraries
echo -e "${BLUE}=======================================${NC}"
echo -e "${BLUE}📦 Sherpa-ONNX Android Downloader${NC}"
echo -e "${BLUE}=======================================${NC}"
echo ""
echo "Version: ${SHERPA_VERSION}"
echo -e "${GREEN}✅ Pre-built libraries are 16KB aligned (Play Store ready)${NC}"
echo ""

# Check if already exists
if [ -d "${SHERPA_DIR}/jniLibs" ]; then
    if [ -f "${SHERPA_DIR}/jniLibs/arm64-v8a/libsherpa-onnx-jni.so" ]; then
        echo "✅ Sherpa-ONNX Android libraries already exist"
        echo "   Location: ${SHERPA_DIR}"
        echo ""
        echo "To force re-download, remove the directory first:"
        echo "   rm -rf ${SHERPA_DIR}"
        exit 0
    else
        echo "⚠️  Existing directory appears incomplete, re-downloading..."
        rm -rf "${SHERPA_DIR}"
    fi
fi

# Create temp directory for download
TEMP_DIR=$(mktemp -d)
TEMP_ARCHIVE="${TEMP_DIR}/sherpa-onnx-android.tar.bz2"

echo ""
echo "Downloading from ${DOWNLOAD_URL}..."

# Download
HTTP_CODE=$(curl -L -w "%{http_code}" -o "${TEMP_ARCHIVE}" "${DOWNLOAD_URL}" 2>/dev/null) || true

if [ "${HTTP_CODE}" = "200" ] && [ -f "${TEMP_ARCHIVE}" ] && [ -s "${TEMP_ARCHIVE}" ]; then
    echo "Download complete. Size: $(du -h "${TEMP_ARCHIVE}" | cut -f1)"

    # Extract
    echo "Extracting..."
    mkdir -p "${SHERPA_DIR}"
    tar -xjf "${TEMP_ARCHIVE}" -C "${TEMP_DIR}"

    # Find the extracted directory - check multiple possible structures
    EXTRACTED_DIR=$(find "${TEMP_DIR}" -maxdepth 1 -type d -name "sherpa-onnx-*-android" | head -1)
    if [ -z "${EXTRACTED_DIR}" ]; then
        EXTRACTED_DIR=$(find "${TEMP_DIR}" -maxdepth 1 -type d -name "build-android*" | head -1)
    fi

    # Copy JNI libraries - handle different extraction structures
    if [ -n "${EXTRACTED_DIR}" ] && [ -d "${EXTRACTED_DIR}/jniLibs" ]; then
        cp -R "${EXTRACTED_DIR}/jniLibs" "${SHERPA_DIR}/"
    elif [ -n "${EXTRACTED_DIR}" ] && [ -d "${EXTRACTED_DIR}/lib" ]; then
        mkdir -p "${SHERPA_DIR}/jniLibs"
        # Copy each ABI directory
        for abi_dir in "${EXTRACTED_DIR}/lib"/*; do
            if [ -d "$abi_dir" ]; then
                abi_name=$(basename "$abi_dir")
                mkdir -p "${SHERPA_DIR}/jniLibs/${abi_name}"
                cp "${abi_dir}"/*.so "${SHERPA_DIR}/jniLibs/${abi_name}/" 2>/dev/null || true
            fi
        done
    elif [ -d "${TEMP_DIR}/jniLibs" ]; then
        # jniLibs extracted directly to temp dir
        cp -R "${TEMP_DIR}/jniLibs" "${SHERPA_DIR}/"
    else
        echo "Error: Could not find jniLibs in extracted archive"
        ls -la "${TEMP_DIR}"
        rm -rf "${TEMP_DIR}"
        exit 1
    fi

    # Copy headers if present
    if [ -n "${EXTRACTED_DIR}" ] && [ -d "${EXTRACTED_DIR}/include" ]; then
        cp -R "${EXTRACTED_DIR}/include" "${SHERPA_DIR}/"
    elif [ -d "${TEMP_DIR}/include" ]; then
        cp -R "${TEMP_DIR}/include" "${SHERPA_DIR}/"
    fi

    # Clean up
    rm -rf "${TEMP_DIR}"

    # Download headers if not present (Android release doesn't include them)
    if [ ! -d "${SHERPA_DIR}/include/sherpa-onnx" ]; then
        echo ""
        echo "Downloading Sherpa-ONNX headers..."
        mkdir -p "${SHERPA_DIR}/include"

        # Try to download from iOS since headers are platform-independent
        IOS_SHERPA_HEADERS="${ROOT_DIR}/third_party/sherpa-onnx-ios/sherpa-onnx.xcframework/ios-arm64/Headers"
        if [ -d "${IOS_SHERPA_HEADERS}/sherpa-onnx" ]; then
            echo "Using headers from iOS Sherpa-ONNX..."
            cp -R "${IOS_SHERPA_HEADERS}"/* "${SHERPA_DIR}/include/"
        else
            # Fallback: Download headers from source repo
            echo "Downloading headers from Sherpa-ONNX source..."
            curl -sL "https://raw.githubusercontent.com/k2-fsa/sherpa-onnx/v${SHERPA_VERSION}/sherpa-onnx/c-api/c-api.h" \
                -o "${SHERPA_DIR}/include/sherpa-onnx/c-api/c-api.h" --create-dirs
            curl -sL "https://raw.githubusercontent.com/k2-fsa/sherpa-onnx/v${SHERPA_VERSION}/sherpa-onnx/c-api/cxx-api.h" \
                -o "${SHERPA_DIR}/include/sherpa-onnx/c-api/cxx-api.h" --create-dirs
        fi
        echo "✅ Sherpa-ONNX headers installed"
    fi

    # Download ONNX Runtime C API header (required for ONNX backend compilation)
    # Uses ONNX_VERSION_ANDROID from VERSIONS file (Sherpa-ONNX must be compatible)
    if [ ! -f "${SHERPA_DIR}/include/onnxruntime_c_api.h" ]; then
        echo ""
        echo "Downloading ONNX Runtime C API header..."
        if [ -z "${ONNX_VERSION_ANDROID:-}" ]; then
            echo "ERROR: ONNX_VERSION_ANDROID not loaded from VERSIONS file" >&2
            exit 1
        fi
        ONNX_RT_VERSION="${ONNX_VERSION_ANDROID}"
        curl -sL "https://raw.githubusercontent.com/microsoft/onnxruntime/v${ONNX_RT_VERSION}/include/onnxruntime/core/session/onnxruntime_c_api.h" \
            -o "${SHERPA_DIR}/include/onnxruntime_c_api.h"
        echo "✅ ONNX Runtime header installed (v${ONNX_RT_VERSION})"
    fi

    echo ""
    echo "✅ Sherpa-ONNX Android libraries downloaded to ${SHERPA_DIR}"
    echo ""
    echo "Contents:"
    ls -lh "${SHERPA_DIR}"
    if [ -d "${SHERPA_DIR}/jniLibs" ]; then
        echo ""
        echo "JNI Libraries:"
        find "${SHERPA_DIR}/jniLibs" -name "*.so" -exec ls -lh {} \;
    fi
    if [ -d "${SHERPA_DIR}/include" ]; then
        echo ""
        echo "Headers:"
        find "${SHERPA_DIR}/include" -name "*.h"
    fi
else
    echo ""
    echo "⚠️  Download failed (HTTP: ${HTTP_CODE})"
    echo ""
    rm -rf "${TEMP_DIR}"

    echo "=============================================="
    echo "❌ Sherpa-ONNX download failed"
    echo "=============================================="
    echo ""
    echo "Manual download options:"
    echo ""
    echo "1. Download directly from Sherpa-ONNX releases:"
    echo "   ${DOWNLOAD_URL}"
    echo ""
    echo "2. Extract and copy jniLibs to:"
    echo "   ${SHERPA_DIR}/jniLibs/"
    echo ""
    exit 1
fi
