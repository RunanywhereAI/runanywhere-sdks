#!/bin/bash
# =============================================================================
# Update Package.swift with Remote Checksums
# =============================================================================
# This script updates Package.swift with checksums for a specific release version.
#
# Usage:
#   ./scripts/update-package-checksums.sh v3.0.0
#
# This will:
#   1. Download the checksums.txt from the release
#   2. Parse the checksums for each xcframework
#   3. Update Package.swift with the new URLs and checksums
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

VERSION="${1:-}"
BINARIES_REPO="RunanywhereAI/runanywhere-binaries"
PACKAGE_SWIFT="$ROOT_DIR/sdk/runanywhere-swift/Package.swift"

if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 v3.0.0"
    exit 1
fi

log_info "Updating Package.swift for version $VERSION"

# Download checksums
CHECKSUMS_URL="https://github.com/$BINARIES_REPO/releases/download/$VERSION/checksums.txt"
log_info "Downloading checksums from $CHECKSUMS_URL"

CHECKSUMS=$(curl -sL "$CHECKSUMS_URL")
if [ -z "$CHECKSUMS" ]; then
    log_error "Failed to download checksums"
    exit 1
fi

echo "Downloaded checksums:"
echo "$CHECKSUMS"
echo ""

# Parse checksums
get_checksum() {
    local filename="$1"
    echo "$CHECKSUMS" | grep "$filename" | awk '{print $1}'
}

CHECKSUM_RACOMMONS=$(get_checksum "RACommons.xcframework.zip")
CHECKSUM_LLAMACPP=$(get_checksum "RABackendLlamaCPP.xcframework.zip")
CHECKSUM_ONNX=$(get_checksum "RABackendONNX.xcframework.zip")
CHECKSUM_ONNXRUNTIME=$(get_checksum "onnxruntime.xcframework.zip")

log_info "Parsed checksums:"
echo "  RACommons: $CHECKSUM_RACOMMONS"
echo "  RABackendLlamaCPP: $CHECKSUM_LLAMACPP"
echo "  RABackendONNX: $CHECKSUM_ONNX"
echo "  ONNXRuntime: $CHECKSUM_ONNXRUNTIME"
echo ""

# Update Package.swift
log_info "Updating $PACKAGE_SWIFT"

# Use sed to update the version and checksums
BASE_URL="https://github.com/$BINARIES_REPO/releases/download/$VERSION"

# macOS sed requires different syntax
if [[ "$OSTYPE" == "darwin"* ]]; then
    SED_INPLACE="sed -i ''"
else
    SED_INPLACE="sed -i"
fi

# Update URLs
$SED_INPLACE "s|runanywhere-binaries/releases/download/v[0-9.]*|runanywhere-binaries/releases/download/$VERSION|g" "$PACKAGE_SWIFT"

# Update checksums
$SED_INPLACE "s|PLACEHOLDER_CHECKSUM_RACommons|$CHECKSUM_RACOMMONS|g" "$PACKAGE_SWIFT"
$SED_INPLACE "s|PLACEHOLDER_CHECKSUM_RABackendLlamaCPP|$CHECKSUM_LLAMACPP|g" "$PACKAGE_SWIFT"
$SED_INPLACE "s|PLACEHOLDER_CHECKSUM_RABackendONNX|$CHECKSUM_ONNX|g" "$PACKAGE_SWIFT"
$SED_INPLACE "s|PLACEHOLDER_CHECKSUM_ONNXRuntime|$CHECKSUM_ONNXRUNTIME|g" "$PACKAGE_SWIFT"

# Also update if they were previously set
if [ -n "$CHECKSUM_RACOMMONS" ]; then
    $SED_INPLACE "s|checksum: \"[a-f0-9]*\" // RACommons|checksum: \"$CHECKSUM_RACOMMONS\" // RACommons|g" "$PACKAGE_SWIFT"
fi

log_success "Package.swift updated for version $VERSION"
echo ""
echo "Next steps:"
echo "  1. Review changes: git diff $PACKAGE_SWIFT"
echo "  2. Commit: git add $PACKAGE_SWIFT && git commit -m 'Update binaries to $VERSION'"
echo "  3. Push to update remote users"
