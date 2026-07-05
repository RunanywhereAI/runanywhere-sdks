#!/usr/bin/env bash
set -euo pipefail

# RunAnywhere Web SDK - WASM Build Script
#
# Builds one or more per-package WebAssembly executables using Emscripten.
# Each requested target is a self-contained Emscripten module + .wasm staged
# into the matching packages/<pkg>/wasm/ directory.
#
# Available targets (each maps 1:1 to an npm package):
#   --core        packages/core/wasm/racommons.{js,wasm}                  (commons only — no engines)
#   --llamacpp    packages/llamacpp/wasm/racommons-llamacpp.{js,wasm}    (LLM + VLM)
#   --webgpu      packages/llamacpp/wasm/racommons-llamacpp-webgpu.{js,wasm} (variant of llamacpp)
#   --onnx        packages/onnx/wasm/racommons-onnx-sherpa.{js,wasm}     (STT/TTS/VAD)
#
# Common options:
#   --debug      Debug build with assertions and safe heap
#   --pthreads   Enable pthreads (default; requires Cross-Origin Isolation)
#   --no-pthreads Disable pthreads
#   --rag        Pull in RAG (requires --onnx)
#   --clean      Clean the matching build directory before building
#
# Prerequisites:
#   - Emscripten SDK (emsdk) installed and activated
#   - CMake 3.24+
#
# Each --webgpu/--llamacpp/--onnx/--core uses a separate build dir so they
# don't share CMake caches with conflicting backend flags.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
REPO_ROOT="${RAC_ROOT}"
COMMONS_DIR="${REPO_ROOT}/sdk/runanywhere-commons"
WASM_DIR="${REPO_ROOT}/sdk/runanywhere-web-next/wasm"

# Defaults
BUILD_TYPE="Release"
PTHREADS="ON"
DEBUG="OFF"
BUILD_CORE="OFF"
LLAMACPP="OFF"
ONNX="OFF"
WEBGPU="OFF"
RAG="OFF"
ONNX_REQUESTED="OFF"
CLEAN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --debug)
            BUILD_TYPE="Debug"
            DEBUG="ON"
            shift
            ;;
        --pthreads)
            PTHREADS="ON"
            shift
            ;;
        --no-pthreads)
            PTHREADS="OFF"
            shift
            ;;
        --core)
            BUILD_CORE="ON"
            shift
            ;;
        --llamacpp)
            LLAMACPP="ON"
            shift
            ;;
        --onnx)
            ONNX="ON"
            ONNX_REQUESTED="ON"
            # ONNX target ships the ORT + Sherpa matched set, so RAG can ride
            # along without an extra opt-in flag. RAG routes embeddings through
            # the ONNX embedding provider's rac_embeddings_service vtable at
            # runtime — when ONNX is on, every prerequisite is met.
            RAG="ON"
            shift
            ;;
        --rag)
            # --rag emits the rac_rag_*_proto symbols
            # into every requested target (llamacpp, webgpu, onnx). The default
            # `--onnx` path already pulls in RAG via the ONNX embedding provider.
            # `--rag` without `--onnx` is the Docs/RAG path where the llamacpp
            # bundle exports the proto-byte ABI and the runtime layer surfaces
            # RAC_ERROR_FEATURE_NOT_AVAILABLE when the embeddings provider has
            # not been registered yet (matches the non-WASM platform contract).
            RAG="ON"
            shift
            ;;
        --webgpu)
            WEBGPU="ON"
            LLAMACPP="ON"  # WebGPU accelerates llama.cpp
            shift
            ;;
        --all-backends)
            # Build every per-package target in sequence. We just set the flags
            # here; the dispatcher loop below iterates and calls cmake for each.
            BUILD_CORE="ON"
            LLAMACPP="ON"
            ONNX="ON"
            ONNX_REQUESTED="ON"
            RAG="ON"
            shift
            ;;
        --clean)
            CLEAN=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [TARGETS...] [OPTIONS]"
            echo ""
            echo "Targets (at least one required):"
            echo "  --core           Build packages/core/wasm/racommons (commons only)"
            echo "  --llamacpp       Build packages/llamacpp/wasm/racommons-llamacpp (LLM + VLM)"
            echo "  --webgpu         Build packages/llamacpp/wasm/racommons-llamacpp-webgpu (variant of llamacpp)"
            echo "  --onnx           Build packages/onnx/wasm/racommons-onnx-sherpa (STT/TTS/VAD)"
            echo "  --all-backends   Build core + llamacpp (CPU) + onnx"
            echo ""
            echo "Options:"
            echo "  --debug          Debug build with assertions and safe heap"
            echo "  --pthreads       Enable pthreads (default; requires Cross-Origin Isolation)"
            echo "  --no-pthreads    Disable pthreads"
            echo "  --rag            Pull in RAG (requires --onnx)"
            echo "  --clean          Clean matching build dirs before building"
            echo "  --help           Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Default to building llamacpp CPU if no target was requested (back-compat with
