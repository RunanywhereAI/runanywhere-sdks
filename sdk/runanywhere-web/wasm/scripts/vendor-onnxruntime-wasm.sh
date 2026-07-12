#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WASM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${WASM_DIR}/../../.." && pwd)"

# Source the canonical VERSIONS file. Web has its own ORT/Sherpa matched set so
# native platform pins can remain on their validated binary versions.
# shellcheck disable=SC1091
source "${REPO_ROOT}/sdk/runanywhere-commons/scripts/load-versions.sh"

# The Web speech runtime is a single canonical matched set. Source-directory
# and prebuilt-repository overrides remain supported, but version overrides do
# not: an independently overridden ORT cannot safely satisfy Sherpa provenance.
ONNX_RUNTIME_VERSION="${ONNX_VERSION_WEB}"
: "${SHERPA_ONNX_VERSION_WEB:?SHERPA_ONNX_VERSION_WEB is missing from VERSIONS}"
: "${EMSCRIPTEN_VERSION:?EMSCRIPTEN_VERSION is missing from VERSIONS}"
: "${ONNX_COMMIT_WEB:?ONNX_COMMIT_WEB is missing from VERSIONS}"
SRC_DIR="${ONNX_RUNTIME_SRC_DIR:-${WASM_DIR}/third_party/onnxruntime}"
DEST_DIR="${REPO_ROOT}/sdk/runanywhere-commons/third_party/onnxruntime-wasm"
BUILD_CONFIG="${ONNX_RUNTIME_BUILD_CONFIG:-Release}"
case "$(uname -s)" in
  Darwin) _ORT_OS_DIR="MacOS" ;;
  *)      _ORT_OS_DIR="Linux" ;;
esac
ORT_BUILD_DIR="${SRC_DIR}/build/${_ORT_OS_DIR}/${BUILD_CONFIG}"
PROVENANCE_FILE="${DEST_DIR}/.rac-wasm-provenance"
BUILD_PROVENANCE_FILE="${ORT_BUILD_DIR}/.rac-wasm-build-provenance"
ORT_ARCHIVE_DEST="${DEST_DIR}/lib/libonnxruntime.a"
# ORT v1.27.1 intentionally pins protobuf v21.12, while RACommons-generated
# protocol bindings pin protobuf v35.1. Both runtimes are linked into the one
# canonical ONNX/Sherpa module. Shade ORT's private C++ protobuf namespace so
# wasm-ld can never resolve its protobuf21 virtual calls to protobuf35 symbols.
# The public Ort C ABI and Sherpa's C API do not expose protobuf types.
ORT_PROTOBUF_NAMESPACE="google::rac_ort_protobuf"
ORT_PROTOBUF_NAMESPACE_MANGLED="6google16rac_ort_protobuf"
UNSHADED_PROTOBUF_NAMESPACE_MANGLED="6google8protobuf"
# Both ORT and RACommons also carry different, inline-namespaced Abseil
# versions. Their C++ symbols are already isolated, but Abseil's Emscripten
# symbolizer declares one fixed-name EM_JS helper outside that namespace.
# Rename ORT's private copy so strict wasm-ld duplicate enforcement remains on.
ORT_ABSL_OFFSET_CONVERTER_SYMBOL="rac_ort_have_offset_converter"
UNSHADED_ABSL_OFFSET_CONVERTER_SYMBOL="HaveOffsetConverter"
RECIPE_SCHEMA="6"
SOURCE_REVISION=""
PATCH_STATE=""
ORT_REQUIRED_FILES=(
  "${ORT_ARCHIVE_DEST}"
  "${DEST_DIR}/include/onnxruntime_c_api.h"
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
# Sherpa-ONNX 1.13.4 creates its WASM Ort::Env through
# CreateEnvWithGlobalThreadPools. Keep ORT's matching upstream
# DEFAULT_USE_PER_SESSION_THREADS=false behavior; the legacy per-session patch
# predated that Sherpa fix and would bypass the validated global pools.
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
  # setup-emsdk.sh installs beside wasm/, at sdk/runanywhere-web/emsdk. Keep
  # check-only provenance validation usable before emsdk_env.sh is sourced.
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
  local llvm_nm
  local counts
  local shaded_count
  local unshaded_count
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
    echo "ERROR: ORT WASM archive references ${unshaded_count} unshaded google::protobuf symbols." >&2
    echo "       Linking it with RACommons protobuf v35 would mix incompatible virtual ABIs." >&2
    return 1
  fi
  if [ "${shaded_count}" -eq 0 ]; then
    echo "ERROR: ORT WASM archive contains no ${ORT_PROTOBUF_NAMESPACE} definitions." >&2
    echo "       The required protobuf namespace shading was not applied." >&2
    return 1
  fi

  echo "ORT protobuf namespace audit: ${shaded_count} shaded definitions, 0 unshaded references"
}

