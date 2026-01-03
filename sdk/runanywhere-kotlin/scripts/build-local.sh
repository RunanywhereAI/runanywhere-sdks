#!/bin/bash
# =============================================================================
# RunAnywhere Kotlin SDK - Local Build Script
# =============================================================================
#
# This script builds native libraries locally from runanywhere-commons,
# matching the Swift SDK's architecture:
#
# Swift Architecture:
#   runanywhere-core → RACommons.xcframework + RABackendLlamaCPP.xcframework + RABackendONNX.xcframework
#
# Android/Kotlin Architecture (this script produces):
#   runanywhere-core → runanywhere-commons → JNI libraries:
#     - librunanywhere_jni.so (main JNI bridge with rac_* APIs)
#     - libracommons.so (commons core)
#     - librac_backend_llamacpp.so (LlamaCPP backend)
#     - librac_backend_onnx.so (ONNX backend)
#     - libc++_shared.so (C++ STL)
#     - Dependencies from runanywhere-core (llama.cpp, onnxruntime, etc.)
#
# Usage:
#   ./scripts/build-local.sh [--backends=llamacpp,onnx] [--abis=arm64-v8a] [--skip-core]
#
# Environment variables:
#   ANDROID_NDK_HOME - Path to Android NDK (required)
#   BUILD_TYPE       - Release or Debug (default: Release)
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KOTLIN_SDK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SDKS_DIR="$(cd "${KOTLIN_SDK_DIR}/../.." && pwd)"
COMMONS_DIR="${SDKS_DIR}/sdk/runanywhere-commons"
CORE_DIR="${SDKS_DIR}/../runanywhere-core"

# Output directory in Kotlin SDK
JNILIBS_DIR="${KOTLIN_SDK_DIR}/src/androidMain/jniLibs"

# =============================================================================
# Configuration
# =============================================================================

# Parse arguments
BACKENDS="llamacpp,onnx"
ABIS="arm64-v8a"
SKIP_CORE=false

for arg in "$@"; do
    case $arg in
        --backends=*)
            BACKENDS="${arg#*=}"
            ;;
        --abis=*)
            ABIS="${arg#*=}"
            ;;
        --skip-core)
            SKIP_CORE=true
            ;;
        --help|-h)
            echo "Usage: $0 [--backends=llamacpp,onnx] [--abis=arm64-v8a] [--skip-core]"
            echo ""
            echo "Options:"
            echo "  --backends=BACKENDS  Comma-separated list of backends (default: llamacpp,onnx)"
            echo "  --abis=ABIS          Comma-separated list of ABIs (default: arm64-v8a)"
            echo "  --skip-core          Skip building runanywhere-core"
            echo ""
            exit 0
            ;;
    esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
}

print_step() {
    echo -e "${GREEN}▶ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}  ℹ $1${NC}"
}

print_success() {
    echo -e "${GREEN}  ✓ $1${NC}"
}

print_error() {
    echo -e "${RED}  ✗ $1${NC}"
}

# =============================================================================
# Validation
# =============================================================================

print_header "Build Configuration"

# Check NDK
if [ -z "${ANDROID_NDK_HOME}" ]; then
    # Try to find NDK
    if [ -d "${HOME}/Library/Android/sdk/ndk" ]; then
        ANDROID_NDK_HOME=$(ls -d "${HOME}/Library/Android/sdk/ndk/"* 2>/dev/null | sort -V | tail -1)
    fi
fi

if [ -z "${ANDROID_NDK_HOME}" ] || [ ! -d "${ANDROID_NDK_HOME}" ]; then
    print_error "ANDROID_NDK_HOME not set or NDK not found"
    echo "Please set ANDROID_NDK_HOME to your NDK installation path"
    exit 1
fi

echo "NDK:        ${ANDROID_NDK_HOME}"
echo "Backends:   ${BACKENDS}"
echo "ABIs:       ${ABIS}"
echo "Skip Core:  ${SKIP_CORE}"
echo ""
echo "Directories:"
echo "  Core:     ${CORE_DIR}"
echo "  Commons:  ${COMMONS_DIR}"
echo "  Output:   ${JNILIBS_DIR}"

# Validate directories
if [ ! -d "${COMMONS_DIR}" ]; then
    print_error "runanywhere-commons not found at ${COMMONS_DIR}"
    exit 1
fi

