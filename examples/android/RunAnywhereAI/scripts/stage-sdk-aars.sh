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
    --no-daemon \
    --max-workers=2 \
    --dependency-verification strict \
    -Prunanywhere.useLocalNatives=true \
    -x buildLocalJniLibs \
    "${SDK_TASK}" \
    ":modules:runanywhere-core-llamacpp:${SDK_TASK}" \
    ":modules:runanywhere-core-onnx:${SDK_TASK}" \
    ":modules:runanywhere-core-qhexrt:${SDK_TASK}"

mkdir -p "${LIBS_DIR}"

find_exact_aar() {
    local search_dir="$1"
    local label="$2"
    local match=""
    local count=0
    local candidate

    while IFS= read -r candidate; do
        count=$((count + 1))
        match="${candidate}"
    done < <(find "${search_dir}" -maxdepth 1 -type f -name "*-${AAR_VARIANT}.aar" -print)

    [ "${count}" -eq 1 ] || {
        echo "Expected exactly one ${label} ${AAR_VARIANT} AAR, found ${count}" >&2
        exit 1
    }
    printf '%s\n' "${match}"
}

SDK_AAR="$(find_exact_aar "${SDK_DIR}/build/outputs/aar" "SDK")"
LLAMA_AAR="$(find_exact_aar "${SDK_DIR}/modules/runanywhere-core-llamacpp/build/outputs/aar" "LlamaCPP")"
ONNX_AAR="$(find_exact_aar "${SDK_DIR}/modules/runanywhere-core-onnx/build/outputs/aar" "ONNX")"
QHEXRT_AAR="$(find_exact_aar "${SDK_DIR}/modules/runanywhere-core-qhexrt/build/outputs/aar" "QHexRT")"

cp "${SDK_AAR}" "${LIBS_DIR}/runanywhere-sdk.aar"
cp "${LLAMA_AAR}" "${LIBS_DIR}/runanywhere-llamacpp.aar"
cp "${ONNX_AAR}" "${LIBS_DIR}/runanywhere-onnx.aar"
cp "${QHEXRT_AAR}" "${LIBS_DIR}/runanywhere-qhexrt.aar"

echo "Staged AARs into ${LIBS_DIR}:"
ls -lh "${LIBS_DIR}"/*.aar
