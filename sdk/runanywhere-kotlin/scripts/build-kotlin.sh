#!/bin/bash
# =============================================================================
# RunAnywhere Kotlin SDK - Build Script
# =============================================================================
#
# Single entry point for building the Kotlin SDK and its C++ dependencies.
# Similar to iOS's build-swift.sh - handles everything from download to build.
#
# USAGE:
#   ./scripts/build-kotlin.sh [options]
#
# OPTIONS:
#   --setup             First-time setup: download deps, build commons, copy libs
#   --local             Use locally built libs (sets testLocal=true)
#   --remote            Use remote libs from GitHub releases (sets testLocal=false)
#   --rebuild-commons   Force rebuild of runanywhere-commons (even if cached)
#   --clean             Clean build directories before building
#   --skip-build        Skip Gradle build (only setup native libs)
#   --abis=ABIS         ABIs to build (default: arm64-v8a)
#                       Supported: arm64-v8a, armeabi-v7a, x86_64, x86
#                       Multiple: Use comma-separated (e.g., arm64-v8a,armeabi-v7a)
#   --help              Show this help message
#
# ABI Guide:
#   arm64-v8a        64-bit ARM (modern devices, ~85% coverage)
#   armeabi-v7a      32-bit ARM (older devices, ~12% coverage)
#   x86_64           64-bit Intel (emulators on Intel Macs, ~2%)
#
# EXAMPLES:
#   # First-time setup (modern devices only, ~4min build)
#   ./scripts/build-kotlin.sh --setup
#
#   # RECOMMENDED for production (97% device coverage, ~7min build)
#   ./scripts/build-kotlin.sh --setup --abis=arm64-v8a,armeabi-v7a
#
#   # Development with emulator support (device + Intel Mac emulator)
#   ./scripts/build-kotlin.sh --setup --abis=arm64-v8a,x86_64
#
#   # Rebuild only commons (after C++ code changes)
#   ./scripts/build-kotlin.sh --local --rebuild-commons
#
#   # Rebuild with multiple ABIs
#   ./scripts/build-kotlin.sh --local --rebuild-commons --abis=arm64-v8a,armeabi-v7a
#
#   # Just switch to local mode (uses cached libs)
#   ./scripts/build-kotlin.sh --local --skip-build
#
#   # Clean build everything
#   ./scripts/build-kotlin.sh --setup --clean
#
# =============================================================================

set -e

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KOTLIN_SDK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SDK_ROOT="$(cd "${KOTLIN_SDK_DIR}/.." && pwd)"
COMMONS_DIR="${SDK_ROOT}/runanywhere-commons"
COMMONS_BUILD_SCRIPT="${COMMONS_DIR}/scripts/build-android.sh"

# Output directories
MAIN_JNILIBS_DIR="${KOTLIN_SDK_DIR}/src/androidMain/jniLibs"
LLAMACPP_JNILIBS_DIR="${KOTLIN_SDK_DIR}/modules/runanywhere-core-llamacpp/src/androidMain/jniLibs"
ONNX_JNILIBS_DIR="${KOTLIN_SDK_DIR}/modules/runanywhere-core-onnx/src/androidMain/jniLibs"

# Defaults
MODE="local"
SETUP_MODE=false
REBUILD_COMMONS=false
CLEAN_BUILD=false
SKIP_BUILD=false
ABIS="arm64-v8a"

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
    head -50 "$0" | tail -45
    exit 0
}

for arg in "$@"; do
    case $arg in
        --setup)
            SETUP_MODE=true
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
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# =============================================================================
# Validation
# =============================================================================

