#!/bin/bash
# =============================================================================
# RunAnywhere Commons - iOS (+ macOS) Build Script
# =============================================================================
#
# Builds everything for iOS: RACommons + Backend frameworks.
# Optionally includes macOS native builds with --include-macos.
#
# USAGE:
#   ./scripts/build-ios.sh [options]
#
# OPTIONS:
#   --skip-download     Skip downloading dependencies
#   --skip-backends     Build RACommons only, skip backend frameworks
#   --backend NAME      Build specific backend: llamacpp, onnx, sdcpp, all (default: all)
#                       - llamacpp: LLM text generation (GGUF models)
#                       - onnx: STT/TTS/VAD (Sherpa-ONNX models)
#                       - sdcpp: Diffusion image generation (stable-diffusion.cpp, Metal)
#                       - all: All backends (default)
#   --skip-macos        Skip macOS build (iOS only). macOS is included by default.
#   --clean             Clean build directories first
#   --release           Release build (default)
#   --debug             Debug build
#   --package           Create release ZIP packages
#   --help              Show this help
#
# OUTPUTS:
#   dist/RACommons.xcframework                 (always built)
#   dist/RABackendLLAMACPP.xcframework         (if --backend llamacpp or all)
#   dist/RABackendONNX.xcframework             (if --backend onnx or all)
#   dist/RABackendSDCPP.xcframework            (if --backend sdcpp or all)
#
# EXAMPLES:
#   # Full build (all backends, iOS only)
#   ./scripts/build-ios.sh
#
#   # Full build with macOS support (iOS + macOS slices)
#   ./scripts/build-ios.sh --include-macos
#
#   # Build only LlamaCPP backend (LLM/text generation)
#   ./scripts/build-ios.sh --backend llamacpp
#
#   # Build only ONNX backend (speech-to-text/text-to-speech)
#   ./scripts/build-ios.sh --backend onnx
#
#   # Build only sd.cpp backend (diffusion image generation)
#   ./scripts/build-ios.sh --backend sdcpp
#
#   # Build only RACommons (no backends)
#   ./scripts/build-ios.sh --skip-backends
#
#   # Other useful combinations
#   ./scripts/build-ios.sh --skip-download    # Use cached dependencies
#   ./scripts/build-ios.sh --clean --package  # Clean build with packaging
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build/ios"
DIST_DIR="${PROJECT_ROOT}/dist"

# Load versions
source "${SCRIPT_DIR}/load-versions.sh"

# Get version
VERSION=$(cat "${PROJECT_ROOT}/VERSION" 2>/dev/null | head -1 || echo "0.1.0")

# Options
SKIP_DOWNLOAD=false
SKIP_BACKENDS=false
BUILD_BACKEND="all"
INCLUDE_MACOS=true
CLEAN_BUILD=false
BUILD_TYPE="Release"
CREATE_PACKAGE=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()   { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn()   { echo -e "${YELLOW}[!]${NC} $1"; }
log_error()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }
log_step()   { echo -e "${BLUE}==>${NC} $1"; }
log_time()   { echo -e "${CYAN}[⏱]${NC} $1"; }
log_header() { echo -e "\n${GREEN}═══════════════════════════════════════════${NC}"; echo -e "${GREEN} $1${NC}"; echo -e "${GREEN}═══════════════════════════════════════════${NC}"; }
require_cmd() {
    local cmd="$1"
    local hint="$2"
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        log_warn "Required tool '${cmd}' is not installed or not in PATH."
        [[ -n "${hint}" ]] && log_warn "${hint}"
        log_error "Cannot continue without '${cmd}'."
    fi
}

show_help() {
    head -45 "$0" | tail -40
    exit 0
}

# =============================================================================
# Parse Arguments
# =============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-download) SKIP_DOWNLOAD=true; shift ;;
        --skip-backends) SKIP_BACKENDS=true; shift ;;
        --backend) BUILD_BACKEND="$2"; shift 2 ;;
        --include-macos) INCLUDE_MACOS=true; shift ;;
        --skip-macos) INCLUDE_MACOS=false; shift ;;
        --clean) CLEAN_BUILD=true; shift ;;
        --release) BUILD_TYPE="Release"; shift ;;
        --debug) BUILD_TYPE="Debug"; shift ;;
        --package) CREATE_PACKAGE=true; shift ;;
        --help|-h) show_help ;;
        *) log_error "Unknown option: $1" ;;
    esac
done

# Timing
TOTAL_START=$(date +%s)

# =============================================================================
# Download Dependencies
# =============================================================================

