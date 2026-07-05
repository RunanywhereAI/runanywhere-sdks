#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

usage() {
    cat <<'EOF'
Usage: scripts/release/package-kotlin.sh [--mode local|ci] [--natives-from PATH]

Unified SDK packaging contract for the Kotlin SDK. Consumes pre-built native
artifacts (.so files) and produces AAR + JAR distribution files with checksums.
Assumes the natives already exist (this is not the developer build pipeline).

Options:
  --mode local|ci      Build mode (default: auto-detect from $CI)
  --natives-from PATH  Directory containing per-ABI librac_*.so files
                       Expected: PATH/{arm64-v8a,x86_64,...}/librac_*.so OR zipped
                       Default: src/main/jniLibs/ (in-place)

Outputs:
  sdk/runanywhere-kotlin/dist/sdk-kotlin/*.aar    + .sha256
  sdk/runanywhere-kotlin/dist/sdk-kotlin/*.jar    + .sha256
EOF
}

KOTLIN_ROOT="${RAC_ROOT}/sdk/runanywhere-kotlin"

source "${RAC_ROOT}/scripts/lib/detect-mode.sh"

NATIVES_FROM=""

while [ $# -gt 0 ]; do
    case "$1" in
        --mode) RAC_BUILD_MODE="$2"; shift 2 ;;
        --natives-from) NATIVES_FROM="$2"; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

info "Kotlin SDK packaging (mode=${RAC_BUILD_MODE})"

JNI_DIR="${KOTLIN_ROOT}/src/main/jniLibs"

if [ -n "$NATIVES_FROM" ]; then
    [ -d "$NATIVES_FROM" ] || die "--natives-from not found: $NATIVES_FROM"
    info "Staging .so files from $NATIVES_FROM → $JNI_DIR"
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
        log "   extracting: $(basename "$zip")"
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

# Packaging builds only the release deliverables. Compilation/lint/test gating
# is pr-build.yml's job — running `gradlew build` here would recompile drifted
# test sources and is redundant with the PR gate.
info "./gradlew assembleRelease jvmJar $GRADLE_FLAGS"
./gradlew assembleRelease jvmJar $GRADLE_FLAGS

DIST_DIR="${KOTLIN_ROOT}/dist/sdk-kotlin"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
find build/outputs/aar -name "*.aar" -exec cp {} "$DIST_DIR/" \; 2>/dev/null || true
find build/libs -name "*.jar" -exec cp {} "$DIST_DIR/" \; 2>/dev/null || true
find modules -path "*/build/outputs/aar/*.aar" -exec cp {} "$DIST_DIR/" \; 2>/dev/null || true

info "Artifacts in $DIST_DIR:"
for f in "$DIST_DIR"/*; do
    [ -f "$f" ] || continue
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$f" > "$f.sha256"
    else
        sha256sum "$f" > "$f.sha256"
    fi
    log "  $(basename "$f")"
done

if [ -x "${RAC_ROOT}/scripts/release/validate-artifact.sh" ]; then
    if [ "$RAC_BUILD_MODE" = "ci" ]; then
        "${RAC_ROOT}/scripts/release/validate-artifact.sh" "$DIST_DIR"/*.aar "$DIST_DIR"/*.jar 2>/dev/null
    else
        "${RAC_ROOT}/scripts/release/validate-artifact.sh" "$DIST_DIR"/*.aar "$DIST_DIR"/*.jar 2>/dev/null || true
    fi
fi
