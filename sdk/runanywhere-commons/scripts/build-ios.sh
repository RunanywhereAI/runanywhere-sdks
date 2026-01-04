#!/bin/bash
# RunAnywhere Commons - iOS XCFramework Build Script
#
# Builds separate XCFrameworks for:
# - RACommons.xcframework (core commons library)
# - RABackendLlamaCPP.xcframework (LlamaCpp backend)
# - RABackendONNX.xcframework (ONNX backend)
#
# Prerequisites:
#   Run ./scripts/download-core.sh first to download runanywhere-core
#
# Usage:
#   ./scripts/download-core.sh    # Download core first
#   ./scripts/build-ios.sh        # Then build

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build/ios"
DIST_DIR="${PROJECT_ROOT}/dist"

# Load versions from VERSIONS file
source "${SCRIPT_DIR}/load-versions.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# =============================================================================
# PATHS - Downloaded dependencies in third_party/runanywhere-core/third_party/
# =============================================================================
RUNANYWHERE_CORE_DIR="${PROJECT_ROOT}/third_party/runanywhere-core"
# Note: CMake looks for sherpa-onnx relative to RUNANYWHERE_CORE_DIR
SHERPA_ONNX_XCFW="${RUNANYWHERE_CORE_DIR}/third_party/sherpa-onnx-ios/sherpa-onnx.xcframework"

# Validate core exists
if [ ! -d "${RUNANYWHERE_CORE_DIR}" ]; then
    echo -e "${RED}ERROR: runanywhere-core not found${NC}"
    echo ""
    echo "Run this first:"
    echo "  ./scripts/download-core.sh"
    exit 1
fi

# Configuration
IOS_DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET:-13.0}"
BUILD_TYPE="${BUILD_TYPE:-Release}"

# Backends to build
BUILD_LLAMACPP="${BUILD_LLAMACPP:-ON}"
BUILD_ONNX="${BUILD_ONNX:-ON}"
BUILD_WHISPERCPP="${BUILD_WHISPERCPP:-OFF}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}RunAnywhere Commons - iOS Build${NC}"
echo -e "${GREEN}========================================${NC}"
echo "Core: ${RUNANYWHERE_CORE_DIR}"
echo "Sherpa-ONNX: ${SHERPA_ONNX_XCFW}"
echo ""
echo "iOS ${IOS_DEPLOYMENT_TARGET} | ${BUILD_TYPE}"
echo "LlamaCpp: ${BUILD_LLAMACPP} | ONNX: ${BUILD_ONNX}"
echo ""

# Clean previous build
clean_build() {
    echo -e "${YELLOW}Cleaning previous build...${NC}"
    rm -rf "${BUILD_DIR}"
    mkdir -p "${BUILD_DIR}"
}

# Build for a specific platform
build_platform() {
    local PLATFORM=$1
    local PLATFORM_DIR="${BUILD_DIR}/${PLATFORM}"

    echo -e "${GREEN}Building for ${PLATFORM}...${NC}"
    mkdir -p "${PLATFORM_DIR}"
    cd "${PLATFORM_DIR}"

    # Check if pre-built core libraries are available
    local USE_PREBUILT="${USE_PREBUILT_CORE:-OFF}"
    if [[ "${USE_PREBUILT}" == "OFF" ]] && [[ -d "${PROJECT_ROOT}/third_party/runanywhere-core-prebuilt" ]]; then
        # Auto-detect pre-built libraries if available
        if [[ -f "${PROJECT_ROOT}/third_party/runanywhere-core-prebuilt/lib/librunanywhere_bridge.a" ]] || \
           [[ -f "${PROJECT_ROOT}/third_party/runanywhere-core-prebuilt/librunanywhere_bridge.a" ]]; then
            USE_PREBUILT="ON"
            echo "Auto-detected pre-built core libraries, using USE_PREBUILT_CORE=ON"
        fi
    fi

    local CMAKE_ARGS=(
        -DCMAKE_TOOLCHAIN_FILE="${PROJECT_ROOT}/cmake/ios.toolchain.cmake"
        -DIOS_PLATFORM="${PLATFORM}"
        -DIOS_DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET}"
        -DCMAKE_BUILD_TYPE="${BUILD_TYPE}"
        -DRAC_BUILD_LLAMACPP="${BUILD_LLAMACPP}"
        -DRAC_BUILD_ONNX="${BUILD_ONNX}"
        -DRAC_BUILD_WHISPERCPP="${BUILD_WHISPERCPP}"
        -DRAC_BUILD_SHARED=OFF
        -DUSE_PREBUILT_CORE="${USE_PREBUILT}"
    )

    # Only set RUNANYWHERE_CORE_DIR if not using pre-built
    if [[ "${USE_PREBUILT}" == "OFF" ]]; then
        CMAKE_ARGS+=(-DRUNANYWHERE_CORE_DIR="${RUNANYWHERE_CORE_DIR}")
    fi

    cmake "${PROJECT_ROOT}" "${CMAKE_ARGS[@]}"

    cmake --build . --config "${BUILD_TYPE}" -j$(sysctl -n hw.ncpu)

    cd "${PROJECT_ROOT}"
}

