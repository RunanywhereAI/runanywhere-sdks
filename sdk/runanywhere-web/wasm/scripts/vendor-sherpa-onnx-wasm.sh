#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WASM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${WASM_DIR}/../../.." && pwd)"

# Source the canonical Web-specific ORT/Sherpa matched set without moving the
# independently validated iOS/Android pins.
# shellcheck disable=SC1091
source "${REPO_ROOT}/sdk/runanywhere-commons/scripts/load-versions.sh"

# Keep the Web pair canonical. Directory/repository overrides are supported;
# independently overriding the Sherpa version would make the ORT pair invalid.
SHERPA_ONNX_VERSION="${SHERPA_ONNX_VERSION_WEB}"
: "${ONNX_VERSION_WEB:?ONNX_VERSION_WEB is missing from VERSIONS}"
: "${EMSCRIPTEN_VERSION:?EMSCRIPTEN_VERSION is missing from VERSIONS}"
SRC_DIR="${SHERPA_ONNX_SRC_DIR:-${WASM_DIR}/third_party/sherpa-onnx}"
DEST_DIR="${REPO_ROOT}/sdk/runanywhere-commons/third_party/sherpa-onnx-wasm"
ORT_DIR="${REPO_ROOT}/sdk/runanywhere-commons/third_party/onnxruntime-wasm"
BUILD_DIR="${SRC_DIR}/build-wasm-static"
PROVENANCE_FILE="${DEST_DIR}/.rac-wasm-provenance"
BUILD_PROVENANCE_FILE="${BUILD_DIR}/.rac-wasm-build-provenance"
SHERPA_ARCHIVE_DEST="${DEST_DIR}/lib/libsherpa-onnx-c-api.a"
SHERPA_HEADER_DEST="${DEST_DIR}/include/sherpa-onnx/c-api/c-api.h"
ORT_ARCHIVE="${ORT_DIR}/lib/libonnxruntime.a"
ORT_HEADER="${ORT_DIR}/include/onnxruntime_c_api.h"
ORT_PROVENANCE_FILE="${ORT_DIR}/.rac-wasm-provenance"
ORT_VENDOR_SCRIPT="${SCRIPT_DIR}/vendor-onnxruntime-wasm.sh"
# These schemas belong to different provenance producers. Never use the
# Sherpa schema to validate ORT just because the records are checked together.
SHERPA_RECIPE_SCHEMA="3"
ORT_RECIPE_SCHEMA="5"
PATCH_DIR="${WASM_DIR}/patches"
SHERPA_PATCH="${PATCH_DIR}/sherpa-onnx-c-api-try-catch.patch"
SOURCE_REVISION=""
PATCH_STATE=""
SHERPA_REQUIRED_FILES=(
  "${SHERPA_ARCHIVE_DEST}"
  "${SHERPA_HEADER_DEST}"
  "${DEST_DIR}/lib/libsherpa-onnx-core.a"
  "${DEST_DIR}/lib/libsherpa-onnx-fst.a"
  "${DEST_DIR}/lib/libsherpa-onnx-fstfar.a"
  "${DEST_DIR}/lib/libsherpa-onnx-kaldifst-core.a"
  "${DEST_DIR}/lib/libkaldi-decoder-core.a"
  "${DEST_DIR}/lib/libkaldi-native-fbank-core.a"
  "${DEST_DIR}/lib/libkissfft-float.a"
  "${DEST_DIR}/lib/libssentencepiece_core.a"
  "${DEST_DIR}/lib/libpiper_phonemize.a"
  "${DEST_DIR}/lib/libespeak-ng.a"
  "${DEST_DIR}/lib/libucd.a"
)
ORT_REQUIRED_FILES=(
  "${ORT_ARCHIVE}"
  "${ORT_DIR}/include/onnxruntime_c_api.h"
  "${ORT_DIR}/include/onnxruntime_cxx_api.h"
  "${ORT_DIR}/include/onnxruntime_cxx_inline.h"
  "${ORT_DIR}/include/onnxruntime_float16.h"
  "${ORT_DIR}/include/onnxruntime_session_options_config_keys.h"
  "${ORT_DIR}/include/onnxruntime_run_options_config_keys.h"
  "${ORT_DIR}/include/onnxruntime_ep_c_api.h"
  "${ORT_DIR}/include/onnxruntime_ep_device_ep_metadata_keys.h"
)

