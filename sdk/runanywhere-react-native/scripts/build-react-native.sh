#!/bin/bash
# =============================================================================
# RunAnywhere React Native SDK - Build Script
# =============================================================================
#
# Single entry point for building the React Native SDK and its native dependencies.
# Builds native C++ libraries for both iOS (XCFrameworks) and Android (JNI .so libs).
#
# USAGE:
#   ./scripts/build-react-native.sh [options]
#
# OPTIONS:
#   --setup             First-time setup: install deps, build commons, copy frameworks/libs
#   --local             Use locally built native libs (sets RA_TEST_LOCAL=1)
#   --remote            Use remote libs from GitHub releases (unsets RA_TEST_LOCAL)
#   --rebuild-commons   Force rebuild of runanywhere-commons
#   --ios               Build for iOS only
#   --android           Build for Android only (default: both)
#   --clean             Clean build directories before building
#   --skip-build        Skip native build (only setup frameworks/libs)
#   --abis=ABIS         Android ABIs to build (default: arm64-v8a)
#                       Multiple: Use comma-separated (e.g., arm64-v8a,armeabi-v7a)
#   --backends=LIST     Backends to build (default: onnx)
#                       Options: llamacpp,onnx or just onnx
#                       Note: RAG backend has separation of concerns and can build without providers
#   --help              Show this help message
#
# ANDROID ABI GUIDE:
#   arm64-v8a        64-bit ARM (modern devices, ~85% coverage)
#   armeabi-v7a      32-bit ARM (older devices, ~12% coverage)
#   x86_64           64-bit Intel (emulators on Intel Macs)
#
# BUILD PIPELINE (no fallbacks – single source of truth):
#   This script reuses runanywhere-commons scripts to produce all native artifacts:
#   • iOS:  runanywhere-commons/scripts/build-ios.sh  → .xcframework (with Headers)
#   • Android: runanywhere-commons/scripts/build-android.sh → .so files
#   Then copies from commons dist/ into packages/core, packages/llamacpp, packages/onnx.
#   Run --setup to build both; use --setup --ios or --setup --android for one platform.
#
# WHAT GETS BUILT:
#   iOS Output (in packages/*/ios/):
#     • core/ios/Binaries/RACommons.xcframework
#     • llamacpp/ios/Frameworks/RABackendLLAMACPP.xcframework
#     • onnx/ios/Frameworks/RABackendONNX.xcframework + onnxruntime.xcframework
#     • rag/ios/Libraries/*.a (static libraries) + Headers/*.h
#
#   Android Output (in packages/*/android/src/main/jniLibs/{ABI}/):
#     • core: librunanywhere_jni.so, librac_commons.so, libc++_shared.so, libomp.so
#     • llamacpp: librunanywhere_llamacpp.so, librac_backend_llamacpp_jni.so, libomp.so, librac_commons.so
#     • onnx: librunanywhere_onnx.so, librac_backend_onnx_jni.so, libonnxruntime.so, libsherpa-onnx-*.so, librac_commons.so
#     • rag: librac_commons.so (shared library for RAG)
#
#   NOTE: librac_commons.so is synced to ALL packages (core, llamacpp, onnx, rag) to prevent
#   Gradle native lib merge from picking a stale version. See copy_android_jnilibs().
#
# FRESH CLONE TO RUNNING APP:
#   # 1. Build SDK with native libraries (~15-20 min)
#   cd sdk/runanywhere-react-native
#   ./scripts/build-react-native.sh --setup
#
#   # 2. Setup sample app
#   cd ../../examples/react-native/RunAnywhereAI
#   yarn install
#
#   # 3. Run on iOS
#   cd ios && pod install && cd ..
#   npx react-native run-ios
#
#   # 4. Run on Android
#   cp android/gradle.properties.example android/gradle.properties  # One-time
#   npx react-native run-android
#
# EXAMPLES:
#   # First-time setup (iOS + Android, all backends)
#   ./scripts/build-react-native.sh --setup
#
#   # iOS only setup (~10 min)
#   ./scripts/build-react-native.sh --setup --ios
#
#   # Android only (~7 min)
#   ./scripts/build-react-native.sh --setup --android
#
#   # Android with multiple ABIs for production (97% device coverage)
#   ./scripts/build-react-native.sh --setup --android --abis=arm64-v8a,armeabi-v7a
#
#   # Rebuild after C++ changes
#   ./scripts/build-react-native.sh --local --rebuild-commons
#
#   # Just switch to local mode (uses cached libs)
#   ./scripts/build-react-native.sh --local --skip-build
#
# =============================================================================

