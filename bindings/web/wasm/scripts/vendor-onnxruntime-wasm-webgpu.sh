#!/usr/bin/env bash
# Canonical vendor: ONNX Runtime WASM WITH WebGPU EP (separate from CPU).
#
# Stages:
#   core/third_party/onnxruntime-wasm-webgpu/
#     lib/libonnxruntime.a
#     include/...
#     .rac-wasm-provenance   (must include threads=on + webgpu=on)
#     .rac-webgpu-link-hints (Dawn emdawn JS libs for the final link)
#
# Does NOT touch onnxruntime-wasm/ (CPU twin). Use vendor-onnxruntime-wasm.sh
# for that tree. Release docs: bindings/web/docs/ONNX_WEBGPU.md
#
# Usage (from repo root, after emsdk_env.sh):
#   npm --prefix bindings/web run vendor:wasm:onnxruntime-webgpu
#   # or: ./bindings/web/wasm/scripts/vendor-onnxruntime-wasm-webgpu.sh
# Then:
#   npm --prefix bindings/web run build:wasm -- --onnx-webgpu --clean
#
# Check-only (used by build.sh before linking):
#   RAC_WASM_PROVENANCE_CHECK_ONLY=1 ./vendor-onnxruntime-wasm-webgpu.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WASM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${WASM_DIR}/../../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO_ROOT}/core/scripts/load-versions.sh"

ONNX_RUNTIME_VERSION="${ONNX_VERSION_WEB}"
: "${SHERPA_ONNX_VERSION_WEB:?SHERPA_ONNX_VERSION_WEB is missing from VERSIONS}"
: "${EMSCRIPTEN_VERSION:?EMSCRIPTEN_VERSION is missing from VERSIONS}"
: "${ONNX_COMMIT_WEB:?ONNX_COMMIT_WEB is missing from VERSIONS}"

SRC_DIR="${ONNX_RUNTIME_SRC_DIR:-${WASM_DIR}/third_party/onnxruntime}"
DEST_DIR="${REPO_ROOT}/core/third_party/onnxruntime-wasm-webgpu"
BUILD_CONFIG="${ONNX_RUNTIME_BUILD_CONFIG:-Release}"
case "$(uname -s)" in
  Darwin) _ORT_OS_DIR="MacOS" ;;
  *)      _ORT_OS_DIR="Linux" ;;
esac
# Separate build tree from the CPU vendor (build/MacOS/Release) so caches
# do not collide. ORT appends /${BUILD_CONFIG} under --build_dir.
ORT_BUILD_PARENT="${SRC_DIR}/build/${_ORT_OS_DIR}-webgpu"
ORT_BUILD_DIR="${ORT_BUILD_PARENT}/${BUILD_CONFIG}"
PROVENANCE_FILE="${DEST_DIR}/.rac-wasm-provenance"
BUILD_PROVENANCE_FILE="${ORT_BUILD_DIR}/.rac-wasm-build-provenance"
ORT_ARCHIVE_DEST="${DEST_DIR}/lib/libonnxruntime.a"
DAWN_HINT_FILE="${DEST_DIR}/.rac-webgpu-link-hints"

ORT_PROTOBUF_NAMESPACE="google::rac_ort_protobuf"
ORT_PROTOBUF_NAMESPACE_MANGLED="6google16rac_ort_protobuf"
UNSHADED_PROTOBUF_NAMESPACE_MANGLED="6google8protobuf"
ORT_ABSL_OFFSET_CONVERTER_SYMBOL="rac_ort_have_offset_converter"
UNSHADED_ABSL_OFFSET_CONVERTER_SYMBOL="HaveOffsetConverter"
RECIPE_SCHEMA="7-webgpu"
SOURCE_REVISION=""
PATCH_STATE="absent"
ORT_REQUIRED_FILES=(
  "${ORT_ARCHIVE_DEST}"
  "${DEST_DIR}/include/onnxruntime_c_api.h"
  "${DEST_DIR}/include/onnxruntime_error_code.h"
  "${DEST_DIR}/include/onnxruntime_cxx_api.h"
  "${DEST_DIR}/include/onnxruntime_cxx_inline.h"
  "${DEST_DIR}/include/onnxruntime_float16.h"
  "${DEST_DIR}/include/onnxruntime_session_options_config_keys.h"
  "${DEST_DIR}/include/onnxruntime_run_options_config_keys.h"
  "${DEST_DIR}/include/onnxruntime_ep_c_api.h"
  "${DEST_DIR}/include/onnxruntime_ep_device_ep_metadata_keys.h"
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
PATCH_SHA256="absent"

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
  for file in "${ORT_REQUIRED_FILES[@]}"; do
    [ -f "${file}" ] || return 1
  done
}

