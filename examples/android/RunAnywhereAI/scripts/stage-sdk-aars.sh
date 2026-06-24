#!/usr/bin/env bash
set -euo pipefail

EXAMPLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "${EXAMPLE_DIR}/../../.." && pwd)"
SDK_DIR="${REPO_ROOT}/sdk/runanywhere-kotlin"
LIBS_DIR="${EXAMPLE_DIR}/libs"

BUILD_TYPE="${1:-release}"
case "${BUILD_TYPE}" in
    debug)
        SDK_TASK="assembleDebug"
        AAR_VARIANT="debug"
        ;;
    release)
        SDK_TASK="assembleRelease"
        AAR_VARIANT="release"
        ;;
    *)
        echo "Usage: $0 [debug|release]" >&2
        exit 1
        ;;
esac

cd "${SDK_DIR}"
./gradlew \
    "${SDK_TASK}" \
    ":modules:runanywhere-core-llamacpp:${SDK_TASK}" \
    ":modules:runanywhere-core-onnx:${SDK_TASK}" \
    ":modules:runanywhere-core-qhexrt:${SDK_TASK}"

mkdir -p "${LIBS_DIR}"

SDK_AAR=$(find "${SDK_DIR}/build/outputs/aar" -name "*-${AAR_VARIANT}.aar" | head -1)
LLAMA_AAR=$(find "${SDK_DIR}/modules/runanywhere-core-llamacpp/build/outputs/aar" -name "*-${AAR_VARIANT}.aar" | head -1)
ONNX_AAR=$(find "${SDK_DIR}/modules/runanywhere-core-onnx/build/outputs/aar" -name "*-${AAR_VARIANT}.aar" | head -1)
QHEXRT_AAR=$(find "${SDK_DIR}/modules/runanywhere-core-qhexrt/build/outputs/aar" -name "*-${AAR_VARIANT}.aar" | head -1)

[ -n "${SDK_AAR}" ] && [ -f "${SDK_AAR}" ] || { echo "SDK AAR not found" >&2; exit 1; }
[ -n "${LLAMA_AAR}" ] && [ -f "${LLAMA_AAR}" ] || { echo "LlamaCPP AAR not found" >&2; exit 1; }
[ -n "${ONNX_AAR}" ] && [ -f "${ONNX_AAR}" ] || { echo "ONNX AAR not found" >&2; exit 1; }
[ -n "${QHEXRT_AAR}" ] && [ -f "${QHEXRT_AAR}" ] || { echo "QHexRT AAR not found" >&2; exit 1; }

cp "${SDK_AAR}" "${LIBS_DIR}/runanywhere-sdk.aar"
cp "${LLAMA_AAR}" "${LIBS_DIR}/runanywhere-llamacpp.aar"
cp "${ONNX_AAR}" "${LIBS_DIR}/runanywhere-onnx.aar"
cp "${QHEXRT_AAR}" "${LIBS_DIR}/runanywhere-qhexrt.aar"

echo "Staged AARs into ${LIBS_DIR}:"
ls -lh "${LIBS_DIR}"/*.aar
