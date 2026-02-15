#!/bin/bash
# =============================================================================
# Create Combined ONNX Runtime XCFramework (iOS + macOS)
# =============================================================================
#
# Combines the iOS ONNX Runtime xcframework (from pod archive) with
# the macOS ONNX Runtime dylib into a single xcframework.
#
# This is needed because:
# - The pod archive from onnxruntime.ai only contains iOS slices
# - The macOS release from GitHub only contains macOS dylibs
# - SPM needs a single xcframework binary target for both platforms
#
# Prerequisites:
#   - iOS ONNX Runtime: sdk/runanywhere-commons/third_party/onnxruntime-ios/
#   - macOS ONNX Runtime: sdk/runanywhere-commons/third_party/onnxruntime-macos/
#
# Output:
#   sdk/runanywhere-swift/Binaries/onnxruntime.xcframework
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWIFT_SDK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SDK_DIR="$(cd "${SWIFT_SDK_DIR}/.." && pwd)"
COMMONS_DIR="${SDK_DIR}/runanywhere-commons"
OUTPUT_DIR="${SWIFT_SDK_DIR}/Binaries"

# Source paths
IOS_ONNX="${COMMONS_DIR}/third_party/onnxruntime-ios/onnxruntime.xcframework"
MACOS_ONNX="${COMMONS_DIR}/third_party/onnxruntime-macos"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
log_step()  { echo -e "${BLUE}==>${NC} $1"; }

echo ""
echo "═══════════════════════════════════════════"
echo " ONNX Runtime - Combined XCFramework"
echo "═══════════════════════════════════════════"
echo ""

# Verify iOS ONNX Runtime exists
if [[ ! -d "${IOS_ONNX}" ]]; then
    log_error "iOS ONNX Runtime not found at: ${IOS_ONNX}"
fi

# Verify macOS ONNX Runtime exists
if [[ ! -d "${MACOS_ONNX}/lib" ]]; then
    log_error "macOS ONNX Runtime not found at: ${MACOS_ONNX}/lib\nRun: cd sdk/runanywhere-commons && ./scripts/macos/download-onnx.sh"
fi

TEMP_DIR=$(mktemp -d)

# ============================================================================
# Step 1: Extract iOS frameworks from existing xcframework
# ============================================================================
log_step "Extracting iOS frameworks from existing xcframework..."