download_deps() {
    log_header "Downloading iOS Dependencies"

    # ONNX Runtime
    if [[ ! -d "${PROJECT_ROOT}/third_party/onnxruntime-ios/onnxruntime.xcframework" ]]; then
        log_step "Downloading ONNX Runtime..."
        "${SCRIPT_DIR}/ios/download-onnx.sh"
    else
        log_info "ONNX Runtime already present"
    fi

    # Sherpa-ONNX
    if [[ ! -d "${PROJECT_ROOT}/third_party/sherpa-onnx-ios/sherpa-onnx.xcframework" ]]; then
        log_step "Downloading Sherpa-ONNX..."
        "${SCRIPT_DIR}/ios/download-sherpa-onnx.sh"
    else
        log_info "Sherpa-ONNX already present"
    fi
}

# =============================================================================
# Download macOS Dependencies
# =============================================================================

download_macos_deps() {
    log_header "Downloading macOS Dependencies"

    # ONNX Runtime for macOS
    if [[ ! -d "${PROJECT_ROOT}/third_party/onnxruntime-macos/lib" ]]; then
        log_step "Downloading ONNX Runtime for macOS..."
        "${SCRIPT_DIR}/macos/download-onnx.sh"
    else
        log_info "ONNX Runtime macOS already present"
    fi

    # Sherpa-ONNX static for macOS (builds from source if needed)
    if [[ ! -f "${PROJECT_ROOT}/third_party/sherpa-onnx-macos/lib/libsherpa-onnx-c-api.a" ]]; then
        log_step "Building Sherpa-ONNX static for macOS..."
        "${SCRIPT_DIR}/macos/download-sherpa-onnx.sh"
    else
        log_info "Sherpa-ONNX macOS already present"
    fi
}

# =============================================================================
# Build for macOS (native, no toolchain needed)
# =============================================================================

build_macos() {
    local PLATFORM_DIR="${BUILD_DIR}/MACOS"

    log_step "Building for macOS (native arm64)..."
    require_cmd "cmake" "Install it with: brew install cmake"
    mkdir -p "${PLATFORM_DIR}"
    cd "${PLATFORM_DIR}"

    # Determine backend flags (same logic as iOS)
    local BACKEND_FLAGS=""
    if [[ "$SKIP_BACKENDS" == true ]]; then
        BACKEND_FLAGS="-DRAC_BUILD_BACKENDS=OFF"
    else
        BACKEND_FLAGS="-DRAC_BUILD_BACKENDS=ON"
        case "$BUILD_BACKEND" in
            llamacpp)
                BACKEND_FLAGS="$BACKEND_FLAGS -DRAC_BACKEND_LLAMACPP=ON -DRAC_BACKEND_ONNX=OFF -DRAC_BACKEND_WHISPERCPP=OFF -DRAC_BACKEND_SDCPP=OFF"
                ;;
            onnx)
                BACKEND_FLAGS="$BACKEND_FLAGS -DRAC_BACKEND_LLAMACPP=OFF -DRAC_BACKEND_ONNX=ON -DRAC_BACKEND_WHISPERCPP=OFF -DRAC_BACKEND_SDCPP=OFF"
                ;;
            sdcpp)
                BACKEND_FLAGS="$BACKEND_FLAGS -DRAC_BACKEND_LLAMACPP=OFF -DRAC_BACKEND_ONNX=OFF -DRAC_BACKEND_WHISPERCPP=OFF -DRAC_BACKEND_SDCPP=ON"
                ;;
            all|*)
                BACKEND_FLAGS="$BACKEND_FLAGS -DRAC_BACKEND_LLAMACPP=ON -DRAC_BACKEND_ONNX=ON -DRAC_BACKEND_WHISPERCPP=OFF -DRAC_BACKEND_SDCPP=ON"
                ;;
        esac
    fi

    # Native macOS build - NO toolchain file needed
    cmake "${PROJECT_ROOT}" \
        -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
        -DCMAKE_OSX_ARCHITECTURES="arm64" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="14.0" \
        -DRAC_BUILD_PLATFORM=ON \
        -DRAC_BUILD_SHARED=OFF \
        -DRAC_BUILD_JNI=OFF \
        $BACKEND_FLAGS

    cmake --build . --config "${BUILD_TYPE}" -j"$(sysctl -n hw.ncpu)"

    cd "${PROJECT_ROOT}"
    log_info "Built macOS arm64"
}

# =============================================================================
# Build for iOS Platform
# =============================================================================

