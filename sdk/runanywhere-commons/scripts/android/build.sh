#!/bin/bash

# =============================================================================
# build-android.sh
# Unified Android build script - builds JNI bridge + selected backends
#
# Usage: ./build-android.sh [options] [backends] [abis]
#        backends: onnx | llamacpp | whispercpp | tflite | all (default: all)
#        abis: comma-separated list (default: arm64-v8a)
#
# Options:
#   --check   Check 16KB alignment of existing libraries in dist/
#   --help    Show this help message
#
# Examples:
#   ./build-android.sh                    # Build all backends
#   ./build-android.sh --check            # Verify 16KB alignment
#   ./build-android.sh onnx               # Build only ONNX backend
#
# 16KB Page Size Alignment (Google Play deadline: November 1, 2025):
#   ✅ Sherpa-ONNX v1.12.20+ pre-built binaries ARE 16KB aligned!
#      (Fixed in https://github.com/k2-fsa/sherpa-onnx/pull/2520)
#   ✅ This script uses Sherpa-ONNX's bundled libonnxruntime.so for ONNX backend
#   ✅ CMake builds runanywhere_*.so with 16KB alignment flags
# =============================================================================

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build/android"
DIST_DIR="${ROOT_DIR}/dist/android"

# Load centralized versions
source "${SCRIPT_DIR}/../load-versions.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

print_step() {
    echo -e "${YELLOW}-> $1${NC}"
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
    echo -e "${CYAN}[INFO] $1${NC}"
}

# =============================================================================
# Parse Options (before positional arguments)
# =============================================================================

CHECK_ONLY=false

while [[ "$1" == --* ]]; do
    case "$1" in
        --check)
            CHECK_ONLY=true
            shift
            ;;
        --help|-h)
            head -25 "$0" | tail -20
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# =============================================================================
# Check Alignment Mode
# =============================================================================

