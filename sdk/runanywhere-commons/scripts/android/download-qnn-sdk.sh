#!/bin/bash

# =============================================================================
# download-qnn-sdk.sh
# Downloads and extracts Qualcomm QNN SDK for Android NPU acceleration
#
# The QNN SDK provides:
#   - libQnnHtp.so    - Hexagon NPU backend for Snapdragon chips
#   - libQnnCpu.so    - CPU backend (fallback)
#   - libQnnSystem.so - System interface layer
#
# Requirements:
#   - Qualcomm AI Hub account (free): https://aihub.qualcomm.com
#   - Or manual download from: https://qpm.qualcomm.com
#
# Usage:
#   ./download-qnn-sdk.sh                    # Auto-detect from environment
#   ./download-qnn-sdk.sh --version 2.28.0   # Specific version
#   ./download-qnn-sdk.sh --extract-libs     # Just copy libs for APK bundling
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
QNN_DIR="${ROOT_DIR}/third_party/qnn-sdk"
QNN_LIBS_DIR="${ROOT_DIR}/third_party/qnn-libs"

# Default QNN SDK version (check https://qpm.qualcomm.com for latest)
QNN_VERSION="${QNN_VERSION:-2.28.0}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}[OK] $1${NC}"
}

print_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[WARN] $1${NC}"
}

print_info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# =============================================================================
# Parse Arguments
# =============================================================================

EXTRACT_LIBS_ONLY=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --version) QNN_VERSION="$2"; shift ;;
        --extract-libs) EXTRACT_LIBS_ONLY=true ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --version VERSION    QNN SDK version (default: ${QNN_VERSION})"
            echo "  --extract-libs       Only extract libs for APK bundling"
            echo "  --help               Show this help"
            exit 0
            ;;
        *) print_error "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

print_header "Qualcomm QNN SDK Setup for Android NPU"
echo "Version: ${QNN_VERSION}"
echo "Target:  ${QNN_DIR}"

# =============================================================================
# Check for Existing QNN SDK
# =============================================================================

check_qnn_sdk() {
    # Check environment variable first
    if [ -n "$QNN_SDK_ROOT" ] && [ -d "$QNN_SDK_ROOT" ]; then
        print_success "Found QNN SDK at: $QNN_SDK_ROOT"
        return 0
    fi
    
    # Check our third_party directory
    if [ -d "${QNN_DIR}" ] && [ -f "${QNN_DIR}/lib/aarch64-android/libQnnHtp.so" ]; then
        print_success "Found QNN SDK at: ${QNN_DIR}"
        export QNN_SDK_ROOT="${QNN_DIR}"
        return 0
    fi
    
    return 1
}

# =============================================================================
# Extract Libraries for APK Bundling
# =============================================================================

extract_libs_for_apk() {
    local SDK_PATH="${1:-$QNN_SDK_ROOT}"
    
    if [ -z "$SDK_PATH" ] || [ ! -d "$SDK_PATH" ]; then
        print_error "QNN SDK not found. Download it first."
        exit 1
    fi
    
    print_header "Extracting QNN Libraries for APK"
    
    mkdir -p "${QNN_LIBS_DIR}/arm64-v8a"
    
    # Required libraries for Hexagon NPU
    QNN_LIBS=(
        "libQnnHtp.so"              # Hexagon NPU backend
        "libQnnHtpPrepare.so"       # Model preparation
        "libQnnHtpV75Stub.so"       # V75 HTP stub (Snapdragon 8 Gen 3)
        "libQnnHtpV73Stub.so"       # V73 HTP stub (Snapdragon 8 Gen 2)
        "libQnnHtpV69Stub.so"       # V69 HTP stub (Snapdragon 8 Gen 1)
        "libQnnHtpV68Stub.so"       # V68 HTP stub (older chips)
        "libQnnSystem.so"           # System interface
        "libQnnCpu.so"              # CPU backend (fallback)
    )
    
    # Optional: Skel libraries (for direct DSP access)
    QNN_SKEL_LIBS=(
        "libQnnHtpV75Skel.so"
        "libQnnHtpV73Skel.so"
        "libQnnHtpV69Skel.so"
        "libQnnHtpV68Skel.so"
    )
    
    for lib in "${QNN_LIBS[@]}"; do
        if [ -f "${SDK_PATH}/lib/aarch64-android/${lib}" ]; then
            cp "${SDK_PATH}/lib/aarch64-android/${lib}" "${QNN_LIBS_DIR}/arm64-v8a/"
            echo "  Copied: ${lib}"
        else
            print_warning "Not found: ${lib}"
        fi
    done
    
    # Copy skel libraries if present
    for lib in "${QNN_SKEL_LIBS[@]}"; do
        if [ -f "${SDK_PATH}/lib/hexagon-v75/unsigned/${lib}" ]; then
            cp "${SDK_PATH}/lib/hexagon-v75/unsigned/${lib}" "${QNN_LIBS_DIR}/arm64-v8a/"
            echo "  Copied: ${lib} (from hexagon-v75)"
        elif [ -f "${SDK_PATH}/lib/hexagon-v73/unsigned/${lib}" ]; then
            cp "${SDK_PATH}/lib/hexagon-v73/unsigned/${lib}" "${QNN_LIBS_DIR}/arm64-v8a/"
            echo "  Copied: ${lib} (from hexagon-v73)"
        fi
    done
    
    # Create README for the libs
    cat > "${QNN_LIBS_DIR}/README.md" << 'EOF'
# QNN Libraries for Android APK

These libraries provide Qualcomm NPU (Hexagon) acceleration for Android devices.

## Directory Structure

```
arm64-v8a/
├── libQnnHtp.so           # Main Hexagon NPU backend
├── libQnnHtpPrepare.so    # Model preparation utilities
├── libQnnHtpV75Stub.so    # Snapdragon 8 Gen 3 (SM8650)
├── libQnnHtpV73Stub.so    # Snapdragon 8 Gen 2 (SM8550)
├── libQnnHtpV69Stub.so    # Snapdragon 8 Gen 1 (SM8450)
├── libQnnSystem.so        # System interface
└── libQnnCpu.so           # CPU fallback
```

## Usage in Gradle

Add to your `build.gradle`:

```groovy
android {
    sourceSets {
        main {
            jniLibs.srcDirs = ['src/main/jniLibs', '/path/to/qnn-libs']
        }
    }
}
```

## Supported Devices

| Chip | Codename | HTP Version | Example Devices |
|------|----------|-------------|-----------------|
| SM8650 | Pineapple | V75 | Galaxy S24, OnePlus 12 |
| SM8550 | Kalama | V73 | Galaxy S23, Pixel 8 Pro |
| SM8450 | Waipio | V69 | Galaxy S22, OnePlus 10 |
| SM8350 | Lahaina | V68 | Galaxy S21, OnePlus 9 |

## License

Qualcomm AI Engine Direct SDK is subject to Qualcomm's license terms.
See: https://qpm.qualcomm.com
EOF

    print_success "QNN libraries extracted to: ${QNN_LIBS_DIR}"
    echo ""
    echo "To use in Android project:"
    echo "  1. Copy ${QNN_LIBS_DIR}/arm64-v8a/* to app/src/main/jniLibs/arm64-v8a/"
    echo "  2. Or configure jniLibs.srcDirs in build.gradle"
}

