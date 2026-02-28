#!/bin/bash
# =============================================================================
# RunAnywhere Flutter SDK - Build Script
# =============================================================================
#
# Single entry point for building the Flutter SDK and its native dependencies.
# Similar to iOS's build-swift.sh, Android's build-kotlin.sh, and RN's build-react-native.sh.
#
# USAGE:
#   ./scripts/build-flutter.sh [options]
#
# OPTIONS:
#   --setup             First-time setup: install deps, build commons, copy frameworks/libs
#   --local             Use locally built native libs (sets testLocal=true)
#   --remote            Use remote libs from GitHub releases (sets testLocal=false)
#   --rebuild-commons   Force rebuild of runanywhere-commons
#   --ios               Build for iOS only
#   --android           Build for Android only (default: both)
#   --clean             Clean build directories before building
#   --skip-build        Skip native build (only setup frameworks/libs)
#   --help              Show this help message
#
# EXAMPLES:
#   # First-time setup (downloads + builds + copies everything)
#   ./scripts/build-flutter.sh --setup
#
#   # Rebuild only commons (after C++ code changes)
#   ./scripts/build-flutter.sh --local --rebuild-commons
#
#   # Just switch to local mode (uses cached libs)
#   ./scripts/build-flutter.sh --local --skip-build
#
#   # iOS only setup
#   ./scripts/build-flutter.sh --setup --ios
#
# =============================================================================

set -e

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUTTER_SDK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SDK_ROOT="$(cd "${FLUTTER_SDK_DIR}/.." && pwd)"
COMMONS_DIR="${SDK_ROOT}/runanywhere-commons"
COMMONS_IOS_SCRIPT="${COMMONS_DIR}/scripts/build-ios.sh"
COMMONS_ANDROID_SCRIPT="${COMMONS_DIR}/scripts/build-android.sh"

# Package directories
CORE_PKG="${FLUTTER_SDK_DIR}/packages/runanywhere"
LLAMACPP_PKG="${FLUTTER_SDK_DIR}/packages/runanywhere_llamacpp"
ONNX_PKG="${FLUTTER_SDK_DIR}/packages/runanywhere_onnx"

# iOS output directories
CORE_IOS_FRAMEWORKS="${CORE_PKG}/ios/Frameworks"
LLAMACPP_IOS_FRAMEWORKS="${LLAMACPP_PKG}/ios/Frameworks"
ONNX_IOS_FRAMEWORKS="${ONNX_PKG}/ios/Frameworks"

# Android output directories
CORE_ANDROID_JNILIBS="${CORE_PKG}/android/src/main/jniLibs"
LLAMACPP_ANDROID_JNILIBS="${LLAMACPP_PKG}/android/src/main/jniLibs"
ONNX_ANDROID_JNILIBS="${ONNX_PKG}/android/src/main/jniLibs"

# Defaults
MODE="local"
SETUP_MODE=false
REBUILD_COMMONS=false
CLEAN_BUILD=false
SKIP_BUILD=false
BUILD_IOS=true
BUILD_ANDROID=true
ABIS="arm64-v8a,x86_64"

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
    head -40 "$0" | tail -37
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
    log_header "Setting Up Flutter Environment"

    cd "$FLUTTER_SDK_DIR"

    # Check for flutter
    if ! command -v flutter &> /dev/null; then
        log_error "flutter is not installed. Please install Flutter SDK first."
        exit 1
    fi

    log_info "Flutter version: $(flutter --version | head -1)"

    # Check for melos (optional but recommended)
    if command -v melos &> /dev/null; then
        log_step "Running melos bootstrap..."
        melos bootstrap || true
    else
        log_warn "melos not found, running flutter pub get for each package..."
        for pkg in "$CORE_PKG" "$LLAMACPP_PKG" "$ONNX_PKG"; do
            if [[ -f "$pkg/pubspec.yaml" ]]; then
                (cd "$pkg" && flutter pub get)
            fi
        done
    fi

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

    log_step "Running: build-ios.sh $FLAGS"
    "$COMMONS_IOS_SCRIPT" $FLAGS

    log_info "iOS commons build complete"
}