build_platform() {
    local PLATFORM=$1
    local PLATFORM_DIR="${BUILD_DIR}/${PLATFORM}"

    log_step "Building for ${PLATFORM}..."
    require_cmd "cmake" "Install it with: brew install cmake (macOS) or: sudo apt-get install cmake (Debian/Ubuntu)"
    mkdir -p "${PLATFORM_DIR}"
    cd "${PLATFORM_DIR}"

    # Determine backend flags
    local BACKEND_FLAGS=""
    if [[ "$SKIP_BACKENDS" == true ]]; then
        BACKEND_FLAGS="-DRAC_BUILD_BACKENDS=OFF"
    else
        BACKEND_FLAGS="-DRAC_BUILD_BACKENDS=ON"
        case "$BUILD_BACKEND" in
            llamacpp)
                BACKEND_FLAGS="$BACKEND_FLAGS -DRAC_BACKEND_LLAMACPP=ON -DRAC_BACKEND_ONNX=OFF -DRAC_BACKEND_WHISPERCPP=OFF -DRAC_BACKEND_SDCPP=OFF"
                ;;
            onnx)
                BACKEND_FLAGS="$BACKEND_FLAGS -DRAC_BACKEND_LLAMACPP=OFF -DRAC_BACKEND_ONNX=ON -DRAC_BACKEND_WHISPERCPP=OFF -DRAC_BACKEND_SDCPP=OFF"
                ;;
            sdcpp)
                BACKEND_FLAGS="$BACKEND_FLAGS -DRAC_BACKEND_LLAMACPP=OFF -DRAC_BACKEND_ONNX=OFF -DRAC_BACKEND_WHISPERCPP=OFF -DRAC_BACKEND_SDCPP=ON"
                ;;
            all|*)
                BACKEND_FLAGS="$BACKEND_FLAGS -DRAC_BACKEND_LLAMACPP=ON -DRAC_BACKEND_ONNX=ON -DRAC_BACKEND_WHISPERCPP=OFF -DRAC_BACKEND_SDCPP=ON"
                ;;
        esac
    fi

    # BLAS (Accelerate) works on device but FindBLAS fails during simulator
    # cross-compilation. Disable BLAS for simulator targets.
    local BLAS_FLAGS="-DGGML_BLAS=ON -DGGML_BLAS_VENDOR=Apple"
    if [[ "$PLATFORM" == "SIMULATOR"* ]]; then
        BLAS_FLAGS="-DGGML_BLAS=OFF"
    fi

    cmake "${PROJECT_ROOT}" \
        -DCMAKE_TOOLCHAIN_FILE="${PROJECT_ROOT}/cmake/ios.toolchain.cmake" \
        -DIOS_PLATFORM="${PLATFORM}" \
        -DIOS_DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET}" \
        -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
        -DRAC_BUILD_PLATFORM=ON \
        -DRAC_BUILD_SHARED=OFF \
        -DRAC_BUILD_JNI=OFF \
        $BLAS_FLAGS \
        $BACKEND_FLAGS

    cmake --build . --config "${BUILD_TYPE}" -j"$(sysctl -n hw.ncpu)"

    cd "${PROJECT_ROOT}"
    log_info "Built ${PLATFORM}"
}

# =============================================================================
# Create macOS Versioned Framework Bundle
# =============================================================================
# macOS frameworks require a versioned layout:
#   Framework.framework/Versions/A/{binary,Headers,Modules,Resources}
#   Framework.framework/{binary,Headers,Modules,Resources} -> Versions/Current/...

create_macos_versioned_framework() {
    local SRC_DIR=$1       # Flat framework dir with binary, Headers/, Modules/
    local FRAMEWORK_NAME=$2

    local FLAT="${SRC_DIR}/${FRAMEWORK_NAME}.framework"
    local VERSIONED="${SRC_DIR}/${FRAMEWORK_NAME}.framework.versioned"

    mkdir -p "${VERSIONED}/Versions/A/Headers"
    mkdir -p "${VERSIONED}/Versions/A/Modules"
    mkdir -p "${VERSIONED}/Versions/A/Resources"

    # Copy binary
    cp "${FLAT}/${FRAMEWORK_NAME}" "${VERSIONED}/Versions/A/${FRAMEWORK_NAME}"

    # Copy headers
    cp -R "${FLAT}/Headers/"* "${VERSIONED}/Versions/A/Headers/" 2>/dev/null || true

    # Copy modules
    cp -R "${FLAT}/Modules/"* "${VERSIONED}/Versions/A/Modules/" 2>/dev/null || true

    # Move Info.plist to Resources
    cp "${FLAT}/Info.plist" "${VERSIONED}/Versions/A/Resources/Info.plist"

    # Create Current symlink
    cd "${VERSIONED}/Versions"
    ln -sf A Current
    cd "${VERSIONED}"

    # Create top-level symlinks
    ln -sf Versions/Current/${FRAMEWORK_NAME} ${FRAMEWORK_NAME}
    ln -sf Versions/Current/Headers Headers
    ln -sf Versions/Current/Modules Modules
    ln -sf Versions/Current/Resources Resources

    cd "${PROJECT_ROOT}"

    # Replace flat framework with versioned
    rm -rf "${FLAT}"
    mv "${VERSIONED}" "${FLAT}"

    # Ad-hoc sign the framework binary so Xcode codesigning succeeds
    codesign --force --sign - "${FLAT}/Versions/A/${FRAMEWORK_NAME}" 2>/dev/null || true
}