set -e

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RN_SDK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SDK_ROOT="$(cd "${RN_SDK_DIR}/.." && pwd)"
COMMONS_DIR="${SDK_ROOT}/runanywhere-commons"
COMMONS_IOS_SCRIPT="${COMMONS_DIR}/scripts/build-ios.sh"
COMMONS_ANDROID_SCRIPT="${COMMONS_DIR}/scripts/build-android.sh"

# Output directories
CORE_IOS_BINARIES="${RN_SDK_DIR}/packages/core/ios/Binaries"
LLAMACPP_IOS_FRAMEWORKS="${RN_SDK_DIR}/packages/llamacpp/ios/Frameworks"
ONNX_IOS_FRAMEWORKS="${RN_SDK_DIR}/packages/onnx/ios/Frameworks"
RAG_IOS_LIBRARIES="${RN_SDK_DIR}/packages/rag/ios/Libraries"
RAG_IOS_HEADERS="${RN_SDK_DIR}/packages/rag/ios/Headers"

CORE_ANDROID_JNILIBS="${RN_SDK_DIR}/packages/core/android/src/main/jniLibs"
LLAMACPP_ANDROID_JNILIBS="${RN_SDK_DIR}/packages/llamacpp/android/src/main/jniLibs"
ONNX_ANDROID_JNILIBS="${RN_SDK_DIR}/packages/onnx/android/src/main/jniLibs"
RAG_ANDROID_JNILIBS="${RN_SDK_DIR}/packages/rag/android/src/main/jniLibs"

# Defaults
MODE="local"
SETUP_MODE=false
REBUILD_COMMONS=false
CLEAN_BUILD=false
SKIP_BUILD=false
BUILD_IOS=true
BUILD_ANDROID=true
ABIS="arm64-v8a"
BACKENDS="onnx"  # Default: only ONNX (RAG works without LlamaCPP due to separation of concerns)

# =============================================================================
# Colors & Logging
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_header() {
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════${NC}"
    echo -e "${GREEN} $1${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════${NC}"
}

log_step() {
    echo -e "${BLUE}==>${NC} $1"
}

log_info() {
    echo -e "${CYAN}[✓]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# =============================================================================
# Argument Parsing
# =============================================================================

show_help() {
    head -75 "$0" | tail -70
    exit 0
}

for arg in "$@"; do
    case "$arg" in
        --setup)
            SETUP_MODE=true
            REBUILD_COMMONS=true
            ;;
        --local)
            MODE="local"
            ;;
        --remote)
            MODE="remote"
            ;;
        --rebuild-commons)
            REBUILD_COMMONS=true
            ;;
        --ios)
            BUILD_IOS=true
            BUILD_ANDROID=false
            ;;
        --android)
            BUILD_IOS=false
            BUILD_ANDROID=true
            ;;
        --clean)
            CLEAN_BUILD=true
            ;;
        --skip-build)
            SKIP_BUILD=true
            ;;
        --abis=*)
            ABIS="${arg#*=}"
            ;;
        --backends=*)
            BACKENDS="${arg#*=}"
            ;;
        --help|-h)
            show_help
            ;;
        *)
            log_error "Unknown option: $arg"
            show_help
            ;;
    esac
done

# =============================================================================
# Setup Environment
# =============================================================================

setup_environment() {
    log_header "Setting Up Environment"

    cd "$RN_SDK_DIR"

    # Enable corepack if available (for Yarn 3.x support)
    if command -v corepack &> /dev/null; then
        log_step "Enabling corepack for Yarn 3.x..."
        if ! corepack enable 2>/dev/null; then
            log_warn "Failed to enable corepack. You may need to run: sudo corepack enable"
            log_warn "Continuing without corepack - yarn may not work correctly"
        fi
        
        # Prepare the yarn version specified in package.json
        if [[ -f "package.json" ]] && grep -q '"packageManager"' package.json; then
            log_step "Preparing yarn version from package.json..."
            corepack prepare 2>/dev/null || log_warn "Could not prepare yarn version"
        fi
        
        YARN_CMD="corepack yarn"
    else
        log_warn "Corepack not available, using system yarn"
        YARN_CMD="yarn"
    fi

    # Check for yarn
    if ! command -v yarn &> /dev/null; then
        log_error "yarn is not installed. Please install Node.js 16.9+ which includes corepack."
        exit 1
    fi

    # Install dependencies
    log_step "Installing yarn dependencies..."
    $YARN_CMD install

    log_info "Dependencies installed"
}