sha256_file() {
  local file="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${file}" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${file}" | awk '{print $1}'
  else
    echo "ERROR: shasum or sha256sum is required for WASM provenance." >&2
    return 1
  fi
}

SCRIPT_SHA256="$(sha256_file "${BASH_SOURCE[0]}")"
if [ -f "${SHERPA_PATCH}" ]; then
  PATCH_SHA256="$(sha256_file "${SHERPA_PATCH}")"
else
  PATCH_SHA256="absent"
fi
ORT_SCRIPT_SHA256="$(sha256_file "${ORT_VENDOR_SCRIPT}")"
ORT_PATCH_SHA256="absent"

provenance_has() {
  local file="$1"
  local value="$2"
  [ -f "${file}" ] && grep -Fqx "${value}" "${file}"
}

provenance_has_pattern() {
  local file="$1"
  local pattern="$2"
  [ -f "${file}" ] && grep -Eq "${pattern}" "${file}"
}

required_files_present() {
  local file
  for file in "${SHERPA_REQUIRED_FILES[@]}"; do
    [ -f "${file}" ] || return 1
  done
}

ort_required_files_present() {
  local file
  for file in "${ORT_REQUIRED_FILES[@]}"; do
    [ -f "${file}" ] || return 1
  done
}

provenance_matches() {
  required_files_present &&
    provenance_has "${PROVENANCE_FILE}" "schema=1" &&
    provenance_has "${PROVENANCE_FILE}" "component=sherpa-onnx-wasm" &&
    provenance_has "${PROVENANCE_FILE}" "version=${SHERPA_ONNX_VERSION}" &&
    provenance_has "${PROVENANCE_FILE}" "onnxruntime_version=${ONNX_VERSION_WEB}" &&
    provenance_has "${PROVENANCE_FILE}" "emscripten_version=${EMSCRIPTEN_VERSION}" &&
    provenance_has "${PROVENANCE_FILE}" "threads=on" &&
    provenance_has "${PROVENANCE_FILE}" "recipe_schema=${SHERPA_RECIPE_SCHEMA}" &&
    provenance_has "${PROVENANCE_FILE}" "script_sha256=${SCRIPT_SHA256}" &&
    provenance_has "${PROVENANCE_FILE}" "patch_sha256=${PATCH_SHA256}" &&
    provenance_has_pattern "${PROVENANCE_FILE}" '^source_revision=[0-9a-f]{40,64}$' &&
    provenance_has_pattern "${PROVENANCE_FILE}" '^patch_state=(applied|skipped|absent)$'
}

ort_provenance_matches() {
  ort_required_files_present &&
    provenance_has "${ORT_PROVENANCE_FILE}" "schema=1" &&
    provenance_has "${ORT_PROVENANCE_FILE}" "component=onnxruntime-wasm" &&
    provenance_has "${ORT_PROVENANCE_FILE}" "version=${ONNX_VERSION_WEB}" &&
    provenance_has "${ORT_PROVENANCE_FILE}" "sherpa_version=${SHERPA_ONNX_VERSION}" &&
    provenance_has "${ORT_PROVENANCE_FILE}" "emscripten_version=${EMSCRIPTEN_VERSION}" &&
    provenance_has "${ORT_PROVENANCE_FILE}" "build_config=Release" &&
    provenance_has "${ORT_PROVENANCE_FILE}" "threads=on" &&
    provenance_has "${ORT_PROVENANCE_FILE}" "recipe_schema=${ORT_RECIPE_SCHEMA}" &&
    provenance_has "${ORT_PROVENANCE_FILE}" "script_sha256=${ORT_SCRIPT_SHA256}" &&
    provenance_has "${ORT_PROVENANCE_FILE}" "patch_sha256=${ORT_PATCH_SHA256}" &&
    provenance_has_pattern "${ORT_PROVENANCE_FILE}" '^source_revision=[0-9a-f]{40,64}$' &&
    provenance_has_pattern "${ORT_PROVENANCE_FILE}" '^patch_state=(applied|absent)$'
}