# `npm run build:wasm` invocations that pass no flags).
if [ "$BUILD_CORE" = "OFF" ] && [ "$LLAMACPP" = "OFF" ] && [ "$ONNX" = "OFF" ] && [ "$WEBGPU" = "OFF" ]; then
    LLAMACPP="ON"
fi

# Check Emscripten
if ! command -v emcmake &> /dev/null; then
    echo "ERROR: Emscripten not found. Please install and activate emsdk:"
    echo "  ./scripts/build/wasm/setup-emsdk.sh"
    echo "  source <emsdk-path>/emsdk_env.sh"
    exit 1
fi

ORT_WASM_ARCHIVE="${REPO_ROOT}/sdk/runanywhere-commons/third_party/onnxruntime-wasm/lib/libonnxruntime.a"
SHERPA_WASM_ARCHIVE="${REPO_ROOT}/sdk/runanywhere-commons/third_party/sherpa-onnx-wasm/lib/libsherpa-onnx-c-api.a"

# ONNX target needs the ORT WASM archive. Standalone --rag (without --onnx)
# does NOT — the RAG OBJECT library depends only on USearch + nlohmann_json
# and the rac_embeddings_service vtable, both already in librac_commons.
if [ "$ONNX" = "ON" ]; then
    if [ ! -f "${ORT_WASM_ARCHIVE}" ]; then
        echo "ERROR: Web ONNX requires sdk/runanywhere-commons/third_party/onnxruntime-wasm/lib/libonnxruntime.a"
        echo "       Build or vendor ONNX Runtime WASM static archives first:"
        echo "       scripts/build/wasm/vendor-onnxruntime.sh"
        exit 1
    fi
fi

if [ "$ONNX_REQUESTED" = "ON" ] && [ ! -f "${SHERPA_WASM_ARCHIVE}" ]; then
    echo "ERROR: --onnx requires sdk/runanywhere-commons/third_party/sherpa-onnx-wasm/lib/libsherpa-onnx-c-api.a"
    echo "       Build or vendor Sherpa-ONNX WASM static archives first:"
    echo "       scripts/build/wasm/vendor-sherpa-onnx.sh"
    exit 1
fi

# =============================================================================
# Per-target dispatcher
# =============================================================================
#
# A single configure cannot service every target combination (e.g. the WebGPU
# variant wants different llama.cpp link flags than the CPU variant). Each
# requested target gets its own build dir + cmake configure, then we build
# only the matching target.