validate_environment() {
    # Check NDK
    if [ -z "${ANDROID_NDK_HOME}" ]; then
        # Try to find NDK
        if [ -d "${HOME}/Library/Android/sdk/ndk" ]; then
            ANDROID_NDK_HOME=$(ls -d "${HOME}/Library/Android/sdk/ndk/"* 2>/dev/null | sort -V | tail -1)
            export ANDROID_NDK_HOME
        fi
    fi

    if [ -z "${ANDROID_NDK_HOME}" ] || [ ! -d "${ANDROID_NDK_HOME}" ]; then
        log_error "ANDROID_NDK_HOME not set or NDK not found"
        echo "Please set ANDROID_NDK_HOME or install NDK via Android Studio"
        exit 1
    fi

    # Check Commons
    if [ ! -d "${COMMONS_DIR}" ]; then
        log_error "runanywhere-commons not found at ${COMMONS_DIR}"
        exit 1
    fi

    # Check build script
    if [ ! -f "${COMMONS_BUILD_SCRIPT}" ]; then
        log_error "Android build script not found: ${COMMONS_BUILD_SCRIPT}"
        exit 1
    fi
}

# =============================================================================
# Check if JNI libs need to be rebuilt
# =============================================================================

check_libs_exist() {
    local abi="$1"

    # Check main SDK libs
    if [ ! -f "${MAIN_JNILIBS_DIR}/${abi}/libc++_shared.so" ]; then
        return 1
    fi

    # Check LlamaCPP module
    if [ ! -f "${LLAMACPP_JNILIBS_DIR}/${abi}/librac_backend_llamacpp_jni.so" ]; then
        return 1
    fi

    # Check ONNX module
    if [ ! -f "${ONNX_JNILIBS_DIR}/${abi}/librac_backend_onnx_jni.so" ]; then
        return 1
    fi

    return 0
}

check_commons_changed() {
    local marker_file="${KOTLIN_SDK_DIR}/.commons-build-marker"

    if [ ! -f "$marker_file" ]; then
        return 0  # No marker = needs rebuild
    fi

    # Check if any C++ source files are newer than the marker
    local newer_files=$(find "${COMMONS_DIR}/src" -name "*.cpp" -o -name "*.h" 2>/dev/null | \
        xargs stat -f "%m %N" 2>/dev/null | \
        while read mtime file; do
            marker_mtime=$(stat -f "%m" "$marker_file" 2>/dev/null || echo 0)
            if [ "$mtime" -gt "$marker_mtime" ]; then
                echo "$file"
            fi
        done | head -1)

    if [ -n "$newer_files" ]; then
        return 0  # Changed
    fi

    return 1  # No changes
}

# =============================================================================
# Build Functions
# =============================================================================

download_dependencies() {
    log_header "Downloading Dependencies"

    cd "${COMMONS_DIR}"

    # Download Sherpa-ONNX for Android
    if [ -f "scripts/android/download-sherpa-onnx.sh" ]; then
        log_step "Downloading Sherpa-ONNX for Android..."
        ./scripts/android/download-sherpa-onnx.sh
    fi

    log_info "Dependencies downloaded"
}

build_commons() {
    log_header "Building runanywhere-commons for Android"

    cd "${COMMONS_DIR}"

    local FLAGS=""
    if [ "$CLEAN_BUILD" = true ]; then
        FLAGS="--clean"
        # Clean Android build directory
        rm -rf "${COMMONS_DIR}/build/android"
        rm -rf "${COMMONS_DIR}/dist/android"
    fi

    log_step "Running: build-android.sh"
    log_info "Building for ABIs: ${ABIS}"
    log_info "Building backends: llamacpp,onnx (WhisperCPP disabled due to ggml version conflict)"
    log_info "This may take several minutes..."
    echo ""

    # Build for Android - only llamacpp and onnx (WhisperCPP has ggml version conflict)
    "${COMMONS_BUILD_SCRIPT}" llamacpp,onnx "${ABIS}"

    # Update build marker
    touch "${KOTLIN_SDK_DIR}/.commons-build-marker"

    log_info "runanywhere-commons build complete"
}

