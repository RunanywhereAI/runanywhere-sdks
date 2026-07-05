#!/usr/bin/env bash
# stage-natives.sh — stage the private QHexRT native libraries into this
# Flutter plugin's android/src/main/jniLibs/arm64-v8a.
#
# Mirrors the qhexrt section of
# sdk/runanywhere-react-native/scripts/package-sdk.sh: the QHexRT backend .so
# plus the QAIRT runtime/skel set (libQnn*) are PRIVATE and staged directly
# into the package from a local build output — they are never fetched from a
# public release. QHexRT is Qualcomm-only: arm64-v8a exclusively.
#
# Usage:
#   scripts/stage-natives.sh --natives-from /path/to/dir
#
# where /path/to/dir either contains the .so files directly or an arm64-v8a/
# subdirectory (the package-sdk.sh convention). Missing optional libs are
# skipped with a note; the backend .so itself is required.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEST="$PKG_DIR/android/src/main/jniLibs/arm64-v8a"

NATIVES_FROM=""
while [ $# -gt 0 ]; do
    case "$1" in
        --natives-from)
            NATIVES_FROM="${2:?--natives-from requires a directory argument}"
            shift 2
            ;;
        -h|--help)
            sed -n '2,16p' "$0"
            exit 0
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

if [ -z "$NATIVES_FROM" ]; then
    echo "ERROR: --natives-from <dir> is required." >&2
    exit 1
fi

# Accept either the ABI dir itself or its parent (package-sdk.sh layout).
SRC="$NATIVES_FROM"
if [ -d "$NATIVES_FROM/arm64-v8a" ]; then
    SRC="$NATIVES_FROM/arm64-v8a"
fi
if [ ! -d "$SRC" ]; then
    echo "ERROR: natives dir not found: $SRC" >&2
    exit 1
fi

# The same lib set package-sdk.sh stages for the RN qhexrt package, plus the
# _jni backend variant this plugin's bindings also probe for.
LIBS=(
    librac_backend_qhexrt.so
    librac_backend_qhexrt_jni.so
    libc++_shared.so
    libQnnHtp.so
    libQnnHtpNetRunExtensions.so
    libQnnHtpPrepare.so
    libQnnSystem.so
    libQnnHtpV75CalculatorStub.so
    libQnnHtpV75Skel.so
    libQnnHtpV75Stub.so
    libQnnHtpV79CalculatorStub.so
    libQnnHtpV79Skel.so
    libQnnHtpV79Stub.so
    libQnnHtpV81CalculatorStub.so
    libQnnHtpV81Skel.so
    libQnnHtpV81Stub.so
)

mkdir -p "$DEST"

staged=0
for lib in "${LIBS[@]}"; do
    if [ -f "$SRC/$lib" ]; then
        cp -f "$SRC/$lib" "$DEST/"
        staged=$((staged + 1))
    else
        echo "  (skipping $lib — not present in $SRC)"
    fi
done

if [ ! -f "$DEST/librac_backend_qhexrt.so" ] && [ ! -f "$DEST/librac_backend_qhexrt_jni.so" ]; then
    echo "ERROR: no QHexRT backend .so (librac_backend_qhexrt*.so) was staged from $SRC" >&2
    exit 1
fi

echo "Staged $staged native lib(s) into $DEST"
