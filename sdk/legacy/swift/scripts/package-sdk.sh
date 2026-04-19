#!/usr/bin/env bash
# =============================================================================
# sdk/runanywhere-swift/scripts/package-sdk.sh
# =============================================================================
# Unified SDK build contract. This script builds the Swift SDK against a set
# of native artifacts (XCFrameworks) and produces a sanity-check build result.
#
# The Swift SDK is not shipped as a tarball — SwiftPM consumers reference the
# repo at a git tag. This script's job is to validate that the Swift package
# resolves and compiles with the given natives in place.
#
# USAGE:
#   build-sdk.sh [--mode local|ci] [--natives-from PATH]
#
# OPTIONS:
#   --mode local|ci      Build mode (default: auto-detect from $CI)
#   --natives-from PATH  Directory containing *.xcframework (default: sdk/runanywhere-swift/Binaries/)
#
# OUTPUTS:
#   .build/              SwiftPM build directory
#   (no tarball — consumers reference the repo at a tag)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Load the shared build-mode detection
source "${REPO_ROOT}/scripts/detect-mode.sh"

NATIVES_FROM=""

while [ $# -gt 0 ]; do
    case "$1" in
        --mode) RAC_BUILD_MODE="$2"; shift 2 ;;
        --natives-from) NATIVES_FROM="$2"; shift 2 ;;
        --help|-h) head -25 "$0" | tail -20; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 1 ;;
    esac
done

echo ">> Swift SDK build (mode=${RAC_BUILD_MODE})"

BINARIES_DIR="${REPO_ROOT}/sdk/runanywhere-swift/Binaries"

# If --natives-from given and different from canonical Binaries/ dir, copy.
if [ -n "$NATIVES_FROM" ] && [ "$NATIVES_FROM" != "$BINARIES_DIR" ]; then
    if [ ! -d "$NATIVES_FROM" ]; then
        echo "ERROR: --natives-from path not found: $NATIVES_FROM" >&2
        exit 1
    fi
    echo ">> Staging XCFrameworks from $NATIVES_FROM → $BINARIES_DIR"
    rm -rf "$BINARIES_DIR"
    mkdir -p "$BINARIES_DIR"
    # Handle both loose xcframeworks and zipped ones
    find "$NATIVES_FROM" -maxdepth 3 -name "*.xcframework" -type d -exec cp -R {} "$BINARIES_DIR/" \; 2>/dev/null || true
    for zip in "$NATIVES_FROM"/*.xcframework.zip "$NATIVES_FROM"/*-v*.zip; do
        [ -f "$zip" ] || continue
        echo "   extracting: $(basename "$zip")"
        unzip -qo "$zip" -d "$BINARIES_DIR/"
    done
fi

cd "$REPO_ROOT"

echo ">> swift package resolve"
swift package resolve

echo ">> swift build"
if [ "$RAC_BUILD_MODE" = "ci" ]; then
    # CI mode: strict — fail on any build error
    swift build
else
    # Local mode: tolerant — warn on missing Binaries/ but don't block iteration
    if ! swift build; then
        echo "::warning::swift build failed — check Binaries/ has required XCFrameworks."
        exit 1
    fi
fi

echo ""
echo ">> Swift SDK build OK. No tarball produced — SPM consumers reference"
echo "   this repo at a git tag. Package.swift checksums must match the"
echo "   freshly-released zips (run scripts/sync-checksums.sh on release)."