# Copy iOS device framework
IOS_DEVICE_DIR=""
IOS_SIM_DIR=""
for dir in "${IOS_ONNX}"/*/; do
    dir_name=$(basename "$dir")
    if [[ "$dir_name" == "ios-arm64" ]]; then
        IOS_DEVICE_DIR="$dir"
    elif [[ "$dir_name" == *"simulator"* ]]; then
        IOS_SIM_DIR="$dir"
    fi
done

if [[ -z "$IOS_DEVICE_DIR" ]]; then
    log_error "Could not find ios-arm64 slice in ${IOS_ONNX}"
fi

# ============================================================================
# Step 2: Create macOS framework from dylib
# ============================================================================
log_step "Creating macOS framework from dylib..."

MACOS_FW="${TEMP_DIR}/macos-arm64/onnxruntime.framework"
# macOS frameworks require versioned bundle layout
mkdir -p "${MACOS_FW}/Versions/A/Headers"
mkdir -p "${MACOS_FW}/Versions/A/Modules"
mkdir -p "${MACOS_FW}/Versions/A/Resources"

# Find the actual dylib
DYLIB_PATH="${MACOS_ONNX}/lib/libonnxruntime.dylib"
if [[ ! -f "${DYLIB_PATH}" ]]; then
    # Try to find a versioned dylib
    DYLIB_PATH=$(find "${MACOS_ONNX}/lib" -name "libonnxruntime*.dylib" -not -name "*_providers*" | head -1)
fi

if [[ -z "${DYLIB_PATH}" || ! -f "${DYLIB_PATH}" ]]; then
    log_error "Could not find ONNX Runtime dylib in ${MACOS_ONNX}/lib/"
fi

# Copy the dylib as the framework binary (into versioned dir)
cp "${DYLIB_PATH}" "${MACOS_FW}/Versions/A/onnxruntime"

# Fix the install name to be framework-relative
install_name_tool -id "@rpath/onnxruntime.framework/Versions/A/onnxruntime" "${MACOS_FW}/Versions/A/onnxruntime" 2>/dev/null || true

# Ad-hoc sign the dylib so Xcode can codesign the app bundle
codesign --force --sign - "${MACOS_FW}/Versions/A/onnxruntime"
log_info "Ad-hoc signed macOS onnxruntime binary"

# Copy headers
if [[ -d "${MACOS_ONNX}/include" ]]; then
    cp -R "${MACOS_ONNX}/include/"* "${MACOS_FW}/Versions/A/Headers/" 2>/dev/null || true
fi

# Module map
cat > "${MACOS_FW}/Versions/A/Modules/module.modulemap" << 'EOF'
framework module onnxruntime {
    umbrella header "onnxruntime_c_api.h"
    export *
    module * { export * }
}
EOF

# Info.plist in Resources
cat > "${MACOS_FW}/Versions/A/Resources/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>onnxruntime</string>
    <key>CFBundleIdentifier</key><string>ai.onnxruntime</string>
    <key>CFBundlePackageType</key><string>FMWK</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict>
</plist>
EOF

# Create versioned symlinks
cd "${MACOS_FW}/Versions" && ln -sf A Current
cd "${MACOS_FW}"
ln -sf Versions/Current/onnxruntime onnxruntime
ln -sf Versions/Current/Headers Headers
ln -sf Versions/Current/Modules Modules
ln -sf Versions/Current/Resources Resources
cd "${SCRIPT_DIR}"

log_info "Created macOS framework"

# ============================================================================
# Step 3: Create combined XCFramework
# ============================================================================
log_step "Creating combined xcframework..."

XCFW_OUTPUT="${OUTPUT_DIR}/onnxruntime.xcframework"
rm -rf "${XCFW_OUTPUT}"
mkdir -p "${OUTPUT_DIR}"

# Build the xcframework command args
XCFW_ARGS=()

# Add iOS device framework (from existing xcframework)
if [[ -n "$IOS_DEVICE_DIR" ]]; then
    # Check if it's a framework or static lib
    if [[ -d "${IOS_DEVICE_DIR}/onnxruntime.framework" ]]; then
        XCFW_ARGS+=(-framework "${IOS_DEVICE_DIR}/onnxruntime.framework")
    elif [[ -f "${IOS_DEVICE_DIR}/libonnxruntime.a" ]]; then
        XCFW_ARGS+=(-library "${IOS_DEVICE_DIR}/libonnxruntime.a")
        if [[ -d "${IOS_DEVICE_DIR}/Headers" ]]; then
            XCFW_ARGS+=(-headers "${IOS_DEVICE_DIR}/Headers")
        fi
    fi
fi

# Add iOS simulator framework
if [[ -n "$IOS_SIM_DIR" ]]; then
    if [[ -d "${IOS_SIM_DIR}/onnxruntime.framework" ]]; then
        XCFW_ARGS+=(-framework "${IOS_SIM_DIR}/onnxruntime.framework")
    elif [[ -f "${IOS_SIM_DIR}/libonnxruntime.a" ]]; then
        XCFW_ARGS+=(-library "${IOS_SIM_DIR}/libonnxruntime.a")
        if [[ -d "${IOS_SIM_DIR}/Headers" ]]; then
            XCFW_ARGS+=(-headers "${IOS_SIM_DIR}/Headers")
        fi
    fi
fi

# Add macOS framework
XCFW_ARGS+=(-framework "${MACOS_FW}")

xcodebuild -create-xcframework "${XCFW_ARGS[@]}" -output "${XCFW_OUTPUT}"

# Clean up
rm -rf "${TEMP_DIR}"

# Verify
if [[ -d "${XCFW_OUTPUT}" ]]; then
    log_info "Combined ONNX Runtime xcframework created!"
    echo ""
    echo "Output: ${XCFW_OUTPUT}"
    echo "Size: $(du -sh "${XCFW_OUTPUT}" | cut -f1)"
    echo ""
    echo "Slices:"
    for dir in "${XCFW_OUTPUT}"/*/; do
        [[ -d "$dir" ]] && echo "  $(basename "$dir")"
    done
else
    log_error "Failed to create combined xcframework"
fi