build_provenance_matches() {
  provenance_has "${BUILD_PROVENANCE_FILE}" "schema=1" &&
    provenance_has "${BUILD_PROVENANCE_FILE}" "component=sherpa-onnx-wasm-build" &&
    provenance_has "${BUILD_PROVENANCE_FILE}" "version=${SHERPA_ONNX_VERSION}" &&
    provenance_has "${BUILD_PROVENANCE_FILE}" "onnxruntime_version=${ONNX_VERSION_WEB}" &&
    provenance_has "${BUILD_PROVENANCE_FILE}" "emscripten_version=${EMSCRIPTEN_VERSION}" &&
    provenance_has "${BUILD_PROVENANCE_FILE}" "threads=on" &&
    provenance_has "${BUILD_PROVENANCE_FILE}" "recipe_schema=${SHERPA_RECIPE_SCHEMA}" &&
    provenance_has "${BUILD_PROVENANCE_FILE}" "script_sha256=${SCRIPT_SHA256}" &&
    provenance_has "${BUILD_PROVENANCE_FILE}" "patch_sha256=${PATCH_SHA256}" &&
    provenance_has_pattern "${BUILD_PROVENANCE_FILE}" '^source_revision=[0-9a-f]{40,64}$' &&
    provenance_has_pattern "${BUILD_PROVENANCE_FILE}" '^patch_state=(applied|skipped|absent)$'
}

write_provenance() {
  local file="$1"
  local component="$2"
  local source="$3"
  local tmp="${file}.tmp.$$"
  : "${SOURCE_REVISION:?source revision must be known before writing provenance}"
  : "${PATCH_STATE:?patch state must be known before writing provenance}"
  mkdir -p "$(dirname "${file}")"
  {
    echo "schema=1"
    echo "component=${component}"
    echo "version=${SHERPA_ONNX_VERSION}"
    echo "onnxruntime_version=${ONNX_VERSION_WEB}"
    echo "emscripten_version=${EMSCRIPTEN_VERSION}"
    echo "threads=on"
    echo "recipe_schema=${SHERPA_RECIPE_SCHEMA}"
    echo "script_sha256=${SCRIPT_SHA256}"
    echo "patch_sha256=${PATCH_SHA256}"
    echo "source_revision=${SOURCE_REVISION}"
    echo "patch_state=${PATCH_STATE}"
    echo "source=${source}"
  } > "${tmp}"
  mv "${tmp}" "${file}"
}

require_canonical_emscripten() {
  if ! command -v emcc >/dev/null 2>&1 || ! command -v emcmake >/dev/null 2>&1; then
    echo "ERROR: Emscripten ${EMSCRIPTEN_VERSION} is required for the Web Sherpa source build." >&2
    echo "Run: sdk/runanywhere-web/wasm/scripts/setup-emsdk.sh" >&2
    exit 1
  fi

  local actual
  actual="$(emcc --version 2>/dev/null | sed -nE '1s/.*[^0-9]([0-9]+\.[0-9]+\.[0-9]+)(-git)?.*/\1/p')"
  if [ "${actual}" != "${EMSCRIPTEN_VERSION}" ]; then
    echo "ERROR: Emscripten provenance mismatch: expected ${EMSCRIPTEN_VERSION}, found ${actual:-unknown}." >&2
    echo "Activate the canonical emsdk before rebuilding Web native archives." >&2
    exit 1
  fi
}