# =============================================================================
# Build Commons (Native Libraries)
# =============================================================================

build_commons_ios() {
    log_header "Building runanywhere-commons for iOS"

    if [[ ! -x "$COMMONS_IOS_SCRIPT" ]]; then
        log_error "iOS build script not found: $COMMONS_IOS_SCRIPT"
        exit 1
    fi

    local FLAGS=""
    [[ "$CLEAN_BUILD" == true ]] && FLAGS="$FLAGS --clean"
    
    # Pass backends to commons build script
    # Convert comma-separated backends to space-separated format for build-ios.sh
    if [[ "$BACKENDS" != "all" ]]; then
        # Convert "onnx" or "llamacpp,onnx" to multiple --backend flags
        local BACKENDS_SPACE="${BACKENDS//,/ }"
        for BACKEND in $BACKENDS_SPACE; do
            FLAGS="$FLAGS --backend $BACKEND"
        done
    fi

    log_step "Running: build-ios.sh $FLAGS"
    "$COMMONS_IOS_SCRIPT" $FLAGS

    log_info "iOS commons build complete"
}

build_rag_ios() {
    log_header "Building RAG Static Libraries for iOS"

    local RAG_BUILD_SCRIPT="${RN_SDK_DIR}/packages/rag/scripts/build-ios-libs.sh"

    if [[ ! -x "$RAG_BUILD_SCRIPT" ]]; then
        log_error "RAG iOS build script not found: $RAG_BUILD_SCRIPT"
        return 1
    fi

    local FLAGS=""
    [[ "$CLEAN_BUILD" == true ]] && FLAGS="$FLAGS --clean"

    log_step "Running: build-ios-libs.sh $FLAGS"
    bash "$RAG_BUILD_SCRIPT" $FLAGS || {
        log_error "RAG iOS build failed"
        return 1
    }

    log_info "RAG iOS build complete"
}

build_commons_android() {
    log_header "Building runanywhere-commons for Android"

    if [[ ! -x "$COMMONS_ANDROID_SCRIPT" ]]; then
        log_error "Android build script not found: $COMMONS_ANDROID_SCRIPT"
        exit 1
    fi

    # build-android.sh takes positional args: BACKENDS ABIS
    # BACKENDS variable set via --backends option (default: onnx)
    # RAG backend has separation of concerns - can build without LlamaCPP

    log_step "Running: build-android.sh $BACKENDS $ABIS"
    "$COMMONS_ANDROID_SCRIPT" "$BACKENDS" "$ABIS"

    log_info "Android commons build complete"
}

build_rag_android() {
    log_header "Building RAG Native Libraries for Android"

    local RAG_BUILD_SCRIPT="${RN_SDK_DIR}/packages/rag/scripts/build-android-libs.sh"

    if [[ ! -x "$RAG_BUILD_SCRIPT" ]]; then
        log_error "RAG build script not found: $RAG_BUILD_SCRIPT"
        return 1
    fi

    # Check for Android NDK
    if [[ -z "$ANDROID_NDK" ]]; then
        # Try common locations
        if [[ -d "$HOME/Library/Android/sdk/ndk" ]]; then
            # Find the latest NDK version
            ANDROID_NDK=$(find "$HOME/Library/Android/sdk/ndk" -maxdepth 1 -type d | sort -V | tail -1)
            if [[ -n "$ANDROID_NDK" ]] && [[ "$ANDROID_NDK" != "$HOME/Library/Android/sdk/ndk" ]]; then
                export ANDROID_NDK
                log_info "Using Android NDK: $ANDROID_NDK"
            else
                log_error "ANDROID_NDK not set and couldn't find NDK in default location"
                log_error "Please install Android NDK 26.1+ or set ANDROID_NDK environment variable"
                return 1
            fi
        else
            log_error "ANDROID_NDK not set and couldn't find SDK at $HOME/Library/Android/sdk"
            log_error "Please install Android NDK 26.1+ or set ANDROID_NDK environment variable"
            return 1
        fi
    fi

    log_step "Building RAG libraries for ABIs: $ABIS"
    
    # Convert comma-separated ABIs to space-separated for the RAG script
    local ABIS_SPACE="${ABIS//,/ }"
    
    # Build for specified ABIs
    for ABI in $ABIS_SPACE; do
        log_step "Building RAG for $ABI..."
        bash "$RAG_BUILD_SCRIPT" "$ABI" || {
            log_error "RAG build failed for $ABI"
            return 1
        }
    done

    log_info "RAG Android build complete"
}