canonical_llvm_nm() {
  local emsdk_root="${EMSDK:-${WASM_DIR}/../emsdk}"
  local llvm_nm="${emsdk_root}/upstream/bin/llvm-nm"
  if [ ! -x "${llvm_nm}" ]; then
    echo "ERROR: canonical Emscripten llvm-nm not found at ${llvm_nm}." >&2
    return 1
  fi
  printf '%s\n' "${llvm_nm}"
}

archive_namespace_is_shaded() {
  local archive="$1"
  local llvm_nm
  [ -f "${archive}" ] || return 1
  llvm_nm="$(canonical_llvm_nm)" || return 1
  "${llvm_nm}" --format=posix "${archive}" 2>/dev/null |
    awk -v shaded="${ORT_PROTOBUF_NAMESPACE_MANGLED}" \
        -v unshaded="${UNSHADED_PROTOBUF_NAMESPACE_MANGLED}" '
      index($1, shaded) && $2 != "U" { has_shaded_definition = 1 }
      index($1, unshaded) { has_unshaded = 1 }
      END { exit !(has_shaded_definition && !has_unshaded) }
    '
}

audit_ort_protobuf_namespace() {
  local archive="$1"
  local llvm_nm counts shaded_count unshaded_count
  llvm_nm="$(canonical_llvm_nm)" || return 1
  counts="$(
    "${llvm_nm}" -g --format=posix "${archive}" 2>/dev/null |
      awk -v shaded="${ORT_PROTOBUF_NAMESPACE_MANGLED}" \
          -v unshaded="${UNSHADED_PROTOBUF_NAMESPACE_MANGLED}" '
        index($1, shaded) && $2 != "U" { ++shaded_count }
        index($1, unshaded) { ++unshaded_count }
        END { printf "%d %d\n", shaded_count, unshaded_count }
      '
  )"
  shaded_count="${counts%% *}"
  unshaded_count="${counts##* }"
  if [ "${unshaded_count}" -ne 0 ]; then
    echo "ERROR: ORT WebGPU archive references ${unshaded_count} unshaded google::protobuf symbols." >&2
    return 1
  fi
  if [ "${shaded_count}" -eq 0 ]; then
    echo "ERROR: ORT WebGPU archive contains no ${ORT_PROTOBUF_NAMESPACE} definitions." >&2
    return 1
  fi
  echo "ORT protobuf namespace audit: ${shaded_count} shaded definitions, 0 unshaded references"
}

archive_absl_em_js_is_shaded() {
  local archive="$1"
  local llvm_nm
  [ -f "${archive}" ] || return 1
  llvm_nm="$(canonical_llvm_nm)" || return 1
  "${llvm_nm}" --format=posix "${archive}" 2>/dev/null |
    awk -v shaded_body="__em_js__${ORT_ABSL_OFFSET_CONVERTER_SYMBOL}" \
        -v shaded_ref="__em_js_ref_${ORT_ABSL_OFFSET_CONVERTER_SYMBOL}" \
        -v unshaded_body="__em_js__${UNSHADED_ABSL_OFFSET_CONVERTER_SYMBOL}" \
        -v unshaded_ref="__em_js_ref_${UNSHADED_ABSL_OFFSET_CONVERTER_SYMBOL}" '
      $1 == shaded_body { has_body = 1 }
      $1 == shaded_ref { has_ref = 1 }
      $1 == unshaded_body || $1 == unshaded_ref { has_unshaded = 1 }
      END { exit !(has_body && has_ref && !has_unshaded) }
    '
}