if [ "$CHECK_ONLY" = true ]; then
    print_header "Checking 16KB Alignment"

    # Find readelf
    READELF=""
    if command -v llvm-readelf &> /dev/null; then
        READELF="llvm-readelf"
    elif [ -d "$HOME/Library/Android/sdk/ndk" ]; then
        NDK_PATH=$(ls -d "$HOME/Library/Android/sdk/ndk"/*/ 2>/dev/null | sort -V | tail -1)
        if [ -f "$NDK_PATH/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-readelf" ]; then
            READELF="$NDK_PATH/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-readelf"
        fi
    fi

    if [ -z "$READELF" ]; then
        print_error "readelf not found. Install Android NDK."
        exit 1
    fi

    ALL_ALIGNED=true
    ALIGNED_COUNT=0
    MISALIGNED_COUNT=0

    for so_file in $(find "${DIST_DIR}" -name "*.so" -type f 2>/dev/null); do
        filename=$(basename "$so_file")
        LOAD_OUTPUT=$("$READELF" -l "$so_file" 2>/dev/null | grep "LOAD" || true)

        HAS_4KB=false
        HAS_16KB=false

        while IFS= read -r line; do
            ALIGN_VAL=$(echo "$line" | grep -oE '0x[0-9a-fA-F]+' | tail -1)
            case "$ALIGN_VAL" in
                0x1000|0x001000) HAS_4KB=true ;;
                0x4000|0x004000) HAS_16KB=true ;;
            esac
        done <<< "$LOAD_OUTPUT"

        if [ "$HAS_4KB" = true ] && [ "$HAS_16KB" = false ]; then
            print_error "$filename - 4KB aligned (NOT Play Store ready)"
            ALL_ALIGNED=false
            MISALIGNED_COUNT=$((MISALIGNED_COUNT + 1))
        elif [ "$HAS_16KB" = true ]; then
            print_success "$filename - 16KB aligned"
            ALIGNED_COUNT=$((ALIGNED_COUNT + 1))
        fi
    done

    echo ""
    echo "16KB aligned: $ALIGNED_COUNT"
    echo "Misaligned:   $MISALIGNED_COUNT"

    if [ "$ALL_ALIGNED" = true ] && [ "$ALIGNED_COUNT" -gt 0 ]; then
        echo ""
        print_success "All libraries are 16KB aligned - Play Store ready!"
        exit 0
    else
        echo ""
        print_error "Some libraries are NOT 16KB aligned!"
        echo ""
        echo "Re-download Sherpa-ONNX v1.12.20+:"
        echo "  ./scripts/android/download-sherpa-onnx.sh"
        exit 1
    fi
fi

# =============================================================================
# Parse Positional Arguments
# =============================================================================

BACKENDS="${1:-all}"
ABIS="${2:-arm64-v8a}"
# Use version from VERSIONS file, allow env override
ANDROID_API_LEVEL="${ANDROID_API_LEVEL:-$ANDROID_API_LEVEL}"

# Determine which backends to build
BUILD_ONNX=OFF
BUILD_LLAMACPP=OFF
BUILD_WHISPERCPP=OFF
BUILD_TFLITE=OFF

case "$BACKENDS" in
    all)
        BUILD_ONNX=ON
        BUILD_LLAMACPP=ON
        BUILD_WHISPERCPP=ON
        DIST_SUBDIR="unified"
        ;;
    onnx)
        BUILD_ONNX=ON
        DIST_SUBDIR="onnx"
        ;;
    llamacpp)
        BUILD_LLAMACPP=ON
        DIST_SUBDIR="llamacpp"
        ;;
    whispercpp)
        BUILD_WHISPERCPP=ON
        DIST_SUBDIR="whispercpp"
        ;;
    tflite)
        BUILD_TFLITE=ON
        DIST_SUBDIR="tflite"
        ;;
    onnx,llamacpp|llamacpp,onnx)
        BUILD_ONNX=ON
        BUILD_LLAMACPP=ON
        DIST_SUBDIR="unified"
        ;;
    onnx,whispercpp|whispercpp,onnx)
        BUILD_ONNX=ON
        BUILD_WHISPERCPP=ON
        DIST_SUBDIR="unified"
        ;;
    llamacpp,whispercpp|whispercpp,llamacpp)
        BUILD_LLAMACPP=ON
        BUILD_WHISPERCPP=ON
        DIST_SUBDIR="unified"
        ;;
    onnx,llamacpp,whispercpp|*)
        # Handle any other combination containing onnx,llamacpp,whispercpp
        if [[ "$BACKENDS" == *"onnx"* ]] && [[ "$BACKENDS" == *"llamacpp"* ]] && [[ "$BACKENDS" == *"whispercpp"* ]]; then
            BUILD_ONNX=ON
            BUILD_LLAMACPP=ON
            BUILD_WHISPERCPP=ON
            DIST_SUBDIR="unified"
        else
            print_error "Unknown backend(s): $BACKENDS"
            echo "Usage: $0 [backends] [abis]"
            echo "  backends: onnx | llamacpp | whispercpp | tflite | all"
            echo "  abis: comma-separated list (default: arm64-v8a)"
            exit 1
        fi
        ;;
esac

print_header "RunAnywhere Android Build (Unified)"
echo "Backends: ONNX=$BUILD_ONNX, LlamaCPP=$BUILD_LLAMACPP, WhisperCPP=$BUILD_WHISPERCPP, TFLite=$BUILD_TFLITE"
echo "ABIs: ${ABIS}"
echo "Android API Level: ${ANDROID_API_LEVEL}"
echo "Output: dist/android/${DIST_SUBDIR}/"

# =============================================================================
# Prerequisites
# =============================================================================

print_step "Checking prerequisites..."

if ! command -v cmake &> /dev/null; then
    print_error "cmake not found. Install with: brew install cmake (macOS) or apt install cmake (Linux)"
    exit 1
fi
print_success "Found cmake"

# Find Android NDK
if [ -z "$ANDROID_NDK_HOME" ] && [ -z "$NDK_HOME" ]; then
    if [ -d "$HOME/Library/Android/sdk/ndk" ]; then
        ANDROID_NDK_HOME=$(ls -d "$HOME/Library/Android/sdk/ndk"/*/ 2>/dev/null | sort -V | tail -1)
    elif [ -d "$HOME/Android/Sdk/ndk" ]; then
        ANDROID_NDK_HOME=$(ls -d "$HOME/Android/Sdk/ndk"/*/ 2>/dev/null | sort -V | tail -1)
    elif [ -d "$ANDROID_HOME/ndk" ]; then
        ANDROID_NDK_HOME=$(ls -d "$ANDROID_HOME/ndk"/*/ 2>/dev/null | sort -V | tail -1)
    elif [ -d "$ANDROID_SDK_ROOT/ndk" ]; then
        ANDROID_NDK_HOME=$(ls -d "$ANDROID_SDK_ROOT/ndk"/*/ 2>/dev/null | sort -V | tail -1)
    fi
fi

NDK_PATH="${ANDROID_NDK_HOME:-$NDK_HOME}"
if [ -z "$NDK_PATH" ] || [ ! -d "$NDK_PATH" ]; then
    print_error "Android NDK not found. Set ANDROID_NDK_HOME or NDK_HOME environment variable."
    exit 1
fi
print_success "Found Android NDK: $NDK_PATH"

TOOLCHAIN_FILE="$NDK_PATH/build/cmake/android.toolchain.cmake"
if [ ! -f "$TOOLCHAIN_FILE" ]; then
    print_error "Android toolchain file not found at: $TOOLCHAIN_FILE"
    exit 1
fi
print_success "Found toolchain file"

# Backend-specific checks
if [ "$BUILD_ONNX" = "ON" ]; then
    # Sherpa-ONNX is REQUIRED for ONNX backend (provides 16KB-aligned libonnxruntime.so)
    if [ ! -d "${ROOT_DIR}/third_party/sherpa-onnx-android/jniLibs" ]; then
        print_step "Sherpa-ONNX not found. Downloading..."
        "${ROOT_DIR}/scripts/android/download-sherpa-onnx.sh"
    fi
    print_success "Found Sherpa-ONNX (provides 16KB-aligned ONNX Runtime + STT/TTS/VAD)"
fi

if [ "$BUILD_LLAMACPP" = "ON" ]; then
    print_success "LlamaCPP will be fetched via CMake FetchContent"
fi

if [ "$BUILD_WHISPERCPP" = "ON" ]; then
    print_success "WhisperCPP will be fetched via CMake FetchContent"
fi

# =============================================================================
# Clean Previous Build
# =============================================================================

print_step "Cleaning previous builds..."
BACKEND_BUILD_DIR="${BUILD_DIR}/${DIST_SUBDIR}"
BACKEND_DIST_DIR="${DIST_DIR}/${DIST_SUBDIR}"
rm -rf "${BACKEND_BUILD_DIR}"
rm -rf "${BACKEND_DIST_DIR}"
mkdir -p "${BACKEND_BUILD_DIR}"
mkdir -p "${BACKEND_DIST_DIR}"

# Also create jni distribution directory (always contains jni + bridge)
JNI_DIST_DIR="${DIST_DIR}/jni"
rm -rf "${JNI_DIST_DIR}"
mkdir -p "${JNI_DIST_DIR}"

# =============================================================================
# Build for Each ABI
# =============================================================================

IFS=',' read -ra ABI_ARRAY <<< "$ABIS"

for ABI in "${ABI_ARRAY[@]}"; do
    print_header "Building for ${ABI}"

    ABI_BUILD_DIR="${BACKEND_BUILD_DIR}/${ABI}"
    mkdir -p "${ABI_BUILD_DIR}"

    cmake -B "${ABI_BUILD_DIR}" \
        -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN_FILE}" \
        -DANDROID_ABI="${ABI}" \
        -DANDROID_PLATFORM="android-${ANDROID_API_LEVEL}" \
        -DANDROID_STL=c++_shared \
        -DCMAKE_BUILD_TYPE=Release \
        -DRA_BUILD_ONNX=${BUILD_ONNX} \
        -DRA_BUILD_LLAMACPP=${BUILD_LLAMACPP} \
        -DRA_BUILD_WHISPERCPP=${BUILD_WHISPERCPP} \
        -DRA_BUILD_TFLITE=${BUILD_TFLITE} \
        -DRA_BUILD_TESTS=OFF \
        -DRA_BUILD_SHARED=ON \
        -DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON \
        -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384" \
        "${ROOT_DIR}"

    cmake --build "${ABI_BUILD_DIR}" \
        --config Release \
        -j$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

    print_success "${ABI} build complete"

    # Create distribution directories
    mkdir -p "${BACKEND_DIST_DIR}/${ABI}"
    mkdir -p "${JNI_DIST_DIR}/${ABI}"

    # Copy JNI bridge libraries (always to jni/ directory)
    print_step "Copying JNI bridge libraries for ${ABI}..."
    if [ -f "${ABI_BUILD_DIR}/librunanywhere_loader.so" ]; then
        cp "${ABI_BUILD_DIR}/librunanywhere_loader.so" "${JNI_DIST_DIR}/${ABI}/"
        echo "  Copied: librunanywhere_loader.so -> jni/${ABI}/"
    fi
    if [ -f "${ABI_BUILD_DIR}/librunanywhere_jni.so" ]; then
        cp "${ABI_BUILD_DIR}/librunanywhere_jni.so" "${JNI_DIST_DIR}/${ABI}/"
        echo "  Copied: librunanywhere_jni.so -> jni/${ABI}/"
    fi
    if [ -f "${ABI_BUILD_DIR}/librunanywhere_bridge.so" ]; then
        cp "${ABI_BUILD_DIR}/librunanywhere_bridge.so" "${JNI_DIST_DIR}/${ABI}/"
        echo "  Copied: librunanywhere_bridge.so -> jni/${ABI}/"
    fi

    # Detect NDK prebuilt directory (works across all platforms: darwin-x86_64, darwin-arm64, linux-x86_64)
    PREBUILT_DIR=""
    if [ -d "$NDK_PATH/toolchains/llvm/prebuilt" ]; then
        PREBUILT_DIR=$(ls -d "$NDK_PATH/toolchains/llvm/prebuilt"/*/ 2>/dev/null | head -1 | xargs basename 2>/dev/null)
    fi

    # Determine arch-specific search pattern for libomp.so
    case "$ABI" in
        arm64-v8a)
            ARCH_PATTERN="aarch64"
            ;;
        armeabi-v7a)
            ARCH_PATTERN="arm"
            ;;
        x86_64)
            ARCH_PATTERN="x86_64"
            ;;
        x86)
            ARCH_PATTERN="i686"
            ;;
    esac

    # Copy libomp.so using find (robust across NDK versions and directory structures)
    # libomp.so is required by librac_backend_llamacpp_jni.so when OpenMP is enabled
    LIBOMP_FOUND=$(find "$NDK_PATH/toolchains/llvm/prebuilt" -name "libomp.so" -path "*/${ARCH_PATTERN}/*" 2>/dev/null | head -1)
    if [ -n "$LIBOMP_FOUND" ] && [ -f "$LIBOMP_FOUND" ]; then
        cp "$LIBOMP_FOUND" "${JNI_DIST_DIR}/${ABI}/"
        echo "  Copied: libomp.so -> jni/${ABI}/ (from $LIBOMP_FOUND)"
    else
        # Fallback: try to find any libomp.so for this architecture
        LIBOMP_FOUND=$(find "$NDK_PATH" -name "libomp.so" -path "*linux*${ARCH_PATTERN}*" 2>/dev/null | head -1)
        if [ -n "$LIBOMP_FOUND" ] && [ -f "$LIBOMP_FOUND" ]; then
            cp "$LIBOMP_FOUND" "${JNI_DIST_DIR}/${ABI}/"
            echo "  Copied: libomp.so -> jni/${ABI}/ (fallback from $LIBOMP_FOUND)"
        else
            echo "  WARNING: libomp.so not found for ${ABI} (${ARCH_PATTERN}). LlamaCPP/WhisperCPP may fail at runtime!"
            echo "    Searched in: $NDK_PATH/toolchains/llvm/prebuilt"
        fi
    fi

    # Copy libc++_shared.so using find (robust across NDK versions)
    if [ -n "$PREBUILT_DIR" ]; then
        LIBCXX_FOUND=$(find "$NDK_PATH/toolchains/llvm/prebuilt/$PREBUILT_DIR/sysroot/usr/lib" -name "libc++_shared.so" -path "*${ARCH_PATTERN}*" 2>/dev/null | head -1)
        if [ -n "$LIBCXX_FOUND" ] && [ -f "$LIBCXX_FOUND" ]; then
            cp "$LIBCXX_FOUND" "${JNI_DIST_DIR}/${ABI}/"
            echo "  Copied: libc++_shared.so -> jni/${ABI}/"
        fi
    fi

    # Copy backend-specific libraries
    print_step "Copying backend libraries for ${ABI}..."

    # ONNX backend
    if [ "$BUILD_ONNX" = "ON" ]; then
        mkdir -p "${DIST_DIR}/onnx/${ABI}"
        if [ -f "${ABI_BUILD_DIR}/backends/onnx/librunanywhere_onnx.so" ]; then
            cp "${ABI_BUILD_DIR}/backends/onnx/librunanywhere_onnx.so" "${DIST_DIR}/onnx/${ABI}/"
            echo "  Copied: librunanywhere_onnx.so -> onnx/${ABI}/"
        fi

        # Copy JNI bridge library (required for Kotlin SDK)
        if [ -f "${ABI_BUILD_DIR}/backends/onnx/librac_backend_onnx_jni.so" ]; then
            cp "${ABI_BUILD_DIR}/backends/onnx/librac_backend_onnx_jni.so" "${DIST_DIR}/onnx/${ABI}/"
            echo "  Copied: librac_backend_onnx_jni.so -> onnx/${ABI}/"
        else
            print_warning "librac_backend_onnx_jni.so not found - JNI bridge not built"
        fi

        # Copy libonnxruntime.so from Sherpa-ONNX (16KB aligned in v1.12.20+)
        # Sherpa-ONNX bundles a compatible version of ONNX Runtime
        SHERPA_DIR="${ROOT_DIR}/third_party/sherpa-onnx-android/jniLibs/${ABI}"
        if [ -d "$SHERPA_DIR" ]; then
            # Copy libonnxruntime.so from Sherpa-ONNX (16KB aligned)
            if [ -f "${SHERPA_DIR}/libonnxruntime.so" ]; then
                cp "${SHERPA_DIR}/libonnxruntime.so" "${DIST_DIR}/onnx/${ABI}/"
                echo "  Copied: libonnxruntime.so -> onnx/${ABI}/ (from Sherpa-ONNX, 16KB aligned)"
            fi

            # Copy all sherpa-onnx libraries (c-api, cxx-api, jni)
            for lib in "${SHERPA_DIR}"/libsherpa-onnx-*.so; do
                if [ -f "$lib" ]; then
                    cp "$lib" "${DIST_DIR}/onnx/${ABI}/"
                    echo "  Copied: $(basename "$lib") -> onnx/${ABI}/"
                fi
            done
        else
            print_warning "Sherpa-ONNX not found - libonnxruntime.so will not be copied"
            print_warning "Run: ./scripts/android/download-sherpa-onnx.sh to download"
        fi
    fi

    # LlamaCPP backend
    if [ "$BUILD_LLAMACPP" = "ON" ]; then
        mkdir -p "${DIST_DIR}/llamacpp/${ABI}"
        if [ -f "${ABI_BUILD_DIR}/backends/llamacpp/librunanywhere_llamacpp.so" ]; then
            cp "${ABI_BUILD_DIR}/backends/llamacpp/librunanywhere_llamacpp.so" "${DIST_DIR}/llamacpp/${ABI}/"
            echo "  Copied: librunanywhere_llamacpp.so -> llamacpp/${ABI}/"
        fi

        # Copy JNI bridge library (required for Kotlin SDK)
        if [ -f "${ABI_BUILD_DIR}/backends/llamacpp/librac_backend_llamacpp_jni.so" ]; then
            cp "${ABI_BUILD_DIR}/backends/llamacpp/librac_backend_llamacpp_jni.so" "${DIST_DIR}/llamacpp/${ABI}/"
            echo "  Copied: librac_backend_llamacpp_jni.so -> llamacpp/${ABI}/"
        else
            print_warning "librac_backend_llamacpp_jni.so not found - JNI bridge not built"
        fi

        # Copy OpenMP and C++ shared library for LlamaCPP
        # Note: ARCH_PATTERN is already set above in the ABI detection
        LIBOMP_FOUND=$(find "$NDK_PATH/toolchains/llvm/prebuilt" -name "libomp.so" -path "*/${ARCH_PATTERN}/*" 2>/dev/null | head -1)
        if [ -n "$LIBOMP_FOUND" ] && [ -f "$LIBOMP_FOUND" ]; then
            cp "$LIBOMP_FOUND" "${DIST_DIR}/llamacpp/${ABI}/"
            echo "  Copied: libomp.so -> llamacpp/${ABI}/ (from $LIBOMP_FOUND)"
        else
            # Fallback: try to find any libomp.so for this architecture
            LIBOMP_FOUND=$(find "$NDK_PATH" -name "libomp.so" -path "*linux*${ARCH_PATTERN}*" 2>/dev/null | head -1)
            if [ -n "$LIBOMP_FOUND" ] && [ -f "$LIBOMP_FOUND" ]; then
                cp "$LIBOMP_FOUND" "${DIST_DIR}/llamacpp/${ABI}/"
                echo "  Copied: libomp.so -> llamacpp/${ABI}/ (fallback from $LIBOMP_FOUND)"
            else
                echo "  WARNING: libomp.so not found for ${ABI}. LlamaCPP may fail at runtime!"
            fi
        fi

        # Copy libc++_shared.so for LlamaCPP
        if [ -n "$PREBUILT_DIR" ]; then
            LIBCXX_FOUND=$(find "$NDK_PATH/toolchains/llvm/prebuilt/$PREBUILT_DIR/sysroot/usr/lib" -name "libc++_shared.so" -path "*${ARCH_PATTERN}*" 2>/dev/null | head -1)
            if [ -n "$LIBCXX_FOUND" ] && [ -f "$LIBCXX_FOUND" ]; then
                cp "$LIBCXX_FOUND" "${DIST_DIR}/llamacpp/${ABI}/"
                echo "  Copied: libc++_shared.so -> llamacpp/${ABI}/"
            fi
        fi
    fi

    # WhisperCPP backend
    if [ "$BUILD_WHISPERCPP" = "ON" ]; then
        mkdir -p "${DIST_DIR}/whispercpp/${ABI}"
        if [ -f "${ABI_BUILD_DIR}/backends/whispercpp/librunanywhere_whispercpp.so" ]; then
            cp "${ABI_BUILD_DIR}/backends/whispercpp/librunanywhere_whispercpp.so" "${DIST_DIR}/whispercpp/${ABI}/"
            echo "  Copied: librunanywhere_whispercpp.so -> whispercpp/${ABI}/"
        fi

        # Copy JNI bridge library (required for Kotlin SDK)
        if [ -f "${ABI_BUILD_DIR}/backends/whispercpp/librac_backend_whispercpp_jni.so" ]; then
            cp "${ABI_BUILD_DIR}/backends/whispercpp/librac_backend_whispercpp_jni.so" "${DIST_DIR}/whispercpp/${ABI}/"
            echo "  Copied: librac_backend_whispercpp_jni.so -> whispercpp/${ABI}/"
        else
            print_warning "librac_backend_whispercpp_jni.so not found - JNI bridge not built"
        fi

        # Copy OpenMP and C++ shared library for WhisperCPP
        # Note: ARCH_PATTERN is already set above in the ABI detection
        LIBOMP_FOUND=$(find "$NDK_PATH/toolchains/llvm/prebuilt" -name "libomp.so" -path "*/${ARCH_PATTERN}/*" 2>/dev/null | head -1)
        if [ -n "$LIBOMP_FOUND" ] && [ -f "$LIBOMP_FOUND" ]; then
            cp "$LIBOMP_FOUND" "${DIST_DIR}/whispercpp/${ABI}/"
            echo "  Copied: libomp.so -> whispercpp/${ABI}/ (from $LIBOMP_FOUND)"
        else
            # Fallback: try to find any libomp.so for this architecture
            LIBOMP_FOUND=$(find "$NDK_PATH" -name "libomp.so" -path "*linux*${ARCH_PATTERN}*" 2>/dev/null | head -1)
            if [ -n "$LIBOMP_FOUND" ] && [ -f "$LIBOMP_FOUND" ]; then
                cp "$LIBOMP_FOUND" "${DIST_DIR}/whispercpp/${ABI}/"
                echo "  Copied: libomp.so -> whispercpp/${ABI}/ (fallback from $LIBOMP_FOUND)"
            else
                echo "  WARNING: libomp.so not found for ${ABI}. WhisperCPP may fail at runtime!"
            fi
        fi

        # Copy libc++_shared.so for WhisperCPP
        if [ -n "$PREBUILT_DIR" ]; then
            LIBCXX_FOUND=$(find "$NDK_PATH/toolchains/llvm/prebuilt/$PREBUILT_DIR/sysroot/usr/lib" -name "libc++_shared.so" -path "*${ARCH_PATTERN}*" 2>/dev/null | head -1)
            if [ -n "$LIBCXX_FOUND" ] && [ -f "$LIBCXX_FOUND" ]; then
                cp "$LIBCXX_FOUND" "${DIST_DIR}/whispercpp/${ABI}/"
                echo "  Copied: libc++_shared.so -> whispercpp/${ABI}/"
            fi
        fi
    fi

    # TFLite backend
    if [ "$BUILD_TFLITE" = "ON" ]; then
        mkdir -p "${DIST_DIR}/tflite/${ABI}"
        if [ -f "${ABI_BUILD_DIR}/backends/tflite/librunanywhere_tflite.so" ]; then
            cp "${ABI_BUILD_DIR}/backends/tflite/librunanywhere_tflite.so" "${DIST_DIR}/tflite/${ABI}/"
            echo "  Copied: librunanywhere_tflite.so -> tflite/${ABI}/"
        fi
    fi

    # RAC Commons (shared library for logging, error handling, events)
    # This is built from runanywhere-commons and linked by all backends
    RAC_COMMONS_LIB="${ABI_BUILD_DIR}/rac_commons/librac_commons.so"
    if [ -f "${RAC_COMMONS_LIB}" ]; then
        mkdir -p "${DIST_DIR}/commons/${ABI}"
        cp "${RAC_COMMONS_LIB}" "${DIST_DIR}/commons/${ABI}/"
        echo "  Copied: librac_commons.so -> commons/${ABI}/"

        # Also copy to each backend directory since they depend on it
        for backend in onnx llamacpp whispercpp tflite; do
            if [ -d "${DIST_DIR}/${backend}/${ABI}" ]; then
                cp "${RAC_COMMONS_LIB}" "${DIST_DIR}/${backend}/${ABI}/"
                echo "  Copied: librac_commons.so -> ${backend}/${ABI}/"
            fi
        done
    fi

    print_success "${ABI} libraries copied"