# =============================================================================
# Copy iOS Frameworks
# =============================================================================

copy_ios_frameworks() {
    log_header "Copying iOS XCFrameworks"

    local COMMONS_DIST="${COMMONS_DIR}/dist"

    # Create directories
    mkdir -p "$CORE_IOS_BINARIES"
    mkdir -p "$LLAMACPP_IOS_FRAMEWORKS"
    mkdir -p "$ONNX_IOS_FRAMEWORKS"

    # Copy RACommons.xcframework to core package
    if [[ -d "${COMMONS_DIST}/RACommons.xcframework" ]]; then
        rm -rf "${CORE_IOS_BINARIES}/RACommons.xcframework"
        cp -R "${COMMONS_DIST}/RACommons.xcframework" "${CORE_IOS_BINARIES}/"
        log_info "Core: RACommons.xcframework"
    else
        log_warn "RACommons.xcframework not found at ${COMMONS_DIST}/"
    fi

    # Copy RABackendLLAMACPP.xcframework to llamacpp package
    if [[ -d "${COMMONS_DIST}/RABackendLLAMACPP.xcframework" ]]; then
        rm -rf "${LLAMACPP_IOS_FRAMEWORKS}/RABackendLLAMACPP.xcframework"
        cp -R "${COMMONS_DIST}/RABackendLLAMACPP.xcframework" "${LLAMACPP_IOS_FRAMEWORKS}/"
        log_info "LlamaCPP: RABackendLLAMACPP.xcframework"
    else
        log_warn "RABackendLLAMACPP.xcframework not found at ${COMMONS_DIST}/"
    fi

    # Copy RABackendONNX.xcframework to onnx package
    if [[ -d "${COMMONS_DIST}/RABackendONNX.xcframework" ]]; then
        rm -rf "${ONNX_IOS_FRAMEWORKS}/RABackendONNX.xcframework"
        cp -R "${COMMONS_DIST}/RABackendONNX.xcframework" "${ONNX_IOS_FRAMEWORKS}/"
        log_info "ONNX: RABackendONNX.xcframework"
    else
        log_warn "RABackendONNX.xcframework not found at ${COMMONS_DIST}/"
    fi

    # Copy onnxruntime.xcframework to onnx package (required dependency)
    local ONNX_RUNTIME_PATH="${COMMONS_DIR}/third_party/onnxruntime-ios/onnxruntime.xcframework"
    if [[ -d "${ONNX_RUNTIME_PATH}" ]]; then
        rm -rf "${ONNX_IOS_FRAMEWORKS}/onnxruntime.xcframework"
        cp -R "${ONNX_RUNTIME_PATH}" "${ONNX_IOS_FRAMEWORKS}/"
        log_info "ONNX: onnxruntime.xcframework"
    else
        log_warn "onnxruntime.xcframework not found at ${ONNX_RUNTIME_PATH}"
    fi

    # Copy RAG static libraries and headers (already bundled in package)
    # Note: RAG package uses static libraries (.a) that are already committed to the repo
    # These were built separately using packages/rag/scripts/build-ios-libs.sh
    if [[ -d "${RAG_IOS_LIBRARIES}" ]] && [[ -d "${RAG_IOS_HEADERS}" ]]; then
        local lib_count=$(find "${RAG_IOS_LIBRARIES}" -name "*.a" 2>/dev/null | wc -l)
        local header_count=$(find "${RAG_IOS_HEADERS}" -name "*.h" 2>/dev/null | wc -l)
        log_info "RAG: ${lib_count} static libraries + ${header_count} headers (pre-bundled)"
    else
        log_warn "RAG iOS libraries not found (expected to be pre-bundled)"
    fi

    # Create .testlocal markers for local mode
    touch "${RN_SDK_DIR}/packages/core/ios/.testlocal"
    touch "${RN_SDK_DIR}/packages/llamacpp/ios/.testlocal"
    touch "${RN_SDK_DIR}/packages/onnx/ios/.testlocal"
    touch "${RN_SDK_DIR}/packages/rag/ios/.testlocal"

    log_info "iOS frameworks copied"
}

# =============================================================================
# Copy Android JNI Libraries
# =============================================================================

