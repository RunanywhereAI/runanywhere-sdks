#!/bin/bash
# =============================================================================
# RunAnywhere Kotlin SDK - Local Build Script (Modular Architecture)
# =============================================================================
#
# This script builds native libraries locally and distributes them to the
# correct module directories, matching the Swift SDK's modular XCFramework
# architecture:
#
# Swift Architecture:
#   RACommons.xcframework           → Commons only
#   RABackendLlamaCPP.xcframework   → LlamaCPP backend (self-contained)
#   RABackendONNX.xcframework       → ONNX backend (self-contained)
#
# Android/Kotlin Architecture (this script produces):
#
# Main SDK (runanywhere-kotlin/src/androidMain/jniLibs/):
#   - librunanywhere_jni.so         → Commons JNI bridge
#   - librac_commons.so             → Commons C++ library
#   - libc++_shared.so              → Common C++ runtime
#
# LlamaCPP Module (modules/runanywhere-core-llamacpp/src/androidMain/jniLibs/):
#   - librac_backend_llamacpp_jni.so → Self-contained LlamaCPP backend
#
# ONNX Module (modules/runanywhere-core-onnx/src/androidMain/jniLibs/):
#   - librac_backend_onnx_jni.so    → ONNX backend JNI
#   - libonnxruntime.so             → ONNX Runtime
#   - libsherpa-onnx-c-api.so       → Sherpa-ONNX
#
# Usage:
#   ./scripts/build-local.sh [--backends=llamacpp,onnx] [--abis=arm64-v8a] [--skip-core]
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KOTLIN_SDK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SDKS_DIR="$(cd "${KOTLIN_SDK_DIR}/../.." && pwd)"
COMMONS_DIR="${SDKS_DIR}/sdk/runanywhere-commons"
CORE_DIR="${SDKS_DIR}/../runanywhere-core"

# Output directories (MODULAR ARCHITECTURE)
MAIN_JNILIBS_DIR="${KOTLIN_SDK_DIR}/src/androidMain/jniLibs"
LLAMACPP_JNILIBS_DIR="${KOTLIN_SDK_DIR}/modules/runanywhere-core-llamacpp/src/androidMain/jniLibs"
ONNX_JNILIBS_DIR="${KOTLIN_SDK_DIR}/modules/runanywhere-core-onnx/src/androidMain/jniLibs"

# =============================================================================
# Configuration
# =============================================================================

# Parse arguments
BACKENDS="llamacpp,onnx"
ABIS="arm64-v8a"
SKIP_CORE=false
CLEAN=false

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
        --clean)
            CLEAN=true
            ;;
        --help|-h)
            echo "Usage: $0 [--backends=llamacpp,onnx] [--abis=arm64-v8a] [--skip-core] [--clean]"
            echo ""
            echo "Options:"
            echo "  --backends=BACKENDS  Comma-separated list of backends (default: llamacpp,onnx)"
            echo "  --abis=ABIS          Comma-separated list of ABIs (default: arm64-v8a)"
            echo "  --skip-core          Skip building runanywhere-core"
            echo "  --clean              Clean all jniLibs directories before building"
            echo ""
            echo "Output directories:"
            echo "  Main SDK:        ${MAIN_JNILIBS_DIR}"
            echo "  LlamaCPP Module: ${LLAMACPP_JNILIBS_DIR}"
            echo "  ONNX Module:     ${ONNX_JNILIBS_DIR}"
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
CYAN='\033[0;36m'
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

print_module() {
    echo -e "${CYAN}  📦 $1${NC}"
}

# =============================================================================
# Validation
# =============================================================================

print_header "Modular Build Configuration"

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
echo "Output Directories (Modular):"
echo "  Main SDK:        ${MAIN_JNILIBS_DIR}"
echo "  LlamaCPP Module: ${LLAMACPP_JNILIBS_DIR}"
echo "  ONNX Module:     ${ONNX_JNILIBS_DIR}"

# Validate directories
if [ ! -d "${COMMONS_DIR}" ]; then
    print_error "runanywhere-commons not found at ${COMMONS_DIR}"
    exit 1
