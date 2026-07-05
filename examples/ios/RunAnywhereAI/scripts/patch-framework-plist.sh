#!/bin/bash
# =============================================================================
# patch-framework-plist.sh
# =============================================================================
# Patches framework Info.plist files to ensure MinimumOSVersion is set to 17.0.
# This fixes App Store validation errors for frameworks that either:
# - Don't include the required MinimumOSVersion key
# - Have a mismatched MinimumOSVersion value
#
# Usage:
#   ./scripts/patch-framework-plist.sh
#
# This script patches the following frameworks in DerivedData:
# - onnxruntime.framework (Microsoft ONNX Runtime - downloaded via SPM)
# - RACommons.framework (RunAnywhere SDK)
# - RABackendLLAMACPP.framework (RunAnywhere SDK)
# - RABackendONNX.framework (RunAnywhere SDK)
#
# When to run:
# - After cleaning DerivedData
# - After resetting SPM packages
# - Before archiving if you've done a clean build
# =============================================================================

set -e

MIN_OS_VERSION="17.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "========================================"
echo "Framework Info.plist Patcher"
echo "========================================"
echo "Target MinimumOSVersion: $MIN_OS_VERSION"
echo ""

# Function to patch MinimumOSVersion in a plist
patch_plist() {
    local plist_path="$1"

    if [ ! -f "$plist_path" ]; then
        return 1
    fi

    # Check current MinimumOSVersion value
    local current_version
    current_version=$(/usr/libexec/PlistBuddy -c "Print :MinimumOSVersion" "$plist_path" 2>/dev/null || echo "")

    if [ "$current_version" = "$MIN_OS_VERSION" ]; then
        echo -e "${GREEN}[OK]${NC} Already set to $MIN_OS_VERSION: $plist_path"
        return 0
    elif [ -n "$current_version" ]; then
        # Update existing value
        /usr/libexec/PlistBuddy -c "Set :MinimumOSVersion $MIN_OS_VERSION" "$plist_path" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo -e "${YELLOW}[UPDATED]${NC} $current_version -> $MIN_OS_VERSION: $plist_path"
        else
            echo -e "${RED}[ERROR]${NC} Failed to update: $plist_path"
            return 1
        fi
    else
        # Add missing key
        /usr/libexec/PlistBuddy -c "Add :MinimumOSVersion string $MIN_OS_VERSION" "$plist_path" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo -e "${YELLOW}[ADDED]${NC} MinimumOSVersion=$MIN_OS_VERSION: $plist_path"
        else
            echo -e "${RED}[ERROR]${NC} Failed to add: $plist_path"
            return 1
        fi
    fi
    return 0
}

# Find DerivedData directory for this project
DERIVED_DATA_DIR="$HOME/Library/Developer/Xcode/DerivedData"

if [ ! -d "$DERIVED_DATA_DIR" ]; then
    echo -e "${RED}Error: DerivedData directory not found${NC}"
    exit 1
fi

# List of frameworks to patch
FRAMEWORKS=(
    "onnxruntime.framework"
    "RACommons.framework"
    "RABackendLLAMACPP.framework"
    "RABackendONNX.framework"
)

TOTAL_PATCHED=0
TOTAL_FOUND=0

for framework in "${FRAMEWORKS[@]}"; do
    echo -e "${BLUE}Searching for ${framework}...${NC}"

    FRAMEWORK_COUNT=0
    while IFS= read -r plist_path; do
        if patch_plist "$plist_path"; then
            ((FRAMEWORK_COUNT++)) || true
        fi
        ((TOTAL_FOUND++)) || true
    done < <(find "$DERIVED_DATA_DIR" -path "*/${framework}/Info.plist" -type f 2>/dev/null)

    if [ $FRAMEWORK_COUNT -eq 0 ]; then
        echo -e "${YELLOW}  No ${framework} found in DerivedData${NC}"
    fi
    echo ""
done

echo "========================================"
if [ $TOTAL_FOUND -eq 0 ]; then
    echo -e "${YELLOW}No framework Info.plist files found.${NC}"
    echo ""
    echo "Make sure to:"
    echo "  1. Build the project first (Cmd+B)"
    echo "  2. Then run this script"
    echo "  3. Then archive (Product > Archive)"
else
    echo -e "${GREEN}Done! Processed $TOTAL_FOUND plist file(s).${NC}"
    echo ""
    echo "You can now archive the app without cleaning."
    echo "  Product > Archive"
fi
echo "========================================"