audit_ort_absl_em_js() {
  local archive="$1"
  if ! archive_absl_em_js_is_shaded "${archive}"; then
    echo "ERROR: ORT WebGPU archive has an invalid Abseil EM_JS symbolizer namespace." >&2
    return 1
  fi
  echo "ORT Abseil EM_JS audit: ${ORT_ABSL_OFFSET_CONVERTER_SYMBOL} shaded"
}

archive_has_webgpu_symbols() {
  local archive="$1"
  local llvm_nm
  llvm_nm="$(canonical_llvm_nm)" || return 1
  # Accept either the named-provider path or WebGPU-specific symbols from Dawn/EP.
  "${llvm_nm}" --format=posix "${archive}" 2>/dev/null |
    awk '
      /WebGpu|WebGPU|webgpu/ { hit = 1 }
      END { exit !hit }
    '
}

provenance_matches() {
  required_files_present &&
    provenance_has "${PROVENANCE_FILE}" "schema=1" &&
    provenance_has "${PROVENANCE_FILE}" "component=onnxruntime-wasm-webgpu" &&
    provenance_has "${PROVENANCE_FILE}" "version=${ONNX_RUNTIME_VERSION}" &&
    provenance_has "${PROVENANCE_FILE}" "sherpa_version=${SHERPA_ONNX_VERSION_WEB}" &&
    provenance_has "${PROVENANCE_FILE}" "emscripten_version=${EMSCRIPTEN_VERSION}" &&
    provenance_has "${PROVENANCE_FILE}" "build_config=${BUILD_CONFIG}" &&
    provenance_has "${PROVENANCE_FILE}" "threads=on" &&
    provenance_has "${PROVENANCE_FILE}" "webgpu=on" &&
    provenance_has "${PROVENANCE_FILE}" "protobuf_namespace=${ORT_PROTOBUF_NAMESPACE}" &&
    provenance_has "${PROVENANCE_FILE}" "absl_em_js_symbol=${ORT_ABSL_OFFSET_CONVERTER_SYMBOL}" &&
    provenance_has "${PROVENANCE_FILE}" "recipe_schema=${RECIPE_SCHEMA}" &&
    provenance_has "${PROVENANCE_FILE}" "script_sha256=${SCRIPT_SHA256}" &&
    provenance_has "${PROVENANCE_FILE}" "source_revision=${ONNX_COMMIT_WEB}" &&
    archive_namespace_is_shaded "${ORT_ARCHIVE_DEST}" &&
    archive_absl_em_js_is_shaded "${ORT_ARCHIVE_DEST}" &&
    archive_has_webgpu_symbols "${ORT_ARCHIVE_DEST}"
}

build_provenance_matches() {
  provenance_has "${BUILD_PROVENANCE_FILE}" "schema=1" &&
    provenance_has "${BUILD_PROVENANCE_FILE}" "component=onnxruntime-wasm-webgpu-build" &&
    provenance_has "${BUILD_PROVENANCE_FILE}" "version=${ONNX_RUNTIME_VERSION}" &&
    provenance_has "${BUILD_PROVENANCE_FILE}" "webgpu=on" &&
    provenance_has "${BUILD_PROVENANCE_FILE}" "script_sha256=${SCRIPT_SHA256}" &&
    provenance_has "${BUILD_PROVENANCE_FILE}" "source_revision=${ONNX_COMMIT_WEB}"
}

write_provenance() {
  local file="$1"
  local component="$2"
  local source="$3"
  local tmp="${file}.tmp.$$"
  : "${SOURCE_REVISION:?source revision must be known before writing provenance}"
  mkdir -p "$(dirname "${file}")"
  {
    echo "schema=1"
    echo "component=${component}"
    echo "version=${ONNX_RUNTIME_VERSION}"
    echo "sherpa_version=${SHERPA_ONNX_VERSION_WEB}"
    echo "emscripten_version=${EMSCRIPTEN_VERSION}"
    echo "build_config=${BUILD_CONFIG}"
    echo "threads=on"
    echo "webgpu=on"
    echo "protobuf_namespace=${ORT_PROTOBUF_NAMESPACE}"
    echo "absl_em_js_symbol=${ORT_ABSL_OFFSET_CONVERTER_SYMBOL}"
    echo "recipe_schema=${RECIPE_SCHEMA}"
    echo "script_sha256=${SCRIPT_SHA256}"
    echo "patch_sha256=${PATCH_SHA256}"
    echo "source_revision=${SOURCE_REVISION}"
    echo "patch_state=${PATCH_STATE}"
    echo "source=${source}"
  } > "${tmp}"
  mv "${tmp}" "${file}"
}