done

# =============================================================================
# Copy Headers
# =============================================================================

print_step "Copying headers..."
HEADERS_DIR="${DIST_DIR}/include"
mkdir -p "${HEADERS_DIR}"

# Copy RAC headers from commons
COMMONS_DIR="${ROOT_DIR}/../sdk/runanywhere-commons"
if [ -d "${COMMONS_DIR}/include/rac" ]; then
    cp -r "${COMMONS_DIR}/include/rac" "${HEADERS_DIR}/"
    print_success "RAC Commons headers copied"
fi

# Copy backend-specific RAC headers
if [ -d "${ROOT_DIR}/include" ]; then
    cp "${ROOT_DIR}/include/"*.h "${HEADERS_DIR}/" 2>/dev/null || true
    print_success "Backend RAC headers copied"
fi

# Copy capabilities headers
if [ -d "${ROOT_DIR}/backends/capabilities" ]; then
    cp "${ROOT_DIR}/backends/capabilities/"*.h "${HEADERS_DIR}/" 2>/dev/null || true
    print_success "Capabilities headers copied"
fi

# =============================================================================
# Summary
# =============================================================================

print_header "Build Complete!"

echo "Distribution structure:"
echo ""
echo "dist/android/"
echo "├── commons/                  # RAC Commons library"
for ABI in "${ABI_ARRAY[@]}"; do
    echo "│   └── ${ABI}/"
    echo "│       └── librac_commons.so"