build_commons_android() {
    log_header "Building runanywhere-commons for Android"

    if [[ ! -x "$COMMONS_ANDROID_SCRIPT" ]]; then
        log_error "Android build script not found: $COMMONS_ANDROID_SCRIPT"
        exit 1
    fi

    # build-android.sh takes positional args: BACKENDS ABIS
    # Use "llamacpp,onnx" for backends to get both LlamaCPP and ONNX
    local BACKENDS="llamacpp,onnx"

    log_step "Running: build-android.sh $BACKENDS $ABIS"
    "$COMMONS_ANDROID_SCRIPT" "$BACKENDS" "$ABIS"

    log_info "Android commons build complete"
}

# =============================================================================
# Copy iOS Frameworks
# =============================================================================

copy_ios_frameworks() {
    log_header "Copying iOS XCFrameworks"

    local COMMONS_DIST="${COMMONS_DIR}/dist"

    # Create directories
    mkdir -p "$CORE_IOS_FRAMEWORKS"
    mkdir -p "$LLAMACPP_IOS_FRAMEWORKS"
    mkdir -p "$ONNX_IOS_FRAMEWORKS"

    # Copy RACommons.xcframework to core package
    if [[ -d "${COMMONS_DIST}/RACommons.xcframework" ]]; then
        rm -rf "${CORE_IOS_FRAMEWORKS}/RACommons.xcframework"
        cp -R "${COMMONS_DIST}/RACommons.xcframework" "${CORE_IOS_FRAMEWORKS}/"
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

    # Copy RABackendRAG.xcframework to core package (RAG pipeline)
    if [[ -d "${COMMONS_DIST}/RABackendRAG.xcframework" ]]; then
        rm -rf "${CORE_IOS_FRAMEWORKS}/RABackendRAG.xcframework"
        cp -R "${COMMONS_DIST}/RABackendRAG.xcframework" "${CORE_IOS_FRAMEWORKS}/"
        log_info "Core: RABackendRAG.xcframework"
    else
        log_warn "RABackendRAG.xcframework not found at ${COMMONS_DIST}/"
    fi

    # Copy onnxruntime.xcframework to onnx package (required dependency)
    # This matches the architecture of React Native and Swift SDKs
    local ONNX_RUNTIME_PATH="${COMMONS_DIR}/third_party/onnxruntime-ios/onnxruntime.xcframework"
    if [[ -d "${ONNX_RUNTIME_PATH}" ]]; then
        rm -rf "${ONNX_IOS_FRAMEWORKS}/onnxruntime.xcframework"
        cp -R "${ONNX_RUNTIME_PATH}" "${ONNX_IOS_FRAMEWORKS}/"
        log_info "ONNX: onnxruntime.xcframework"
    else
        log_warn "onnxruntime.xcframework not found at ${ONNX_RUNTIME_PATH}"
    fi

    # Create .testlocal markers for local mode
    touch "${CORE_PKG}/ios/.testlocal"
    touch "${LLAMACPP_PKG}/ios/.testlocal"
    touch "${ONNX_PKG}/ios/.testlocal"

    log_info "iOS frameworks copied"
}

# =============================================================================
# Copy Android JNI Libraries
# =============================================================================