copy_android_jnilibs() {
    log_header "Copying Android JNI Libraries"

    local COMMONS_DIST="${COMMONS_DIR}/dist/android"
    local COMMONS_BUILD="${COMMONS_DIR}/build/android/unified"

    IFS=',' read -ra ABI_ARRAY <<< "$ABIS"

    for ABI in "${ABI_ARRAY[@]}"; do
        log_step "Copying libraries for ${ABI}..."

        # Create directories
        mkdir -p "${CORE_ANDROID_JNILIBS}/${ABI}"
        mkdir -p "${LLAMACPP_ANDROID_JNILIBS}/${ABI}"
        mkdir -p "${ONNX_ANDROID_JNILIBS}/${ABI}"

        # =======================================================================
        # Core Package: RACommons (librunanywhere_jni.so, librac_commons.so, libc++_shared.so)
        # =======================================================================

        # Copy librunanywhere_jni.so
        if [[ -f "${COMMONS_DIST}/jni/${ABI}/librunanywhere_jni.so" ]]; then
            cp "${COMMONS_DIST}/jni/${ABI}/librunanywhere_jni.so" "${CORE_ANDROID_JNILIBS}/${ABI}/"
            log_info "Core: librunanywhere_jni.so"
        elif [[ -f "${COMMONS_BUILD}/${ABI}/src/jni/librunanywhere_jni.so" ]]; then
            cp "${COMMONS_BUILD}/${ABI}/src/jni/librunanywhere_jni.so" "${CORE_ANDROID_JNILIBS}/${ABI}/"
            log_info "Core: librunanywhere_jni.so (from build)"
        else
            log_warn "Core: librunanywhere_jni.so NOT FOUND"
        fi

        # Copy librac_commons.so
        if [[ -f "${COMMONS_BUILD}/${ABI}/librac_commons.so" ]]; then
            cp "${COMMONS_BUILD}/${ABI}/librac_commons.so" "${CORE_ANDROID_JNILIBS}/${ABI}/"
            log_info "Core: librac_commons.so"
        fi

        # Copy libc++_shared.so
        if [[ -f "${COMMONS_DIST}/llamacpp/${ABI}/libc++_shared.so" ]]; then
            cp "${COMMONS_DIST}/llamacpp/${ABI}/libc++_shared.so" "${CORE_ANDROID_JNILIBS}/${ABI}/"
            log_info "Core: libc++_shared.so"
        elif [[ -f "${COMMONS_DIST}/jni/${ABI}/libc++_shared.so" ]]; then
            cp "${COMMONS_DIST}/jni/${ABI}/libc++_shared.so" "${CORE_ANDROID_JNILIBS}/${ABI}/"
            log_info "Core: libc++_shared.so"
        fi

        # Copy libomp.so
        if [[ -f "${COMMONS_DIST}/llamacpp/${ABI}/libomp.so" ]]; then
            cp "${COMMONS_DIST}/llamacpp/${ABI}/libomp.so" "${CORE_ANDROID_JNILIBS}/${ABI}/"
            log_info "Core: libomp.so"
        elif [[ -f "${COMMONS_DIST}/jni/${ABI}/libomp.so" ]]; then
            cp "${COMMONS_DIST}/jni/${ABI}/libomp.so" "${CORE_ANDROID_JNILIBS}/${ABI}/"
            log_info "Core: libomp.so"
        fi

        # =======================================================================
        # LlamaCPP Package: RABackendLlamaCPP
        # Keep original library name (bridge libs depend on it)
        # =======================================================================

        # Copy backend library with original name
        if [[ -f "${COMMONS_DIST}/llamacpp/${ABI}/librac_backend_llamacpp.so" ]]; then
            cp "${COMMONS_DIST}/llamacpp/${ABI}/librac_backend_llamacpp.so" "${LLAMACPP_ANDROID_JNILIBS}/${ABI}/librac_backend_llamacpp.so"
            log_info "LlamaCPP: librac_backend_llamacpp.so"
        elif [[ -f "${COMMONS_BUILD}/${ABI}/src/backends/llamacpp/librac_backend_llamacpp.so" ]]; then
            cp "${COMMONS_BUILD}/${ABI}/src/backends/llamacpp/librac_backend_llamacpp.so" "${LLAMACPP_ANDROID_JNILIBS}/${ABI}/librac_backend_llamacpp.so"
            log_info "LlamaCPP: librac_backend_llamacpp.so (from build)"
        fi

        # Copy JNI bridge
        if [[ -f "${COMMONS_DIST}/llamacpp/${ABI}/librac_backend_llamacpp_jni.so" ]]; then
            cp "${COMMONS_DIST}/llamacpp/${ABI}/librac_backend_llamacpp_jni.so" "${LLAMACPP_ANDROID_JNILIBS}/${ABI}/"
            log_info "LlamaCPP: librac_backend_llamacpp_jni.so"
        elif [[ -f "${COMMONS_BUILD}/${ABI}/src/backends/llamacpp/librac_backend_llamacpp_jni.so" ]]; then
            cp "${COMMONS_BUILD}/${ABI}/src/backends/llamacpp/librac_backend_llamacpp_jni.so" "${LLAMACPP_ANDROID_JNILIBS}/${ABI}/"
            log_info "LlamaCPP: librac_backend_llamacpp_jni.so (from build)"
        fi

        # Copy libomp.so (required by LlamaCPP backend)
        if [[ -f "${COMMONS_DIST}/llamacpp/${ABI}/libomp.so" ]]; then
            cp "${COMMONS_DIST}/llamacpp/${ABI}/libomp.so" "${LLAMACPP_ANDROID_JNILIBS}/${ABI}/"
            log_info "LlamaCPP: libomp.so"
        fi

        # =======================================================================
        # ONNX Package: RABackendONNX
        # Keep original library name (bridge libs depend on it)
        # =======================================================================

        # Copy backend library with original name
        if [[ -f "${COMMONS_DIST}/onnx/${ABI}/librac_backend_onnx.so" ]]; then
            cp "${COMMONS_DIST}/onnx/${ABI}/librac_backend_onnx.so" "${ONNX_ANDROID_JNILIBS}/${ABI}/librac_backend_onnx.so"
            log_info "ONNX: librac_backend_onnx.so"
        elif [[ -f "${COMMONS_BUILD}/${ABI}/src/backends/onnx/librac_backend_onnx.so" ]]; then
            cp "${COMMONS_BUILD}/${ABI}/src/backends/onnx/librac_backend_onnx.so" "${ONNX_ANDROID_JNILIBS}/${ABI}/librac_backend_onnx.so"
            log_info "ONNX: librac_backend_onnx.so (from build)"
        fi

        # Copy JNI bridge
        if [[ -f "${COMMONS_DIST}/onnx/${ABI}/librac_backend_onnx_jni.so" ]]; then
            cp "${COMMONS_DIST}/onnx/${ABI}/librac_backend_onnx_jni.so" "${ONNX_ANDROID_JNILIBS}/${ABI}/"
            log_info "ONNX: librac_backend_onnx_jni.so"
        elif [[ -f "${COMMONS_BUILD}/${ABI}/src/backends/onnx/librac_backend_onnx_jni.so" ]]; then
            cp "${COMMONS_BUILD}/${ABI}/src/backends/onnx/librac_backend_onnx_jni.so" "${ONNX_ANDROID_JNILIBS}/${ABI}/"
            log_info "ONNX: librac_backend_onnx_jni.so (from build)"
        fi

        # Copy ONNX Runtime
        if [[ -f "${COMMONS_DIST}/onnx/${ABI}/libonnxruntime.so" ]]; then
            cp "${COMMONS_DIST}/onnx/${ABI}/libonnxruntime.so" "${ONNX_ANDROID_JNILIBS}/${ABI}/"
            log_info "ONNX: libonnxruntime.so"
        fi

        # Copy Sherpa-ONNX libraries
        for lib in libsherpa-onnx-c-api.so libsherpa-onnx-cxx-api.so libsherpa-onnx-jni.so; do
            if [[ -f "${COMMONS_DIST}/onnx/${ABI}/${lib}" ]]; then
                cp "${COMMONS_DIST}/onnx/${ABI}/${lib}" "${ONNX_ANDROID_JNILIBS}/${ABI}/"
                log_info "ONNX: ${lib}"
            fi
        done

        # =======================================================================
        # Sync librac_commons.so to ALL packages
        # =======================================================================
        # Gradle merges native libs from all modules into the final APK. If
        # packages/onnx or packages/llamacpp ship an older librac_commons.so
        # (from GitHub release archives or a previous build), the stale copy can
        # win the merge and the app will crash with UnsatisfiedLinkError for
        # symbols that only exist in the newer core build.
        #
        # Fix: always overwrite with the version we just built/copied into core.
        # =======================================================================
        local CORE_RAC="${CORE_ANDROID_JNILIBS}/${ABI}/librac_commons.so"
        if [[ -f "$CORE_RAC" ]]; then
            cp "$CORE_RAC" "${LLAMACPP_ANDROID_JNILIBS}/${ABI}/librac_commons.so"
            cp "$CORE_RAC" "${ONNX_ANDROID_JNILIBS}/${ABI}/librac_commons.so"
            log_info "Synced librac_commons.so to llamacpp + onnx packages"
        fi
    done

    log_info "Android JNI libraries copied"
}