done
echo "├── include/                  # Headers"
echo "│   ├── rac/                  # RAC Commons headers"
echo "│   └── *.h                   # Backend headers"

if [ "$BUILD_ONNX" = "ON" ]; then
    echo "├── onnx/                     # ONNX backend libraries"
    for ABI in "${ABI_ARRAY[@]}"; do
        echo "│   └── ${ABI}/"
        echo "│       ├── librunanywhere_onnx.so"
        echo "│       ├── libonnxruntime.so"
        if [ -f "${DIST_DIR}/onnx/${ABI}/libsherpa-onnx-jni.so" ]; then
            echo "│       └── libsherpa-onnx-jni.so  # STT/TTS/VAD"
        fi
    done
fi

if [ "$BUILD_LLAMACPP" = "ON" ]; then
    echo "├── llamacpp/                 # LlamaCPP backend libraries"
    for ABI in "${ABI_ARRAY[@]}"; do
        echo "│   └── ${ABI}/"
        echo "│       ├── librunanywhere_llamacpp.so"
        echo "│       ├── libomp.so"
        echo "│       └── libc++_shared.so"
    done
fi

if [ "$BUILD_WHISPERCPP" = "ON" ]; then
    echo "├── whispercpp/               # WhisperCPP backend libraries (STT)"
    for ABI in "${ABI_ARRAY[@]}"; do
        echo "│   └── ${ABI}/"
        echo "│       ├── librunanywhere_whispercpp.so"
        echo "│       ├── libomp.so"
        echo "│       └── libc++_shared.so"
    done
