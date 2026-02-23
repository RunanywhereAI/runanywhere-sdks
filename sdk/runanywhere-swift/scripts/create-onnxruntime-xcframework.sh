#!/bin/bash
# =============================================================================
# Create ONNX Runtime XCFrameworks (iOS + macOS, separate)
# =============================================================================
#
# Creates TWO separate xcframeworks:
#   - onnxruntime-ios.xcframework  (library format, static .a)
#   - onnxruntime-macos.xcframework (framework format, dynamic dylib)
#
# Why separate?
#   - iOS uses static libraries → library format prevents SPM from embedding
#   - macOS uses dynamic library → framework format allows proper embedding
#   - xcframeworks can't mix static/dynamic or library/framework formats
#   - Package.swift uses platform-conditional dependencies to pick the right one
#
# Prerequisites:
#   - iOS ONNX Runtime: sdk/runanywhere-commons/third_party/onnxruntime-ios/
#   - macOS ONNX Runtime: sdk/runanywhere-commons/third_party/onnxruntime-macos/
#
# Output:
#   sdk/runanywhere-swift/Binaries/onnxruntime-ios.xcframework
#   sdk/runanywhere-swift/Binaries/onnxruntime-macos.xcframework
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
echo " ONNX Runtime - Split XCFrameworks"
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
mkdir -p "${OUTPUT_DIR}"

# ============================================================================
# Step 1: Create iOS xcframework (library format, static)
# ============================================================================
log_step "Creating onnxruntime-ios.xcframework (library format)..."

# Find iOS slices from existing xcframework
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

# Extract static libraries and headers from .framework wrappers
XCFW_ARGS=()

for SLICE_DIR in "$IOS_DEVICE_DIR" "$IOS_SIM_DIR"; do
    [[ -z "$SLICE_DIR" ]] && continue
    SLICE_NAME=$(basename "$SLICE_DIR")
    DEST="${TEMP_DIR}/ios/${SLICE_NAME}"
    mkdir -p "$DEST"

    if [[ -d "${SLICE_DIR}/onnxruntime.framework" ]]; then
        # Extract .a from .framework wrapper
        cp "${SLICE_DIR}/onnxruntime.framework/onnxruntime" "${DEST}/libonnxruntime.a"
        cp -R "${SLICE_DIR}/onnxruntime.framework/Headers" "${DEST}/Headers" 2>/dev/null || true
    elif [[ -f "${SLICE_DIR}/libonnxruntime.a" ]]; then
        # Already in library format
        cp "${SLICE_DIR}/libonnxruntime.a" "${DEST}/libonnxruntime.a"
        [[ -d "${SLICE_DIR}/Headers" ]] && cp -R "${SLICE_DIR}/Headers" "${DEST}/Headers"
    else
        log_error "Could not find onnxruntime binary in ${SLICE_DIR}"
    fi

    XCFW_ARGS+=(-library "${DEST}/libonnxruntime.a")
    [[ -d "${DEST}/Headers" ]] && XCFW_ARGS+=(-headers "${DEST}/Headers")
    log_info "  Prepared ${SLICE_NAME} slice"
done

IOS_XCFW="${OUTPUT_DIR}/onnxruntime-ios.xcframework"
rm -rf "${IOS_XCFW}"
xcodebuild -create-xcframework "${XCFW_ARGS[@]}" -output "${IOS_XCFW}"
log_info "Created onnxruntime-ios.xcframework"

# ============================================================================
# Step 2: Create macOS xcframework (framework format, dynamic)
# ============================================================================
log_step "Creating onnxruntime-macos.xcframework (framework format)..."

MACOS_FW="${TEMP_DIR}/macos-arm64/onnxruntime.framework"
# macOS frameworks require versioned bundle layout
mkdir -p "${MACOS_FW}/Versions/A/Headers"
mkdir -p "${MACOS_FW}/Versions/A/Modules"
mkdir -p "${MACOS_FW}/Versions/A/Resources"

# Find the actual dylib
DYLIB_PATH="${MACOS_ONNX}/lib/libonnxruntime.dylib"
if [[ ! -f "${DYLIB_PATH}" ]]; then
    DYLIB_PATH=$(find "${MACOS_ONNX}/lib" -name "libonnxruntime*.dylib" -not -name "*_providers*" | head -1)
fi

if [[ -z "${DYLIB_PATH}" || ! -f "${DYLIB_PATH}" ]]; then
    log_error "Could not find ONNX Runtime dylib in ${MACOS_ONNX}/lib/"
fi

# Copy the dylib as the framework binary
cp "${DYLIB_PATH}" "${MACOS_FW}/Versions/A/onnxruntime"

# Fix the install name to be framework-relative
install_name_tool -id "@rpath/onnxruntime.framework/Versions/A/onnxruntime" "${MACOS_FW}/Versions/A/onnxruntime" 2>/dev/null || true

# Ad-hoc sign the dylib
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
    <key>CFBundleShortVersionString</key><string>1.17.1</string>
    <key>CFBundleVersion</key><string>1.17.1</string>
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

MACOS_XCFW="${OUTPUT_DIR}/onnxruntime-macos.xcframework"
rm -rf "${MACOS_XCFW}"
xcodebuild -create-xcframework -framework "${MACOS_FW}" -output "${MACOS_XCFW}"
log_info "Created onnxruntime-macos.xcframework"

# Clean up
rm -rf "${TEMP_DIR}"

# ============================================================================
# Verify
# ============================================================================
echo ""
log_step "Verification"

for XCFW_NAME in "onnxruntime-ios" "onnxruntime-macos"; do
    XCFW="${OUTPUT_DIR}/${XCFW_NAME}.xcframework"
    if [[ -d "${XCFW}" ]]; then
        echo ""
        echo "  ${XCFW_NAME}.xcframework:"
        echo "    Size: $(du -sh "${XCFW}" | cut -f1)"
        echo "    Slices:"
        for dir in "${XCFW}"/*/; do
            [[ -d "$dir" ]] && echo "      $(basename "$dir")"
        done
    else
        log_error "Failed to create ${XCFW_NAME}.xcframework"
    fi
done

echo ""
log_info "Done! Both xcframeworks created in ${OUTPUT_DIR}"