# Create a framework from static library
create_framework() {
    local LIB_NAME=$1
    local FRAMEWORK_NAME=$2
    local PLATFORM=$3
    local ARCH=$4
    local PLATFORM_DIR="${BUILD_DIR}/${PLATFORM}"
    local FRAMEWORK_DIR="${PLATFORM_DIR}/${FRAMEWORK_NAME}.framework"

    echo "Creating ${FRAMEWORK_NAME}.framework for ${PLATFORM}..."

    mkdir -p "${FRAMEWORK_DIR}/Headers"
    mkdir -p "${FRAMEWORK_DIR}/Modules"

    # Copy library - check multiple possible locations
    local LIB_PATH=""
    if [ -f "${PLATFORM_DIR}/lib${LIB_NAME}.a" ]; then
        LIB_PATH="${PLATFORM_DIR}/lib${LIB_NAME}.a"
    elif [ -f "${PLATFORM_DIR}/${LIB_NAME}/lib${LIB_NAME}.a" ]; then
        LIB_PATH="${PLATFORM_DIR}/${LIB_NAME}/lib${LIB_NAME}.a"
    elif [ -f "${PLATFORM_DIR}/backends/llamacpp/lib${LIB_NAME}.a" ]; then
        LIB_PATH="${PLATFORM_DIR}/backends/llamacpp/lib${LIB_NAME}.a"
    elif [ -f "${PLATFORM_DIR}/backends/onnx/lib${LIB_NAME}.a" ]; then
        LIB_PATH="${PLATFORM_DIR}/backends/onnx/lib${LIB_NAME}.a"
    elif [ -f "${PLATFORM_DIR}/backends/whispercpp/lib${LIB_NAME}.a" ]; then
        LIB_PATH="${PLATFORM_DIR}/backends/whispercpp/lib${LIB_NAME}.a"
    fi

    if [ -z "${LIB_PATH}" ]; then
        echo -e "${RED}Library lib${LIB_NAME}.a not found${NC}"
        return 1
    fi

    cp "${LIB_PATH}" "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}"

    # Copy headers
    # Handle both direct library names and combined library names
    local BASE_LIB_NAME="${LIB_NAME}"
    BASE_LIB_NAME="${BASE_LIB_NAME/_combined/}"  # Remove _combined suffix if present

    if [ "${BASE_LIB_NAME}" = "rac_commons" ]; then
        # Copy all headers FLAT (no subdirectory structure) and fix includes
        # The headers are organized as include/rac/core/*.h, include/rac/features/llm/*.h, etc.
        # We need to flatten them and update the #include directives for framework compatibility
        cd "${PROJECT_ROOT}/include"
        find rac -name "*.h" | while read -r header; do
            local filename=$(basename "$header")
            # Copy header and fix includes to use framework-style includes
            # Change: #include "rac/core/rac_types.h" -> #include <RACommons/rac_types.h>
            # Change: #include "rac/features/llm/rac_llm_types.h" -> #include <RACommons/rac_llm_types.h>
            sed -e 's|#include "rac/[^"]*\/\([^"]*\)"|#include <RACommons/\1>|g' \
                -e 's|#include "rac_|#include <RACommons/rac_|g' \
                -e 's|\.h"|.h>|g' \
                "$header" > "${FRAMEWORK_DIR}/Headers/${filename}"
        done
        cd "${PROJECT_ROOT}"

        # Also copy with nested structure for backwards compatibility
        cd "${PROJECT_ROOT}/include"
        find rac -name "*.h" | while read -r header; do
            mkdir -p "${FRAMEWORK_DIR}/Headers/$(dirname "$header")"
            sed -e 's|#include "rac/[^"]*\/\([^"]*\)"|#include <RACommons/\1>|g' \
                -e 's|#include "rac_|#include <RACommons/rac_|g' \
                -e 's|\.h"|.h>|g' \
                "$header" > "${FRAMEWORK_DIR}/Headers/$header"
        done
        cd "${PROJECT_ROOT}"
    elif [ "${BASE_LIB_NAME}" = "rac_backend_llamacpp" ]; then
        # Fix includes in backend headers too
        for header in "${PROJECT_ROOT}/backends/llamacpp/include/"*.h; do
            if [ -f "$header" ]; then
                filename=$(basename "$header")
                sed -e 's|#include "rac/[^"]*\/\([^"]*\)"|#include <RACommons/\1>|g' \
                    -e 's|#include "rac_|#include <RACommons/rac_|g' \
                    -e 's|\.h"|.h>|g' \
                    "$header" > "${FRAMEWORK_DIR}/Headers/${filename}"
            fi
        done
    elif [ "${BASE_LIB_NAME}" = "rac_backend_onnx" ]; then
        for header in "${PROJECT_ROOT}/backends/onnx/include/"*.h; do
            if [ -f "$header" ]; then
                filename=$(basename "$header")
                sed -e 's|#include "rac/[^"]*\/\([^"]*\)"|#include <RACommons/\1>|g' \
                    -e 's|#include "rac_|#include <RACommons/rac_|g' \
                    -e 's|\.h"|.h>|g' \
                    "$header" > "${FRAMEWORK_DIR}/Headers/${filename}"
            fi
        done
    elif [ "${BASE_LIB_NAME}" = "rac_backend_whispercpp" ]; then
        for header in "${PROJECT_ROOT}/backends/whispercpp/include/"*.h; do
            if [ -f "$header" ]; then
                filename=$(basename "$header")
                sed -e 's|#include "rac/[^"]*\/\([^"]*\)"|#include <RACommons/\1>|g' \
                    -e 's|#include "rac_|#include <RACommons/rac_|g' \
                    -e 's|\.h"|.h>|g' \
                    "$header" > "${FRAMEWORK_DIR}/Headers/${filename}"
            fi
        done
    fi

    # Create module.modulemap
    cat > "${FRAMEWORK_DIR}/Modules/module.modulemap" << EOF
framework module ${FRAMEWORK_NAME} {
    umbrella header "${FRAMEWORK_NAME}.h"
    export *
    module * { export * }
}
EOF

    # Create umbrella header
    cat > "${FRAMEWORK_DIR}/Headers/${FRAMEWORK_NAME}.h" << EOF
// ${FRAMEWORK_NAME} Umbrella Header
// Auto-generated by build-ios.sh

#ifndef ${FRAMEWORK_NAME}_h
#define ${FRAMEWORK_NAME}_h

EOF

    # Add includes for all headers
    for header in "${FRAMEWORK_DIR}/Headers/"*.h; do
        if [ "$(basename "$header")" != "${FRAMEWORK_NAME}.h" ]; then
            echo "#include \"$(basename "$header")\"" >> "${FRAMEWORK_DIR}/Headers/${FRAMEWORK_NAME}.h"
        fi
    done

    echo "" >> "${FRAMEWORK_DIR}/Headers/${FRAMEWORK_NAME}.h"
    echo "#endif /* ${FRAMEWORK_NAME}_h */" >> "${FRAMEWORK_DIR}/Headers/${FRAMEWORK_NAME}.h"

    # Create Info.plist
    cat > "${FRAMEWORK_DIR}/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${FRAMEWORK_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>ai.runanywhere.${FRAMEWORK_NAME}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${FRAMEWORK_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>${PROJECT_VERSION:-1.0.0}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>MinimumOSVersion</key>
    <string>${IOS_DEPLOYMENT_TARGET}</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>iPhoneOS</string>
    </array>
</dict>
</plist>
EOF
}

