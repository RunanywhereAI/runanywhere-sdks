#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WASM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${WASM_DIR}/../../.." && pwd)"

# Source the canonical VERSIONS file so the WASM sherpa-onnx vendor matches
# the rest of the matched set. F3 (dep-bump 2026-05-19): WASM previously
# pinned 1.12.23 as a hardcoded fallback; the matched set now requires 1.13.2
# alongside ORT 1.24.4 (see vendor-onnxruntime-wasm.sh for context).
# shellcheck disable=SC1091
source "${REPO_ROOT}/sdk/runanywhere-commons/scripts/load-versions.sh"

SHERPA_ONNX_VERSION="${SHERPA_ONNX_VERSION:-${SHERPA_ONNX_VERSION_LINUX}}"
SRC_DIR="${SHERPA_ONNX_SRC_DIR:-${WASM_DIR}/third_party/sherpa-onnx}"
DEST_DIR="${REPO_ROOT}/sdk/runanywhere-commons/third_party/sherpa-onnx-wasm"
ORT_DIR="${REPO_ROOT}/sdk/runanywhere-commons/third_party/onnxruntime-wasm"
BUILD_DIR="${SRC_DIR}/build-wasm-static"

# --- Prebuilt WASM bundle (download-first; mirrors the Android prebuilt .so) ---
# Download + extract the matched ORT+sherpa WASM static libs from the
# sherpa-onnx-rac release instead of building from source. Force a source build
# with RAC_WASM_BUILD_FROM_SOURCE=1; override the source repo/tag with
# RAC_WASM_PREBUILT_REPO / RAC_WASM_PREBUILT_TAG.
if [ "${RAC_WASM_BUILD_FROM_SOURCE:-0}" != "1" ]; then
  if [ -f "${DEST_DIR}/lib/libsherpa-onnx-c-api.a" ]; then
    echo "Sherpa-ONNX WASM already vendored: ${DEST_DIR}/lib/libsherpa-onnx-c-api.a"
    exit 0
  fi
  _RAC_TP="${REPO_ROOT}/sdk/runanywhere-commons/third_party"
  _RAC_REPO="${RAC_WASM_PREBUILT_REPO:-${SHERPA_ONNX_REPO_ANDROID:-Siddhesh2377/sherpa-onnx-rac}}"
  _RAC_TAG="${RAC_WASM_PREBUILT_TAG:-v${SHERPA_ONNX_VERSION_LINUX}}"
  _RAC_TARBALL="sherpa-onnx-${_RAC_TAG}-wasm.tar.bz2"
  _RAC_URL="https://github.com/${_RAC_REPO}/releases/download/${_RAC_TAG}/${_RAC_TARBALL}"
  _RAC_CACHE="${WASM_DIR}/third_party/${_RAC_TARBALL}"
  if [ ! -f "${_RAC_CACHE}" ]; then
    echo "Downloading prebuilt WASM bundle: ${_RAC_URL}"
    if curl -fL --retry 3 -o "${_RAC_CACHE}.part" "${_RAC_URL}"; then
      mv "${_RAC_CACHE}.part" "${_RAC_CACHE}"
    else
      echo "Prebuilt download failed; falling back to from-source build."
      rm -f "${_RAC_CACHE}.part"
    fi
  fi
  if [ -f "${_RAC_CACHE}" ]; then
    mkdir -p "${_RAC_TP}"
    tar -xjf "${_RAC_CACHE}" -C "${_RAC_TP}" onnxruntime-wasm sherpa-onnx-wasm
    if [ -f "${DEST_DIR}/lib/libsherpa-onnx-c-api.a" ]; then
      echo "Vendored Sherpa-ONNX WASM from prebuilt bundle: ${DEST_DIR}/lib/libsherpa-onnx-c-api.a"
      exit 0
    fi
    echo "Prebuilt extract did not produce libsherpa-onnx-c-api.a; falling back to from-source build."
  fi
fi
# --- from-source build (reached if RAC_WASM_BUILD_FROM_SOURCE=1 or download failed) ---