archive_absl_em_js_is_shaded() {
  local archive="$1"
  local llvm_nm
  [ -f "${archive}" ] || return 1
  llvm_nm="$(canonical_llvm_nm)" || return 1
  # EM_JS metadata symbols are hidden by design, so inspect the complete
  # archive symbol table rather than only externally visible globals.
  "${llvm_nm}" --format=posix "${archive}" 2>/dev/null |
    awk -v shaded_body="__em_js__${ORT_ABSL_OFFSET_CONVERTER_SYMBOL}" \
        -v shaded_ref="__em_js_ref_${ORT_ABSL_OFFSET_CONVERTER_SYMBOL}" \
        -v unshaded_body="__em_js__${UNSHADED_ABSL_OFFSET_CONVERTER_SYMBOL}" \
        -v unshaded_ref="__em_js_ref_${UNSHADED_ABSL_OFFSET_CONVERTER_SYMBOL}" '
      $1 == shaded_body { has_body = 1 }
      $1 == shaded_ref { has_ref = 1 }
      $1 == unshaded_body || $1 == unshaded_ref {
        has_unshaded = 1
      }
      END { exit !(has_body && has_ref && !has_unshaded) }
    '
}

audit_ort_absl_em_js() {
  local archive="$1"
  if ! archive_absl_em_js_is_shaded "${archive}"; then
    echo "ERROR: ORT WASM archive has an invalid Abseil EM_JS symbolizer namespace." >&2
    echo "       Expected only __em_js__${ORT_ABSL_OFFSET_CONVERTER_SYMBOL} and its ref." >&2
    return 1
  fi
  echo "ORT Abseil EM_JS audit: ${ORT_ABSL_OFFSET_CONVERTER_SYMBOL} shaded, 0 unshaded helpers"
}

provenance_matches() {
  required_files_present &&
    provenance_has "${PROVENANCE_FILE}" "schema=1" &&
    provenance_has "${PROVENANCE_FILE}" "component=onnxruntime-wasm" &&
    provenance_has "${PROVENANCE_FILE}" "version=${ONNX_RUNTIME_VERSION}" &&
    provenance_has "${PROVENANCE_FILE}" "sherpa_version=${SHERPA_ONNX_VERSION_WEB}" &&
    provenance_has "${PROVENANCE_FILE}" "emscripten_version=${EMSCRIPTEN_VERSION}" &&
    provenance_has "${PROVENANCE_FILE}" "build_config=${BUILD_CONFIG}" &&
    provenance_has "${PROVENANCE_FILE}" "threads=on" &&
    provenance_has "${PROVENANCE_FILE}" "protobuf_namespace=${ORT_PROTOBUF_NAMESPACE}" &&
    provenance_has "${PROVENANCE_FILE}" "absl_em_js_symbol=${ORT_ABSL_OFFSET_CONVERTER_SYMBOL}" &&
    provenance_has "${PROVENANCE_FILE}" "recipe_schema=${RECIPE_SCHEMA}" &&
    provenance_has "${PROVENANCE_FILE}" "script_sha256=${SCRIPT_SHA256}" &&
    provenance_has "${PROVENANCE_FILE}" "patch_sha256=${PATCH_SHA256}" &&
    provenance_has "${PROVENANCE_FILE}" "source_revision=${ONNX_COMMIT_WEB}" &&
    provenance_has_pattern "${PROVENANCE_FILE}" '^patch_state=(applied|absent)$' &&
    archive_namespace_is_shaded "${ORT_ARCHIVE_DEST}" &&
    archive_absl_em_js_is_shaded "${ORT_ARCHIVE_DEST}"
}

