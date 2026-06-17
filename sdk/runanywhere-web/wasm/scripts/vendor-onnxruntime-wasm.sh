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
case "$(uname -s)" in
  Darwin) _ORT_OS_DIR="MacOS" ;;
  *)      _ORT_OS_DIR="Linux" ;;
esac
ORT_BUILD_DIR="${SRC_DIR}/build/${_ORT_OS_DIR}/${BUILD_CONFIG}"

mkdir -p "$(dirname "${SRC_DIR}")" "${DEST_DIR}/lib" "${DEST_DIR}/include"

# --- Prebuilt WASM bundle (download-first; mirrors the Android prebuilt .so) ---
# The matched ORT+sherpa WASM static libs are published on the sherpa-onnx-rac
# release. Download + extract instead of the ~30-60 min from-source build.
# Force a source build with RAC_WASM_BUILD_FROM_SOURCE=1; override the source
# repo/tag with RAC_WASM_PREBUILT_REPO / RAC_WASM_PREBUILT_TAG.
if [ "${RAC_WASM_BUILD_FROM_SOURCE:-0}" != "1" ]; then
  if [ -f "${DEST_DIR}/lib/libonnxruntime.a" ]; then
    echo "ONNX Runtime WASM already vendored: ${DEST_DIR}/lib/libonnxruntime.a"
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
    if [ -f "${DEST_DIR}/lib/libonnxruntime.a" ]; then
      echo "Vendored ONNX Runtime WASM from prebuilt bundle: ${DEST_DIR}/lib/libonnxruntime.a"
      exit 0
    fi
    echo "Prebuilt extract did not produce libonnxruntime.a; falling back to from-source build."
  fi
fi
# --- from-source build (reached if RAC_WASM_BUILD_FROM_SOURCE=1 or download failed) ---

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
  --parallel "${CMAKE_BUILD_PARALLEL_LEVEL:-12}" \
  --cmake_extra_defines CMAKE_POLICY_VERSION_MINIMUM=3.5
BUILD_RC=$?
set -e

if [ "${BUILD_RC}" -ne 0 ]; then
  if [ ! -f "${ORT_BUILD_DIR}/CMakeCache.txt" ]; then
    echo "ERROR: ONNX Runtime configure failed before producing ${ORT_BUILD_DIR}/CMakeCache.txt" >&2
    exit "${BUILD_RC}"
  fi
  # F3 (dep-bump 2026-05-19): ORT 1.24.x's build.py honors --skip_tests by
  # disabling test target *execution* but still adds test sources to the
  # `make all` graph; one test (onnxruntime_provider_test, e.g.
  # gather_block_quantized_op_test.cc) fails to compile under WASM+Emscripten,
  # making `make all` exit 2 even when every library target succeeds.
  # `libonnxruntime_webassembly.a` is not exposed as a discrete cmake target
  # in 1.24.x — it's produced by a custom command bundled into `make all`.
  # Use `make -k` (keep going on error) so the failing test compile doesn't
  # halt the build before the WASM static library is produced, then tolerate
  # a non-zero exit since the `find` step below verifies the archive.
  echo "ONNX Runtime build.py returned ${BUILD_RC}; falling back to direct make -k (keep-going) to skip the failing test compile."
  set +e
  cmake --build "${ORT_BUILD_DIR}" --parallel "${CMAKE_BUILD_PARALLEL_LEVEL:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}" -- -k
  CMAKE_FALLBACK_RC=$?
  set -e
  echo "Fallback cmake --build exit: ${CMAKE_FALLBACK_RC} (non-zero is OK if libonnxruntime_webassembly.a was still produced)."
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
# F3 (dep-bump 2026-05-19): ORT 1.24.x added onnxruntime_ep_c_api.h and
# onnxruntime_ep_device_ep_metadata_keys.h to the EP plugin C ABI;
# onnxruntime_c_api.h:8289 now `#include "onnxruntime_ep_c_api.h"` so the
# header must be vendored alongside the core C API or downstream consumers
# (sherpa-onnx) fail at the very first include.
for header in \
  onnxruntime_c_api.h \
  onnxruntime_cxx_api.h \
  onnxruntime_cxx_inline.h \
  onnxruntime_float16.h \
  onnxruntime_session_options_config_keys.h \
  onnxruntime_run_options_config_keys.h \
  onnxruntime_ep_c_api.h \
  onnxruntime_ep_device_ep_metadata_keys.h
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