# Create XCFramework from device and simulator frameworks
create_xcframework() {
    local FRAMEWORK_NAME=$1
    local XCFRAMEWORK_DIR="${DIST_DIR}/${FRAMEWORK_NAME}.xcframework"

    echo -e "${GREEN}Creating ${FRAMEWORK_NAME}.xcframework...${NC}"

    # Remove existing xcframework
    rm -rf "${XCFRAMEWORK_DIR}"

    # Build xcodebuild command
    local XCODEBUILD_ARGS="-create-xcframework"

    # Add device framework
    if [ -d "${BUILD_DIR}/OS/${FRAMEWORK_NAME}.framework" ]; then
        XCODEBUILD_ARGS="${XCODEBUILD_ARGS} -framework ${BUILD_DIR}/OS/${FRAMEWORK_NAME}.framework"
    fi

    # Add simulator framework (combine arm64 and x86_64 if both exist)
    if [ -d "${BUILD_DIR}/SIMULATORARM64/${FRAMEWORK_NAME}.framework" ] && [ -d "${BUILD_DIR}/SIMULATOR/${FRAMEWORK_NAME}.framework" ]; then
        # Create fat binary for simulator
        local SIM_FAT_DIR="${BUILD_DIR}/SIMULATOR_FAT"
        mkdir -p "${SIM_FAT_DIR}"
        cp -R "${BUILD_DIR}/SIMULATORARM64/${FRAMEWORK_NAME}.framework" "${SIM_FAT_DIR}/"

        lipo -create \
            "${BUILD_DIR}/SIMULATORARM64/${FRAMEWORK_NAME}.framework/${FRAMEWORK_NAME}" \
            "${BUILD_DIR}/SIMULATOR/${FRAMEWORK_NAME}.framework/${FRAMEWORK_NAME}" \
            -output "${SIM_FAT_DIR}/${FRAMEWORK_NAME}.framework/${FRAMEWORK_NAME}"

        XCODEBUILD_ARGS="${XCODEBUILD_ARGS} -framework ${SIM_FAT_DIR}/${FRAMEWORK_NAME}.framework"
    elif [ -d "${BUILD_DIR}/SIMULATORARM64/${FRAMEWORK_NAME}.framework" ]; then
        XCODEBUILD_ARGS="${XCODEBUILD_ARGS} -framework ${BUILD_DIR}/SIMULATORARM64/${FRAMEWORK_NAME}.framework"
    fi

    XCODEBUILD_ARGS="${XCODEBUILD_ARGS} -output ${XCFRAMEWORK_DIR}"

    xcodebuild ${XCODEBUILD_ARGS}

    echo -e "${GREEN}Created: ${XCFRAMEWORK_DIR}${NC}"
}