write_dawn_link_hints() {
  # Stage emdawn JS into the vendor tree so --onnx-webgpu linking does not
  # depend on the ORT source build directory (safe to delete after vendor).
  local staged_dir="${DEST_DIR}/emdawn"
  local gen_dir="${ORT_BUILD_DIR}/_deps/dawn-build/gen/src/emdawnwebgpu"
  local js_lib cpp_src externs
  js_lib="$(find "${ORT_BUILD_DIR}" -type f -path '*/emdawnwebgpu/pkg/webgpu/src/library_webgpu.js' 2>/dev/null | head -n 1 || true)"
  cpp_src="$(find "${ORT_BUILD_DIR}" -type f -path '*/emdawnwebgpu/pkg/webgpu/src/webgpu.cpp' 2>/dev/null | head -n 1 || true)"
  externs="$(find "${ORT_BUILD_DIR}" -type f -path '*/emdawnwebgpu/pkg/webgpu/src/webgpu-externs.js' 2>/dev/null | head -n 1 || true)"

  mkdir -p "${staged_dir}" "$(dirname "${DAWN_HINT_FILE}")"
  local req
  for req in \
    "${gen_dir}/library_webgpu_enum_tables.js" \
    "${gen_dir}/library_webgpu_generated_sig_info.js" \
    "${gen_dir}/library_webgpu_generated_struct_info.js" \
    "${js_lib}"
  do
    if [ -z "${req}" ] || [ ! -f "${req}" ]; then
      echo "ERROR: missing Dawn emdawn input for staging: ${req:-<empty>}" >&2
      exit 1
    fi
    cp "${req}" "${staged_dir}/$(basename "${req}")"
  done
  if [ -n "${externs}" ] && [ -f "${externs}" ]; then
    cp "${externs}" "${staged_dir}/$(basename "${externs}")"
  fi
  if [ -n "${cpp_src}" ] && [ -f "${cpp_src}" ]; then
    cp "${cpp_src}" "${staged_dir}/$(basename "${cpp_src}")"
  fi

  {
    echo "# Staged under ${staged_dir} (ORT build dir is optional after vendor)."
    echo "# Order matters: enum → sig → struct → library_webgpu.js (Dawn CMakeLists)."
    echo "ORT_BUILD_DIR=${ORT_BUILD_DIR}"
    echo "EMDAWN_LIBRARY_WEBGPU_ENUM_TABLES=${staged_dir}/library_webgpu_enum_tables.js"
    echo "EMDAWN_LIBRARY_WEBGPU_SIG_INFO=${staged_dir}/library_webgpu_generated_sig_info.js"
    echo "EMDAWN_LIBRARY_WEBGPU_STRUCT_INFO=${staged_dir}/library_webgpu_generated_struct_info.js"
    echo "EMDAWN_LIBRARY_WEBGPU_JS=${staged_dir}/library_webgpu.js"
    if [ -f "${staged_dir}/webgpu-externs.js" ]; then
      echo "EMDAWN_WEBGPU_EXTERNS=${staged_dir}/webgpu-externs.js"
    else
      echo "EMDAWN_WEBGPU_EXTERNS="
    fi
    if [ -f "${staged_dir}/webgpu.cpp" ]; then
      echo "EMDAWN_WEBGPU_CPP=${staged_dir}/webgpu.cpp"
    else
      echo "EMDAWN_WEBGPU_CPP="
    fi
  } > "${DAWN_HINT_FILE}"
  echo "Wrote Dawn link hints (staged): ${DAWN_HINT_FILE}"
}