fi

# Auto-detect if runanywhere-core exists
# If it doesn't exist, auto-skip core build and use downloaded backend libraries
USE_DOWNLOADED_BACKENDS=false
if [ ! -d "${CORE_DIR}" ]; then
    if [ "${SKIP_CORE}" = "false" ]; then
        print_info "runanywhere-core not found at ${CORE_DIR}"
        print_info "Will use downloaded backend libraries from build/jniLibs instead"
    fi
    SKIP_CORE=true
    USE_DOWNLOADED_BACKENDS=true
fi

# Downloaded libraries locations (from gradle downloadJniLibs tasks)
# Main SDK downloads commons, modules download their respective backends
DOWNLOADED_MAIN_JNILIBS="${KOTLIN_SDK_DIR}/build/jniLibs"
DOWNLOADED_LLAMACPP_JNILIBS="${KOTLIN_SDK_DIR}/modules/runanywhere-core-llamacpp/build/jniLibs"
DOWNLOADED_ONNX_JNILIBS="${KOTLIN_SDK_DIR}/modules/runanywhere-core-onnx/build/jniLibs"

# If using downloaded backends, ensure ALL module libraries are downloaded
if [ "${USE_DOWNLOADED_BACKENDS}" = "true" ]; then
    print_step "Checking downloaded backend libraries..."

    # Check if we need to download LlamaCPP libs
    NEED_DOWNLOAD_LLAMACPP=false
    if [[ "${BACKENDS}" == *"llamacpp"* ]]; then
        if [ ! -d "${DOWNLOADED_LLAMACPP_JNILIBS}" ] || [ -z "$(ls -A ${DOWNLOADED_LLAMACPP_JNILIBS} 2>/dev/null)" ]; then
            NEED_DOWNLOAD_LLAMACPP=true
        fi
    fi

    # Check if we need to download ONNX libs
    NEED_DOWNLOAD_ONNX=false
    if [[ "${BACKENDS}" == *"onnx"* ]]; then
        if [ ! -d "${DOWNLOADED_ONNX_JNILIBS}" ] || [ -z "$(ls -A ${DOWNLOADED_ONNX_JNILIBS} 2>/dev/null)" ]; then
            NEED_DOWNLOAD_ONNX=true
        fi
    fi

    # Download missing libraries
    if [ "${NEED_DOWNLOAD_LLAMACPP}" = "true" ] || [ "${NEED_DOWNLOAD_ONNX}" = "true" ]; then
        print_step "Downloading backend libraries from GitHub releases..."
        cd "${KOTLIN_SDK_DIR}"

        # Run all module downloadJniLibs tasks with testLocal=false
        # This downloads backend-specific libraries to each module's build/jniLibs/
        ./gradlew \
            :modules:runanywhere-core-llamacpp:downloadJniLibs \
            :modules:runanywhere-core-onnx:downloadJniLibs \
            -Prunanywhere.testLocal=false \
            --no-daemon -q 2>/dev/null || true

        # Verify downloads
        if [[ "${BACKENDS}" == *"llamacpp"* ]] && [ ! -d "${DOWNLOADED_LLAMACPP_JNILIBS}/arm64-v8a" ]; then
            print_error "Failed to download LlamaCPP backend libraries"
            print_info "Check: https://github.com/RunanywhereAI/runanywhere-binaries/releases"
            exit 1
        fi

        if [[ "${BACKENDS}" == *"onnx"* ]] && [ ! -d "${DOWNLOADED_ONNX_JNILIBS}/arm64-v8a" ]; then
            print_error "Failed to download ONNX backend libraries"
            print_info "Check: https://github.com/RunanywhereAI/runanywhere-binaries/releases"
            exit 1
        fi

        print_success "Backend libraries downloaded"
        cd "${COMMONS_DIR}"
    else
        print_info "Using existing downloaded backend libraries"
    fi
fi