# =============================================================================
# Copy C++ Headers (required for Android build)
# =============================================================================

copy_cpp_headers() {
    log_header "Copying C++ Headers for Android"

    local COMMONS_INCLUDE="${COMMONS_DIR}/include/rac"
    local COMMONS_SRC="${COMMONS_DIR}/src"
    local CORE_INCLUDE="${RN_SDK_DIR}/packages/core/android/src/main/include"

    # Check if headers exist
    if [[ ! -d "${COMMONS_INCLUDE}" ]]; then
        log_warn "Headers not found at ${COMMONS_INCLUDE}"
        return 1
    fi

    # Clean and recreate include directory
    rm -rf "${CORE_INCLUDE}"
    mkdir -p "${CORE_INCLUDE}"

    # Copy entire rac directory structure (public API)
    cp -R "${COMMONS_INCLUDE}" "${CORE_INCLUDE}/"

    # Copy internal backend headers (needed by React Native wrappers)
    mkdir -p "${CORE_INCLUDE}/rac/backends"
    cp -R "${COMMONS_SRC}/backends/rag" "${CORE_INCLUDE}/rac/backends/" 2>/dev/null || true
    cp -R "${COMMONS_SRC}/backends/onnx" "${CORE_INCLUDE}/rac/backends/" 2>/dev/null || true
    cp -R "${COMMONS_SRC}/backends/llamacpp" "${CORE_INCLUDE}/rac/backends/" 2>/dev/null || true

    # Copy third-party headers (nlohmann json, etc.)
    if [[ -d "${COMMONS_DIR}/build/android/onnx/arm64-v8a/_deps/nlohmann_json-src/single_include/nlohmann" ]]; then
        mkdir -p "${CORE_INCLUDE}/nlohmann"
        cp "${COMMONS_DIR}/build/android/onnx/arm64-v8a/_deps/nlohmann_json-src/single_include/nlohmann/json.hpp" "${CORE_INCLUDE}/nlohmann/" 2>/dev/null || true
    fi

    # Count headers
    local count=$(find "${CORE_INCLUDE}" -name "*.h" -o -name "*.hpp" | wc -l | tr -d ' ')
    log_info "Copied ${count} headers to packages/core/android/src/main/include/"
}