copy_android_jnilibs() {
    log_header "Copying Android JNI Libraries"

    local COMMONS_DIST="${COMMONS_DIR}/dist/android"
    local COMMONS_BUILD="${COMMONS_DIR}/build/android/unified"

    # Find Android NDK for runtime libraries (libc++_shared.so, libomp.so)
    local NDK_PATH="${ANDROID_NDK_HOME:-$NDK_HOME}"
    if [[ -z "$NDK_PATH" ]] || [[ ! -d "$NDK_PATH" ]]; then
        # Try common locations
        if [[ -d "$HOME/Library/Android/sdk/ndk" ]]; then
            NDK_PATH=$(ls -d "$HOME/Library/Android/sdk/ndk"/*/ 2>/dev/null | sort -V | tail -1)
        elif [[ -d "$HOME/Android/Sdk/ndk" ]]; then
            NDK_PATH=$(ls -d "$HOME/Android/Sdk/ndk"/*/ 2>/dev/null | sort -V | tail -1)
        elif [[ -n "$ANDROID_HOME" ]] && [[ -d "$ANDROID_HOME/ndk" ]]; then
            NDK_PATH=$(ls -d "$ANDROID_HOME/ndk"/*/ 2>/dev/null | sort -V | tail -1)
        fi
    fi

    if [[ -n "$NDK_PATH" ]] && [[ -d "$NDK_PATH" ]]; then
        log_info "Using Android NDK: $NDK_PATH"
    else
        log_warn "Android NDK not found - runtime libraries (libc++_shared.so, libomp.so) may not be copied"
    fi

    IFS=',' read -ra ABI_ARRAY <<< "$ABIS"

    for ABI in "${ABI_ARRAY[@]}"; do
        log_step "Copying libraries for ${ABI}..."

        # Create directories
        mkdir -p "${CORE_ANDROID_JNILIBS}/${ABI}"
        mkdir -p "${LLAMACPP_ANDROID_JNILIBS}/${ABI}"
        mkdir -p "${ONNX_ANDROID_JNILIBS}/${ABI}"

        # Determine arch-specific search pattern for NDK libraries
        local ARCH_PATTERN=""
        case "$ABI" in
            arm64-v8a)   ARCH_PATTERN="aarch64" ;;
            armeabi-v7a) ARCH_PATTERN="arm" ;;
            x86_64)      ARCH_PATTERN="x86_64" ;;
            x86)         ARCH_PATTERN="i686" ;;
        esac

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

        # Copy libc++_shared.so - try dist first, then NDK
        if [[ -f "${COMMONS_DIST}/llamacpp/${ABI}/libc++_shared.so" ]]; then
            cp "${COMMONS_DIST}/llamacpp/${ABI}/libc++_shared.so" "${CORE_ANDROID_JNILIBS}/${ABI}/"
            log_info "Core: libc++_shared.so"
        elif [[ -f "${COMMONS_DIST}/jni/${ABI}/libc++_shared.so" ]]; then
            cp "${COMMONS_DIST}/jni/${ABI}/libc++_shared.so" "${CORE_ANDROID_JNILIBS}/${ABI}/"
            log_info "Core: libc++_shared.so"
        elif [[ -n "$NDK_PATH" ]] && [[ -n "$ARCH_PATTERN" ]]; then
            # Find libc++_shared.so from NDK
            local LIBCXX_FOUND=$(find "$NDK_PATH/toolchains/llvm/prebuilt" -name "libc++_shared.so" -path "*${ARCH_PATTERN}*" 2>/dev/null | head -1)
            if [[ -n "$LIBCXX_FOUND" ]] && [[ -f "$LIBCXX_FOUND" ]]; then
                cp "$LIBCXX_FOUND" "${CORE_ANDROID_JNILIBS}/${ABI}/"
                log_info "Core: libc++_shared.so (from NDK)"
            fi
        fi

        # Copy libomp.so - try dist first, then NDK
        if [[ -f "${COMMONS_DIST}/llamacpp/${ABI}/libomp.so" ]]; then
            cp "${COMMONS_DIST}/llamacpp/${ABI}/libomp.so" "${CORE_ANDROID_JNILIBS}/${ABI}/"
            log_info "Core: libomp.so"
        elif [[ -f "${COMMONS_DIST}/jni/${ABI}/libomp.so" ]]; then
            cp "${COMMONS_DIST}/jni/${ABI}/libomp.so" "${CORE_ANDROID_JNILIBS}/${ABI}/"
            log_info "Core: libomp.so"
        elif [[ -n "$NDK_PATH" ]] && [[ -n "$ARCH_PATTERN" ]]; then
            # Find libomp.so from NDK
            local LIBOMP_FOUND=$(find "$NDK_PATH/toolchains/llvm/prebuilt" -name "libomp.so" -path "*/${ARCH_PATTERN}/*" 2>/dev/null | head -1)
            if [[ -n "$LIBOMP_FOUND" ]] && [[ -f "$LIBOMP_FOUND" ]]; then
                cp "$LIBOMP_FOUND" "${CORE_ANDROID_JNILIBS}/${ABI}/"
                log_info "Core: libomp.so (from NDK)"
            fi
        fi

        # =======================================================================
        # LlamaCPP Package: RABackendLlamaCPP
        # =======================================================================

        # Copy backend library
        if [[ -f "${COMMONS_DIST}/llamacpp/${ABI}/librac_backend_llamacpp.so" ]]; then
            cp "${COMMONS_DIST}/llamacpp/${ABI}/librac_backend_llamacpp.so" "${LLAMACPP_ANDROID_JNILIBS}/${ABI}/"
            log_info "LlamaCPP: librac_backend_llamacpp.so"
        elif [[ -f "${COMMONS_BUILD}/${ABI}/src/backends/llamacpp/librac_backend_llamacpp.so" ]]; then
            cp "${COMMONS_BUILD}/${ABI}/src/backends/llamacpp/librac_backend_llamacpp.so" "${LLAMACPP_ANDROID_JNILIBS}/${ABI}/"
            log_info "LlamaCPP: librac_backend_llamacpp.so (from build)"
        fi

        # Copy JNI bridge (if exists)
        if [[ -f "${COMMONS_DIST}/llamacpp/${ABI}/librac_backend_llamacpp_jni.so" ]]; then
            cp "${COMMONS_DIST}/llamacpp/${ABI}/librac_backend_llamacpp_jni.so" "${LLAMACPP_ANDROID_JNILIBS}/${ABI}/"
            log_info "LlamaCPP: librac_backend_llamacpp_jni.so"
        elif [[ -f "${COMMONS_BUILD}/${ABI}/src/backends/llamacpp/librac_backend_llamacpp_jni.so" ]]; then
            cp "${COMMONS_BUILD}/${ABI}/src/backends/llamacpp/librac_backend_llamacpp_jni.so" "${LLAMACPP_ANDROID_JNILIBS}/${ABI}/"
            log_info "LlamaCPP: librac_backend_llamacpp_jni.so (from build)"
        fi

        # Copy libomp.so to LlamaCPP package (required for OpenMP support)
        if [[ -f "${COMMONS_DIST}/llamacpp/${ABI}/libomp.so" ]]; then
            cp "${COMMONS_DIST}/llamacpp/${ABI}/libomp.so" "${LLAMACPP_ANDROID_JNILIBS}/${ABI}/"
            log_info "LlamaCPP: libomp.so"
        elif [[ -f "${COMMONS_DIST}/jni/${ABI}/libomp.so" ]]; then
            cp "${COMMONS_DIST}/jni/${ABI}/libomp.so" "${LLAMACPP_ANDROID_JNILIBS}/${ABI}/"
            log_info "LlamaCPP: libomp.so (from jni)"
        elif [[ -n "$NDK_PATH" ]] && [[ -n "$ARCH_PATTERN" ]]; then
            # Find libomp.so from NDK
            local LIBOMP_FOUND=$(find "$NDK_PATH/toolchains/llvm/prebuilt" -name "libomp.so" -path "*/${ARCH_PATTERN}/*" 2>/dev/null | head -1)
            if [[ -n "$LIBOMP_FOUND" ]] && [[ -f "$LIBOMP_FOUND" ]]; then
                cp "$LIBOMP_FOUND" "${LLAMACPP_ANDROID_JNILIBS}/${ABI}/"
                log_info "LlamaCPP: libomp.so (from NDK)"
            fi
        fi

        # Copy libc++_shared.so to LlamaCPP package
        if [[ -f "${COMMONS_DIST}/llamacpp/${ABI}/libc++_shared.so" ]]; then
            cp "${COMMONS_DIST}/llamacpp/${ABI}/libc++_shared.so" "${LLAMACPP_ANDROID_JNILIBS}/${ABI}/"
            log_info "LlamaCPP: libc++_shared.so"
        elif [[ -f "${COMMONS_DIST}/jni/${ABI}/libc++_shared.so" ]]; then
            cp "${COMMONS_DIST}/jni/${ABI}/libc++_shared.so" "${LLAMACPP_ANDROID_JNILIBS}/${ABI}/"
            log_info "LlamaCPP: libc++_shared.so (from jni)"
        elif [[ -n "$NDK_PATH" ]] && [[ -n "$ARCH_PATTERN" ]]; then
            # Find libc++_shared.so from NDK
            local LIBCXX_FOUND=$(find "$NDK_PATH/toolchains/llvm/prebuilt" -name "libc++_shared.so" -path "*${ARCH_PATTERN}*" 2>/dev/null | head -1)
            if [[ -n "$LIBCXX_FOUND" ]] && [[ -f "$LIBCXX_FOUND" ]]; then
                cp "$LIBCXX_FOUND" "${LLAMACPP_ANDROID_JNILIBS}/${ABI}/"
                log_info "LlamaCPP: libc++_shared.so (from NDK)"
            fi
        fi

        # =======================================================================
        # ONNX Package: RABackendONNX
        # =======================================================================

        # Copy backend library
        if [[ -f "${COMMONS_DIST}/onnx/${ABI}/librac_backend_onnx.so" ]]; then
            cp "${COMMONS_DIST}/onnx/${ABI}/librac_backend_onnx.so" "${ONNX_ANDROID_JNILIBS}/${ABI}/"
            log_info "ONNX: librac_backend_onnx.so"
        elif [[ -f "${COMMONS_BUILD}/${ABI}/src/backends/onnx/librac_backend_onnx.so" ]]; then
            cp "${COMMONS_BUILD}/${ABI}/src/backends/onnx/librac_backend_onnx.so" "${ONNX_ANDROID_JNILIBS}/${ABI}/"
            log_info "ONNX: librac_backend_onnx.so (from build)"
        fi

        # Copy JNI bridge (if exists)
        if [[ -f "${COMMONS_DIST}/onnx/${ABI}/librac_backend_onnx_jni.so" ]]; then
            cp "${COMMONS_DIST}/onnx/${ABI}/librac_backend_onnx_jni.so" "${ONNX_ANDROID_JNILIBS}/${ABI}/"
            log_info "ONNX: librac_backend_onnx_jni.so"
        elif [[ -f "${COMMONS_BUILD}/${ABI}/src/backends/onnx/librac_backend_onnx_jni.so" ]]; then
            cp "${COMMONS_BUILD}/${ABI}/src/backends/onnx/librac_backend_onnx_jni.so" "${ONNX_ANDROID_JNILIBS}/${ABI}/"
            log_info "ONNX: librac_backend_onnx_jni.so (from build)"
        fi

        # Copy ONNX Runtime - try dist first, then third_party (from Sherpa-ONNX)
        local SHERPA_JNILIBS="${COMMONS_DIR}/third_party/sherpa-onnx-android/jniLibs/${ABI}"
        if [[ -f "${COMMONS_DIST}/onnx/${ABI}/libonnxruntime.so" ]]; then
            cp "${COMMONS_DIST}/onnx/${ABI}/libonnxruntime.so" "${ONNX_ANDROID_JNILIBS}/${ABI}/"
            log_info "ONNX: libonnxruntime.so"
        elif [[ -f "${SHERPA_JNILIBS}/libonnxruntime.so" ]]; then
            cp "${SHERPA_JNILIBS}/libonnxruntime.so" "${ONNX_ANDROID_JNILIBS}/${ABI}/"
            log_info "ONNX: libonnxruntime.so (from Sherpa-ONNX)"
        fi

        # Copy Sherpa-ONNX libraries - try dist first, then third_party
        for lib in libsherpa-onnx-c-api.so libsherpa-onnx-cxx-api.so libsherpa-onnx-jni.so; do
            if [[ -f "${COMMONS_DIST}/onnx/${ABI}/${lib}" ]]; then
                cp "${COMMONS_DIST}/onnx/${ABI}/${lib}" "${ONNX_ANDROID_JNILIBS}/${ABI}/"
                log_info "ONNX: ${lib}"
            elif [[ -f "${SHERPA_JNILIBS}/${lib}" ]]; then
                cp "${SHERPA_JNILIBS}/${lib}" "${ONNX_ANDROID_JNILIBS}/${ABI}/"
                log_info "ONNX: ${lib} (from Sherpa-ONNX)"
            fi
        done

        # =======================================================================
        # RAG Pipeline: librac_backend_rag.so (into core package)
        # =======================================================================

        if [[ -f "${COMMONS_DIST}/rag/${ABI}/librac_backend_rag.so" ]]; then
            cp "${COMMONS_DIST}/rag/${ABI}/librac_backend_rag.so" "${CORE_ANDROID_JNILIBS}/${ABI}/"
            log_info "RAG: librac_backend_rag.so"
        elif [[ -f "${COMMONS_BUILD}/${ABI}/src/features/rag/librac_backend_rag.so" ]]; then
            cp "${COMMONS_BUILD}/${ABI}/src/features/rag/librac_backend_rag.so" "${CORE_ANDROID_JNILIBS}/${ABI}/"
            log_info "RAG: librac_backend_rag.so (from build)"
        fi
    done

    log_info "Android JNI libraries copied"
}

# =============================================================================
# Set Mode (Local/Remote)
# =============================================================================

set_mode() {
    log_header "Setting Build Mode: $MODE"

    if [[ "$MODE" == "local" ]]; then
        export RA_TEST_LOCAL=1

        # Create .testlocal markers for iOS
        touch "${CORE_PKG}/ios/.testlocal"
        touch "${LLAMACPP_PKG}/ios/.testlocal"
        touch "${ONNX_PKG}/ios/.testlocal"

        # Update Android binary_config.gradle files to use testLocal = true
        for pkg in "$CORE_PKG" "$LLAMACPP_PKG" "$ONNX_PKG"; do
            local config_file="${pkg}/android/binary_config.gradle"
            if [[ -f "$config_file" ]]; then
                sed -i.bak 's/testLocal = false/testLocal = true/g' "$config_file"
                rm -f "${config_file}.bak"
            fi
        done

        log_info "Switched to LOCAL mode"
        log_info "  iOS: Using Frameworks/ directories"
        log_info "  Android: Using src/main/jniLibs/ directories"
    else
        unset RA_TEST_LOCAL

        # Remove .testlocal markers
        rm -f "${CORE_PKG}/ios/.testlocal"
        rm -f "${LLAMACPP_PKG}/ios/.testlocal"
        rm -f "${ONNX_PKG}/ios/.testlocal"

        # Update Android binary_config.gradle files to use testLocal = false
        for pkg in "$CORE_PKG" "$LLAMACPP_PKG" "$ONNX_PKG"; do
            local config_file="${pkg}/android/binary_config.gradle"
            if [[ -f "$config_file" ]]; then
                sed -i.bak 's/testLocal = true/testLocal = false/g' "$config_file"
                rm -f "${config_file}.bak"
            fi
        done

        log_info "Switched to REMOTE mode"
        log_info "  iOS: Will download from GitHub releases during pod install"
        log_info "  Android: Will download from GitHub releases during Gradle sync"
    fi
}

# =============================================================================
# Clean
# =============================================================================

clean_build() {
    log_header "Cleaning Build Directories"

    if [[ "$BUILD_IOS" == true ]]; then
        rm -rf "${CORE_IOS_FRAMEWORKS}"
        rm -rf "${LLAMACPP_IOS_FRAMEWORKS}"
        rm -rf "${ONNX_IOS_FRAMEWORKS}"
        log_info "Cleaned iOS frameworks"
    fi

    if [[ "$BUILD_ANDROID" == true ]]; then
        rm -rf "${CORE_ANDROID_JNILIBS}"
        rm -rf "${LLAMACPP_ANDROID_JNILIBS}"
        rm -rf "${ONNX_ANDROID_JNILIBS}"
        log_info "Cleaned Android jniLibs"
    fi

    # Run flutter clean on packages
    log_step "Running flutter clean..."
    for pkg in "$CORE_PKG" "$LLAMACPP_PKG" "$ONNX_PKG"; do
        if [[ -f "$pkg/pubspec.yaml" ]]; then
            (cd "$pkg" && flutter clean) || true
        fi
    done
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
        ls -la "${CORE_IOS_FRAMEWORKS}" 2>/dev/null || echo "  (none)"
        ls -la "${LLAMACPP_IOS_FRAMEWORKS}" 2>/dev/null || echo "  (none)"
        ls -la "${ONNX_IOS_FRAMEWORKS}" 2>/dev/null || echo "  (none)"
        echo ""
    fi

    if [[ "$BUILD_ANDROID" == true ]]; then
        echo "Android JNI Libraries:"
        for pkg_name in runanywhere runanywhere_llamacpp runanywhere_onnx; do
            local dir="${FLUTTER_SDK_DIR}/packages/${pkg_name}/android/src/main/jniLibs"
            if [[ -d "$dir" ]]; then
                local count=$(find "$dir" -name "*.so" 2>/dev/null | wc -l)
                local size=$(du -sh "$dir" 2>/dev/null | cut -f1)
                echo "  ${pkg_name}: ${count} libs (${size})"
            fi
        done
        echo ""
    fi

    echo "Next steps:"
    echo "  1. Run example app: cd examples/flutter/RunAnywhereAI"
    echo "  2. flutter pub get"
    echo "  3. iOS: cd ios && pod install && cd .. && flutter run"
    echo "  4. Android: flutter run"
    echo ""
    echo "To rebuild after C++ changes:"
    echo "  ./scripts/build-flutter.sh --local --rebuild-commons"
}

# =============================================================================
# Main
# =============================================================================

main() {
    log_header "RunAnywhere Flutter SDK Build"
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
        [[ "$BUILD_IOS" == true ]] && build_commons_ios
        [[ "$BUILD_ANDROID" == true ]] && build_commons_android
    fi

    # Copy frameworks/libs if in local mode
    if [[ "$MODE" == "local" ]]; then
        [[ "$BUILD_IOS" == true ]] && copy_ios_frameworks
        [[ "$BUILD_ANDROID" == true ]] && copy_android_jnilibs
    fi

    # Set mode
    set_mode

    # Print summary
    print_summary
}

main "$@"
