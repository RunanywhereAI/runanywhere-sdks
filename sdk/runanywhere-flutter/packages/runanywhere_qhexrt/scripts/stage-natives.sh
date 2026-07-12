#!/usr/bin/env bash
# stage-natives.sh — stage the private QHexRT native libraries into this
# Flutter plugin. Android host/stub libraries go to jniLibs; FastRPC DSP
# Skel.so files go to assets and are extracted to app-private storage at runtime.
#
# Mirrors the qhexrt section of
# sdk/runanywhere-react-native/scripts/package-sdk.sh: the QHexRT backend .so
# plus the QAIRT runtime/skel set (libQnn*) are PRIVATE and staged into the
# package from a local build output — they are never fetched from a
# public release. QHexRT is Qualcomm-only: arm64-v8a exclusively.
#
# Usage:
#   scripts/stage-natives.sh --natives-from /path/to/dir
#
# where /path/to/dir is the explicit canonical private ownership directory
# PATH/arm64-v8a/qhexrt. Missing optional libs are skipped with a note; the
# backend .so itself is required.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
JNI_DEST="$PKG_DIR/android/src/main/jniLibs/arm64-v8a"
SKEL_DEST="$PKG_DIR/android/src/main/assets/runanywhere/qhexrt/skels/arm64-v8a"

NATIVES_FROM=""
while [ $# -gt 0 ]; do
    case "$1" in
        --natives-from)
            NATIVES_FROM="${2:?--natives-from requires a directory argument}"
            shift 2
            ;;
        -h|--help)
            sed -n '2,17p' "$0"
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

SRC="$NATIVES_FROM"
if [ ! -d "$SRC" ]; then
    echo "ERROR: natives dir not found: $SRC" >&2
    exit 1
fi

# The same lib set package-sdk.sh stages for the RN qhexrt package, plus the
# _jni backend variant this plugin's bindings also probe for.
JNI_LIBS=(
    librac_backend_qhexrt.so
    librac_backend_qhexrt_jni.so
    libc++_shared.so
    libQnnHtp.so
    libQnnHtpNetRunExtensions.so
    libQnnHtpPrepare.so
    libQnnSystem.so
    libQnnHtpV75CalculatorStub.so
    libQnnHtpV75Stub.so
    libQnnHtpV79CalculatorStub.so
    libQnnHtpV79Stub.so
    libQnnHtpV81CalculatorStub.so
    libQnnHtpV81Stub.so
)

SKEL_LIBS=(
    libQnnHtpV75Skel.so
    libQnnHtpV79Skel.so
    libQnnHtpV81Skel.so
)

# Never let a missing input be masked by a previously staged private runtime.
rm -rf "$JNI_DEST" "$SKEL_DEST"
mkdir -p "$JNI_DEST" "$SKEL_DEST"

staged_jni=0
for lib in "${JNI_LIBS[@]}"; do
    if [ -f "$SRC/$lib" ]; then
        cp -f "$SRC/$lib" "$JNI_DEST/"
        staged_jni=$((staged_jni + 1))
    else
        echo "  (skipping $lib — not present in $SRC)"
    fi
done

staged_skels=0
for lib in "${SKEL_LIBS[@]}"; do
    if [ -f "$SRC/$lib" ]; then
        cp -f "$SRC/$lib" "$SKEL_DEST/"
        staged_skels=$((staged_skels + 1))
    else
        echo "  (skipping $lib — not present in $SRC)"
    fi
done

# Never leave DSP binaries in Android's JNI namespace. FastRPC needs real
# private filesystem paths, not Android linker paths.
find "$JNI_DEST" -maxdepth 1 -type f -name 'libQnnHtpV*Skel.so' -delete

if [ ! -f "$JNI_DEST/librac_backend_qhexrt.so" ] && [ ! -f "$JNI_DEST/librac_backend_qhexrt_jni.so" ]; then
    echo "ERROR: no QHexRT backend .so (librac_backend_qhexrt*.so) was staged from $SRC" >&2
    exit 1
fi

if [ "$staged_skels" -eq 0 ] && ! find "$SKEL_DEST" -maxdepth 1 -type f -name 'libQnnHtpV*Skel.so' -print -quit | grep -q .; then
    echo "ERROR: no QHexRT DSP Skel.so assets were staged from $SRC" >&2
    exit 1
fi

echo "Staged $staged_jni JNI lib(s) into $JNI_DEST"
echo "Staged $staged_skels DSP skel asset(s) into $SKEL_DEST"