ensure_source_checkout() {
  local expected_tag="v${SHERPA_ONNX_VERSION}"
  local actual_tag=""
  local dirty="0"
  local source_root=""
  local source_real=""
  local has_own_git="0"
  if [ -d "${SRC_DIR}" ]; then
    source_real="$(cd "${SRC_DIR}" && pwd -P)"
    source_root="$(git -C "${SRC_DIR}" rev-parse --show-toplevel 2>/dev/null || true)"
    if [ -n "${source_root}" ]; then
      source_root="$(cd "${source_root}" && pwd -P)"
      [ "${source_root}" = "${source_real}" ] && has_own_git="1"
    fi
  fi

  if [ "${has_own_git}" = "1" ]; then
    actual_tag="$(git -C "${SRC_DIR}" describe --tags --exact-match HEAD 2>/dev/null || true)"
    if ! git -C "${SRC_DIR}" diff --quiet --ignore-submodules -- ||
       ! git -C "${SRC_DIR}" diff --cached --quiet --ignore-submodules -- ||
       [ -n "$(git -C "${SRC_DIR}" ls-files --others --exclude-standard)" ]; then
      dirty="1"
    fi
    if [ "${actual_tag}" != "${expected_tag}" ] || [ "${dirty}" = "1" ]; then
      if [ -n "${SHERPA_ONNX_SRC_DIR:-}" ]; then
        echo "ERROR: SHERPA_ONNX_SRC_DIR must be clean and exactly at ${expected_tag} (found ${actual_tag:-untagged}, dirty=${dirty})." >&2
        exit 1
      fi
      echo "Removing stale/dirty Sherpa-ONNX source checkout (${actual_tag:-unknown}, dirty=${dirty}; need ${expected_tag})."
      rm -rf "${SRC_DIR}"
      has_own_git="0"
    fi
  elif [ -e "${SRC_DIR}" ]; then
    if [ -n "${SHERPA_ONNX_SRC_DIR:-}" ]; then
      echo "ERROR: SHERPA_ONNX_SRC_DIR is not a git checkout at ${SRC_DIR}." >&2
      exit 1
    fi
    echo "Removing unversioned Sherpa-ONNX source tree: ${SRC_DIR}"
    rm -rf "${SRC_DIR}"
  fi

  if [ "${has_own_git}" != "1" ]; then
    git clone --depth 1 --branch "${expected_tag}" \
      https://github.com/k2-fsa/sherpa-onnx.git "${SRC_DIR}"
  fi
}

# Read-only probe for CI/release scripts that need to check whether a rebuild
# is required without deleting or downloading anything.
if [ "${RAC_WASM_ORT_PROVENANCE_CHECK_ONLY:-0}" = "1" ]; then
  if ort_provenance_matches; then
    echo "Sherpa dependency ONNX Runtime WASM provenance: current"
    exit 0
  fi
  echo "Sherpa dependency ONNX Runtime WASM provenance: stale or missing"
  exit 2
fi

if [ "${RAC_WASM_PROVENANCE_CHECK_ONLY:-0}" = "1" ]; then
  if provenance_matches && ort_provenance_matches; then
    echo "Sherpa-ONNX WASM provenance: current"
    exit 0
  fi
  echo "Sherpa-ONNX WASM provenance: stale or missing"
  exit 2
fi

if [ -e "${DEST_DIR}" ] && ! provenance_matches; then
  echo "Removing stale/unproven Sherpa-ONNX WASM vendor directory: ${DEST_DIR}"
  rm -rf "${DEST_DIR}"
fi

mkdir -p "$(dirname "${SRC_DIR}")" "${DEST_DIR}/lib" "${DEST_DIR}/include"

if ! ort_provenance_matches; then
  echo "ERROR: provenance-matched ONNX Runtime ${ONNX_VERSION_WEB} WASM is required first." >&2
  echo "Run: sdk/runanywhere-web/wasm/scripts/vendor-onnxruntime-wasm.sh" >&2
  exit 1
fi