# Build one target. Args:
#   $1 -- short label (used for build dir naming + log messages)
#   $2 -- cmake target name
#   $3 -- output filename base
#   $4 -- output staging directory
#   $5 -- "ON"/"OFF" for RAC_WASM_BUILD_CORE
#   $6 -- "ON"/"OFF" for RAC_WASM_LLAMACPP
#   $7 -- "ON"/"OFF" for RAC_WASM_ONNX
#   $8 -- "ON"/"OFF" for RAC_WASM_WEBGPU
build_target() {
    local label="$1"
    local target_name="$2"
    local out_name="$3"
    local out_dir="$4"
    local wasm_core="$5"
    local wasm_llamacpp="$6"
    local wasm_onnx="$7"
    local wasm_webgpu="$8"

    local build_dir="${WASM_DIR}/build-${label}"

    # ONNX target gating: the vendored libsherpa-onnx-c-api.a is built without
    # the wasm 'atomics' feature, so wasm-ld rejects --shared-memory when
    # linking it into a pthreads-enabled module. Force pthreads OFF for this
    # single target. (Threads made the small speech models ~10x slower anyway —
    # ORT thread-pool overhead dwarfs the parallelism — so single-thread is the
    # right config here; num_threads stays 1 via rac_set_inference_threads.)
    local pthreads_for_target="${PTHREADS}"
    if [ "$wasm_onnx" = "ON" ] && [ "$pthreads_for_target" = "ON" ]; then
        echo "NOTE: ONNX target requires pthreads=OFF (vendored sherpa-onnx-c-api.a"
        echo "      lacks the wasm 'atomics' feature; --shared-memory disallowed)."
        pthreads_for_target="OFF"
    fi

    echo ""
    echo "======================================"
    echo " Build target: ${label}"
    echo "  cmake target : ${target_name}"
    echo "  output       : ${out_dir}/${out_name}.{js,wasm}"
    echo "  build dir    : ${build_dir}"
    echo "  RAC_WASM_BUILD_CORE  = ${wasm_core}"
    echo "  RAC_WASM_LLAMACPP    = ${wasm_llamacpp}"
    echo "  RAC_WASM_ONNX        = ${wasm_onnx}"
    echo "  RAC_WASM_WEBGPU      = ${wasm_webgpu}"
    echo "======================================"

    if [ "$CLEAN" = true ]; then
        echo "Cleaning ${build_dir}..."
        rm -rf "${build_dir}"
    fi
    rm -f "${REPO_ROOT}/a.out.js" "${REPO_ROOT}/a.out.wasm" "${WASM_DIR}/a.out.js" "${WASM_DIR}/a.out.wasm"
    mkdir -p "${build_dir}"

    local cmake_thread_args=()
    if [ "$pthreads_for_target" = "ON" ]; then
        # pthreads must be present on every object that is linked into the final
        # shared-memory module, not just on the final Emscripten executable target.
        cmake_thread_args=(
            -DCMAKE_C_FLAGS="-pthread"
            -DCMAKE_CXX_FLAGS="-pthread"
        )
    fi

    local cmake_link_args=()
    if [ "$wasm_onnx" = "ON" ]; then
        # Vendored ONNX Runtime WASM static archives include protobuf objects.
        # RACommons also links generated-proto support, so allow duplicate archive
        # members at the final wasm-ld step while resolving ONNX/Sherpa/RAG builds.
        cmake_link_args=(-DCMAKE_EXE_LINKER_FLAGS="-Wl,--allow-multiple-definition")
    fi

    echo ""
    echo ">>> Configuring CMake with Emscripten..."
    # dep-bump 2026-05-19: zlib 1.3.2 introduced ZLIB_BUILD_SHARED as an
    # independent option that defaults to ON and ignores BUILD_SHARED_LIBS.
    # Emscripten's wasm-ld rejects shared archives, so we must explicitly turn
    # it OFF here even though the commons CMake also forces BUILD_SHARED_LIBS
    # OFF for the zlib FetchContent block. Passing it as a CMake variable is
    # enough — the variable is read inside zlib's own CMakeLists.txt.
    #
    # Also explicitly pass ZLIB_VERSION in its
    # purely-numeric form so libarchive's nested `FIND_PACKAGE(ZLIB 1.2.1)`
    # accepts it. The VERSIONS file holds `v1.3.2` (the GIT_TAG madler/zlib
    # uses); CMake's FindZLIB rejects 'v1.3.2' against the `>= 1.2.1` request
    # and leaves HAVE_ZLIB_H undefined, which silently re-enables libarchive's
    # `program("gzip -d")` fallback. Emscripten/OPFS cannot fork+exec, so
    # every .tar.gz extraction fails with "Can't initialize filter; unable
    # to run program 'gzip -d'". Forcing the numeric form on the command
    # line guarantees the value is correct even when the commons CMakeLists
    # in-tree pre-normalization races a stale FetchContent cache.
    emcmake cmake \
        -B "${build_dir}" \
        -S "${COMMONS_DIR}" \
        -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
        -DCMAKE_CXX_SCAN_FOR_MODULES=OFF \
        -DRAC_ENABLE_PROTOBUF=ON \
        -DRAC_ENABLE_SOLUTIONS=OFF \
        -DRAC_STATIC_PLUGINS=ON \
        -DRAC_BUILD_PLATFORM=OFF \
        -DRAC_BUILD_SHARED=OFF \
        -DZLIB_BUILD_SHARED=OFF \
        -DZLIB_VERSION="1.3.2" \
        -DZLIB_VERSION_STRING="1.3.2" \
        -DRAC_WASM_PTHREADS="${pthreads_for_target}" \
        -DRAC_WASM_DEBUG="${DEBUG}" \
        -DRAC_WASM_BUILD_CORE="${wasm_core}" \
        -DRAC_WASM_LLAMACPP="${wasm_llamacpp}" \
        -DRAC_WASM_ONNX="${wasm_onnx}" \
        -DRAC_RUNTIME_ONNXRT="${wasm_onnx}" \
        -DRAC_WASM_WEBGPU="${wasm_webgpu}" \
        -DRAC_BACKEND_RAG="${RAG}" \
        -DRAC_WASM_RAG_STANDALONE="${RAG}" \
        ${cmake_thread_args[@]+"${cmake_thread_args[@]}"} \
        ${cmake_link_args[@]+"${cmake_link_args[@]}"}

    echo ""
    echo ">>> Building ${target_name}..."
    # Force serial build (--parallel 1) to avoid an intermittent zlib static-lib
    # race; see prior commit log for the analysis. Local devs can override
    # by exporting CMAKE_BUILD_PARALLEL_LEVEL=N.
    cmake --build "${build_dir}" --target "${target_name}" --parallel "${CMAKE_BUILD_PARALLEL_LEVEL:-1}"

    local wasm_file="${out_dir}/${out_name}.wasm"
    local js_file="${out_dir}/${out_name}.js"

    if [ -f "${wasm_file}" ] && [ -f "${js_file}" ]; then
        local wasm_size
        local js_size
        wasm_size=$(du -h "${wasm_file}" | cut -f1)
        js_size=$(du -h "${js_file}" | cut -f1)
        echo "SUCCESS: ${label} build complete"
        echo "  ${out_name}.wasm: ${wasm_size}"
        echo "  ${out_name}.js:   ${js_size}"

        # Assert the libarchive program() fallback
        # is NOT linked into this artifact. The bug surface is libarchive's
        # filter_gzip.c registering archive_read_support_filter_program("gzip -d")
        # when HAVE_ZLIB_H is undefined; that pulls the string "gzip -d" plus
        # the symbol prefix `archive_read_support_filter_program` into the
        # final .wasm. With the in-process zlib filter linked, neither should
        # appear in the artifact. Fail the build if either is present so a
        # regression cannot ship to the npm packages.
        local _rac_libarchive_config_h="${build_dir}/_deps/libarchive-build/config.h"
        if [ -f "${_rac_libarchive_config_h}" ]; then
            if ! grep -q "^#define HAVE_ZLIB_H 1" "${_rac_libarchive_config_h}"; then
                echo "ERROR: libarchive built WITHOUT HAVE_ZLIB_H."
                echo "  config.h: ${_rac_libarchive_config_h}"
                echo "  libarchive will fall back to program(\"gzip -d\"); Emscripten can't fork+exec."
                grep -E "HAVE_ZLIB_H|HAVE_LIBZ|HAVE_BZLIB_H" "${_rac_libarchive_config_h}" || true
                exit 1
            fi
            if ! grep -q "^#define HAVE_BZLIB_H 1" "${_rac_libarchive_config_h}"; then
                echo "ERROR: libarchive built WITHOUT HAVE_BZLIB_H."
                echo "  config.h: ${_rac_libarchive_config_h}"
                exit 1
            fi
            echo "  libarchive config.h: HAVE_ZLIB_H + HAVE_BZLIB_H both defined (no program() fallback)"
        else
            echo "WARNING: ${_rac_libarchive_config_h} not found — cannot verify HAVE_ZLIB_H."
        fi

        # Surface-level guard: if the wasm artifact contains the literal
        # "gzip -d" command string AND the program-filter symbol, the gzip
        # external-program fallback survived linking. Search both via strings.
        if command -v strings >/dev/null 2>&1; then
            if strings "${wasm_file}" | grep -q '^gzip -d$'; then
                echo "ERROR: '${wasm_file}' contains literal 'gzip -d' string."
                echo "       This indicates libarchive's archive_read_support_filter_program(\"gzip -d\")"
                echo "       compiled into the final bundle. Emscripten/OPFS cannot fork+exec."
                exit 1
            fi
            echo "  WASM gzip-fallback string scan: clean (no 'gzip -d' literal)"
        fi

        if [ "$pthreads_for_target" = "ON" ]; then
            local worker_file="${out_dir}/${out_name}.worker.js"
            local emcc_major="0"
            if command -v emcc >/dev/null 2>&1; then
                local emcc_ver_line
                emcc_ver_line="$(emcc --version 2>/dev/null | head -n1 || true)"
                local emcc_major_detected
                emcc_major_detected="$(printf '%s' "${emcc_ver_line}" \
                    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
                    | head -n1 \
                    | cut -d. -f1 || true)"
                if [ -n "${emcc_major_detected}" ]; then
                    emcc_major="${emcc_major_detected}"
                fi
            fi
            if [ ! -f "${worker_file}" ]; then
                if [ "${emcc_major}" -ge 5 ] 2>/dev/null; then
                    echo "  ${out_name}.worker.js: bundled into main glue (Emscripten ${emcc_major}.x)"
                else
                    echo "ERROR: pthread worker missing!"
                    echo "  Expected: ${worker_file}"
                    echo "  emcc major version: ${emcc_major} (Emscripten <5.x must emit a companion worker)"
                    exit 1
                fi
            else
                local worker_size
                worker_size=$(du -h "${worker_file}" | cut -f1)
                echo "  ${out_name}.worker.js: ${worker_size}"
            fi
        fi
    else
        echo "ERROR: Build outputs not found!"
        echo "  Expected: ${wasm_file}"
        echo "  Expected: ${js_file}"
        exit 1
    fi

    rm -f "${REPO_ROOT}/a.out.js" "${REPO_ROOT}/a.out.wasm" "${WASM_DIR}/a.out.js" "${WASM_DIR}/a.out.wasm"
}

