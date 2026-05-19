#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WASM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${WASM_DIR}/../../.." && pwd)"

# Source the canonical VERSIONS file so the WASM vendor matches the rest of the
# matched set (iOS/Android/macOS/Linux all consume ORT/Sherpa from VERSIONS).
# F3 (dep-bump 2026-05-19): WASM previously had its own hardcoded fallbacks
# (1.18.0 / 1.12.23) that drifted from VERSIONS. The matched set now picks
# ORT 1.24.4 + sherpa-onnx 1.13.2 across every platform.
# shellcheck disable=SC1091
source "${REPO_ROOT}/sdk/runanywhere-commons/scripts/load-versions.sh"

# Allow callers to override via env, otherwise read from VERSIONS. ORT WASM is
# built from source so we use the Linux pin (which is what `cmake/FetchONNXRuntime.cmake`
# uses for Linux/macOS/WASM and is kept in lockstep with sherpa-onnx).
ONNX_RUNTIME_VERSION="${ONNX_RUNTIME_VERSION:-${ONNX_VERSION_LINUX}}"
SRC_DIR="${ONNX_RUNTIME_SRC_DIR:-${WASM_DIR}/third_party/onnxruntime}"
DEST_DIR="${REPO_ROOT}/sdk/runanywhere-commons/third_party/onnxruntime-wasm"
BUILD_CONFIG="${ONNX_RUNTIME_BUILD_CONFIG:-Release}"
ORT_BUILD_DIR="${SRC_DIR}/build/MacOS/${BUILD_CONFIG}"

mkdir -p "$(dirname "${SRC_DIR}")" "${DEST_DIR}/lib" "${DEST_DIR}/include"

if [ ! -d "${SRC_DIR}/.git" ]; then
  rm -rf "${SRC_DIR}"
  git clone --depth 1 --branch "v${ONNX_RUNTIME_VERSION}" \
    https://github.com/microsoft/onnxruntime.git "${SRC_DIR}"
fi

# Apply RACommons patches. Currently we patch
# `core/framework/session_options.h` so per-session threadpools default to
# `true` even on WASM+pthreads builds, which prevents
# `InferenceSession::ConstructorCommon` from throwing when Sherpa-ONNX
# creates a fresh `Ort::Env` per session.
PATCH_DIR="${WASM_DIR}/patches"
ORT_PATCH="${PATCH_DIR}/onnxruntime-per-session-threads.patch"
if [ -f "${ORT_PATCH}" ]; then
  if ! git -C "${SRC_DIR}" apply --reverse --check "${ORT_PATCH}" >/dev/null 2>&1; then
    echo "Applying ORT patch: ${ORT_PATCH}"
    git -C "${SRC_DIR}" apply "${ORT_PATCH}"
  else
    echo "ORT patch already applied: ${ORT_PATCH}"
  fi
fi

cd "${SRC_DIR}"

# Force regeneration of the bundled archive so that incremental rebuilds
# (e.g. after editing core/framework/session_options.h) actually pick up the
# new object files. Without this the bundling_target is treated as already
# satisfied by CMake and the stale archive ships unchanged.
rm -f "${ORT_BUILD_DIR}/libonnxruntime_webassembly.a"

# F3 (dep-bump 2026-05-19): ORT 1.24.x removed `--use_preinstalled_eigen` and
# `--eigen_path` from build.py. Eigen is now fetched as part of the ORT build
# via the bundled `cmake/external/eigen.cmake` FetchContent declaration, so
# the previously vendored `third_party/eigen` checkout is no longer needed
# (and supplying the legacy flags causes argparse to reject them outright).
set +e
./build.sh \
  --config "${BUILD_CONFIG}" \
  --build_wasm_static_lib \
  --enable_wasm_simd \
  --skip_tests \
  --disable_rtti \
  --cmake_extra_defines CMAKE_POLICY_VERSION_MINIMUM=3.5
BUILD_RC=$?
set -e

if [ "${BUILD_RC}" -ne 0 ]; then
  if [ ! -f "${ORT_BUILD_DIR}/CMakeCache.txt" ]; then
    echo "ERROR: ONNX Runtime configure failed before producing ${ORT_BUILD_DIR}/CMakeCache.txt" >&2
    exit "${BUILD_RC}"
  fi
  echo "ONNX Runtime build.py returned ${BUILD_RC}; falling back to direct CMake build."
  cmake --build "${ORT_BUILD_DIR}" --parallel "${CMAKE_BUILD_PARALLEL_LEVEL:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"
fi

ORT_ARCHIVE="$(
  find "${SRC_DIR}/build" -type f \( \
    -name 'libonnxruntime_webassembly.a' -o \
    -name 'libonnxruntime.a' -o \
    -name 'onnxruntime_webassembly.a' \
  \) | sort | tail -n 1
)"

if [ -z "${ORT_ARCHIVE}" ] || [ ! -f "${ORT_ARCHIVE}" ]; then
  echo "ERROR: ONNX Runtime WASM static archive was not produced under ${SRC_DIR}/build" >&2
  exit 1
fi

cp "${ORT_ARCHIVE}" "${DEST_DIR}/lib/libonnxruntime.a"

HEADER_SRC="${SRC_DIR}/include/onnxruntime/core/session"
for header in \
  onnxruntime_c_api.h \
  onnxruntime_cxx_api.h \
  onnxruntime_cxx_inline.h \
  onnxruntime_float16.h \
  onnxruntime_session_options_config_keys.h \
  onnxruntime_run_options_config_keys.h
do
  if [ ! -f "${HEADER_SRC}/${header}" ]; then
    echo "ERROR: missing ONNX Runtime header ${HEADER_SRC}/${header}" >&2
    exit 1
  fi
  cp "${HEADER_SRC}/${header}" "${DEST_DIR}/include/${header}"
done

echo "Vendored ONNX Runtime WASM:"
echo "  ${DEST_DIR}/lib/libonnxruntime.a"
echo "  ${DEST_DIR}/include/*.h"