require_canonical_emscripten() {
  if ! command -v emcc >/dev/null 2>&1 || ! command -v emcmake >/dev/null 2>&1; then
    echo "ERROR: Emscripten ${EMSCRIPTEN_VERSION} is required." >&2
    echo "Run: bindings/web/wasm/scripts/setup-emsdk.sh && source emsdk_env.sh" >&2
    exit 1
  fi
  local actual
  actual="$(emcc --version 2>/dev/null | sed -nE '1s/.*[^0-9]([0-9]+\.[0-9]+\.[0-9]+)(-git)?.*/\1/p')"
  if [ "${actual}" != "${EMSCRIPTEN_VERSION}" ]; then
    echo "ERROR: Emscripten mismatch: expected ${EMSCRIPTEN_VERSION}, found ${actual:-unknown}." >&2
    exit 1
  fi
}

ensure_source_checkout() {
  local expected_tag="v${ONNX_RUNTIME_VERSION}"
  if [ ! -d "${SRC_DIR}/.git" ]; then
    mkdir -p "$(dirname "${SRC_DIR}")"
    git clone --depth 1 --branch "${expected_tag}" \
      https://github.com/microsoft/onnxruntime.git "${SRC_DIR}"
  fi
  local actual_revision
  actual_revision="$(git -C "${SRC_DIR}" rev-parse HEAD)"
  if [ "${actual_revision}" != "${ONNX_COMMIT_WEB}" ]; then
    echo "ERROR: ORT source at ${SRC_DIR} is ${actual_revision}, need ${ONNX_COMMIT_WEB}." >&2
    echo "Remove the checkout or set ONNX_RUNTIME_SRC_DIR to the pinned revision." >&2
    exit 1
  fi
}

if [ "${RAC_WASM_PROVENANCE_CHECK_ONLY:-0}" = "1" ]; then
  if provenance_matches; then
    echo "ONNX Runtime WASM WebGPU provenance: current"
    exit 0
  fi
  echo "ONNX Runtime WASM WebGPU provenance: stale or missing"
  exit 2
fi

if [ -e "${DEST_DIR}" ] && ! provenance_matches; then
  echo "Removing stale ORT WebGPU vendor directory: ${DEST_DIR}"
  rm -rf "${DEST_DIR}"
fi

mkdir -p "$(dirname "${SRC_DIR}")" "${DEST_DIR}/lib" "${DEST_DIR}/include"

if provenance_matches; then
  echo "ONNX Runtime WASM WebGPU already vendored: ${ORT_ARCHIVE_DEST}"
  exit 0
fi

require_canonical_emscripten
ensure_source_checkout
SOURCE_REVISION="$(git -C "${SRC_DIR}" rev-parse HEAD)"

if [ -d "${ORT_BUILD_DIR}" ] && ! build_provenance_matches; then
  if [ "${RAC_ORT_WEBGPU_KEEP_BUILD:-0}" = "1" ]; then
    echo "Keeping existing ORT WebGPU build tree (RAC_ORT_WEBGPU_KEEP_BUILD=1)."
  else
    echo "Removing stale ORT WebGPU build tree."
    rm -rf "${ORT_BUILD_DIR}"
  fi
fi

: "${EMSDK:?Source the canonical emsdk_env.sh before building ONNX Runtime}"
# ORT's build.py always activates cmake/external/emsdk. A symlink to the
# canonical emsdk makes emcc's sanity hash flip between symlink and realpath
# strings, which CLEARS the sysroot cache mid-build (missing headers under
# parallel Dawn/ORT compiles). Use an APFS clone (or recursive copy) so the
# path ORT sees is a single real directory.
EMSDK_CANONICAL="$(cd "${EMSDK}" && pwd -P)"
export EMSDK="${EMSDK_CANONICAL}"
# shellcheck disable=SC1091
source "${EMSDK}/emsdk_env.sh"

git -C "${SRC_DIR}" submodule sync --recursive
git -C "${SRC_DIR}" submodule update --init \
  cmake/external/onnx \
  cmake/external/libprotobuf-mutator

