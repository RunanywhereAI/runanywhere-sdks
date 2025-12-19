#!/bin/bash

# =============================================================================
# check_16kb_alignment.sh
# Verifies that all native libraries in the APK/AAB have 16KB page alignment
# Usage: ./check_16kb_alignment.sh <path-to-apk-or-aab>
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Check if file path provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <path-to-apk-or-aab>"
    echo "Example: $0 app/build/outputs/apk/release/app-release.apk"
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

# Create temp directory for extraction
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Extract APK/AAB
print_header "Extracting archive..."
unzip -q "$APK_PATH" -d "$TEMP_DIR"
print_success "Extracted to $TEMP_DIR"

# Find all .so files
SO_FILES=$(find "$TEMP_DIR" -name "*.so" -type f)

if [ -z "$SO_FILES" ]; then
    print_warning "No native libraries (.so files) found in the archive"
    echo "This app does not use native code, so 16KB alignment is not required."
    exit 0
fi

print_header "Checking ELF Alignment"

ALL_ALIGNED=true
TOTAL_COUNT=0
ALIGNED_COUNT=0
MISALIGNED_COUNT=0

echo "Legend:"
echo "  align 2**14 (16384) = 16KB aligned ✅"
echo "  align 2**13 (8192)  = 8KB aligned  ❌"
echo "  align 2**12 (4096)  = 4KB aligned  ❌"
echo ""

while IFS= read -r SO_FILE; do
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    SO_NAME=$(basename "$SO_FILE")

    echo "Checking: $SO_NAME"

    # Check if llvm-objdump or objdump is available
    if command -v llvm-objdump &> /dev/null; then
        OBJDUMP="llvm-objdump"
    elif command -v objdump &> /dev/null; then
        OBJDUMP="objdump"
    elif command -v readelf &> /dev/null; then
        # Use readelf as fallback
        ALIGNMENT_OUTPUT=$(readelf -l "$SO_FILE" 2>/dev/null | grep LOAD || true)

        if [ -z "$ALIGNMENT_OUTPUT" ]; then
            print_warning "Could not read ELF headers for $SO_NAME"
            continue
        fi

        # Check if all LOAD segments have 16KB alignment (0x4000)
        MISALIGNED=$(echo "$ALIGNMENT_OUTPUT" | grep -v "0x004000" || true)

        if [ -z "$MISALIGNED" ]; then
            print_success "$SO_NAME - All LOAD segments are 16KB aligned"
            ALIGNED_COUNT=$((ALIGNED_COUNT + 1))
        else
            print_error "$SO_NAME - Found misaligned LOAD segments:"
            echo "$ALIGNMENT_OUTPUT" | sed 's/^/  /'
            ALL_ALIGNED=false
            MISALIGNED_COUNT=$((MISALIGNED_COUNT + 1))
        fi
        continue
    else
        print_error "No suitable tool found (llvm-objdump, objdump, or readelf required)"
        exit 1
    fi

    # Get LOAD segment alignment using objdump
    ALIGNMENT_OUTPUT=$($OBJDUMP -p "$SO_FILE" 2>/dev/null | grep LOAD || true)

    if [ -z "$ALIGNMENT_OUTPUT" ]; then
        print_warning "Could not read LOAD segments for $SO_NAME"
        continue
    fi

    # Check if all LOAD segments have align 2**14 (16KB)
    MISALIGNED=$(echo "$ALIGNMENT_OUTPUT" | grep -v "align 2\*\*14" | grep "align 2\*\*" || true)

    if [ -z "$MISALIGNED" ]; then
        print_success "$SO_NAME - All LOAD segments are 16KB aligned"
        echo "$ALIGNMENT_OUTPUT" | sed 's/^/  /'
        ALIGNED_COUNT=$((ALIGNED_COUNT + 1))
    else
        print_error "$SO_NAME - Found misaligned LOAD segments:"
        echo "$ALIGNMENT_OUTPUT" | sed 's/^/  /'
        ALL_ALIGNED=false
        MISALIGNED_COUNT=$((MISALIGNED_COUNT + 1))
    fi

    echo ""
done <<< "$SO_FILES"

# Check ZIP alignment (16KB for page-aligned uncompressed files)
print_header "Checking ZIP Alignment"

if command -v zipalign &> /dev/null; then
    # -P 16 specifies 16KB page size, -c checks, -v verbose, 4 is default ZIP alignment
    if zipalign -c -P 16 -v 4 "$APK_PATH" > /dev/null 2>&1; then
        print_success "APK/AAB is properly aligned for 16KB page sizes"
    else
        print_error "APK/AAB is NOT aligned for 16KB page sizes"
        echo "Run: zipalign -P 16 -f -v 4 input.apk output.apk"
        ALL_ALIGNED=false
    fi
else
    print_warning "zipalign tool not found - skipping ZIP alignment check"
    echo "Install Android SDK build-tools to get zipalign"
fi

# Final summary
print_header "Summary"
echo "Total libraries checked: $TOTAL_COUNT"
echo "16KB aligned: $ALIGNED_COUNT"
echo "Misaligned: $MISALIGNED_COUNT"
echo ""

if [ "$ALL_ALIGNED" = true ] && [ "$TOTAL_COUNT" -gt 0 ]; then
    print_success "All checks passed! This app supports 16KB page sizes."
    echo ""
    echo "Your app is ready for:"
    echo "  - Android 15+ devices with 16KB page sizes"
    echo "  - Google Play Store submission (targeting SDK 35+)"
    exit 0
else
    print_error "16KB alignment check FAILED!"
    echo ""
    echo "Required actions:"
    echo "  1. Rebuild native libraries with 16KB alignment flags:"
    echo "     -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384"
    echo "  2. Ensure you're using Android Gradle Plugin 8.5.1+"
    echo "  3. Use Android NDK r28+ (or r27 with ANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON)"
    echo "  4. Rebuild and test again"
    exit 1
fi