# Combine all LlamaCPP-related static libraries into one fat library
combine_llamacpp_libs() {
    local PLATFORM=$1
    local PLATFORM_DIR="${BUILD_DIR}/${PLATFORM}"
    local OUTPUT_LIB="${PLATFORM_DIR}/librac_backend_llamacpp_combined.a"

    echo "Combining LlamaCPP libraries for ${PLATFORM}..."

    # Collect all needed libraries
    local LIBS=""

    # Our wrapper library
    [ -f "${PLATFORM_DIR}/backends/llamacpp/librac_backend_llamacpp.a" ] && LIBS="$LIBS ${PLATFORM_DIR}/backends/llamacpp/librac_backend_llamacpp.a"

    # runanywhere-core LlamaCPP backend (pre-built or compiled)
    if [ -f "${PROJECT_ROOT}/third_party/runanywhere-core-prebuilt/lib/librunanywhere_llamacpp.a" ]; then
        LIBS="$LIBS ${PROJECT_ROOT}/third_party/runanywhere-core-prebuilt/lib/librunanywhere_llamacpp.a"
    elif [ -f "${PROJECT_ROOT}/third_party/runanywhere-core-prebuilt/librunanywhere_llamacpp.a" ]; then
        LIBS="$LIBS ${PROJECT_ROOT}/third_party/runanywhere-core-prebuilt/librunanywhere_llamacpp.a"
    elif [ -f "${PLATFORM_DIR}/runanywhere-core/src/backends/llamacpp/librunanywhere_llamacpp.a" ]; then
        LIBS="$LIBS ${PLATFORM_DIR}/runanywhere-core/src/backends/llamacpp/librunanywhere_llamacpp.a"
    fi

    # llama.cpp libraries
    [ -f "${PLATFORM_DIR}/_deps/llamacpp-build/src/libllama.a" ] && LIBS="$LIBS ${PLATFORM_DIR}/_deps/llamacpp-build/src/libllama.a"
    [ -f "${PLATFORM_DIR}/_deps/llamacpp-build/common/libcommon.a" ] && LIBS="$LIBS ${PLATFORM_DIR}/_deps/llamacpp-build/common/libcommon.a"

    # GGML libraries
    [ -f "${PLATFORM_DIR}/_deps/llamacpp-build/ggml/src/libggml.a" ] && LIBS="$LIBS ${PLATFORM_DIR}/_deps/llamacpp-build/ggml/src/libggml.a"
    [ -f "${PLATFORM_DIR}/_deps/llamacpp-build/ggml/src/libggml-base.a" ] && LIBS="$LIBS ${PLATFORM_DIR}/_deps/llamacpp-build/ggml/src/libggml-base.a"
    [ -f "${PLATFORM_DIR}/_deps/llamacpp-build/ggml/src/libggml-cpu.a" ] && LIBS="$LIBS ${PLATFORM_DIR}/_deps/llamacpp-build/ggml/src/libggml-cpu.a"
    [ -f "${PLATFORM_DIR}/_deps/llamacpp-build/ggml/src/ggml-metal/libggml-metal.a" ] && LIBS="$LIBS ${PLATFORM_DIR}/_deps/llamacpp-build/ggml/src/ggml-metal/libggml-metal.a"
    [ -f "${PLATFORM_DIR}/_deps/llamacpp-build/ggml/src/ggml-blas/libggml-blas.a" ] && LIBS="$LIBS ${PLATFORM_DIR}/_deps/llamacpp-build/ggml/src/ggml-blas/libggml-blas.a"

    if [ -n "$LIBS" ]; then
        libtool -static -o "${OUTPUT_LIB}" $LIBS
        echo "Created combined library: ${OUTPUT_LIB} ($(du -h "${OUTPUT_LIB}" | cut -f1))"
    else
        echo -e "${RED}No LlamaCPP libraries found to combine${NC}"
        return 1
    fi
}

