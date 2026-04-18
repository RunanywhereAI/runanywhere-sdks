#!/usr/bin/env bash
# =============================================================================
# sdk/runanywhere-kotlin/scripts/package-sdk.sh
# =============================================================================
# Unified SDK packaging contract. Consumes pre-built native artifacts (.so
# files) and produces AAR + JAR distribution files with checksums.
#
# This is NOT the same as build-sdk.sh — that's the developer pipeline that
# also builds C++ from source. package-sdk.sh assumes the natives already
# exist.
#
# USAGE:
#   package-sdk.sh [--mode local|ci] [--natives-from PATH]
#
# OPTIONS:
#   --mode local|ci      Build mode (default: auto-detect from $CI)
#   --natives-from PATH  Directory containing per-ABI librac_*.so files
#                        Expected: PATH/{arm64-v8a,x86_64,...}/librac_*.so OR zipped
#                        Default: src/androidMain/jniLibs/ (in-place)
#
# OUTPUTS:
#   dist/sdk-kotlin/*.aar    + .sha256
#   dist/sdk-kotlin/*.jar    + .sha256
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
KOTLIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

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

echo ">> Kotlin SDK packaging (mode=${RAC_BUILD_MODE})"

JNI_DIR="${KOTLIN_ROOT}/src/androidMain/jniLibs"

if [ -n "$NATIVES_FROM" ]; then
    [ -d "$NATIVES_FROM" ] || { echo "ERROR: --natives-from not found: $NATIVES_FROM" >&2; exit 1; }
    echo ">> Staging .so files from $NATIVES_FROM → $JNI_DIR"
    rm -rf "$JNI_DIR"
    mkdir -p "$JNI_DIR"
    for abi in arm64-v8a armeabi-v7a x86_64 x86; do
        if [ -d "$NATIVES_FROM/$abi" ]; then
            mkdir -p "$JNI_DIR/$abi"
            cp -f "$NATIVES_FROM/$abi"/*.so "$JNI_DIR/$abi/" 2>/dev/null || true
        fi
    done
    for zip in "$NATIVES_FROM"/*android*.zip; do
        [ -f "$zip" ] || continue
        echo "   extracting: $(basename "$zip")"
        tmp=$(mktemp -d)
        unzip -qo "$zip" -d "$tmp"
        for abi in arm64-v8a armeabi-v7a x86_64 x86; do
            if [ -d "$tmp/$abi" ]; then
                mkdir -p "$JNI_DIR/$abi"
                cp -R "$tmp/$abi"/. "$JNI_DIR/$abi/"
            fi
        done
        rm -rf "$tmp"
    done
fi

cd "$KOTLIN_ROOT"
GRADLE_FLAGS="--no-daemon"
[ -n "$NATIVES_FROM" ] && GRADLE_FLAGS="$GRADLE_FLAGS -Prunanywhere.useLocalNatives=true"

echo ">> ./gradlew build $GRADLE_FLAGS -x test"
./gradlew build $GRADLE_FLAGS -x test

echo ">> ./gradlew assembleRelease jvmJar $GRADLE_FLAGS"
./gradlew assembleRelease jvmJar $GRADLE_FLAGS

DIST_DIR="${KOTLIN_ROOT}/dist/sdk-kotlin"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
find build/outputs/aar -name "*.aar" -exec cp {} "$DIST_DIR/" \; 2>/dev/null || true
find build/libs -name "*.jar" -exec cp {} "$DIST_DIR/" \; 2>/dev/null || true
find modules -path "*/build/outputs/aar/*.aar" -exec cp {} "$DIST_DIR/" \; 2>/dev/null || true

echo ""
echo ">> Artifacts in $DIST_DIR:"
for f in "$DIST_DIR"/*; do
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
    if [ "$RAC_BUILD_MODE" = "ci" ]; then
        "${REPO_ROOT}/scripts/validate-artifact.sh" "$DIST_DIR"/*.aar "$DIST_DIR"/*.jar 2>/dev/null
    else
        "${REPO_ROOT}/scripts/validate-artifact.sh" "$DIST_DIR"/*.aar "$DIST_DIR"/*.jar 2>/dev/null || true
    fi
fi