# =============================================================================
# Set Mode (Local/Remote)
# =============================================================================

set_mode() {
    log_header "Setting Build Mode: $MODE"

    if [[ "$MODE" == "local" ]]; then
        export RA_TEST_LOCAL=1

        # Create .testlocal markers for iOS
        touch "${RN_SDK_DIR}/packages/core/ios/.testlocal"
        touch "${RN_SDK_DIR}/packages/llamacpp/ios/.testlocal"
        touch "${RN_SDK_DIR}/packages/onnx/ios/.testlocal"

        log_info "Switched to LOCAL mode"
        log_info "  iOS: Using Binaries/ and Frameworks/ directories"
        log_info "  Android: Set RA_TEST_LOCAL=1 or runanywhere.testLocal=true"
    else
        unset RA_TEST_LOCAL

        # Remove .testlocal markers
        rm -f "${RN_SDK_DIR}/packages/core/ios/.testlocal"
        rm -f "${RN_SDK_DIR}/packages/llamacpp/ios/.testlocal"
        rm -f "${RN_SDK_DIR}/packages/onnx/ios/.testlocal"

        log_info "Switched to REMOTE mode"
        log_info "  iOS: Will download from GitHub releases"
        log_info "  Android: Will download from GitHub releases"
    fi
}

# =============================================================================
# Clean
# =============================================================================