# =============================================================================
# Download QNN SDK (Manual Instructions)
# =============================================================================

download_qnn_sdk() {
    print_header "QNN SDK Download Instructions"
    
    cat << 'EOF'
Qualcomm QNN SDK requires manual download due to license agreement.

Option 1: Qualcomm AI Hub (Recommended - Free)
----------------------------------------------
1. Create account at: https://aihub.qualcomm.com
2. After login, get API key from profile settings
3. Install qai-hub: pip install qai-hub
4. Login: qai-hub login
5. Download will happen automatically when compiling models

Option 2: Qualcomm Package Manager (Full SDK)
---------------------------------------------
1. Go to: https://qpm.qualcomm.com
2. Search for "AI Engine Direct SDK" or "QNN"
3. Download the Android version (qairt-X.X.X-android.zip)
4. Extract to: third_party/qnn-sdk/
5. Run: export QNN_SDK_ROOT=/path/to/qnn-sdk

Option 3: Pre-built Libraries from GitHub Release
-------------------------------------------------
We've prepared QNN libraries for common use cases:
EOF

    echo ""
    echo "Would you like to download pre-built QNN libraries from our GitHub release?"
    echo "These include all required .so files for Snapdragon 8 Gen 1/2/3 devices."
    echo ""
    
    # Offer to download from our release
    QNN_RELEASE_URL="https://github.com/RunanywhereAI/sherpa-onnx/releases/download/qnn-libs-v2.28.0/qnn-android-libs-v2.28.0.tar.gz"
    
    echo "Attempting to download from: ${QNN_RELEASE_URL}"
    echo ""
    
    mkdir -p "${QNN_DIR}"
    
    if curl -L -o "/tmp/qnn-libs.tar.gz" "${QNN_RELEASE_URL}" 2>/dev/null; then
        print_success "Downloaded QNN libraries"
        tar -xzf "/tmp/qnn-libs.tar.gz" -C "${QNN_DIR}"
        rm -f "/tmp/qnn-libs.tar.gz"
        export QNN_SDK_ROOT="${QNN_DIR}"
        return 0
    else
        print_warning "Could not download from release. Manual installation required."
        echo ""
        echo "After manual installation, run:"
        echo "  export QNN_SDK_ROOT=/path/to/qnn-sdk"
        echo "  ./scripts/android/download-qnn-sdk.sh --extract-libs"
        return 1
    fi
}

# =============================================================================
# Main
# =============================================================================

if [ "$EXTRACT_LIBS_ONLY" = true ]; then
    if check_qnn_sdk; then
        extract_libs_for_apk
    else
        print_error "QNN SDK not found. Set QNN_SDK_ROOT or download first."
        exit 1
    fi
else
    if check_qnn_sdk; then
        print_success "QNN SDK already installed"
        extract_libs_for_apk
    else
        if download_qnn_sdk; then
            extract_libs_for_apk
        else
            print_warning "Please download QNN SDK manually and re-run this script"
            exit 1
        fi
    fi
fi

print_header "QNN SDK Setup Complete"
echo ""
echo "Next steps:"
echo "  1. Build Android with QNN support:"
echo "     ./scripts/build-android.sh --qnn all arm64-v8a"
echo ""
echo "  2. Or manually copy libs to your APK:"
echo "     cp -r ${QNN_LIBS_DIR}/arm64-v8a/* app/src/main/jniLibs/arm64-v8a/"
echo ""
echo "Supported devices:"
echo "  - Samsung Galaxy S21/S22/S23/S24 series"
echo "  - Google Pixel 6/7/8 (limited QNN support)"  
echo "  - OnePlus 9/10/11/12 series"
echo "  - Xiaomi 12/13/14 series"
echo "  - Any device with Snapdragon 8 Gen 1/2/3"
echo ""