fi

if [ "$BUILD_TFLITE" = "ON" ]; then
    echo "└── tflite/                   # TFLite backend libraries"
    for ABI in "${ABI_ARRAY[@]}"; do
        echo "    └── ${ABI}/"
        echo "        └── librunanywhere_tflite.so"
    done
fi

echo ""
echo "Library sizes:"
echo "  Commons:"
ls -lh "${DIST_DIR}/commons"/*/*.so 2>/dev/null | awk '{print "    " $NF ": " $5}' || echo "    (no files)"

if [ "$BUILD_ONNX" = "ON" ]; then
    echo "  ONNX:"
    ls -lh "${DIST_DIR}/onnx"/*/*.so 2>/dev/null | awk '{print "    " $NF ": " $5}' || echo "    (no files)"
fi

if [ "$BUILD_LLAMACPP" = "ON" ]; then
    echo "  LlamaCPP:"
    ls -lh "${DIST_DIR}/llamacpp"/*/*.so 2>/dev/null | awk '{print "    " $NF ": " $5}' || echo "    (no files)"
fi

if [ "$BUILD_WHISPERCPP" = "ON" ]; then
    echo "  WhisperCPP:"
    ls -lh "${DIST_DIR}/whispercpp"/*/*.so 2>/dev/null | awk '{print "    " $NF ": " $5}' || echo "    (no files)"