# Combine all ONNX-related static libraries into one fat library
# NOTE: We don't include ONNX Runtime here - it should be linked separately via its xcframework
# This avoids architecture conflicts and keeps the framework sizes manageable
combine_onnx_libs() {
    local PLATFORM=$1
    local PLATFORM_DIR="${BUILD_DIR}/${PLATFORM}"
    local OUTPUT_LIB="${PLATFORM_DIR}/librac_backend_onnx_combined.a"

    echo "Combining ONNX libraries for ${PLATFORM}..."

    # Collect all needed libraries (excluding ONNX Runtime itself)
    local LIBS=""

    # Our wrapper library
    [ -f "${PLATFORM_DIR}/backends/onnx/librac_backend_onnx.a" ] && LIBS="$LIBS ${PLATFORM_DIR}/backends/onnx/librac_backend_onnx.a"

    # runanywhere-core ONNX backend (pre-built or compiled)
    if [ -f "${PROJECT_ROOT}/third_party/runanywhere-core-prebuilt/lib/librunanywhere_onnx.a" ]; then
        LIBS="$LIBS ${PROJECT_ROOT}/third_party/runanywhere-core-prebuilt/lib/librunanywhere_onnx.a"
    elif [ -f "${PROJECT_ROOT}/third_party/runanywhere-core-prebuilt/librunanywhere_onnx.a" ]; then
        LIBS="$LIBS ${PROJECT_ROOT}/third_party/runanywhere-core-prebuilt/librunanywhere_onnx.a"
    elif [ -f "${PLATFORM_DIR}/runanywhere-core/src/backends/onnx/librunanywhere_onnx.a" ]; then
        LIBS="$LIBS ${PLATFORM_DIR}/runanywhere-core/src/backends/onnx/librunanywhere_onnx.a"
    fi

    # runanywhere-core bridge (provides ra_create_backend, ra_initialize) (pre-built or compiled)
    if [ -f "${PROJECT_ROOT}/third_party/runanywhere-core-prebuilt/lib/librunanywhere_bridge.a" ]; then
        LIBS="$LIBS ${PROJECT_ROOT}/third_party/runanywhere-core-prebuilt/lib/librunanywhere_bridge.a"
    elif [ -f "${PROJECT_ROOT}/third_party/runanywhere-core-prebuilt/librunanywhere_bridge.a" ]; then
        LIBS="$LIBS ${PROJECT_ROOT}/third_party/runanywhere-core-prebuilt/librunanywhere_bridge.a"
    elif [ -f "${PLATFORM_DIR}/runanywhere-core/librunanywhere_bridge.a" ]; then
        LIBS="$LIBS ${PLATFORM_DIR}/runanywhere-core/librunanywhere_bridge.a"
    fi

    # Sherpa-ONNX static library (provides STT/TTS/VAD implementations)
    # Uses global SHERPA_ONNX_XCFW set at script start based on BUILD_MODE
    local SHERPA_LIB=""
    if [ -d "${SHERPA_ONNX_XCFW}" ]; then
        if [ "${PLATFORM}" = "OS" ]; then
            SHERPA_LIB="${SHERPA_ONNX_XCFW}/ios-arm64/libsherpa-onnx.a"
        elif [ "${PLATFORM}" = "SIMULATORARM64" ]; then
            # Extract arm64 slice from fat simulator binary
            local SHERPA_SIM_LIB="${SHERPA_ONNX_XCFW}/ios-arm64_x86_64-simulator/libsherpa-onnx.a"
            if [ -f "${SHERPA_SIM_LIB}" ]; then
                SHERPA_LIB="${PLATFORM_DIR}/libsherpa-onnx-arm64.a"
                lipo -extract arm64 "${SHERPA_SIM_LIB}" -output "${SHERPA_LIB}" 2>/dev/null || \
                lipo -thin arm64 "${SHERPA_SIM_LIB}" -output "${SHERPA_LIB}" 2>/dev/null || \
                cp "${SHERPA_SIM_LIB}" "${SHERPA_LIB}"
            fi
        elif [ "${PLATFORM}" = "SIMULATOR" ]; then
            # Extract x86_64 slice from fat simulator binary
            local SHERPA_SIM_LIB="${SHERPA_ONNX_XCFW}/ios-arm64_x86_64-simulator/libsherpa-onnx.a"
            if [ -f "${SHERPA_SIM_LIB}" ]; then
                SHERPA_LIB="${PLATFORM_DIR}/libsherpa-onnx-x86_64.a"
                lipo -extract x86_64 "${SHERPA_SIM_LIB}" -output "${SHERPA_LIB}" 2>/dev/null || \
                lipo -thin x86_64 "${SHERPA_SIM_LIB}" -output "${SHERPA_LIB}" 2>/dev/null || \
                cp "${SHERPA_SIM_LIB}" "${SHERPA_LIB}"
            fi
        fi

        if [ -f "${SHERPA_LIB}" ]; then
            LIBS="$LIBS ${SHERPA_LIB}"
            echo "  Including Sherpa-ONNX: ${SHERPA_LIB}"
        else
            echo -e "${YELLOW}Warning: Sherpa-ONNX library not found at ${SHERPA_LIB}${NC}"
        fi
    else
        echo -e "${YELLOW}Warning: Sherpa-ONNX xcframework not found at ${SHERPA_ONNX_XCFW}${NC}"
    fi

    # NOTE: ONNX Runtime xcframework is NOT bundled here.
    # It should be linked separately by the consuming app/framework.
    # This is because the ONNX Runtime xcframework has a specific structure
    # that's hard to merge properly with libtool.

    if [ -n "$LIBS" ]; then
        libtool -static -o "${OUTPUT_LIB}" $LIBS
        echo "Created combined library: ${OUTPUT_LIB} ($(du -h "${OUTPUT_LIB}" | cut -f1))"
        echo "  NOTE: ONNX Runtime xcframework must be linked separately"
    else
        echo -e "${RED}No ONNX libraries found to combine${NC}"
        return 1
    fi
}