if [ ! -d "${CORE_DIR}" ] && [ "${SKIP_CORE}" = "false" ]; then
    print_error "runanywhere-core not found at ${CORE_DIR}"
    exit 1
fi

# =============================================================================
# Step 1: Build runanywhere-core (if not skipping)
# =============================================================================

if [ "${SKIP_CORE}" = "false" ]; then
    print_header "Step 1: Build runanywhere-core"

    cd "${CORE_DIR}"

    # Check for the android build script (could be in scripts/android/build.sh or scripts/build-android.sh)
    if [ -f "./scripts/android/build.sh" ]; then
        CORE_BUILD_SCRIPT="./scripts/android/build.sh"
    elif [ -f "./scripts/build-android.sh" ]; then
        CORE_BUILD_SCRIPT="./scripts/build-android.sh"
    else
        print_error "runanywhere-core android build script not found"
        print_info "Looked for: scripts/android/build.sh or scripts/build-android.sh"
        exit 1
    fi

    print_step "Building runanywhere-core for ${ABIS}..."
    print_info "Using: ${CORE_BUILD_SCRIPT}"

    # Set backend options
    BUILD_LLAMACPP="OFF"
    BUILD_ONNX="OFF"
    BUILD_WHISPERCPP="OFF"

    if [[ "${BACKENDS}" == *"llamacpp"* ]]; then
        BUILD_LLAMACPP="ON"
    fi
    if [[ "${BACKENDS}" == *"onnx"* ]]; then
        BUILD_ONNX="ON"
    fi

    export ANDROID_NDK_HOME="${ANDROID_NDK_HOME}"
    export BUILD_LLAMACPP="${BUILD_LLAMACPP}"
    export BUILD_ONNX="${BUILD_ONNX}"
    export BUILD_WHISPERCPP="${BUILD_WHISPERCPP}"
    export ABIS="${ABIS}"

    ${CORE_BUILD_SCRIPT}

    print_success "runanywhere-core built successfully"
else
    print_header "Step 1: Skipping runanywhere-core build"
fi

# =============================================================================
# Step 2: Build runanywhere-commons with JNI
# =============================================================================

print_header "Step 2: Build runanywhere-commons with JNI"

cd "${COMMONS_DIR}"

if [ ! -f "./scripts/build-android.sh" ]; then
    print_error "runanywhere-commons/scripts/build-android.sh not found"
    exit 1
fi

print_step "Building runanywhere-commons with JNI for ${ABIS}..."

# Set backend options
BUILD_LLAMACPP="OFF"
BUILD_ONNX="OFF"
BUILD_WHISPERCPP="OFF"

if [[ "${BACKENDS}" == *"llamacpp"* ]]; then
    BUILD_LLAMACPP="ON"
fi
if [[ "${BACKENDS}" == *"onnx"* ]]; then
    BUILD_ONNX="ON"
fi

export ANDROID_NDK_HOME="${ANDROID_NDK_HOME}"
export BUILD_LLAMACPP="${BUILD_LLAMACPP}"
export BUILD_ONNX="${BUILD_ONNX}"
export BUILD_WHISPERCPP="${BUILD_WHISPERCPP}"
export BUILD_JNI="ON"
export ABIS="${ABIS}"
export BUILD_TYPE="${BUILD_TYPE:-Release}"

./scripts/build-android.sh

print_success "runanywhere-commons built successfully"

# =============================================================================
# Step 3: Distribute JNI Libraries to Kotlin SDK
# =============================================================================

print_header "Step 3: Distribute JNI Libraries to Kotlin SDK"

# Create jniLibs directory structure
mkdir -p "${JNILIBS_DIR}"

# Parse ABIs
if [[ "${ABIS}" == "all" ]]; then
    ABI_LIST="arm64-v8a armeabi-v7a x86_64"
else
    # Replace commas with spaces
    ABI_LIST=$(echo "${ABIS}" | tr ',' ' ')
fi