build_provenance_matches() {
  provenance_has "${BUILD_PROVENANCE_FILE}" "schema=1" &&
    provenance_has "${BUILD_PROVENANCE_FILE}" "component=onnxruntime-wasm-build" &&
    provenance_has "${BUILD_PROVENANCE_FILE}" "version=${ONNX_RUNTIME_VERSION}" &&
    provenance_has "${BUILD_PROVENANCE_FILE}" "sherpa_version=${SHERPA_ONNX_VERSION_WEB}" &&
    provenance_has "${BUILD_PROVENANCE_FILE}" "emscripten_version=${EMSCRIPTEN_VERSION}" &&
    provenance_has "${BUILD_PROVENANCE_FILE}" "build_config=${BUILD_CONFIG}" &&
    provenance_has "${BUILD_PROVENANCE_FILE}" "threads=on" &&
    provenance_has "${BUILD_PROVENANCE_FILE}" "protobuf_namespace=${ORT_PROTOBUF_NAMESPACE}" &&
    provenance_has "${BUILD_PROVENANCE_FILE}" "absl_em_js_symbol=${ORT_ABSL_OFFSET_CONVERTER_SYMBOL}" &&
    provenance_has "${BUILD_PROVENANCE_FILE}" "recipe_schema=${RECIPE_SCHEMA}" &&
    provenance_has "${BUILD_PROVENANCE_FILE}" "script_sha256=${SCRIPT_SHA256}" &&
    provenance_has "${BUILD_PROVENANCE_FILE}" "patch_sha256=${PATCH_SHA256}" &&
    provenance_has "${BUILD_PROVENANCE_FILE}" "source_revision=${ONNX_COMMIT_WEB}" &&
    provenance_has_pattern "${BUILD_PROVENANCE_FILE}" '^patch_state=(applied|absent)$'
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
    echo "version=${ONNX_RUNTIME_VERSION}"
    echo "sherpa_version=${SHERPA_ONNX_VERSION_WEB}"
    echo "emscripten_version=${EMSCRIPTEN_VERSION}"
    echo "build_config=${BUILD_CONFIG}"
    echo "threads=on"
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

require_canonical_emscripten() {
  if ! command -v emcc >/dev/null 2>&1 || ! command -v emcmake >/dev/null 2>&1; then
    echo "ERROR: Emscripten ${EMSCRIPTEN_VERSION} is required for the Web ORT source build." >&2
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
  local expected_tag="v${ONNX_RUNTIME_VERSION}"
  local actual_tag=""
  local actual_revision=""
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
    actual_revision="$(git -C "${SRC_DIR}" rev-parse HEAD 2>/dev/null || true)"
    if ! git -C "${SRC_DIR}" diff --quiet --ignore-submodules -- ||
       ! git -C "${SRC_DIR}" diff --cached --quiet --ignore-submodules -- ||
       [ -n "$(git -C "${SRC_DIR}" ls-files --others --exclude-standard)" ]; then
      dirty="1"
    fi
    if [ "${actual_tag}" != "${expected_tag}" ] ||
       [ "${actual_revision}" != "${ONNX_COMMIT_WEB}" ] ||
       [ "${dirty}" = "1" ]; then
      if [ -n "${ONNX_RUNTIME_SRC_DIR:-}" ]; then
        echo "ERROR: ONNX_RUNTIME_SRC_DIR must be clean at ${expected_tag}/${ONNX_COMMIT_WEB} (found ${actual_tag:-untagged}/${actual_revision:-unknown}, dirty=${dirty})." >&2
        exit 1
      fi
      echo "Removing stale/dirty ONNX Runtime source checkout (${actual_tag:-unknown}/${actual_revision:-unknown}, dirty=${dirty}; need ${expected_tag}/${ONNX_COMMIT_WEB})."
      rm -rf "${SRC_DIR}"
      has_own_git="0"
    fi
  elif [ -e "${SRC_DIR}" ]; then
    if [ -n "${ONNX_RUNTIME_SRC_DIR:-}" ]; then
      echo "ERROR: ONNX_RUNTIME_SRC_DIR is not a git checkout at ${SRC_DIR}." >&2
      exit 1
    fi
    echo "Removing unversioned ONNX Runtime source tree: ${SRC_DIR}"
    rm -rf "${SRC_DIR}"
  fi

  if [ "${has_own_git}" != "1" ]; then
    git clone --depth 1 --branch "${expected_tag}" \
      https://github.com/microsoft/onnxruntime.git "${SRC_DIR}"
  fi
  actual_revision="$(git -C "${SRC_DIR}" rev-parse HEAD)"
  if [ "${actual_revision}" != "${ONNX_COMMIT_WEB}" ]; then
    echo "ERROR: upstream ${expected_tag} resolved to an unexpected revision." >&2
    exit 1
  fi
}

# Read-only probe for CI/release scripts that need to check whether a rebuild
# is required without deleting or downloading anything.
if [ "${RAC_WASM_PROVENANCE_CHECK_ONLY:-0}" = "1" ]; then
  if provenance_matches; then
    echo "ONNX Runtime WASM provenance: current"
    exit 0
  fi
  echo "ONNX Runtime WASM provenance: stale or missing"
  exit 2
fi

if [ -e "${DEST_DIR}" ] && ! provenance_matches; then
  echo "Removing stale/unproven ONNX Runtime WASM vendor directory: ${DEST_DIR}"
  rm -rf "${DEST_DIR}"
fi

mkdir -p "$(dirname "${SRC_DIR}")" "${DEST_DIR}/lib" "${DEST_DIR}/include"

# Public Web releases are built only from the exact upstream revision pinned in
# VERSIONS. Personal-fork prebuilt archives are not an acceptable OSS input.
if provenance_matches; then
  echo "ONNX Runtime WASM already vendored with current provenance: ${ORT_ARCHIVE_DEST}"
  exit 0
fi

require_canonical_emscripten
ensure_source_checkout
SOURCE_REVISION="$(git -C "${SRC_DIR}" rev-parse HEAD)"

if [ -d "${ORT_BUILD_DIR}" ] && ! build_provenance_matches; then
  echo "Removing stale ONNX Runtime WASM build tree for a different version/toolchain."
  rm -rf "${ORT_BUILD_DIR}"
fi

PATCH_STATE="absent"

# ORT's v1.27.0 build wrapper defaults to its release-time Emscripten 4.0.23
# and its pinned emsdk submodule predates the canonical 6.0.2 manifest. Point
# that expected submodule path at the already-validated active emsdk instead;
# build.py can then activate the exact canonical version while retaining all
# of ORT's WebAssembly CMake configuration.
: "${EMSDK:?Source the canonical emsdk_env.sh before building ONNX Runtime}"
git -C "${SRC_DIR}" submodule sync --recursive
git -C "${SRC_DIR}" submodule update --init \
  cmake/external/onnx \
  cmake/external/libprotobuf-mutator
rm -rf "${SRC_DIR}/cmake/external/emsdk"
ln -s "${EMSDK}" "${SRC_DIR}/cmake/external/emsdk"

cd "${SRC_DIR}"

# Force regeneration of the bundled archive so that incremental rebuilds
# (e.g. after editing core/framework/session_options.h) actually pick up the
# new object files. Without this the bundling_target is treated as already
# satisfied by CMake and the stale archive ships unchanged.
rm -f "${ORT_BUILD_DIR}/libonnxruntime_webassembly.a"

# ORT 1.24+ removed `--use_preinstalled_eigen` and
# `--eigen_path` from build.py. Eigen is now fetched as part of the ORT build
# via the bundled `cmake/external/eigen.cmake` FetchContent declaration, so
# the previously vendored `third_party/eigen` checkout is no longer needed
# (and supplying the legacy flags causes argparse to reject them outright).
set +e
./build.sh \
  --config "${BUILD_CONFIG}" \
  --build_wasm_static_lib \
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
    "CMAKE_C_FLAGS=-fexceptions -ffile-prefix-map=${SRC_DIR}=/runanywhere-deps/onnxruntime -fmacro-prefix-map=${SRC_DIR}=/runanywhere-deps/onnxruntime -fdebug-prefix-map=${SRC_DIR}=/runanywhere-deps/onnxruntime -ffile-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fmacro-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fdebug-prefix-map=${REPO_ROOT}=/runanywhere-sdks" \
    "CMAKE_CXX_FLAGS=-fexceptions -Dprotobuf=rac_ort_protobuf -DHaveOffsetConverter=rac_ort_have_offset_converter -ffile-prefix-map=${SRC_DIR}=/runanywhere-deps/onnxruntime -fmacro-prefix-map=${SRC_DIR}=/runanywhere-deps/onnxruntime -fdebug-prefix-map=${SRC_DIR}=/runanywhere-deps/onnxruntime -ffile-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fmacro-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fdebug-prefix-map=${REPO_ROOT}=/runanywhere-sdks"
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
  find "${ORT_BUILD_DIR}" -type f \( \
    -name 'libonnxruntime_webassembly.a' -o \
    -name 'libonnxruntime.a' -o \
    -name 'onnxruntime_webassembly.a' \
  \) | sort | tail -n 1
)"

if [ -z "${ORT_ARCHIVE}" ] || [ ! -f "${ORT_ARCHIVE}" ]; then
  echo "ERROR: ONNX Runtime WASM static archive was not produced under ${ORT_BUILD_DIR}" >&2
  exit 1
fi

audit_ort_protobuf_namespace "${ORT_ARCHIVE}"
audit_ort_absl_em_js "${ORT_ARCHIVE}"
cp "${ORT_ARCHIVE}" "${DEST_DIR}/lib/libonnxruntime.a"

HEADER_SRC="${SRC_DIR}/include/onnxruntime/core/session"
# ORT 1.24+ added onnxruntime_ep_c_api.h and
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

write_provenance "${BUILD_PROVENANCE_FILE}" "onnxruntime-wasm-build" "source:v${ONNX_RUNTIME_VERSION}"
write_provenance "${PROVENANCE_FILE}" "onnxruntime-wasm" "source:v${ONNX_RUNTIME_VERSION}"

echo "Vendored ONNX Runtime WASM:"
echo "  ${DEST_DIR}/lib/libonnxruntime.a"
echo "  ${DEST_DIR}/include/*.h"