# Main build process
main() {
    clean_build

    # Build for device (arm64)
    build_platform "OS"

    # Build for simulator (arm64 for Apple Silicon Macs)
    build_platform "SIMULATORARM64"

    # Build for simulator (x86_64 for Intel Macs)
    build_platform "SIMULATOR"

    # Combine backend libraries for each platform
    echo -e "${GREEN}Combining backend libraries...${NC}"

    if [ "${BUILD_LLAMACPP}" = "ON" ]; then
        combine_llamacpp_libs "OS"
        combine_llamacpp_libs "SIMULATORARM64"
        combine_llamacpp_libs "SIMULATOR"
    fi

    if [ "${BUILD_ONNX}" = "ON" ]; then
        combine_onnx_libs "OS"
        combine_onnx_libs "SIMULATORARM64"
        combine_onnx_libs "SIMULATOR"
    fi

    # Create output directory
    mkdir -p "${DIST_DIR}"

    # Create frameworks for each platform
    echo -e "${GREEN}Creating frameworks...${NC}"

    # RACommons
    create_framework "rac_commons" "RACommons" "OS" "arm64"
    create_framework "rac_commons" "RACommons" "SIMULATORARM64" "arm64"
    create_framework "rac_commons" "RACommons" "SIMULATOR" "x86_64"
    create_xcframework "RACommons"

    # Backend frameworks (if enabled) - use combined libraries
    if [ "${BUILD_LLAMACPP}" = "ON" ]; then
        create_framework "rac_backend_llamacpp_combined" "RABackendLlamaCPP" "OS" "arm64"
        create_framework "rac_backend_llamacpp_combined" "RABackendLlamaCPP" "SIMULATORARM64" "arm64"
        create_framework "rac_backend_llamacpp_combined" "RABackendLlamaCPP" "SIMULATOR" "x86_64"
        create_xcframework "RABackendLlamaCPP"
    fi

    if [ "${BUILD_ONNX}" = "ON" ]; then
        create_framework "rac_backend_onnx_combined" "RABackendONNX" "OS" "arm64"
        create_framework "rac_backend_onnx_combined" "RABackendONNX" "SIMULATORARM64" "arm64"
        create_framework "rac_backend_onnx_combined" "RABackendONNX" "SIMULATOR" "x86_64"
        create_xcframework "RABackendONNX"
    fi

    if [ "${BUILD_WHISPERCPP}" = "ON" ]; then
        create_framework "rac_backend_whispercpp" "RABackendWhisperCPP" "OS" "arm64"
        create_framework "rac_backend_whispercpp" "RABackendWhisperCPP" "SIMULATORARM64" "arm64"
        create_framework "rac_backend_whispercpp" "RABackendWhisperCPP" "SIMULATOR" "x86_64"
        create_xcframework "RABackendWhisperCPP"
    fi

    # Print sizes
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Build Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo "Output: ${DIST_DIR}"
    echo ""
    echo "Framework sizes:"
    for xcf in "${DIST_DIR}"/*.xcframework; do
        if [ -d "$xcf" ]; then
            size=$(du -sh "$xcf" | cut -f1)
            echo "  $(basename "$xcf"): $size"
        fi
    done
}

main "$@"