# =============================================================================
# Create XCFramework
# =============================================================================

create_xcframework() {
    local LIB_NAME=$1
    local FRAMEWORK_NAME=$2

    log_step "Creating ${FRAMEWORK_NAME}.xcframework..."

    # Platforms to build frameworks for (iOS always, macOS if requested)
    local PLATFORMS="OS SIMULATORARM64 SIMULATOR"
    if [[ "$INCLUDE_MACOS" == true ]]; then
        PLATFORMS="$PLATFORMS MACOS"
    fi

    # Create framework for each platform
    for PLATFORM in $PLATFORMS; do
        local PLATFORM_DIR="${BUILD_DIR}/${PLATFORM}"
        local FRAMEWORK_DIR="${PLATFORM_DIR}/${FRAMEWORK_NAME}.framework"

        mkdir -p "${FRAMEWORK_DIR}/Headers"
        mkdir -p "${FRAMEWORK_DIR}/Modules"

        # Find the library
        local LIB_PATH="${PLATFORM_DIR}/lib${LIB_NAME}.a"
        [[ ! -f "${LIB_PATH}" ]] && LIB_PATH="${PLATFORM_DIR}/src/backends/${BUILD_BACKEND}/lib${LIB_NAME}.a"

        if [[ ! -f "${LIB_PATH}" ]]; then
            log_warn "Library not found: ${LIB_PATH}"
            return 1
        fi

        cp "${LIB_PATH}" "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}"

        # Copy headers
        if [[ "$FRAMEWORK_NAME" == "RACommons" ]]; then
            find "${PROJECT_ROOT}/include/rac" -name "*.h" | while read -r header; do
                local filename=$(basename "$header")
                sed -e 's|#include "rac/[^"]*\/\([^"]*\)"|#include <RACommons/\1>|g' \
                    "$header" > "${FRAMEWORK_DIR}/Headers/${filename}"
            done
        else
            # Backend headers
            local backend_name=$(echo "$LIB_NAME" | sed 's/rac_backend_//')
            local header_src="${PROJECT_ROOT}/include/rac/backends/rac_${backend_name}.h"
            [[ -f "$header_src" ]] && cp "$header_src" "${FRAMEWORK_DIR}/Headers/"
        fi

        # Module map
        cat > "${FRAMEWORK_DIR}/Modules/module.modulemap" << EOF
framework module ${FRAMEWORK_NAME} {
    umbrella header "${FRAMEWORK_NAME}.h"
    export *
    module * { export * }
}
EOF

        # Umbrella header
        echo "// ${FRAMEWORK_NAME} Umbrella Header" > "${FRAMEWORK_DIR}/Headers/${FRAMEWORK_NAME}.h"
        echo "#ifndef ${FRAMEWORK_NAME}_h" >> "${FRAMEWORK_DIR}/Headers/${FRAMEWORK_NAME}.h"
        echo "#define ${FRAMEWORK_NAME}_h" >> "${FRAMEWORK_DIR}/Headers/${FRAMEWORK_NAME}.h"
        for h in "${FRAMEWORK_DIR}/Headers/"*.h; do
            [[ "$(basename "$h")" != "${FRAMEWORK_NAME}.h" ]] && \
                echo "#include \"$(basename "$h")\"" >> "${FRAMEWORK_DIR}/Headers/${FRAMEWORK_NAME}.h"
        done
        echo "#endif" >> "${FRAMEWORK_DIR}/Headers/${FRAMEWORK_NAME}.h"

        # Info.plist
        local MIN_OS_KEY="MinimumOSVersion"
        local MIN_OS_VAL="${IOS_DEPLOYMENT_TARGET}"
        if [[ "$PLATFORM" == "MACOS" ]]; then
            MIN_OS_KEY="LSMinimumSystemVersion"
            MIN_OS_VAL="14.0"
        fi
        cat > "${FRAMEWORK_DIR}/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>${FRAMEWORK_NAME}</string>
    <key>CFBundleIdentifier</key><string>ai.runanywhere.${FRAMEWORK_NAME}</string>
    <key>CFBundlePackageType</key><string>FMWK</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>${MIN_OS_KEY}</key><string>${MIN_OS_VAL}</string>
</dict>
</plist>
EOF
    done

    # Create fat simulator
    local SIM_FAT="${BUILD_DIR}/SIMULATOR_FAT_${FRAMEWORK_NAME}"
    mkdir -p "${SIM_FAT}"
    cp -R "${BUILD_DIR}/SIMULATORARM64/${FRAMEWORK_NAME}.framework" "${SIM_FAT}/"

    lipo -create \
        "${BUILD_DIR}/SIMULATORARM64/${FRAMEWORK_NAME}.framework/${FRAMEWORK_NAME}" \
        "${BUILD_DIR}/SIMULATOR/${FRAMEWORK_NAME}.framework/${FRAMEWORK_NAME}" \
        -output "${SIM_FAT}/${FRAMEWORK_NAME}.framework/${FRAMEWORK_NAME}"

    # Create XCFramework (iOS + optionally macOS)
    local XCFW_PATH="${DIST_DIR}/${FRAMEWORK_NAME}.xcframework"
    rm -rf "${XCFW_PATH}"

    local XCFW_ARGS=(
        -framework "${BUILD_DIR}/OS/${FRAMEWORK_NAME}.framework"
        -framework "${SIM_FAT}/${FRAMEWORK_NAME}.framework"
    )

    if [[ "$INCLUDE_MACOS" == true && -f "${BUILD_DIR}/MACOS/${FRAMEWORK_NAME}.framework/${FRAMEWORK_NAME}" ]]; then
        create_macos_versioned_framework "${BUILD_DIR}/MACOS" "${FRAMEWORK_NAME}"
        XCFW_ARGS+=(-framework "${BUILD_DIR}/MACOS/${FRAMEWORK_NAME}.framework")
        log_info "Including macOS slice in ${FRAMEWORK_NAME}.xcframework"
    fi

    xcodebuild -create-xcframework "${XCFW_ARGS[@]}" -output "${XCFW_PATH}"

    log_info "Created: ${XCFW_PATH}"
    echo "  Size: $(du -sh "${XCFW_PATH}" | cut -f1)"
}