# Clean if requested
if [ "${CLEAN}" = "true" ]; then
    print_step "Cleaning all jniLibs directories..."
    rm -rf "${MAIN_JNILIBS_DIR}"
    rm -rf "${LLAMACPP_JNILIBS_DIR}"
    rm -rf "${ONNX_JNILIBS_DIR}"
    print_success "Cleaned"
fi

# =============================================================================
# Step 1: Build runanywhere-core (if not skipping)
# =============================================================================

if [ "${SKIP_CORE}" = "false" ]; then
    print_header "Step 1: Build runanywhere-core"

    cd "${CORE_DIR}"

    # Check for the android build script
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

# Find the build script (either build-rac-commons.sh or build-android.sh)
if [ -f "./scripts/build-rac-commons.sh" ]; then
    COMMONS_BUILD_SCRIPT="./scripts/build-rac-commons.sh"
elif [ -f "./scripts/build-android.sh" ]; then
    COMMONS_BUILD_SCRIPT="./scripts/build-android.sh"
else
    print_error "runanywhere-commons build script not found"
    print_info "Looked for: scripts/build-rac-commons.sh or scripts/build-android.sh"
    exit 1
fi

print_step "Building runanywhere-commons with JNI for ${ABIS}..."
print_info "Using: ${COMMONS_BUILD_SCRIPT}"

# Build for Android with specified ABIs
${COMMONS_BUILD_SCRIPT} --android --abi ${ABIS}

print_success "runanywhere-commons built successfully"

# =============================================================================
# Step 3: Distribute JNI Libraries to MODULAR Directories
# =============================================================================

print_header "Step 3: Distribute JNI Libraries (Modular Architecture)"

# Parse ABIs
if [[ "${ABIS}" == "all" ]]; then
    ABI_LIST="arm64-v8a armeabi-v7a x86_64"
else
    ABI_LIST=$(echo "${ABIS}" | tr ',' ' ')
fi

# Source directories
CORE_DIST="${CORE_DIR}/dist/android"
CORE_ONNX_DIST="${CORE_DIR}/dist/android/onnx"
CORE_LLAMACPP_DIST="${CORE_DIR}/dist/android/llamacpp"
COMMONS_DIST="${COMMONS_DIR}/dist/android/jniLibs"
COMMONS_BUILD="${COMMONS_DIR}/build/android"

# Define which libraries go where
# Main SDK: Commons-only libraries
MAIN_LIBS=(
    "librunanywhere_jni.so"
    "librac_commons.so"
    "libc++_shared.so"
)

# LlamaCPP Module: Self-contained LlamaCPP backend
LLAMACPP_LIBS=(
    "librac_backend_llamacpp_jni.so"
    "librunanywhere_llamacpp.so"
    "libomp.so"
)

# ONNX Module: ONNX backend with dependencies
ONNX_LIBS=(
    "librac_backend_onnx_jni.so"
    "librunanywhere_onnx.so"
    "libonnxruntime.so"
    "libsherpa-onnx-c-api.so"
    "libsherpa-onnx-cxx-api.so"
    "libsherpa-onnx-jni.so"
    "libomp.so"
)

# Helper function to find and copy a library from multiple source locations
find_and_copy_lib() {
    local lib=$1
    local dest_dir=$2
    shift 2
    local search_dirs=("$@")

    for dir in "${search_dirs[@]}"; do
        if [ -f "${dir}/${lib}" ]; then
            cp "${dir}/${lib}" "${dest_dir}/"
            echo "${dir}"
            return 0
        fi
    done
    return 1
}

