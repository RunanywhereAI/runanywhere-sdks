#!/bin/bash

# =============================================================================
# check_16kb_alignment.sh
# Verifies that all native libraries in the APK/AAB have 16KB page alignment
#
# Usage: ./check_16kb_alignment.sh <path-to-apk-or-aab>
#
# Requirements:
# - Android NDK (for llvm-readelf) - required on macOS
# - unzip
#
# Exit codes:
# - 0: All libraries are 16KB aligned (Google Play ready)
# - 1: Some libraries are NOT 16KB aligned (will fail Google Play)
#
# 16KB Page Size Alignment (Google Play requirement)
# --------------------------------------------------
# Starting November 1, 2025, Google Play requires all apps targeting
# Android 15+ (API 35+) to have 16KB-aligned native libraries.
#
# Alignment values in ELF LOAD segments:
#   0x4000 (16384 bytes) = 16KB aligned - PASS
#   0x1000 (4096 bytes)  = 4KB aligned  - FAIL
# =============================================================================

set -e

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

print_success() {
    echo -e "${GREEN}[OK] $1${NC}"
}

print_error() {
    echo -e "${RED}[FAIL] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[WARN] $1${NC}"
}

print_info() {
    echo -e "${CYAN}[INFO] $1${NC}"
}

# Find readelf binary - prefer NDK's llvm-readelf on macOS
find_readelf() {
    local NDK_READELF=""
    local NDK_BASE=""

    # Check system readelf first (Linux)
    if command -v readelf &> /dev/null; then
        echo "readelf"
        return 0
    fi

    # Check llvm-readelf in PATH
    if command -v llvm-readelf &> /dev/null; then
        echo "llvm-readelf"
        return 0
    fi

    # Determine NDK base directory
    if [ -n "$ANDROID_NDK_HOME" ] && [ -d "$ANDROID_NDK_HOME" ]; then
        NDK_BASE="$ANDROID_NDK_HOME"
    elif [ -n "$ANDROID_HOME" ] && [ -d "$ANDROID_HOME/ndk" ]; then
        NDK_BASE=$(ls -d "$ANDROID_HOME/ndk"/*/ 2>/dev/null | sort -V | tail -1)
        NDK_BASE="${NDK_BASE%/}"
    elif [ -d "$HOME/Library/Android/sdk/ndk" ]; then
        NDK_BASE=$(ls -d "$HOME/Library/Android/sdk/ndk"/*/ 2>/dev/null | sort -V | tail -1)
        NDK_BASE="${NDK_BASE%/}"
    elif [ -d "/usr/local/lib/android/sdk/ndk" ]; then
        NDK_BASE=$(ls -d "/usr/local/lib/android/sdk/ndk"/*/ 2>/dev/null | sort -V | tail -1)
        NDK_BASE="${NDK_BASE%/}"
    fi

    # Check for llvm-readelf in the NDK
    if [ -n "$NDK_BASE" ]; then
        for platform in darwin-x86_64 darwin-arm64 linux-x86_64 windows-x86_64; do
            local path="$NDK_BASE/toolchains/llvm/prebuilt/$platform/bin/llvm-readelf"
            if [ -f "$path" ]; then
                NDK_READELF="$path"
                break
            fi
        done
    fi

    if [ -n "$NDK_READELF" ] && [ -f "$NDK_READELF" ]; then
        echo "$NDK_READELF"
        return 0
    fi

    return 1
}

# Check alignment for a single .so file
# Returns: "16KB", "4KB", or "UNKNOWN"
check_so_alignment() {
    local SO_FILE="$1"
    local READELF="$2"

    # Get LOAD segment information
    local LOAD_OUTPUT
    LOAD_OUTPUT=$("$READELF" -l "$SO_FILE" 2>/dev/null | grep "LOAD" || true)

    if [ -z "$LOAD_OUTPUT" ]; then
        echo "UNKNOWN"
        return
    fi

    local FOUND_4KB=0
    local FOUND_16KB=0

    # Parse each LOAD line and check the alignment (last hex value)
    while IFS= read -r line; do
        [ -z "$line" ] && continue

        # Extract alignment - the last hex value on the line
        # The format is: LOAD <offset> <vaddr> <paddr> <filesz> <memsz> <flags> <align>
        local align
        align=$(echo "$line" | awk '{print $NF}')

        # Check if it's a hex value
        case "$align" in
            0x1000|0x001000)
                FOUND_4KB=1
                ;;
            0x4000|0x004000)
                FOUND_16KB=1
                ;;
        esac
    done <<< "$LOAD_OUTPUT"

    # If any LOAD segment has 4KB alignment, the library is NOT 16KB compatible
    if [ "$FOUND_4KB" -eq 1 ]; then
        echo "4KB"
    elif [ "$FOUND_16KB" -eq 1 ]; then
        echo "16KB"
    else
        echo "UNKNOWN"
    fi
}

# Main script
if [ $# -eq 0 ]; then
    echo "Usage: $0 <path-to-apk-or-aab>"
    echo ""
    echo "Examples:"
    echo "  $0 app/build/outputs/apk/release/app-release.apk"
    echo "  $0 app/build/outputs/bundle/release/app-release.aab"
    echo ""
    echo "This script checks if all native libraries (.so files) are built"
    echo "with 16KB page alignment, as required by Google Play for apps"
    echo "targeting Android 15 (API 35+) starting November 1, 2025."
    exit 1
fi

APK_PATH="$1"

if [ ! -f "$APK_PATH" ]; then
    print_error "File not found: $APK_PATH"
    exit 1
fi

print_header "16KB Page Size Alignment Checker"
echo "Analyzing: $APK_PATH"
echo ""

# Find readelf
READELF=$(find_readelf) || {
    print_error "No readelf tool found!"
    echo ""
    echo "Please install Android NDK, then try again."
    echo ""
    echo "Quick fix for macOS:"
    echo "  1. Open Android Studio"
    echo "  2. SDK Manager > SDK Tools > NDK (Side by side)"
    echo "  3. Install any NDK version"
    exit 1
}

print_info "Using readelf: $READELF"

# Create temp directory for extraction
TEMP_DIR=$(mktemp -d)
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Extract APK/AAB
print_header "Extracting archive..."
unzip -o -q "$APK_PATH" -d "$TEMP_DIR" 2>/dev/null || {
    print_error "Failed to extract archive"
    exit 1
}
print_success "Extracted successfully"

# Find all .so files
SO_FILES=$(find "$TEMP_DIR" -name "*.so" -type f 2>/dev/null)

if [ -z "$SO_FILES" ]; then
    print_warning "No native libraries (.so files) found in the archive"
    echo "This app does not use native code, so 16KB alignment is not required."
    exit 0
fi

print_header "Checking ELF Segment Alignment"

echo "Alignment legend:"
echo "  0x4000 = 16KB aligned [OK]  - Google Play ready"
echo "  0x1000 = 4KB aligned  [FAIL] - Will be rejected"
echo ""

TOTAL_COUNT=0
ALIGNED_COUNT=0
MISALIGNED_COUNT=0
UNKNOWN_COUNT=0
MISALIGNED_LIBS=""
UNKNOWN_LIBS=""

while IFS= read -r SO_FILE; do
    [ -z "$SO_FILE" ] && continue

    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    SO_NAME=$(basename "$SO_FILE")

    ALIGNMENT=$(check_so_alignment "$SO_FILE" "$READELF")

    case "$ALIGNMENT" in
        "16KB")
            print_success "$SO_NAME - 16KB aligned"
            ALIGNED_COUNT=$((ALIGNED_COUNT + 1))
            ;;
        "4KB")
            print_error "$SO_NAME - 4KB aligned (NOT 16KB compatible)"
            MISALIGNED_COUNT=$((MISALIGNED_COUNT + 1))
            MISALIGNED_LIBS="$MISALIGNED_LIBS  - $SO_NAME\n"
            ;;
        *)
            print_warning "$SO_NAME - Could not determine alignment"
            UNKNOWN_COUNT=$((UNKNOWN_COUNT + 1))
            UNKNOWN_LIBS="$UNKNOWN_LIBS  - $SO_NAME\n"
            ;;
    esac
done <<< "$SO_FILES"

# Final summary
print_header "Summary"
echo "Total libraries checked: $TOTAL_COUNT"
echo -e "16KB aligned: ${GREEN}$ALIGNED_COUNT${NC}"
echo -e "4KB aligned:  ${RED}$MISALIGNED_COUNT${NC}"
echo -e "Unknown:      ${YELLOW}$UNKNOWN_COUNT${NC}"
echo ""

if [ "$MISALIGNED_COUNT" -gt 0 ]; then
    print_error "16KB alignment check FAILED!"
    echo ""
    echo "Misaligned libraries (must be rebuilt):"
    echo -e "$MISALIGNED_LIBS"
    echo ""
    echo "Required actions:"
    echo "  1. Rebuild native libraries with 16KB alignment flags:"
    echo "     LDFLAGS: -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384"
    echo ""
    echo "  2. For runanywhere-core, update to latest release that includes the fix"
    echo ""
    echo "  3. For third-party libraries (like libonnxruntime.so):"
    echo "     - Sherpa-ONNX v1.12.20+ includes 16KB-aligned libonnxruntime.so"
    echo "     - Update to the latest runanywhere-binaries release"
    echo ""
    echo "See: https://developer.android.com/guide/practices/page-sizes"
    exit 1
elif [ "$UNKNOWN_COUNT" -gt 0 ]; then
    print_warning "Could not verify all libraries"
    echo ""
    echo "Libraries with unknown alignment:"
    echo -e "$UNKNOWN_LIBS"
    echo ""
    echo "Please manually verify these libraries are 16KB aligned."
    exit 1
else
    print_success "All native libraries are 16KB aligned!"
    echo ""
    echo "Your app is ready for:"
    echo "  - Android 15+ devices with 16KB page sizes"
    echo "  - Google Play Store submission (targeting SDK 35+)"
    echo "  - November 1, 2025 deadline compliance"
    exit 0
fi