clean_build() {
    log_header "Cleaning Build Directories"

    if [[ "$BUILD_IOS" == true ]]; then
        rm -rf "${CORE_IOS_BINARIES}"
        rm -rf "${LLAMACPP_IOS_FRAMEWORKS}"
        rm -rf "${ONNX_IOS_FRAMEWORKS}"
        # Note: Don't clean RAG iOS libraries - they're pre-bundled static libs
        log_info "Cleaned iOS frameworks"
    fi

    if [[ "$BUILD_ANDROID" == true ]]; then
        rm -rf "${CORE_ANDROID_JNILIBS}"
        rm -rf "${LLAMACPP_ANDROID_JNILIBS}"
        rm -rf "${ONNX_ANDROID_JNILIBS}"
        rm -rf "${RAG_ANDROID_JNILIBS}"
        rm -rf "${RN_SDK_DIR}/packages/core/android/src/main/include"
        log_info "Cleaned Android jniLibs and headers"
    fi
}

# =============================================================================
# Print Summary
# =============================================================================

print_summary() {
    log_header "Build Complete!"

    echo ""
    echo "Mode: $MODE"
    echo ""

    if [[ "$BUILD_IOS" == true ]]; then
        echo "iOS Frameworks:"
        ls -la "${CORE_IOS_BINARIES}" 2>/dev/null || echo "  (none)"
        ls -la "${LLAMACPP_IOS_FRAMEWORKS}" 2>/dev/null || echo "  (none)"
        ls -la "${ONNX_IOS_FRAMEWORKS}" 2>/dev/null || echo "  (none)"
        
        # Show RAG static libraries
        if [[ -d "${RAG_IOS_LIBRARIES}" ]]; then
            local lib_count=$(find "${RAG_IOS_LIBRARIES}" -name "*.a" 2>/dev/null | wc -l | xargs)
            local lib_size=$(du -sh "${RAG_IOS_LIBRARIES}" 2>/dev/null | cut -f1)
            echo ""
            echo "RAG Static Libraries: ${lib_count} files (${lib_size})"
            ls -lh "${RAG_IOS_LIBRARIES}"/*.a 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
        fi
        echo ""
    fi

    if [[ "$BUILD_ANDROID" == true ]]; then
        echo "Android JNI Libraries:"
        for pkg in core llamacpp onnx rag; do
            local dir="${RN_SDK_DIR}/packages/${pkg}/android/src/main/jniLibs"
            if [[ -d "$dir" ]]; then
                local count=$(find "$dir" -name "*.so" 2>/dev/null | wc -l)
                local size=$(du -sh "$dir" 2>/dev/null | cut -f1)
                echo "  ${pkg}: ${count} libs (${size})"
            fi
        done
        echo ""
    fi

    echo "Next steps:"
    echo "  1. Run example app: cd examples/react-native/RunAnywhereAI"
    echo "  2. iOS: cd ios && pod install && cd .. && npx react-native run-ios"
    echo "  3. Android: npx react-native run-android"
    echo ""
    echo "To rebuild after C++ changes:"
    echo "  ./scripts/build-react-native.sh --local --rebuild-commons"
    echo ""
    echo "Note: iOS needs the xcframework from this script (build-ios.sh)."
    echo "      After --clean, run --setup (no --android/--ios) to rebuild both."
}

# =============================================================================
# Main
# =============================================================================

main() {
    log_header "RunAnywhere React Native SDK Build"
    echo "Mode:           $MODE"
    echo "Setup:          $SETUP_MODE"
    echo "Rebuild Commons: $REBUILD_COMMONS"
    echo "iOS:            $BUILD_IOS"
    echo "Android:        $BUILD_ANDROID"
    echo "ABIs:           $ABIS"
    echo ""

    # Clean if requested
    [[ "$CLEAN_BUILD" == true ]] && clean_build

    # Setup environment (install deps)
    [[ "$SETUP_MODE" == true ]] && setup_environment

    # Build native libraries if needed
    if [[ "$REBUILD_COMMONS" == true ]] && [[ "$SKIP_BUILD" == false ]]; then
        if [[ "$BUILD_IOS" == true ]]; then
            build_commons_ios
            build_rag_ios
        fi
        if [[ "$BUILD_ANDROID" == true ]]; then
            build_commons_android
            build_rag_android
        fi
    fi

    # Copy frameworks/libs if in local mode
    if [[ "$MODE" == "local" ]]; then
        [[ "$BUILD_IOS" == true ]] && copy_ios_frameworks
        [[ "$BUILD_ANDROID" == true ]] && copy_android_jnilibs
        [[ "$BUILD_ANDROID" == true ]] && copy_cpp_headers
    fi

    # Set mode
    set_mode

    # Print summary
    print_summary
}

main "$@"