# Copy libraries for each ABI
for ABI in ${ABI_LIST}; do
    echo ""
    print_step "Distributing libraries for ${ABI}..."

    # Create directories
    mkdir -p "${MAIN_JNILIBS_DIR}/${ABI}"
    mkdir -p "${LLAMACPP_JNILIBS_DIR}/${ABI}"
    mkdir -p "${ONNX_JNILIBS_DIR}/${ABI}"

    # Define all search paths for this ABI
    COMMONS_DIST_ABI="${COMMONS_DIST}/${ABI}"
    COMMONS_BUILD_ABI="${COMMONS_BUILD}/${ABI}"
    CORE_ONNX_ABI="${CORE_ONNX_DIST}/${ABI}"
    CORE_LLAMACPP_ABI="${CORE_LLAMACPP_DIST}/${ABI}"
    CORE_JNI_ABI="${CORE_DIST}/jni/${ABI}"
    # Fallback: downloaded libraries from gradle downloadJniLibs tasks (module-specific)
    DOWNLOADED_MAIN_ABI="${DOWNLOADED_MAIN_JNILIBS}/${ABI}"
    DOWNLOADED_LLAMACPP_ABI="${DOWNLOADED_LLAMACPP_JNILIBS}/${ABI}"
    DOWNLOADED_ONNX_ABI="${DOWNLOADED_ONNX_JNILIBS}/${ABI}"

    # =========================================================================
    # Main SDK Libraries (Commons only)
    # =========================================================================
    print_module "Main SDK (Commons)"

    MAIN_COUNT=0
    for lib in "${MAIN_LIBS[@]}"; do
        found_dir=$(find_and_copy_lib "${lib}" "${MAIN_JNILIBS_DIR}/${ABI}" \
            "${COMMONS_DIST_ABI}" \
            "${COMMONS_BUILD_ABI}" \
            "${CORE_LLAMACPP_ABI}" \
            "${CORE_JNI_ABI}" \
            "${DOWNLOADED_MAIN_ABI}" \
            "${DOWNLOADED_LLAMACPP_ABI}")
        if [ $? -eq 0 ]; then
            print_success "${lib}"
            MAIN_COUNT=$((MAIN_COUNT + 1))
        else
            print_error "${lib} NOT FOUND"
        fi
    done
    echo "    → ${MAIN_COUNT} libraries"

    # =========================================================================
    # LlamaCPP Module Libraries
    # =========================================================================
    if [[ "${BACKENDS}" == *"llamacpp"* ]]; then
        print_module "LlamaCPP Module"

        LLAMACPP_COUNT=0
        for lib in "${LLAMACPP_LIBS[@]}"; do
            found_dir=$(find_and_copy_lib "${lib}" "${LLAMACPP_JNILIBS_DIR}/${ABI}" \
                "${COMMONS_BUILD_ABI}/backends/llamacpp" \
                "${COMMONS_DIST_ABI}" \
                "${CORE_LLAMACPP_ABI}" \
                "${DOWNLOADED_LLAMACPP_ABI}")
            if [ $? -eq 0 ]; then
                print_success "${lib}"
                LLAMACPP_COUNT=$((LLAMACPP_COUNT + 1))
            else
                print_error "${lib} NOT FOUND"
            fi
        done
        echo "    → ${LLAMACPP_COUNT} libraries"
    fi

    # =========================================================================
    # ONNX Module Libraries
    # =========================================================================
    if [[ "${BACKENDS}" == *"onnx"* ]]; then
        print_module "ONNX Module"

        ONNX_COUNT=0
        for lib in "${ONNX_LIBS[@]}"; do
            found_dir=$(find_and_copy_lib "${lib}" "${ONNX_JNILIBS_DIR}/${ABI}" \
                "${COMMONS_BUILD_ABI}/backends/onnx" \
                "${COMMONS_DIST_ABI}" \
                "${CORE_ONNX_ABI}" \
                "${CORE_LLAMACPP_ABI}" \
                "${DOWNLOADED_ONNX_ABI}" \
                "${DOWNLOADED_LLAMACPP_ABI}")
            if [ $? -eq 0 ]; then
                print_success "${lib}"
                ONNX_COUNT=$((ONNX_COUNT + 1))
            else
                print_error "${lib} NOT FOUND"
            fi
        done
        echo "    → ${ONNX_COUNT} libraries"
    fi
done

# =============================================================================
# Step 4: Verification
# =============================================================================

print_header "Step 4: Verification"

