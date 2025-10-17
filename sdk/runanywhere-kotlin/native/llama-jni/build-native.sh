#!/bin/bash

# Build script for llama.cpp JNI native libraries
# Supports: Linux x64, macOS x64/ARM64, Android ARM64/x86_64

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BUILD_DIR="${SCRIPT_DIR}/build"
LLAMA_CPP_DIR="${SCRIPT_DIR}/llama.cpp"
JNI_SRC_DIR="${SCRIPT_DIR}/src"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    echo_info "Checking prerequisites..."

    # Check for CMake
    if ! command -v cmake &> /dev/null; then
        echo_error "CMake is not installed. Please install CMake 3.18 or higher."
        exit 1
    fi

    # Check for git
    if ! command -v git &> /dev/null; then
        echo_error "Git is not installed."
        exit 1
    fi

    # For Android builds, check NDK
    if [[ "$1" == "android" ]] || [[ "$1" == "all" ]]; then
        if [ -z "$ANDROID_NDK_HOME" ]; then
            echo_error "ANDROID_NDK_HOME is not set. Please set it to your Android NDK path."
            exit 1
        fi
    fi
}

# Clone or update llama.cpp
setup_llama_cpp() {
    echo_info "Setting up llama.cpp..."

    if [ ! -d "$LLAMA_CPP_DIR" ]; then
        echo_info "Cloning llama.cpp..."
        git clone https://github.com/ggerganov/llama.cpp.git "$LLAMA_CPP_DIR"
        cd "$LLAMA_CPP_DIR"
        # Use a stable commit
        git checkout b3950
    else
        echo_info "Updating llama.cpp..."
        cd "$LLAMA_CPP_DIR"
        git fetch
        git checkout b3950
    fi

    cd "$SCRIPT_DIR"
}

# Build for JVM (current host platform)
build_jvm() {
    echo_info "Building for JVM (host platform)..."

    local OS_NAME="$(uname -s)"
    local ARCH="$(uname -m)"
    local BUILD_TYPE="Release"

    case "$OS_NAME" in
        Linux*)
            PLATFORM="linux"
            LIB_EXT="so"
            ;;
        Darwin*)
            PLATFORM="macos"
            LIB_EXT="dylib"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            PLATFORM="windows"
            LIB_EXT="dll"
            ;;
        *)
            echo_error "Unsupported platform: $OS_NAME"
            exit 1
            ;;
    esac

    case "$ARCH" in
        x86_64|amd64)
            ARCH_NAME="x64"
            ;;
        arm64|aarch64)
            ARCH_NAME="arm64"
            ;;
        *)
            echo_error "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac

    local BUILD_SUBDIR="jvm/${PLATFORM}-${ARCH_NAME}"
    local JVM_BUILD_DIR="${BUILD_DIR}/${BUILD_SUBDIR}"

    echo_info "Building for ${PLATFORM}-${ARCH_NAME}..."

    mkdir -p "$JVM_BUILD_DIR"
    cd "$JVM_BUILD_DIR"

    # Configure with CMake
    cmake "$SCRIPT_DIR" \
        -DCMAKE_BUILD_TYPE=$BUILD_TYPE \
        -DLLAMA_STATIC=OFF \
        -DLLAMA_NATIVE=ON \
        -DLLAMA_LTO=ON \
        -DLLAMA_CCACHE=OFF \
        -DLLAMA_BUILD_TESTS=OFF \
        -DLLAMA_BUILD_EXAMPLES=OFF \
        -DBUILD_SHARED_LIBS=ON

    # Add platform-specific optimizations
    if [[ "$PLATFORM" == "macos" ]]; then
        cmake "$SCRIPT_DIR" \
            -DLLAMA_METAL=ON \
            -DLLAMA_ACCELERATE=ON
    elif [[ "$PLATFORM" == "linux" ]]; then
        # Check for CUDA
        if command -v nvcc &> /dev/null; then
            echo_info "CUDA detected, enabling GPU support..."
            cmake "$SCRIPT_DIR" -DLLAMA_CUDA=ON
        fi
    fi

    # Build
    cmake --build . --config $BUILD_TYPE -j$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

    # Copy library to output directory
    local OUTPUT_DIR="${SCRIPT_DIR}/../../modules/runanywhere-llm-llamacpp/src/jvmMain/resources/native/${PLATFORM}-${ARCH_NAME}"
    mkdir -p "$OUTPUT_DIR"
    cp "libllama-jni.${LIB_EXT}" "$OUTPUT_DIR/"

    echo_info "JVM library built successfully: ${OUTPUT_DIR}/libllama-jni.${LIB_EXT}"
}

# Build for Android
build_android() {
    echo_info "Building for Android..."

    local BUILD_TYPE="Release"
    local ANDROID_ABIS=("arm64-v8a" "x86_64")
    local MIN_SDK_VERSION=24

    for ABI in "${ANDROID_ABIS[@]}"; do
        echo_info "Building for Android ${ABI}..."

        local ANDROID_BUILD_DIR="${BUILD_DIR}/android/${ABI}"
        mkdir -p "$ANDROID_BUILD_DIR"
        cd "$ANDROID_BUILD_DIR"

        # Configure with CMake for Android
        cmake "$SCRIPT_DIR" \
            -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" \
            -DANDROID_ABI=$ABI \
            -DANDROID_PLATFORM=android-$MIN_SDK_VERSION \
            -DANDROID_STL=c++_shared \
            -DCMAKE_BUILD_TYPE=$BUILD_TYPE \
            -DLLAMA_STATIC=OFF \
            -DLLAMA_BUILD_TESTS=OFF \
            -DLLAMA_BUILD_EXAMPLES=OFF \
            -DBUILD_SHARED_LIBS=ON

        # Build
        cmake --build . --config $BUILD_TYPE -j$(nproc 2>/dev/null || echo 4)

        # Copy library to output directory
        local OUTPUT_DIR="${SCRIPT_DIR}/../../modules/runanywhere-llm-llamacpp/src/androidMain/jniLibs/${ABI}"
        mkdir -p "$OUTPUT_DIR"
        cp "libllama-jni.so" "$OUTPUT_DIR/"

        # Also copy C++ STL
        local STL_PATH="$ANDROID_NDK_HOME/sources/cxx-stl/llvm-libc++/libs/${ABI}/libc++_shared.so"
        if [ -f "$STL_PATH" ]; then
            cp "$STL_PATH" "$OUTPUT_DIR/"
        fi

        echo_info "Android ${ABI} library built successfully"
    done
}

# Clean build artifacts
clean() {
    echo_info "Cleaning build artifacts..."
    rm -rf "$BUILD_DIR"
    echo_info "Clean complete"
}

# Main build logic
main() {
    local TARGET="${1:-all}"

    echo_info "llama.cpp JNI Native Build Script"
    echo_info "Target: $TARGET"

    check_prerequisites "$TARGET"

    if [[ "$TARGET" == "clean" ]]; then
        clean
        exit 0
    fi

    setup_llama_cpp

    # Create build directory
    mkdir -p "$BUILD_DIR"

    case "$TARGET" in
        jvm)
            build_jvm
            ;;
        android)
            build_android
            ;;
        all)
            build_jvm
            build_android
            ;;
        *)
            echo_error "Unknown target: $TARGET"
            echo "Usage: $0 [jvm|android|all|clean]"
            exit 1
            ;;
    esac

    echo_info "Build completed successfully!"
}

# Run main function
main "$@"