if [ ! -f "${ORT_DIR}/lib/libonnxruntime.a" ]; then
  echo "ERROR: ${ORT_DIR}/lib/libonnxruntime.a is required before building Sherpa-ONNX WASM." >&2
  echo "Run: sdk/runanywhere-web-next/wasm/scripts/vendor-onnxruntime-wasm.sh" >&2
  exit 1
fi

mkdir -p "$(dirname "${SRC_DIR}")" "${DEST_DIR}/lib" "${DEST_DIR}/include"

if [ ! -d "${SRC_DIR}/.git" ]; then
  rm -rf "${SRC_DIR}"
  git clone --depth 1 --branch "v${SHERPA_ONNX_VERSION}" \
    https://github.com/k2-fsa/sherpa-onnx.git "${SRC_DIR}"
fi

# Apply RACommons patches. Wraps the C API constructors
# (CreateOfflineRecognizer / CreateOfflineTts / CreateVoiceActivityDetector)
# in try/catch so std::exception thrown from inside ORT or Eigen surfaces as
# `nullptr` + a logged error instead of a raw `CppException` crossing the
# WASM/JS boundary.
PATCH_DIR="${WASM_DIR}/patches"
SHERPA_PATCH="${PATCH_DIR}/sherpa-onnx-c-api-try-catch.patch"
if [ -f "${SHERPA_PATCH}" ]; then
  if git -C "${SRC_DIR}" apply --reverse --check "${SHERPA_PATCH}" >/dev/null 2>&1; then
    echo "Sherpa patch already applied: ${SHERPA_PATCH}"
  elif git -C "${SRC_DIR}" apply --check "${SHERPA_PATCH}" >/dev/null 2>&1; then
    echo "Applying Sherpa patch: ${SHERPA_PATCH}"
    git -C "${SRC_DIR}" apply "${SHERPA_PATCH}"
  else
    # F3 (dep-bump 2026-05-19): Sherpa 1.13.2 reorganized c-api.cc + session.cc
    # so the old line offsets in this patch no longer match. The session.cc
    # WASM inter-op fix is already in upstream 1.13.2 (see csrc/session.cc
    # `#if SHERPA_ONNX_ENABLE_WASM` block); the c-api.cc try/catch hardening
    # remains uncovered but is robustness-only (existing builds without it
    # still work; bad input just surfaces a CppException instead of a logged
    # nullptr). Skip the patch with a warning rather than fail the vendor.
    echo "WARNING: Sherpa patch ${SHERPA_PATCH} does not apply cleanly to v${SHERPA_ONNX_VERSION}; continuing without it." >&2
    echo "         Upstream 1.13.2+ already includes the session.cc WASM inter-op fix; the c-api.cc try/catch hardening is robustness-only." >&2
  fi
fi

export SHERPA_ONNXRUNTIME_INCLUDE_DIR="${ORT_DIR}/include"
export SHERPA_ONNXRUNTIME_LIB_DIR="${ORT_DIR}/lib"

emcmake cmake \
  -B "${BUILD_DIR}" \
  -S "${SRC_DIR}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS="-fexceptions" \
  -DCMAKE_CXX_FLAGS="-fexceptions" \
  -DCMAKE_EXE_LINKER_FLAGS="-fexceptions" \
  -DCMAKE_SHARED_LINKER_FLAGS="-fexceptions" \
  -DBUILD_SHARED_LIBS=OFF \
  -DSHERPA_ONNX_ENABLE_BINARY=OFF \
  -DSHERPA_ONNX_ENABLE_TESTS=OFF \
  -DSHERPA_ONNX_ENABLE_CHECK=OFF \
  -DSHERPA_ONNX_ENABLE_PYTHON=OFF \
  -DSHERPA_ONNX_ENABLE_C_API=ON \
  -DSHERPA_ONNX_ENABLE_WEBSOCKET=OFF \
  -DSHERPA_ONNX_ENABLE_SPEAKER_DIARIZATION=OFF \
  -DSHERPA_ONNX_ENABLE_WASM=ON \
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