copy_jni_libs() {
    log_header "Copying JNI Libraries"

    # Source directories from runanywhere-commons build
    local COMMONS_DIST="${COMMONS_DIR}/dist/android"
    local COMMONS_BUILD="${COMMONS_DIR}/build/android/unified"
    local SHERPA_ONNX_LIBS="${COMMONS_DIR}/third_party/sherpa-onnx-android/jniLibs"

    # =========================================================================
    # Safety check: Remove stale .so from example apps.
    # Example apps get native libraries transitively via SDK module dependencies.
    # Having .so directly in app/src/main/jniLibs/ overrides the SDK module
    # versions and can cause ABI mismatch crashes (e.g., SIGSEGV in Sherpa-ONNX).
    # =========================================================================
    local EXAMPLE_APPS_DIR="${SDK_ROOT}/../examples/android"
    if [ -d "${EXAMPLE_APPS_DIR}" ]; then
        for app_jnilibs in "${EXAMPLE_APPS_DIR}"/*/app/src/main/jniLibs; do
            if [ -d "$app_jnilibs" ]; then
                local stale_count=$(find "$app_jnilibs" -name "*.so" 2>/dev/null | wc -l | tr -d ' ')
                if [ "$stale_count" -gt 0 ]; then
                    log_warn "Found ${stale_count} stale .so in $(basename $(dirname $(dirname $(dirname $(dirname "$app_jnilibs")))))/app/src/main/jniLibs/"
                    log_warn "Removing to prevent ABI mismatch — app gets native libs from SDK modules"
                    rm -rf "$app_jnilibs"
                fi
            fi
        done
    fi

    # Clean output directories
    if [ "$CLEAN_BUILD" = true ]; then
        log_step "Cleaning JNI directories..."
        rm -rf "${MAIN_JNILIBS_DIR}"
        rm -rf "${LLAMACPP_JNILIBS_DIR}"
        rm -rf "${ONNX_JNILIBS_DIR}"
    fi

    # Parse ABIs
    local ABI_LIST
    if [[ "${ABIS}" == "all" ]]; then
        ABI_LIST="arm64-v8a armeabi-v7a x86_64"
    else
        ABI_LIST=$(echo "${ABIS}" | tr ',' ' ')
    fi

    for ABI in ${ABI_LIST}; do
        log_step "Copying libraries for ${ABI}..."

        # Create directories
        mkdir -p "${MAIN_JNILIBS_DIR}/${ABI}"
        mkdir -p "${LLAMACPP_JNILIBS_DIR}/${ABI}"
        mkdir -p "${ONNX_JNILIBS_DIR}/${ABI}"

        # =======================================================================
        # Main SDK (Commons): Core JNI + libc++_shared.so + librac_commons.so
        # =======================================================================

        # Copy librunanywhere_jni.so (CORE JNI BRIDGE - REQUIRED)
        if [ -f "${COMMONS_DIST}/jni/${ABI}/librunanywhere_jni.so" ]; then
            cp "${COMMONS_DIST}/jni/${ABI}/librunanywhere_jni.so" "${MAIN_JNILIBS_DIR}/${ABI}/"
            log_info "Main SDK: librunanywhere_jni.so"
        elif [ -f "${COMMONS_BUILD}/${ABI}/src/jni/librunanywhere_jni.so" ]; then
            cp "${COMMONS_BUILD}/${ABI}/src/jni/librunanywhere_jni.so" "${MAIN_JNILIBS_DIR}/${ABI}/"
            log_info "Main SDK: librunanywhere_jni.so (from build)"
        else
            log_warn "Main SDK: librunanywhere_jni.so NOT FOUND - App will crash!"
        fi

        # Copy libc++_shared.so from dist or NDK
        if [ -f "${COMMONS_DIST}/llamacpp/${ABI}/libc++_shared.so" ]; then
            cp "${COMMONS_DIST}/llamacpp/${ABI}/libc++_shared.so" "${MAIN_JNILIBS_DIR}/${ABI}/"
            log_info "Main SDK: libc++_shared.so"
        elif [ -f "${COMMONS_DIST}/jni/${ABI}/libc++_shared.so" ]; then
            cp "${COMMONS_DIST}/jni/${ABI}/libc++_shared.so" "${MAIN_JNILIBS_DIR}/${ABI}/"
            log_info "Main SDK: libc++_shared.so"
        fi

        # Copy librac_commons.so
        if [ -f "${COMMONS_BUILD}/${ABI}/librac_commons.so" ]; then
            cp "${COMMONS_BUILD}/${ABI}/librac_commons.so" "${MAIN_JNILIBS_DIR}/${ABI}/"
            log_info "Main SDK: librac_commons.so"
        fi

        # Copy libomp.so from dist
        if [ -f "${COMMONS_DIST}/llamacpp/${ABI}/libomp.so" ]; then
            cp "${COMMONS_DIST}/llamacpp/${ABI}/libomp.so" "${MAIN_JNILIBS_DIR}/${ABI}/"
            log_info "Main SDK: libomp.so"
        elif [ -f "${COMMONS_DIST}/jni/${ABI}/libomp.so" ]; then
            cp "${COMMONS_DIST}/jni/${ABI}/libomp.so" "${MAIN_JNILIBS_DIR}/${ABI}/"
            log_info "Main SDK: libomp.so"
        fi

        # =======================================================================
        # LlamaCPP Module: Backend + JNI bridge + shared dependencies
        # =======================================================================
        # Copy backend library
        if [ -f "${COMMONS_DIST}/llamacpp/${ABI}/librac_backend_llamacpp.so" ]; then
            cp "${COMMONS_DIST}/llamacpp/${ABI}/librac_backend_llamacpp.so" "${LLAMACPP_JNILIBS_DIR}/${ABI}/"
            log_info "LlamaCPP: librac_backend_llamacpp.so"
        elif [ -f "${COMMONS_BUILD}/${ABI}/src/backends/llamacpp/librac_backend_llamacpp.so" ]; then
            cp "${COMMONS_BUILD}/${ABI}/src/backends/llamacpp/librac_backend_llamacpp.so" "${LLAMACPP_JNILIBS_DIR}/${ABI}/"
            log_info "LlamaCPP: librac_backend_llamacpp.so (from build)"
        fi

        # Copy JNI bridge
        if [ -f "${COMMONS_DIST}/llamacpp/${ABI}/librac_backend_llamacpp_jni.so" ]; then
            cp "${COMMONS_DIST}/llamacpp/${ABI}/librac_backend_llamacpp_jni.so" "${LLAMACPP_JNILIBS_DIR}/${ABI}/"
            log_info "LlamaCPP: librac_backend_llamacpp_jni.so"
        elif [ -f "${COMMONS_BUILD}/${ABI}/src/backends/llamacpp/librac_backend_llamacpp_jni.so" ]; then
            cp "${COMMONS_BUILD}/${ABI}/src/backends/llamacpp/librac_backend_llamacpp_jni.so" "${LLAMACPP_JNILIBS_DIR}/${ABI}/"
            log_info "LlamaCPP: librac_backend_llamacpp_jni.so (from build)"
        fi

        # Copy shared dependencies (must stay in sync with main SDK)
        # These are duplicated in each module so they work as standalone AARs.
        # Gradle pickFirsts resolves duplicates at APK merge time.
        for shared_lib in librac_commons.so libc++_shared.so libomp.so; do
            if [ -f "${MAIN_JNILIBS_DIR}/${ABI}/${shared_lib}" ]; then
                cp "${MAIN_JNILIBS_DIR}/${ABI}/${shared_lib}" "${LLAMACPP_JNILIBS_DIR}/${ABI}/"
            fi
        done

        # =======================================================================
        # ONNX Module: ONNX Runtime + Sherpa-ONNX + JNI bridge
        # =======================================================================
        # Copy backend library
        if [ -f "${COMMONS_DIST}/onnx/${ABI}/librac_backend_onnx.so" ]; then
            cp "${COMMONS_DIST}/onnx/${ABI}/librac_backend_onnx.so" "${ONNX_JNILIBS_DIR}/${ABI}/"
            log_info "ONNX: librac_backend_onnx.so"
        elif [ -f "${COMMONS_BUILD}/${ABI}/src/backends/onnx/librac_backend_onnx.so" ]; then
            cp "${COMMONS_BUILD}/${ABI}/src/backends/onnx/librac_backend_onnx.so" "${ONNX_JNILIBS_DIR}/${ABI}/"
            log_info "ONNX: librac_backend_onnx.so (from build)"
        fi

        # Copy JNI bridge
        if [ -f "${COMMONS_DIST}/onnx/${ABI}/librac_backend_onnx_jni.so" ]; then
            cp "${COMMONS_DIST}/onnx/${ABI}/librac_backend_onnx_jni.so" "${ONNX_JNILIBS_DIR}/${ABI}/"
            log_info "ONNX: librac_backend_onnx_jni.so"
        elif [ -f "${COMMONS_BUILD}/${ABI}/src/backends/onnx/librac_backend_onnx_jni.so" ]; then
            cp "${COMMONS_BUILD}/${ABI}/src/backends/onnx/librac_backend_onnx_jni.so" "${ONNX_JNILIBS_DIR}/${ABI}/"
            log_info "ONNX: librac_backend_onnx_jni.so (from build)"
        fi

        # Copy Sherpa-ONNX and ONNX Runtime from dist or third_party
        if [ -d "${COMMONS_DIST}/onnx/${ABI}" ]; then
            for lib in libonnxruntime.so libsherpa-onnx-c-api.so libsherpa-onnx-cxx-api.so libsherpa-onnx-jni.so; do
                if [ -f "${COMMONS_DIST}/onnx/${ABI}/${lib}" ]; then
                    cp "${COMMONS_DIST}/onnx/${ABI}/${lib}" "${ONNX_JNILIBS_DIR}/${ABI}/"
                    log_info "ONNX: ${lib}"
                fi
            done
        elif [ -d "${SHERPA_ONNX_LIBS}/${ABI}" ]; then
            for lib in "${SHERPA_ONNX_LIBS}/${ABI}"/*.so; do
                if [ -f "$lib" ]; then
                    cp "$lib" "${ONNX_JNILIBS_DIR}/${ABI}/"
                    log_info "ONNX: $(basename $lib)"
                fi
            done
        fi

        # Copy shared dependencies (must stay in sync with main SDK)
        for shared_lib in librac_commons.so libc++_shared.so libomp.so; do
            if [ -f "${MAIN_JNILIBS_DIR}/${ABI}/${shared_lib}" ]; then
                cp "${MAIN_JNILIBS_DIR}/${ABI}/${shared_lib}" "${ONNX_JNILIBS_DIR}/${ABI}/"
            fi
        done
    done

    log_info "JNI libraries installed"
}

set_gradle_mode() {
    local mode="$1"
    local properties_file="${KOTLIN_SDK_DIR}/gradle.properties"

    log_step "Setting testLocal=${mode} in gradle.properties"

    if [ "$mode" = "local" ]; then
        sed -i '' 's/runanywhere.testLocal=false/runanywhere.testLocal=true/' "$properties_file"
        log_info "Switched to LOCAL mode (using jniLibs/)"
    else
        sed -i '' 's/runanywhere.testLocal=true/runanywhere.testLocal=false/' "$properties_file"
        log_info "Switched to REMOTE mode (downloading from GitHub)"
    fi
}

build_sdk() {
    log_header "Building Kotlin SDK"

    cd "${KOTLIN_SDK_DIR}"

    local FLAGS="-Prunanywhere.testLocal=${MODE:0:1}"  # "true" for local, "false" for remote
    if [ "$MODE" = "local" ]; then
        FLAGS="-Prunanywhere.testLocal=true"
    else
        FLAGS="-Prunanywhere.testLocal=false"
    fi

    log_step "Running: ./gradlew assembleDebug $FLAGS"

    if ./gradlew assembleDebug $FLAGS --no-daemon -q; then
        log_info "Kotlin SDK built successfully"
    else
        log_error "Kotlin SDK build failed"
        exit 1
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    log_header "RunAnywhere Kotlin SDK - Build"

    echo "Project:        ${KOTLIN_SDK_DIR}"
    echo "Commons:        ${COMMONS_DIR}"
    echo "Mode:           ${MODE}"
    echo "Setup:          ${SETUP_MODE}"
    echo "Rebuild Commons: ${REBUILD_COMMONS}"
    echo "ABIs:           ${ABIS}"
    echo ""

    validate_environment

    # ==========================================================================
    # Setup Mode: Full first-time setup
    # ==========================================================================
    if [ "$SETUP_MODE" = true ]; then
        log_header "Running Initial Setup for Local Development"

        # 1. Download dependencies
        download_dependencies

        # 2. Build commons
        build_commons

        # 3. Copy JNI libs
        copy_jni_libs

        # 4. Set local mode
        set_gradle_mode "local"

        log_info "Initial setup complete!"
    else
        # ==========================================================================
        # Normal Mode: Check what needs to be done
        # ==========================================================================

        # Set mode if specified
        if [ "$MODE" = "local" ]; then
            set_gradle_mode "local"
        elif [ "$MODE" = "remote" ]; then
            set_gradle_mode "remote"
        fi

        # In local mode, check if we need to rebuild
        if [ "$MODE" = "local" ]; then
            local need_rebuild=false

            # Check if libs exist
            for abi in $(echo "${ABIS}" | tr ',' ' '); do
                if ! check_libs_exist "$abi"; then
                    log_warn "JNI libs missing for $abi - need to build"
                    need_rebuild=true
                    break
                fi
            done

            # Check if commons changed
            if [ "$REBUILD_COMMONS" = true ]; then
                log_info "Forced rebuild of commons"
                need_rebuild=true
            elif check_commons_changed; then
                log_warn "Commons source changed - need to rebuild"
                need_rebuild=true
            fi

            if [ "$need_rebuild" = true ]; then
                download_dependencies
                build_commons
                copy_jni_libs
            else
                log_info "JNI libs up to date (use --rebuild-commons to force)"
            fi
        fi
    fi

    # ==========================================================================
    # Build SDK
    # ==========================================================================
    if [ "$SKIP_BUILD" = false ]; then
        build_sdk
    else
        log_info "Skipping Gradle build (--skip-build)"
    fi

    # ==========================================================================
    # Summary
    # ==========================================================================
    log_header "Build Complete!"

    echo ""
    echo "JNI Libraries:"
    for dir in "$MAIN_JNILIBS_DIR" "$LLAMACPP_JNILIBS_DIR" "$ONNX_JNILIBS_DIR"; do
        if [ -d "$dir" ]; then
            local count=$(find "$dir" -name "*.so" 2>/dev/null | wc -l | tr -d ' ')
            local size=$(du -sh "$dir" 2>/dev/null | cut -f1)
            local name=$(basename "$(dirname "$dir")")
            echo "  $(basename "$dir"): ${count} libs (${size})"
        fi
    done

    echo ""
    echo "gradle.properties: runanywhere.testLocal=$(grep 'runanywhere.testLocal' "${KOTLIN_SDK_DIR}/gradle.properties" | cut -d= -f2)"
    echo ""

    if [ "$MODE" = "local" ]; then
        echo "Next steps:"
        echo "  1. Open project in Android Studio"
        echo "  2. Sync Gradle"
        echo "  3. Build and run on device"
        echo ""
        echo "To rebuild after C++ changes:"
        echo "  ./scripts/build-kotlin.sh --local --rebuild-commons"
    fi
}

main