ORT_EMSDK="${SRC_DIR}/cmake/external/emsdk"
if [ -L "${ORT_EMSDK}" ] || [ ! -d "${ORT_EMSDK}/upstream/emscripten" ]; then
  echo "Staging ORT-local emsdk clone at ${ORT_EMSDK} (avoids symlink path flips)..."
  rm -rf "${ORT_EMSDK}"
  mkdir -p "$(dirname "${ORT_EMSDK}")"
  if cp -cR "${EMSDK_CANONICAL}" "${ORT_EMSDK}" 2>/dev/null; then
    echo "APFS clone of emsdk ready."
  else
    echo "APFS clone unavailable; falling back to rsync (slower)..."
    mkdir -p "${ORT_EMSDK}"
    rsync -a --delete "${EMSDK_CANONICAL}/" "${ORT_EMSDK}/"
  fi
fi

# From here on, ONLY the ORT-local emsdk path is on PATH / EMSDK — never the
# canonical tree — so sanity hashes stay stable for the whole build.
export EMSDK="${ORT_EMSDK}"
# Drop any prior canonical emsdk entries that would flip emcc's sanity hash.
PATH="$(printf '%s' "${PATH}" | tr ':' '\n' | grep -vF "${EMSDK_CANONICAL}" | paste -sd: -)"
export PATH
# shellcheck disable=SC1091
source "${EMSDK}/emsdk_env.sh"
export EMSCRIPTEN="${EMSDK}/upstream/emscripten"
export EM_CONFIG="${EMSDK}/.emscripten"
: "${EMSDK_PYTHON:?emsdk_env.sh did not provide EMSDK_PYTHON}"
# Dawn launches Emscripten's Python helpers through CMake's discovered
# interpreter. A host Anaconda installation can otherwise win discovery and
# select Python 3.9, which Emscripten 6 rejects. Pin every spelling used by ORT
# and Dawn to the interpreter shipped with the selected emsdk.
export PYTHON="${EMSDK_PYTHON}"
export Python_EXECUTABLE="${EMSDK_PYTHON}"
export Python3_EXECUTABLE="${EMSDK_PYTHON}"
export PATH="$(dirname "${EMSDK_PYTHON}"):${EMSDK}:${EMSCRIPTEN}:${EMSDK}/upstream/bin:${PATH}"

echo "Pre-warming Emscripten sysroot at ${EMSDK}..."
_warmup_c="$(mktemp -t rac_em_warmup.XXXXXX).c"
_warmup_js="$(mktemp -t rac_em_warmup.XXXXXX).js"
printf 'int main(void){return 0;}\n' > "${_warmup_c}"
emcc "${_warmup_c}" -o "${_warmup_js}" -O0
emcc "${_warmup_c}" -o "${_warmup_js}" -O0 -pthread -sALLOW_MEMORY_GROWTH=1
rm -f "${_warmup_c}" "${_warmup_js}" "${_warmup_js%.js}.wasm" "${_warmup_js%.js}.worker.js"

cd "${SRC_DIR}"
rm -f "${ORT_BUILD_DIR}/libonnxruntime_webassembly.a"

echo "======================================"
echo " Building ORT ${ONNX_RUNTIME_VERSION} WASM + WebGPU"
echo "  build dir: ${ORT_BUILD_DIR}"
echo "  dest:      ${DEST_DIR}"
echo "======================================"