fi

echo ""
echo -e "${GREEN}Build complete!${NC}"

# =============================================================================
# Create Distribution Packages
# =============================================================================

# Auto-detect version
VERSION_FILE="${ROOT_DIR}/VERSION"
if [ -f "$VERSION_FILE" ]; then
    VERSION=$(cat "$VERSION_FILE" | tr -d '[:space:]')
elif command -v git &> /dev/null && [ -d "${ROOT_DIR}/.git" ]; then
    VERSION=$(git describe --tags --always --dirty 2>/dev/null || echo "0.0.1-dev")
else
    VERSION="0.0.1-dev"
fi

print_header "Creating Distribution Packages"
echo "Version: ${VERSION}"

PACKAGES_DIR="${DIST_DIR}/packages"
mkdir -p "${PACKAGES_DIR}"

# =============================================================================
# Create Unified Package (Recommended)
# =============================================================================

if [ "$DIST_SUBDIR" = "unified" ]; then
    print_step "Creating unified package with all backends..."

    # Create temporary unified directory
    UNIFIED_TEMP="${DIST_DIR}/temp-unified"
    rm -rf "${UNIFIED_TEMP}"
    mkdir -p "${UNIFIED_TEMP}"

    # Copy all libraries for each ABI
    for ABI in "${ABI_ARRAY[@]}"; do
        mkdir -p "${UNIFIED_TEMP}/${ABI}"

        # Copy JNI bridge libraries (required)
        if [ -d "${JNI_DIST_DIR}/${ABI}" ]; then
            cp "${JNI_DIST_DIR}/${ABI}"/*.so "${UNIFIED_TEMP}/${ABI}/" 2>/dev/null || true
        fi

        # Copy ONNX backend libraries
        if [ -d "${DIST_DIR}/onnx/${ABI}" ]; then
            cp "${DIST_DIR}/onnx/${ABI}"/*.so "${UNIFIED_TEMP}/${ABI}/" 2>/dev/null || true
        fi

        # Copy LlamaCPP backend libraries
        if [ -d "${DIST_DIR}/llamacpp/${ABI}" ]; then
            cp "${DIST_DIR}/llamacpp/${ABI}"/*.so "${UNIFIED_TEMP}/${ABI}/" 2>/dev/null || true
        fi

        # Copy WhisperCPP backend libraries
        if [ -d "${DIST_DIR}/whispercpp/${ABI}" ]; then
            cp "${DIST_DIR}/whispercpp/${ABI}"/*.so "${UNIFIED_TEMP}/${ABI}/" 2>/dev/null || true
        fi

        # Copy TFLite backend libraries
        if [ -d "${DIST_DIR}/tflite/${ABI}" ]; then
            cp "${DIST_DIR}/tflite/${ABI}"/*.so "${UNIFIED_TEMP}/${ABI}/" 2>/dev/null || true
        fi
    done

    # Copy headers
    if [ -d "${JNI_DIST_DIR}/include" ]; then
        cp -r "${JNI_DIST_DIR}/include" "${UNIFIED_TEMP}/"
    fi

    # Create ZIP archive
    ARCHIVE_NAME="RunAnywhereUnified-android-${VERSION}.zip"
    rm -f "${PACKAGES_DIR}/${ARCHIVE_NAME}"

    cd "${UNIFIED_TEMP}"
    zip -r "${PACKAGES_DIR}/${ARCHIVE_NAME}" . > /dev/null
    cd "${DIST_DIR}"

    # Generate checksum
    cd "${PACKAGES_DIR}"
    shasum -a 256 "${ARCHIVE_NAME}" > "${ARCHIVE_NAME}.sha256"
    cd "${DIST_DIR}"

    # Clean up
    rm -rf "${UNIFIED_TEMP}"

    print_success "Unified package: ${PACKAGES_DIR}/${ARCHIVE_NAME}"
    echo "Size: $(du -sh "${PACKAGES_DIR}/${ARCHIVE_NAME}" | awk '{print $1}')"
fi

# =============================================================================
# Create Separate Backend Packages (For backwards compatibility)
# =============================================================================

# ONNX package
if [ "$BUILD_ONNX" = "ON" ]; then
    print_step "Creating ONNX backend package..."

    ONNX_TEMP="${DIST_DIR}/temp-onnx"
    rm -rf "${ONNX_TEMP}"
    mkdir -p "${ONNX_TEMP}"

    for ABI in "${ABI_ARRAY[@]}"; do
        mkdir -p "${ONNX_TEMP}/${ABI}"
        [ -d "${JNI_DIST_DIR}/${ABI}" ] && cp "${JNI_DIST_DIR}/${ABI}"/*.so "${ONNX_TEMP}/${ABI}/" 2>/dev/null || true
        [ -d "${DIST_DIR}/onnx/${ABI}" ] && cp "${DIST_DIR}/onnx/${ABI}"/*.so "${ONNX_TEMP}/${ABI}/" 2>/dev/null || true
    done
    [ -d "${JNI_DIST_DIR}/include" ] && cp -r "${JNI_DIST_DIR}/include" "${ONNX_TEMP}/" || true

    ONNX_ARCHIVE="RunAnywhereONNX-android-${VERSION}.zip"
    cd "${ONNX_TEMP}"
    zip -r "${PACKAGES_DIR}/${ONNX_ARCHIVE}" . > /dev/null
    cd "${DIST_DIR}"
    rm -rf "${ONNX_TEMP}"

    cd "${PACKAGES_DIR}"
    shasum -a 256 "${ONNX_ARCHIVE}" > "${ONNX_ARCHIVE}.sha256"
    cd "${DIST_DIR}"

    print_success "ONNX package: ${PACKAGES_DIR}/${ONNX_ARCHIVE}"
fi

# LlamaCPP package
if [ "$BUILD_LLAMACPP" = "ON" ]; then
    print_step "Creating LlamaCPP backend package..."

    LLAMA_TEMP="${DIST_DIR}/temp-llamacpp"
    rm -rf "${LLAMA_TEMP}"
    mkdir -p "${LLAMA_TEMP}"

    for ABI in "${ABI_ARRAY[@]}"; do
        mkdir -p "${LLAMA_TEMP}/${ABI}"
        [ -d "${JNI_DIST_DIR}/${ABI}" ] && cp "${JNI_DIST_DIR}/${ABI}"/*.so "${LLAMA_TEMP}/${ABI}/" 2>/dev/null || true
        [ -d "${DIST_DIR}/llamacpp/${ABI}" ] && cp "${DIST_DIR}/llamacpp/${ABI}"/*.so "${LLAMA_TEMP}/${ABI}/" 2>/dev/null || true
    done
    [ -d "${JNI_DIST_DIR}/include" ] && cp -r "${JNI_DIST_DIR}/include" "${LLAMA_TEMP}/" || true

    LLAMA_ARCHIVE="RunAnywhereLlamaCPP-android-${VERSION}.zip"
    cd "${LLAMA_TEMP}"
    zip -r "${PACKAGES_DIR}/${LLAMA_ARCHIVE}" . > /dev/null
    cd "${DIST_DIR}"
    rm -rf "${LLAMA_TEMP}"

    cd "${PACKAGES_DIR}"
    shasum -a 256 "${LLAMA_ARCHIVE}" > "${LLAMA_ARCHIVE}.sha256"
    cd "${DIST_DIR}"

    print_success "LlamaCPP package: ${PACKAGES_DIR}/${LLAMA_ARCHIVE}"
fi

# WhisperCPP package
if [ "$BUILD_WHISPERCPP" = "ON" ]; then
    print_step "Creating WhisperCPP backend package..."

    WHISPER_TEMP="${DIST_DIR}/temp-whispercpp"
    rm -rf "${WHISPER_TEMP}"
    mkdir -p "${WHISPER_TEMP}"

    for ABI in "${ABI_ARRAY[@]}"; do
        mkdir -p "${WHISPER_TEMP}/${ABI}"
        [ -d "${JNI_DIST_DIR}/${ABI}" ] && cp "${JNI_DIST_DIR}/${ABI}"/*.so "${WHISPER_TEMP}/${ABI}/" 2>/dev/null || true
        [ -d "${DIST_DIR}/whispercpp/${ABI}" ] && cp "${DIST_DIR}/whispercpp/${ABI}"/*.so "${WHISPER_TEMP}/${ABI}/" 2>/dev/null || true
    done
    [ -d "${JNI_DIST_DIR}/include" ] && cp -r "${JNI_DIST_DIR}/include" "${WHISPER_TEMP}/" || true

    WHISPER_ARCHIVE="RunAnywhereWhisperCPP-android-${VERSION}.zip"
    cd "${WHISPER_TEMP}"
    zip -r "${PACKAGES_DIR}/${WHISPER_ARCHIVE}" . > /dev/null
    cd "${DIST_DIR}"
    rm -rf "${WHISPER_TEMP}"

    cd "${PACKAGES_DIR}"
    shasum -a 256 "${WHISPER_ARCHIVE}" > "${WHISPER_ARCHIVE}.sha256"
    cd "${DIST_DIR}"

    print_success "WhisperCPP package: ${PACKAGES_DIR}/${WHISPER_ARCHIVE}"
fi

# =============================================================================
# Package Summary
# =============================================================================

print_header "Packages Ready for Distribution"

echo "Output directory: ${PACKAGES_DIR}"
echo ""
echo "Packages created:"
ls -lh "${PACKAGES_DIR}"/*.zip 2>/dev/null | awk '{print "  " $9 ": " $5}' || echo "  (none)"
echo ""

if [ -f "${PACKAGES_DIR}/RunAnywhereUnified-android-${VERSION}.zip" ]; then
    echo -e "${YELLOW}RECOMMENDED FOR RELEASE:${NC}"
    echo "  ${PACKAGES_DIR}/RunAnywhereUnified-android-${VERSION}.zip"
    echo ""
    echo "This unified package contains ALL backends with a single bridge library"
    echo "that has ONNX, LlamaCPP, and WhisperCPP support enabled."
    echo ""
fi

echo "To upload to GitHub releases:"
echo "  gh release create v${VERSION} --title \"v${VERSION}\" --notes \"Release v${VERSION}\""
echo "  gh release upload v${VERSION} ${PACKAGES_DIR}/*.zip"
echo ""
echo -e "${GREEN}Done!${NC}"
# Force rebuild to include OpenMP
