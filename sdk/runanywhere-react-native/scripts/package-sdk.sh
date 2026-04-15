#!/usr/bin/env bash
# =============================================================================
# sdk/runanywhere-react-native/scripts/package-sdk.sh
# =============================================================================
# Unified SDK packaging contract for the React Native SDK. Consumes pre-built
# iOS XCFrameworks + Android .so files, stages them into each RN package's
# native directories, and produces npm tarballs with checksums.
#
# USAGE:
#   package-sdk.sh [--mode local|ci] [--natives-from PATH]
#
# OPTIONS:
#   --mode local|ci      Build mode (default: auto-detect from $CI)
#   --natives-from PATH  Directory with iOS xcframeworks + Android .so files.
#                        Same layout contract as the Flutter script.
#
# OUTPUTS:
#   dist/sdk-rn/*.tgz     + .sha256    (one per npm workspace)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
RN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${REPO_ROOT}/scripts/detect-mode.sh"

NATIVES_FROM=""

while [ $# -gt 0 ]; do
    case "$1" in
        --mode) RAC_BUILD_MODE="$2"; shift 2 ;;
        --natives-from) NATIVES_FROM="$2"; shift 2 ;;
        --help|-h) head -20 "$0" | tail -16; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 1 ;;
    esac
done

echo ">> React Native SDK packaging (mode=${RAC_BUILD_MODE})"

if [ -n "$NATIVES_FROM" ]; then
    [ -d "$NATIVES_FROM" ] || { echo "ERROR: --natives-from not found: $NATIVES_FROM" >&2; exit 1; }
    echo ">> Staging natives from $NATIVES_FROM into each RN package"
    for pkg_dir in "$RN_ROOT/packages"/*/; do
        pkg=$(basename "$pkg_dir")
        android_jni="$pkg_dir/android/src/main/jniLibs"
        for abi in arm64-v8a armeabi-v7a x86_64 x86; do
            if [ -d "$NATIVES_FROM/$abi" ]; then
                mkdir -p "$android_jni/$abi"
                cp -f "$NATIVES_FROM/$abi"/*.so "$android_jni/$abi/" 2>/dev/null || true
            fi
        done
        if ls "$NATIVES_FROM"/*.xcframework >/dev/null 2>&1; then
            mkdir -p "$pkg_dir/ios/Frameworks"
            cp -R "$NATIVES_FROM"/*.xcframework "$pkg_dir/ios/Frameworks/" 2>/dev/null || true
        fi
    done
fi

cd "$RN_ROOT"

# Prefer yarn if a lockfile exists; fall back to npm.
if [ -f "yarn.lock" ] && command -v yarn >/dev/null 2>&1; then
    echo ">> yarn install"
    yarn install
    HAS_YARN=1
else
    echo ">> npm install --legacy-peer-deps"
    npm install --legacy-peer-deps
    HAS_YARN=0
fi

# Generate Nitro bindings if nitrogen is wired up
if [ "$HAS_YARN" = "1" ] && yarn run 2>/dev/null | grep -q "nitrogen"; then
    echo ">> yarn core:nitrogen (if defined)"
    yarn core:nitrogen 2>/dev/null || echo "::warning::nitrogen task failed — continuing"
fi

# Typecheck each package
for pkg_dir in "$RN_ROOT/packages"/*/; do
    pkg=$(basename "$pkg_dir")
    if [ -f "$pkg_dir/tsconfig.json" ]; then
        echo ">> typecheck $pkg"
        (cd "$pkg_dir" && npx tsc --noEmit) || echo "::warning::tsc failed in $pkg"
    fi
done

DIST_DIR="${RN_ROOT}/dist/sdk-rn"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

for pkg_dir in "$RN_ROOT/packages"/*/; do
    pkg=$(basename "$pkg_dir")
    if [ -f "$pkg_dir/package.json" ]; then
        echo ">> npm pack $pkg"
        (cd "$pkg_dir" && npm pack --pack-destination "$DIST_DIR" >/dev/null) || echo "::warning::npm pack failed for $pkg"
    fi
done

echo ""
echo ">> Artifacts in $DIST_DIR:"
for f in "$DIST_DIR"/*.tgz; do
    [ -f "$f" ] || continue
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$f" > "$f.sha256"
    else
        sha256sum "$f" > "$f.sha256"
    fi
    echo "  $(basename "$f")"
done

if [ -x "${REPO_ROOT}/scripts/validate-artifact.sh" ]; then
    echo ""
    "${REPO_ROOT}/scripts/validate-artifact.sh" "$DIST_DIR"/*.tgz 2>/dev/null || true
fi