echo "======================================"
echo " RunAnywhere Web SDK - WASM Build"
echo "======================================"
echo " Build type:   ${BUILD_TYPE}"
echo " pthreads:     ${PTHREADS}"
echo " Debug:        ${DEBUG}"
echo " Targets:"
[ "$BUILD_CORE" = "ON" ]   && echo "  - core"
[ "$LLAMACPP" = "ON" ]     && [ "$WEBGPU" = "OFF" ] && echo "  - llamacpp (CPU)"
[ "$WEBGPU" = "ON" ]       && echo "  - llamacpp-webgpu"
[ "$ONNX" = "ON" ]         && echo "  - onnx-sherpa"
echo "======================================"

# Dispatch each requested target individually. Each gets its own configure
# so that backend flags don't bleed across targets that need different
# combinations.

if [ "$BUILD_CORE" = "ON" ]; then
    build_target \
        "core" \
        "racommons_core_wasm" \
        "racommons" \
        "${WASM_DIR}/../packages/core/wasm" \
        "ON" "OFF" "OFF" "OFF"
fi

if [ "$LLAMACPP" = "ON" ] && [ "$WEBGPU" = "OFF" ]; then
    build_target \
        "llamacpp" \
        "racommons_llamacpp_wasm" \
        "racommons-llamacpp" \
        "${WASM_DIR}/../packages/llamacpp/wasm" \
        "OFF" "ON" "OFF" "OFF"
fi

if [ "$WEBGPU" = "ON" ]; then
    build_target \
        "llamacpp-webgpu" \
        "racommons_llamacpp_webgpu_wasm" \
        "racommons-llamacpp-webgpu" \
        "${WASM_DIR}/../packages/llamacpp/wasm" \
        "OFF" "ON" "OFF" "ON"
fi

if [ "$ONNX" = "ON" ]; then
    build_target \
        "onnx" \
        "racommons_onnx_wasm" \
        "racommons-onnx-sherpa" \
        "${WASM_DIR}/../packages/onnx/wasm" \
        "OFF" "ON" "ON" "OFF"
fi

echo ""
echo "All requested WASM targets built successfully."