print_sizes() {
    local dir=$1
    local name=$2

    if [ -d "$dir" ]; then
        echo ""
        print_module "$name"
        for abi_dir in "$dir"/*; do
            if [ -d "$abi_dir" ]; then
                abi=$(basename "$abi_dir")
                total_size=0
                lib_count=0

                for lib in "$abi_dir"/*.so; do
                    if [ -f "$lib" ]; then
                        size=$(ls -lh "$lib" | awk '{print $5}')
                        size_bytes=$(stat -f%z "$lib" 2>/dev/null || stat --printf="%s" "$lib" 2>/dev/null)
                        total_size=$((total_size + size_bytes))
                        lib_count=$((lib_count + 1))
                        echo "    $(basename "$lib"): $size"
                    fi
                done

                if [ $total_size -gt 1048576 ]; then
                    total_hr="$((total_size / 1048576))MB"
                elif [ $total_size -gt 1024 ]; then
                    total_hr="$((total_size / 1024))KB"
                else
                    total_hr="${total_size}B"
                fi

                if [ $lib_count -gt 0 ]; then
                    echo "    ─────────────────"
                    echo "    ${abi}: ${lib_count} libs, ${total_hr} total"
                fi
            fi
        done
    fi
}

print_sizes "${MAIN_JNILIBS_DIR}" "Main SDK (Commons)"
print_sizes "${LLAMACPP_JNILIBS_DIR}" "LlamaCPP Module"
print_sizes "${ONNX_JNILIBS_DIR}" "ONNX Module"

# =============================================================================
# Step 5: Validate Required Libraries
# =============================================================================

print_header "Step 5: Validate Required Libraries"

validate_module() {
    local dir=$1
    local name=$2
    shift 2
    local required_libs=("$@")

    echo ""
    print_module "$name"

    local all_found=true
    for abi_dir in "$dir"/*; do
        if [ -d "$abi_dir" ]; then
            abi=$(basename "$abi_dir")
            for lib in "${required_libs[@]}"; do
                if [ -f "${abi_dir}/${lib}" ]; then
                    print_success "${abi}/${lib}"
                else
                    print_error "${abi}/${lib} MISSING!"
                    all_found=false
                fi
            done
        fi
    done

    if [ "$all_found" = true ]; then
        echo -e "    ${GREEN}✓ All required libraries present${NC}"
    fi
}

validate_module "${MAIN_JNILIBS_DIR}" "Main SDK" "librunanywhere_jni.so" "libc++_shared.so"

if [[ "${BACKENDS}" == *"llamacpp"* ]]; then
    validate_module "${LLAMACPP_JNILIBS_DIR}" "LlamaCPP Module" "librac_backend_llamacpp_jni.so"
fi

if [[ "${BACKENDS}" == *"onnx"* ]]; then
    validate_module "${ONNX_JNILIBS_DIR}" "ONNX Module" "librac_backend_onnx_jni.so" "libonnxruntime.so"
fi

# =============================================================================
# Done
# =============================================================================

print_header "Build Complete! (Modular Architecture)"

echo ""
echo "Native libraries distributed to:"
echo ""
echo "  📦 Main SDK (Commons):"
echo "     ${MAIN_JNILIBS_DIR}"
echo ""
if [[ "${BACKENDS}" == *"llamacpp"* ]]; then
echo "  📦 LlamaCPP Module (Optional):"
echo "     ${LLAMACPP_JNILIBS_DIR}"
echo ""
fi
if [[ "${BACKENDS}" == *"onnx"* ]]; then
echo "  📦 ONNX Module (Optional):"
echo "     ${ONNX_JNILIBS_DIR}"
echo ""
fi
echo "Each module is now SELF-CONTAINED with its own JNI libraries."
echo "Add or remove modules independently in your app's build.gradle:"
echo ""
echo "  // Required: Main SDK"
echo "  implementation(\"com.runanywhere:sdk:1.0.0\")"
echo ""
echo "  // Optional: Add only the backends you need"
echo "  implementation(\"com.runanywhere:sdk-llamacpp:1.0.0\")  // +36MB"
echo "  implementation(\"com.runanywhere:sdk-onnx:1.0.0\")      // +25MB"
echo ""
echo "To use these local libraries, ensure gradle.properties has:"
echo "  runanywhere.testLocal=true"
echo ""
