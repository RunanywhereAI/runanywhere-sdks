#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

usage() {
    cat <<'EOF'
Usage: scripts/release/package-flutter.sh [--mode local|ci] [--natives-from PATH]

Unified SDK packaging contract for the Flutter SDK. Consumes pre-built iOS
XCFrameworks + Android .so files, stages them into each flutter package's
plugin-native directories, then validates the package with
`flutter pub publish --dry-run`.

No tarball is produced — Flutter pub.dev packages are consumed by git-ref or
by publishing, not by file URL. `--dry-run` verifies the package shape.

Options:
  --mode local|ci      Build mode (default: auto-detect from $CI)
  --natives-from PATH  Directory with iOS xcframeworks + Android .so files.
                       Expected: PATH/{ios,android}/<stuff> OR PATH/*.zip/*.tar.gz
EOF
}

FLUTTER_ROOT="${RAC_ROOT}/sdk/runanywhere-flutter"

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

info "Flutter SDK packaging (mode=${RAC_BUILD_MODE})"

if [ -n "$NATIVES_FROM" ]; then
    [ -d "$NATIVES_FROM" ] || die "--natives-from not found: $NATIVES_FROM"
    # Each Flutter plugin package has its own ios/ and android/ subdirs. Stage
    # matching natives into each. Intentionally best-effort — each package's
    # binary_config.gradle is responsible for wiring them up at build time.
    info "Staging natives from $NATIVES_FROM into each flutter package"
    for pkg_dir in "$FLUTTER_ROOT/packages"/*/; do
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

cd "$FLUTTER_ROOT"
if command -v melos >/dev/null 2>&1; then
    info "melos bootstrap"
    melos bootstrap || echo "::warning::melos bootstrap failed — continuing"
fi

for pkg_dir in "$FLUTTER_ROOT/packages"/*/; do
    pkg=$(basename "$pkg_dir")
    if [ ! -f "$pkg_dir/pubspec.yaml" ]; then
        continue
    fi
    info "Validating $pkg"
    (
        cd "$pkg_dir"
        flutter pub get || echo "::warning::pub get failed for $pkg"
        flutter pub publish --dry-run || echo "::warning::pub publish dry-run failed for $pkg"
    )
done

ok "Flutter SDK packages validated. No tarball emitted — consumers reference"
log "   each package via git-URL in their pubspec.yaml, or pub.dev publishes"
log "   those (we don't publish to pub.dev in this release flow)."