set +e
./build.sh \
  --config "${BUILD_CONFIG}" \
  --build_dir "${ORT_BUILD_PARENT}" \
  --build_wasm_static_lib \
  --use_webgpu \
  --emsdk_version "${EMSCRIPTEN_VERSION}" \
  --skip_submodule_sync \
  --compile_no_warning_as_error \
  --enable_wasm_simd \
  --enable_wasm_threads \
  --skip_tests \
  --disable_rtti \
  --parallel "${CMAKE_BUILD_PARALLEL_LEVEL:-12}" \
  --cmake_extra_defines \
    CMAKE_POLICY_VERSION_MINIMUM=3.5 \
    onnxruntime_BUILD_UNIT_TESTS=OFF \
    "Python_EXECUTABLE=${EMSDK_PYTHON}" \
    "Python3_EXECUTABLE=${EMSDK_PYTHON}" \
    "CMAKE_C_FLAGS=-fexceptions -ffile-prefix-map=${SRC_DIR}=/runanywhere-deps/onnxruntime -fmacro-prefix-map=${SRC_DIR}=/runanywhere-deps/onnxruntime -fdebug-prefix-map=${SRC_DIR}=/runanywhere-deps/onnxruntime -ffile-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fmacro-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fdebug-prefix-map=${REPO_ROOT}=/runanywhere-sdks" \
    "CMAKE_CXX_FLAGS=-fexceptions -Dprotobuf=rac_ort_protobuf -DHaveOffsetConverter=rac_ort_have_offset_converter -ffile-prefix-map=${SRC_DIR}=/runanywhere-deps/onnxruntime -fmacro-prefix-map=${SRC_DIR}=/runanywhere-deps/onnxruntime -fdebug-prefix-map=${SRC_DIR}=/runanywhere-deps/onnxruntime -ffile-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fmacro-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fdebug-prefix-map=${REPO_ROOT}=/runanywhere-sdks"
BUILD_RC=$?
set -e

if [ "${BUILD_RC}" -ne 0 ]; then
  if [ ! -f "${ORT_BUILD_DIR}/CMakeCache.txt" ]; then
    echo "ERROR: ORT WebGPU configure failed before CMakeCache.txt" >&2
    exit "${BUILD_RC}"
  fi
  echo "ORT build.py returned ${BUILD_RC}; falling back to cmake --build -k"
  set +e
  cmake --build "${ORT_BUILD_DIR}" --parallel "${CMAKE_BUILD_PARALLEL_LEVEL:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}" -- -k
  set -e
fi

ORT_ARCHIVE="$(
  find "${ORT_BUILD_DIR}" -type f \( \
    -name 'libonnxruntime_webassembly.a' -o \
    -name 'libonnxruntime.a' -o \
    -name 'onnxruntime_webassembly.a' \
  \) | sort | tail -n 1
)"

if [ -z "${ORT_ARCHIVE}" ] || [ ! -f "${ORT_ARCHIVE}" ]; then
  echo "ERROR: ORT WebGPU WASM static archive was not produced under ${ORT_BUILD_DIR}" >&2
  exit 1
fi

if ! archive_has_webgpu_symbols "${ORT_ARCHIVE}"; then
  echo "ERROR: archive lacks WebGPU symbols — --use_webgpu may have been ignored." >&2
  exit 1
fi

audit_ort_protobuf_namespace "${ORT_ARCHIVE}"
audit_ort_absl_em_js "${ORT_ARCHIVE}"
cp "${ORT_ARCHIVE}" "${DEST_DIR}/lib/libonnxruntime.a"

HEADER_SRC="${SRC_DIR}/include/onnxruntime/core/session"
for header in \
  onnxruntime_c_api.h \
  onnxruntime_error_code.h \
  onnxruntime_cxx_api.h \
  onnxruntime_cxx_inline.h \
  onnxruntime_float16.h \
  onnxruntime_session_options_config_keys.h \
  onnxruntime_run_options_config_keys.h \
  onnxruntime_ep_c_api.h \
  onnxruntime_ep_device_ep_metadata_keys.h
do
  if [ ! -f "${HEADER_SRC}/${header}" ]; then
    echo "ERROR: missing header ${HEADER_SRC}/${header}" >&2
    exit 1
  fi
  cp "${HEADER_SRC}/${header}" "${DEST_DIR}/include/${header}"
done

write_dawn_link_hints
write_provenance "${BUILD_PROVENANCE_FILE}" "onnxruntime-wasm-webgpu-build" "source:v${ONNX_RUNTIME_VERSION}+webgpu"
write_provenance "${PROVENANCE_FILE}" "onnxruntime-wasm-webgpu" "source:v${ONNX_RUNTIME_VERSION}+webgpu"

echo "Vendored ONNX Runtime WASM WebGPU:"
echo "  ${DEST_DIR}/lib/libonnxruntime.a"
ls -lh "${DEST_DIR}/lib/libonnxruntime.a"
echo "Next: npm run build:wasm -- --onnx-webgpu --clean"
