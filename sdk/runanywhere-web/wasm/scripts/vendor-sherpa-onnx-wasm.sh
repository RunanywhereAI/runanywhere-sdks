#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WASM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${WASM_DIR}/../../.." && pwd)"

SHERPA_ONNX_VERSION="${SHERPA_ONNX_VERSION:-1.12.23}"
SRC_DIR="${SHERPA_ONNX_SRC_DIR:-${WASM_DIR}/third_party/sherpa-onnx}"
DEST_DIR="${REPO_ROOT}/sdk/runanywhere-commons/third_party/sherpa-onnx-wasm"
ORT_DIR="${REPO_ROOT}/sdk/runanywhere-commons/third_party/onnxruntime-wasm"
BUILD_DIR="${SRC_DIR}/build-wasm-static"

if [ ! -f "${ORT_DIR}/lib/libonnxruntime.a" ]; then
  echo "ERROR: ${ORT_DIR}/lib/libonnxruntime.a is required before building Sherpa-ONNX WASM." >&2
  echo "Run: sdk/runanywhere-web/wasm/scripts/vendor-onnxruntime-wasm.sh" >&2
  exit 1
fi

mkdir -p "$(dirname "${SRC_DIR}")" "${DEST_DIR}/lib" "${DEST_DIR}/include"

if [ ! -d "${SRC_DIR}/.git" ]; then
  rm -rf "${SRC_DIR}"
  git clone --depth 1 --branch "v${SHERPA_ONNX_VERSION}" \
    https://github.com/k2-fsa/sherpa-onnx.git "${SRC_DIR}"
fi

export SHERPA_ONNXRUNTIME_INCLUDE_DIR="${ORT_DIR}/include"
export SHERPA_ONNXRUNTIME_LIB_DIR="${ORT_DIR}/lib"

emcmake cmake \
  -B "${BUILD_DIR}" \
  -S "${SRC_DIR}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS="-pthread" \
  -DCMAKE_CXX_FLAGS="-pthread" \
  -DBUILD_SHARED_LIBS=OFF \
  -DSHERPA_ONNX_ENABLE_BINARY=OFF \
  -DSHERPA_ONNX_ENABLE_TESTS=OFF \
  -DSHERPA_ONNX_ENABLE_CHECK=OFF \
  -DSHERPA_ONNX_ENABLE_PYTHON=OFF \
  -DSHERPA_ONNX_ENABLE_C_API=ON \
  -DSHERPA_ONNX_ENABLE_WEBSOCKET=OFF \
  -DSHERPA_ONNX_ENABLE_SPEAKER_DIARIZATION=OFF \
  -DSHERPA_ONNX_ENABLE_WASM=OFF \
  -DSHERPA_ONNX_ENABLE_WASM_TTS=OFF \
  -DSHERPA_ONNX_ENABLE_WASM_ASR=OFF \
  -DSHERPA_ONNX_ENABLE_WASM_VAD=OFF \
  -DSHERPA_ONNX_USE_PRE_INSTALLED_ONNXRUNTIME=ON \
  -Donnxruntime_SOURCE_DIR="${ORT_DIR}" \
  -Donnxruntime_INCLUDE_DIR="${ORT_DIR}/include" \
  -Donnxruntime_LIBRARY="${ORT_DIR}/lib/libonnxruntime.a"

cmake --build "${BUILD_DIR}" --parallel "${CMAKE_BUILD_PARALLEL_LEVEL:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"

ARCHIVES_FILE="$(mktemp)"
find "${BUILD_DIR}" -type f -name '*.a' | sort > "${ARCHIVES_FILE}"
if [ ! -s "${ARCHIVES_FILE}" ]; then
  rm -f "${ARCHIVES_FILE}"
  echo "ERROR: Sherpa-ONNX WASM static archives were not produced under ${BUILD_DIR}" >&2
  exit 1
fi

while IFS= read -r archive; do
  cp "${archive}" "${DEST_DIR}/lib/$(basename "${archive}")"
done < "${ARCHIVES_FILE}"
rm -f "${ARCHIVES_FILE}"

if [ -d "${SRC_DIR}/sherpa-onnx/c-api" ]; then
  mkdir -p "${DEST_DIR}/include/sherpa-onnx/c-api"
  cp "${SRC_DIR}/sherpa-onnx/c-api/c-api.h" "${DEST_DIR}/include/sherpa-onnx/c-api/c-api.h"
elif [ -f "${SRC_DIR}/sherpa-onnx/csrc/c-api.h" ]; then
  mkdir -p "${DEST_DIR}/include/sherpa-onnx/c-api"
  cp "${SRC_DIR}/sherpa-onnx/csrc/c-api.h" "${DEST_DIR}/include/sherpa-onnx/c-api/c-api.h"
else
  echo "ERROR: could not find Sherpa-ONNX C API header in ${SRC_DIR}" >&2
  exit 1
fi

if [ ! -f "${DEST_DIR}/lib/libsherpa-onnx-c-api.a" ]; then
  echo "ERROR: expected ${DEST_DIR}/lib/libsherpa-onnx-c-api.a after build." >&2
  echo "Sherpa upstream may have renamed the C API archive; inspect ${DEST_DIR}/lib." >&2
  exit 1
fi

echo "Vendored Sherpa-ONNX WASM:"
echo "  ${DEST_DIR}/lib/*.a"
echo "  ${DEST_DIR}/include/sherpa-onnx/c-api/c-api.h"