# --- Prebuilt WASM bundle (download-first; mirrors the Android prebuilt .so) ---
# Download + extract the matched ORT+sherpa WASM static libs from the
# sherpa-onnx-rac release only after validating the embedded marker; the
# release tag/cache filename is not sufficient evidence of the Emscripten
# toolchain used to build it. Force a source build with
# RAC_WASM_BUILD_FROM_SOURCE=1; override the source repo/tag with
# RAC_WASM_PREBUILT_REPO / RAC_WASM_PREBUILT_TAG.
if [ "${RAC_WASM_BUILD_FROM_SOURCE:-0}" != "1" ]; then
  if provenance_matches; then
    echo "Sherpa-ONNX WASM already vendored with current provenance: ${SHERPA_ARCHIVE_DEST}"
    exit 0
  fi
  _RAC_TP="${REPO_ROOT}/sdk/runanywhere-commons/third_party"
  _RAC_REPO="${RAC_WASM_PREBUILT_REPO:-${SHERPA_ONNX_REPO_ANDROID:-Siddhesh2377/sherpa-onnx-rac}}"
  _RAC_TAG="${RAC_WASM_PREBUILT_TAG:-v${SHERPA_ONNX_VERSION}}"
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
    if tar -xjf "${_RAC_CACHE}" -C "${_RAC_TP}" sherpa-onnx-wasm; then
      if provenance_matches; then
        echo "Vendored Sherpa-ONNX WASM from provenance-matched prebuilt bundle: ${SHERPA_ARCHIVE_DEST}"
        exit 0
      fi
      echo "Prebuilt bundle is incomplete or lacks matching version/toolchain provenance; falling back to source."
    else
      echo "Prebuilt bundle is corrupt or lacks the sherpa-onnx-wasm member; falling back to source."
      rm -f "${_RAC_CACHE}"
    fi
    rm -rf "${DEST_DIR}"
    mkdir -p "${DEST_DIR}/lib" "${DEST_DIR}/include"
  fi
fi
# --- from-source build (reached if RAC_WASM_BUILD_FROM_SOURCE=1 or download failed) ---

require_canonical_emscripten
ensure_source_checkout
SOURCE_REVISION="$(git -C "${SRC_DIR}" rev-parse HEAD)"

if [ -d "${BUILD_DIR}" ] && ! build_provenance_matches; then
  echo "Removing stale Sherpa-ONNX WASM build tree for a different version/toolchain."
  rm -rf "${BUILD_DIR}"
fi

# Apply RACommons patches. Wraps the C API constructors
# (CreateOfflineRecognizer / CreateOfflineTts / CreateVoiceActivityDetector)
# in try/catch so std::exception thrown from inside ORT or Eigen surfaces as
# `nullptr` + a logged error instead of a raw `CppException` crossing the
# WASM/JS boundary.
if [ -f "${SHERPA_PATCH}" ]; then
  if git -C "${SRC_DIR}" apply --reverse --check "${SHERPA_PATCH}" >/dev/null 2>&1; then
    PATCH_STATE="applied"
    echo "Sherpa patch already applied: ${SHERPA_PATCH}"
  elif git -C "${SRC_DIR}" apply --check "${SHERPA_PATCH}" >/dev/null 2>&1; then
    echo "Applying Sherpa patch: ${SHERPA_PATCH}"
    git -C "${SRC_DIR}" apply "${SHERPA_PATCH}"
    PATCH_STATE="applied"
  else
    # Sherpa 1.13.2+ reorganized c-api.cc + session.cc
    # so the old line offsets in this patch no longer match. The session.cc
    # WASM inter-op fix is already in upstream 1.13.2 (see csrc/session.cc
    # `#if SHERPA_ONNX_ENABLE_WASM` block); the c-api.cc try/catch hardening
    # remains uncovered but is robustness-only (existing builds without it
    # still work; bad input just surfaces a CppException instead of a logged
    # nullptr). Skip the patch with a warning rather than fail the vendor.
    echo "WARNING: Sherpa patch ${SHERPA_PATCH} does not apply cleanly to v${SHERPA_ONNX_VERSION}; continuing without it." >&2
    echo "         Upstream 1.13.2+ already includes the session.cc WASM inter-op fix; the c-api.cc try/catch hardening is robustness-only." >&2
    PATCH_STATE="skipped"
  fi
else
  PATCH_STATE="absent"
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
  -DSHERPA_ONNX_USE_PRE_INSTALLED_ONNXRUNTIME_IF_AVAILABLE=ON \
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

write_provenance "${BUILD_PROVENANCE_FILE}" "sherpa-onnx-wasm-build" "source:v${SHERPA_ONNX_VERSION}"
write_provenance "${PROVENANCE_FILE}" "sherpa-onnx-wasm" "source:v${SHERPA_ONNX_VERSION}"

echo "Vendored Sherpa-ONNX WASM:"
echo "  ${DEST_DIR}/lib/*.a"
echo "  ${DEST_DIR}/include/sherpa-onnx/c-api/c-api.h"