# =============================================================================
# Create Backend XCFramework (bundles dependencies)
# =============================================================================

create_backend_xcframework() {
    local BACKEND_NAME=$1
    local FRAMEWORK_NAME=$2

    log_step "Creating ${FRAMEWORK_NAME}.xcframework (bundled)..."

    local FOUND_ANY=false

    # Platforms to build frameworks for (iOS always, macOS if requested)
    local PLATFORMS="OS SIMULATORARM64 SIMULATOR"
    if [[ "$INCLUDE_MACOS" == true ]]; then
        PLATFORMS="$PLATFORMS MACOS"
    fi

    for PLATFORM in $PLATFORMS; do
        local PLATFORM_DIR="${BUILD_DIR}/${PLATFORM}"
        local FRAMEWORK_DIR="${PLATFORM_DIR}/${FRAMEWORK_NAME}.framework"

        mkdir -p "${FRAMEWORK_DIR}/Headers"
        mkdir -p "${FRAMEWORK_DIR}/Modules"

        # Collect all libraries to bundle
        local LIBS_TO_BUNDLE=()

        # Backend library - check multiple possible locations
        local BACKEND_LIB=""
        for possible_path in \
            "${PLATFORM_DIR}/src/backends/${BACKEND_NAME}/librac_backend_${BACKEND_NAME}.a" \
            "${PLATFORM_DIR}/librac_backend_${BACKEND_NAME}.a" \
            "${PLATFORM_DIR}/backends/${BACKEND_NAME}/librac_backend_${BACKEND_NAME}.a"; do
            if [[ -f "$possible_path" ]]; then
                BACKEND_LIB="$possible_path"
                break
            fi
        done
        [[ -n "$BACKEND_LIB" ]] && LIBS_TO_BUNDLE+=("$BACKEND_LIB")

        if [[ "$BACKEND_NAME" == "llamacpp" ]]; then
            # Bundle llama.cpp libraries
            local LLAMA_BUILD="${PLATFORM_DIR}/src/backends/llamacpp/_deps/llamacpp-build"
            [[ ! -d "$LLAMA_BUILD" ]] && LLAMA_BUILD="${PLATFORM_DIR}/_deps/llamacpp-build"

            for lib in llama common ggml ggml-base ggml-cpu ggml-metal ggml-blas; do
                local lib_path=""
                for possible in \
                    "${LLAMA_BUILD}/src/lib${lib}.a" \
                    "${LLAMA_BUILD}/common/lib${lib}.a" \
                    "${LLAMA_BUILD}/ggml/src/lib${lib}.a" \
                    "${LLAMA_BUILD}/ggml/src/ggml-metal/lib${lib}.a" \
                    "${LLAMA_BUILD}/ggml/src/ggml-blas/lib${lib}.a" \
                    "${LLAMA_BUILD}/ggml/src/ggml-cpu/lib${lib}.a"; do
                    if [[ -f "$possible" ]]; then
                        lib_path="$possible"
                        break
                    fi
                done
                [[ -n "$lib_path" ]] && LIBS_TO_BUNDLE+=("$lib_path")
            done
        elif [[ "$BACKEND_NAME" == "sdcpp" ]]; then
            # Bundle stable-diffusion.cpp + ggml libraries (Metal GPU on Apple)
            local SDCPP_BUILD="${PLATFORM_DIR}/src/backends/sdcpp/_deps/stable_diffusion_cpp-build"
            [[ ! -d "$SDCPP_BUILD" ]] && SDCPP_BUILD="${PLATFORM_DIR}/_deps/stable_diffusion_cpp-build"

            # stable-diffusion.cpp main library
            for possible in \
                "${SDCPP_BUILD}/libstable-diffusion.a" \
                "${SDCPP_BUILD}/src/libstable-diffusion.a"; do
                if [[ -f "$possible" ]]; then
                    LIBS_TO_BUNDLE+=("$possible")
                    break
                fi
            done

            # ggml libraries (shared with sd.cpp, includes Metal backend)
            for lib in ggml ggml-base ggml-cpu ggml-metal; do
                local lib_path=""
                for possible in \
                    "${SDCPP_BUILD}/ggml/src/lib${lib}.a" \
                    "${SDCPP_BUILD}/ggml/src/ggml-metal/lib${lib}.a" \
                    "${SDCPP_BUILD}/ggml/src/ggml-cpu/lib${lib}.a"; do
                    if [[ -f "$possible" ]]; then
                        lib_path="$possible"
                        break
                    fi
                done
                [[ -n "$lib_path" ]] && LIBS_TO_BUNDLE+=("$lib_path")
            done
        elif [[ "$BACKEND_NAME" == "onnx" ]]; then
            if [[ "$PLATFORM" == "MACOS" ]]; then
                # Bundle Sherpa-ONNX static libs for macOS
                local SHERPA_MACOS="${PROJECT_ROOT}/third_party/sherpa-onnx-macos"
                if [[ -f "${SHERPA_MACOS}/lib/libsherpa-onnx-c-api.a" ]]; then
                    LIBS_TO_BUNDLE+=("${SHERPA_MACOS}/lib/libsherpa-onnx-c-api.a")
                    # Also bundle all dependency static libs
                    for dep_lib in \
                        sherpa-onnx-core sherpa-onnx-fst sherpa-onnx-fstfar \
                        sherpa-onnx-kaldifst-core kaldi-decoder-core kaldi-native-fbank-core \
                        piper_phonemize espeak-ng ucd cppinyin_core ssentencepiece_core kissfft-float; do
                        if [[ -f "${SHERPA_MACOS}/lib/lib${dep_lib}.a" ]]; then
                            LIBS_TO_BUNDLE+=("${SHERPA_MACOS}/lib/lib${dep_lib}.a")
                        fi
                    done
                fi
            else
                # Bundle Sherpa-ONNX for iOS
                local SHERPA_XCFW="${PROJECT_ROOT}/third_party/sherpa-onnx-ios/sherpa-onnx.xcframework"
                local SHERPA_ARCH
                case $PLATFORM in
                    OS) SHERPA_ARCH="ios-arm64" ;;
                    *) SHERPA_ARCH="ios-arm64_x86_64-simulator" ;;
                esac
                # Try both .a and framework binary
                for possible in \
                    "${SHERPA_XCFW}/${SHERPA_ARCH}/libsherpa-onnx.a" \
                    "${SHERPA_XCFW}/${SHERPA_ARCH}/sherpa-onnx.framework/sherpa-onnx"; do
                    if [[ -f "$possible" ]]; then
                        LIBS_TO_BUNDLE+=("$possible")
                        break
                    fi
                done
            fi
        fi

        # Bundle all libraries
        if [[ ${#LIBS_TO_BUNDLE[@]} -gt 0 ]]; then
            log_info "  ${PLATFORM}: Bundling ${#LIBS_TO_BUNDLE[@]} libraries"
            libtool -static -o "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}" "${LIBS_TO_BUNDLE[@]}"
            FOUND_ANY=true
        else
            log_warn "No libraries found for ${BACKEND_NAME} on ${PLATFORM}"
            continue
        fi

        # Headers — find backend header (may use different naming convention)
        local header_src=""
        for possible_header in \
            "${PROJECT_ROOT}/include/rac/backends/rac_${BACKEND_NAME}.h" \
            "${PROJECT_ROOT}/include/rac/backends/rac_diffusion_${BACKEND_NAME}.h" \
            "${PROJECT_ROOT}/include/rac/backends/rac_llm_${BACKEND_NAME}.h" \
            "${PROJECT_ROOT}/include/rac/backends/rac_stt_${BACKEND_NAME}.h"; do
            if [[ -f "$possible_header" ]]; then
                header_src="$possible_header"
                break
            fi
        done
        local header_filename=""
        if [[ -n "$header_src" ]]; then
            header_filename=$(basename "$header_src")
            cp "$header_src" "${FRAMEWORK_DIR}/Headers/"
        fi

        # Module map and umbrella header
        cat > "${FRAMEWORK_DIR}/Modules/module.modulemap" << EOF
framework module ${FRAMEWORK_NAME} {
    umbrella header "${FRAMEWORK_NAME}.h"
    export *
    module * { export * }
}
EOF
        echo "// ${FRAMEWORK_NAME}" > "${FRAMEWORK_DIR}/Headers/${FRAMEWORK_NAME}.h"
        if [[ -n "$header_filename" ]]; then
            echo "#include \"${header_filename}\"" >> "${FRAMEWORK_DIR}/Headers/${FRAMEWORK_NAME}.h"
        fi

        # Info.plist
        local MIN_OS_KEY="MinimumOSVersion"
        local MIN_OS_VAL="${IOS_DEPLOYMENT_TARGET}"
        if [[ "$PLATFORM" == "MACOS" ]]; then
            MIN_OS_KEY="LSMinimumSystemVersion"
            MIN_OS_VAL="14.0"
        fi
        cat > "${FRAMEWORK_DIR}/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>${FRAMEWORK_NAME}</string>
    <key>CFBundleIdentifier</key><string>ai.runanywhere.${FRAMEWORK_NAME}</string>
    <key>CFBundlePackageType</key><string>FMWK</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>${MIN_OS_KEY}</key><string>${MIN_OS_VAL}</string>
</dict>
</plist>
EOF
    done

    if [[ "$FOUND_ANY" == false ]]; then
        log_warn "Skipping ${FRAMEWORK_NAME}.xcframework - no libraries found"
        return 0
    fi

    # Create fat simulator
    local SIM_FAT="${BUILD_DIR}/SIMULATOR_FAT_${FRAMEWORK_NAME}"
    rm -rf "${SIM_FAT}"
    mkdir -p "${SIM_FAT}"
    cp -R "${BUILD_DIR}/SIMULATORARM64/${FRAMEWORK_NAME}.framework" "${SIM_FAT}/"

    lipo -create \
        "${BUILD_DIR}/SIMULATORARM64/${FRAMEWORK_NAME}.framework/${FRAMEWORK_NAME}" \
        "${BUILD_DIR}/SIMULATOR/${FRAMEWORK_NAME}.framework/${FRAMEWORK_NAME}" \
        -output "${SIM_FAT}/${FRAMEWORK_NAME}.framework/${FRAMEWORK_NAME}" 2>/dev/null || true

    # Create XCFramework (iOS + optionally macOS)
    local XCFW_PATH="${DIST_DIR}/${FRAMEWORK_NAME}.xcframework"
    rm -rf "${XCFW_PATH}"

    if [[ -f "${BUILD_DIR}/OS/${FRAMEWORK_NAME}.framework/${FRAMEWORK_NAME}" ]]; then
        local XCFW_ARGS=(
            -framework "${BUILD_DIR}/OS/${FRAMEWORK_NAME}.framework"
            -framework "${SIM_FAT}/${FRAMEWORK_NAME}.framework"
        )

        if [[ "$INCLUDE_MACOS" == true && -f "${BUILD_DIR}/MACOS/${FRAMEWORK_NAME}.framework/${FRAMEWORK_NAME}" ]]; then
            create_macos_versioned_framework "${BUILD_DIR}/MACOS" "${FRAMEWORK_NAME}"
            XCFW_ARGS+=(-framework "${BUILD_DIR}/MACOS/${FRAMEWORK_NAME}.framework")
            log_info "Including macOS slice in ${FRAMEWORK_NAME}.xcframework"
        fi

        xcodebuild -create-xcframework "${XCFW_ARGS[@]}" -output "${XCFW_PATH}"

        log_info "Created: ${XCFW_PATH}"
        echo "  Size: $(du -sh "${XCFW_PATH}" | cut -f1)"
    else
        log_warn "Could not create ${FRAMEWORK_NAME}.xcframework"
    fi
}

# =============================================================================
# Package for Release
# =============================================================================

create_packages() {
    log_header "Creating Release Packages"

    local PKG_DIR="${DIST_DIR}/packages"
    mkdir -p "${PKG_DIR}"

    for xcfw in "${DIST_DIR}"/*.xcframework; do
        if [[ -d "$xcfw" ]]; then
            local name=$(basename "$xcfw" .xcframework)
            local pkg_name="${name}-ios-v${VERSION}.zip"
            log_step "Packaging ${name}..."
            cd "${DIST_DIR}"
            zip -r "packages/${pkg_name}" "$(basename "$xcfw")"
            cd "${PKG_DIR}"
            shasum -a 256 "${pkg_name}" > "${pkg_name}.sha256"
            cd "${PROJECT_ROOT}"
            log_info "Created: ${pkg_name}"
        fi
    done
}

# =============================================================================
# Main
# =============================================================================

main() {
    log_header "RunAnywhere Commons - iOS Build"
    echo "Version:        ${VERSION}"
    echo "Build Type:     ${BUILD_TYPE}"
    echo "Backends:       ${BUILD_BACKEND}"
    echo "Include macOS:  ${INCLUDE_MACOS}"
    echo "Skip Download:  ${SKIP_DOWNLOAD}"
    echo "Skip Backends:  ${SKIP_BACKENDS}"
    echo ""

    # Clean if requested
    if [[ "$CLEAN_BUILD" == true ]]; then
        log_step "Cleaning build directory..."
        rm -rf "${BUILD_DIR}"
        rm -rf "${DIST_DIR}"
    fi

    mkdir -p "${DIST_DIR}"

    # Step 1: Download dependencies
    if [[ "$SKIP_DOWNLOAD" != true ]]; then
        download_deps
        if [[ "$INCLUDE_MACOS" == true ]]; then
            download_macos_deps
        fi
    fi

    # Step 2: Build for all iOS platforms
    log_header "Building for iOS"
    build_platform "OS"
    build_platform "SIMULATORARM64"
    build_platform "SIMULATOR"

    # Step 2b: Build for macOS if requested
    if [[ "$INCLUDE_MACOS" == true ]]; then
        log_header "Building for macOS"
        build_macos
    fi

    # Step 3: Create RACommons.xcframework
    log_header "Creating XCFrameworks"
    create_xcframework "rac_commons" "RACommons"

    # Step 4: Create backend XCFrameworks
    if [[ "$SKIP_BACKENDS" != true ]]; then
        if [[ "$BUILD_BACKEND" == "all" || "$BUILD_BACKEND" == "llamacpp" ]]; then
            create_backend_xcframework "llamacpp" "RABackendLLAMACPP"
        fi
        if [[ "$BUILD_BACKEND" == "all" || "$BUILD_BACKEND" == "onnx" ]]; then
            create_backend_xcframework "onnx" "RABackendONNX"
        fi
        if [[ "$BUILD_BACKEND" == "all" || "$BUILD_BACKEND" == "sdcpp" ]]; then
            create_backend_xcframework "sdcpp" "RABackendSDCPP"
        fi
    fi

    # Step 5: Package if requested
    if [[ "$CREATE_PACKAGE" == true ]]; then
        create_packages
    fi

    # Summary
    local TOTAL_TIME=$(($(date +%s) - TOTAL_START))
    log_header "Build Complete!"
    echo ""
    echo "Output: ${DIST_DIR}/"
    for xcfw in "${DIST_DIR}"/*.xcframework; do
        [[ -d "$xcfw" ]] && echo "  $(du -sh "$xcfw" | cut -f1)  $(basename "$xcfw")"
    done
    if [[ "$INCLUDE_MACOS" == true ]]; then
        echo ""
        echo "✅ XCFrameworks include macOS arm64 slices"
    fi
    echo ""
    log_time "Total build time: ${TOTAL_TIME}s"
}

main "$@"