# Copy libraries for each ABI
for ABI in ${ABI_LIST}; do
    print_step "Copying libraries for ${ABI}..."

    mkdir -p "${JNILIBS_DIR}/${ABI}"

    # Source directories
    CORE_DIST="${CORE_DIR}/dist/android"
    COMMONS_DIST="${COMMONS_DIR}/dist/android/aar/jniLibs"

    COPIED_COUNT=0

    # Priority 1: Copy JNI bridge from commons (this is the main one we want!)
    if [ -d "${COMMONS_DIST}/${ABI}" ]; then
        for lib in "${COMMONS_DIST}/${ABI}"/*.so; do
            if [ -f "$lib" ]; then
                cp "$lib" "${JNILIBS_DIR}/${ABI}/"
                echo "    ✓ $(basename "$lib") (from commons)"
                COPIED_COUNT=$((COPIED_COUNT + 1))
            fi
        done
    fi

    # Priority 2: Copy remaining dependencies from core (llama.cpp, onnxruntime, etc.)
    if [ -d "${CORE_DIST}/${ABI}" ]; then
        for lib in "${CORE_DIST}/${ABI}"/*.so; do
            if [ -f "$lib" ]; then
                # Don't overwrite if already copied from commons
                if [ ! -f "${JNILIBS_DIR}/${ABI}/$(basename "$lib")" ]; then
                    cp "$lib" "${JNILIBS_DIR}/${ABI}/"
                    echo "    ✓ $(basename "$lib") (from core)"
                    COPIED_COUNT=$((COPIED_COUNT + 1))
                fi
            fi
        done
    fi

    # Also check core's jni subdirectory
    if [ -d "${CORE_DIST}/jni/${ABI}" ]; then
        for lib in "${CORE_DIST}/jni/${ABI}"/*.so; do
            if [ -f "$lib" ]; then
                if [ ! -f "${JNILIBS_DIR}/${ABI}/$(basename "$lib")" ]; then
                    cp "$lib" "${JNILIBS_DIR}/${ABI}/"
                    echo "    ✓ $(basename "$lib") (from core/jni)"
                    COPIED_COUNT=$((COPIED_COUNT + 1))
                fi
            fi
        done
    fi

    if [ ${COPIED_COUNT} -eq 0 ]; then
        print_error "No libraries found for ${ABI}!"
        print_info "Expected in: ${COMMONS_DIST}/${ABI} or ${CORE_DIST}/${ABI}"
    else
        print_success "${ABI}: ${COPIED_COUNT} libraries copied"
    fi
done

# =============================================================================
# Step 4: Verify Libraries
# =============================================================================

print_header "Step 4: Verification"

echo ""
echo "Libraries in ${JNILIBS_DIR}:"
echo ""

for abi_dir in "${JNILIBS_DIR}"/*; do
    if [ -d "$abi_dir" ]; then
        abi=$(basename "$abi_dir")
        echo "  ${abi}:"

        total_size=0
        for lib in "$abi_dir"/*.so; do
            if [ -f "$lib" ]; then
                size=$(ls -lh "$lib" | awk '{print $5}')
                size_bytes=$(stat -f%z "$lib" 2>/dev/null || stat --printf="%s" "$lib" 2>/dev/null)
                total_size=$((total_size + size_bytes))
                echo "    $(basename "$lib"): $size"
            fi
        done

        # Convert total size to human readable
        if [ $total_size -gt 1048576 ]; then
            total_hr="$((total_size / 1048576))MB"
        elif [ $total_size -gt 1024 ]; then
            total_hr="$((total_size / 1024))KB"
        else
            total_hr="${total_size}B"
        fi
        echo "    ─────────────────"
        echo "    Total: ${total_hr}"
        echo ""
    fi
done

# Check for required libraries
print_step "Checking required libraries..."

REQUIRED_LIBS=(
    "librunanywhere_jni.so"
    "libc++_shared.so"
)

for abi_dir in "${JNILIBS_DIR}"/*; do
    if [ -d "$abi_dir" ]; then
        abi=$(basename "$abi_dir")
        for lib in "${REQUIRED_LIBS[@]}"; do
            if [ -f "${abi_dir}/${lib}" ]; then
                print_success "${abi}/${lib} found"
            else
                print_error "${abi}/${lib} MISSING!"
            fi
        done
    fi
done

# =============================================================================
# Done
# =============================================================================

print_header "Build Complete!"

echo ""
echo "Native libraries are ready in:"
echo "  ${JNILIBS_DIR}"
echo ""
echo "Next steps:"
echo "  1. Run Gradle sync in Android Studio"
echo "  2. Build and run your Android app"
echo ""
echo "To use these local libraries, ensure gradle.properties has:"
echo "  runanywhere.testLocal=true"
echo ""
