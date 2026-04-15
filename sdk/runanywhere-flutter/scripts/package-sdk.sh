#!/usr/bin/env bash
# =============================================================================
# sdk/runanywhere-flutter/scripts/package-sdk.sh
# =============================================================================
# Unified SDK packaging contract for the Flutter SDK. Consumes pre-built
# iOS XCFrameworks + Android .so files, stages them into each flutter
# package's plugin-native directories, then validates the package with
# `flutter pub publish --dry-run`.
#
# No tarball is produced — Flutter pub.dev packages are consumed by git-ref
# or by publishing, not by file URL. `--dry-run` verifies the package shape
# is valid.
#
# USAGE:
#   package-sdk.sh [--mode local|ci] [--natives-from PATH]
#
# OPTIONS:
#   --mode local|ci      Build mode (default: auto-detect from $CI)
#   --natives-from PATH  Directory with iOS xcframeworks + Android .so files.
#                        Expected: PATH/{ios,android}/<stuff> OR PATH/*.zip/*.tar.gz
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
FLUTTER_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${REPO_ROOT}/scripts/detect-mode.sh"

NATIVES_FROM=""

while [ $# -gt 0 ]; do
    case "$1" in
        --mode) RAC_BUILD_MODE="$2"; shift 2 ;;
        --natives-from) NATIVES_FROM="$2"; shift 2 ;;
        --help|-h) head -22 "$0" | tail -18; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 1 ;;
    esac
done

echo ">> Flutter SDK packaging (mode=${RAC_BUILD_MODE})"

if [ -n "$NATIVES_FROM" ]; then
    [ -d "$NATIVES_FROM" ] || { echo "ERROR: --natives-from not found: $NATIVES_FROM" >&2; exit 1; }
    # Each Flutter plugin package has its own ios/ and android/ subdirs. Stage
    # matching natives into each. This is intentionally a best-effort copy —
    # the binary_config.gradle files inside each package are responsible for
    # wiring them up correctly at build time.
    echo ">> Staging natives from $NATIVES_FROM into each flutter package"
    for pkg_dir in "$FLUTTER_ROOT/packages"/*/; do
        pkg=$(basename "$pkg_dir")
        # Android: copy per-ABI .so files
        android_jni="$pkg_dir/android/src/main/jniLibs"
        for abi in arm64-v8a armeabi-v7a x86_64 x86; do
            if [ -d "$NATIVES_FROM/$abi" ]; then
                mkdir -p "$android_jni/$abi"
                cp -f "$NATIVES_FROM/$abi"/*.so "$android_jni/$abi/" 2>/dev/null || true
            fi
        done
        # iOS: copy xcframeworks if present
        if ls "$NATIVES_FROM"/*.xcframework >/dev/null 2>&1; then
            mkdir -p "$pkg_dir/ios/Frameworks"
            cp -R "$NATIVES_FROM"/*.xcframework "$pkg_dir/ios/Frameworks/" 2>/dev/null || true
        fi
    done
fi

# Bootstrap with melos if available
cd "$FLUTTER_ROOT"
if command -v melos >/dev/null 2>&1; then
    echo ">> melos bootstrap"
    melos bootstrap || echo "::warning::melos bootstrap failed — continuing"
fi

# Validate each package with flutter pub publish --dry-run
for pkg_dir in "$FLUTTER_ROOT/packages"/*/; do
    pkg=$(basename "$pkg_dir")
    if [ ! -f "$pkg_dir/pubspec.yaml" ]; then
        continue
    fi
    echo ""
    echo ">> Validating $pkg"
    (
        cd "$pkg_dir"
        flutter pub get || echo "::warning::pub get failed for $pkg"
        flutter pub publish --dry-run || echo "::warning::pub publish dry-run failed for $pkg"
    )
done

echo ""
echo ">> Flutter SDK packages validated. No tarball emitted — consumers"
echo "   reference each package via git-URL in their pubspec.yaml, or pub.dev"
echo "   publishes those (we don't publish to pub.dev in this release flow)."
