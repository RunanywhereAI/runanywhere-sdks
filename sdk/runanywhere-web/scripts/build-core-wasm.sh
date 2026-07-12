#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# build-core-wasm.sh — wraps the root wasm CMake preset (Emscripten
# toolchain), builds the real runanywhere_wasm target, and verifies the
# package-consumable artifacts under sdk/runanywhere-web/packages/llamacpp/wasm.
#
# WASM uses RAC_STATIC_PLUGINS=ON (set by the preset) — engines link
# directly into the WASM module since dlopen is unavailable.
#
# Output:
#   sdk/runanywhere-web/packages/llamacpp/wasm/racommons-llamacpp.{js,wasm}
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DEST="${REPO_ROOT}/sdk/runanywhere-web/packages/llamacpp/wasm"
OUTPUT_NAME="${RAC_WASM_OUTPUT_NAME:-racommons-llamacpp}"
BUILD_DIR="${REPO_ROOT}/build/wasm"

resolve_emscripten_toolchain() {
    local candidate=""

    if [ -n "${EMSDK:-}" ]; then
        candidate="${EMSDK}/upstream/emscripten/cmake/Modules/Platform/Emscripten.cmake"
        if [ -f "${candidate}" ]; then
            echo "${candidate}"
            return
        fi
    fi

    if command -v emcc >/dev/null 2>&1; then
        local emcc_real emscripten_root
        emcc_real="$(python3 - <<'PY'
import os, shutil
print(os.path.realpath(shutil.which("emcc")))
PY
)"
        emscripten_root="$(cd "$(dirname "${emcc_real}")/.." && pwd)"
        for candidate in \
            "${emscripten_root}/libexec/cmake/Modules/Platform/Emscripten.cmake" \
            "${emscripten_root}/upstream/emscripten/cmake/Modules/Platform/Emscripten.cmake"
        do
            if [ -f "${candidate}" ]; then
                echo "${candidate}"
                return
            fi
        done
    fi

    return 1
}

TOOLCHAIN_FILE="$(resolve_emscripten_toolchain || true)"
if [ -z "${TOOLCHAIN_FILE}" ]; then
    echo "error: could not locate Emscripten.cmake. Export EMSDK or install emcc/emcmake on PATH." >&2
    exit 1
fi

rm -f "${REPO_ROOT}/a.out.js" "${REPO_ROOT}/a.out.wasm"

echo "▶ Configure wasm build"
# NOTE: these flags mirror the canonical multi-target builder
# sdk/runanywhere-web/wasm/scripts/build.sh so this thin wrapper produces an
# equivalent llama.cpp artifact:
#   * RAC_ENABLE_PROTOBUF=ON — the Web SDK is driven ENTIRELY through the
#     proto-byte C ABI (every *_proto export, incl. the hybrid STT router's
#     rac_stt_hybrid_router_*_proto). On Emscripten RAC_ENABLE_PROTOBUF DEFAULTS
#     TO OFF (see sdk/runanywhere-commons/CMakeLists.txt), which turns every
#     proto ABI symbol into a FEATURE_NOT_AVAILABLE stub AND fails to compile
#     src/router/hybrid/rac_stt_hybrid_router_proto.cpp (it unconditionally
#     #includes hybrid_router.pb.h). Forcing it ON makes commons vendor+build
#     libprotobuf for WASM (RAC_VENDOR_PROTOBUF=ON default) and define
#     RAC_HAVE_PROTOBUF=1 so the real proto implementations link.
#   * RAC_ENABLE_SOLUTIONS=OFF — the L5 Solutions runtime is not part of this
#     bundle; keep it explicitly off (it also requires protobuf+absl).
#   * ZLIB_BUILD_SHARED=OFF — zlib 1.3.2 added ZLIB_BUILD_SHARED (default ON,
#     ignores BUILD_SHARED_LIBS); Emscripten's wasm-ld rejects the SHARED
#     add_library, so force it off. Commons exposes the fetched source header to
#     FindZLIB so the dependency's own numeric version satisfies libarchive.
cmake \
    -S "${REPO_ROOT}" \
    -B "${BUILD_DIR}" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN_FILE}" \
    -DCMAKE_CXX_SCAN_FOR_MODULES=OFF \
    -DRAC_ENABLE_PROTOBUF=ON \
    -DRAC_ENABLE_SOLUTIONS=OFF \
    -DRAC_STATIC_PLUGINS=ON \
    -DRAC_BUILD_BACKENDS=ON \
    -DRAC_BUILD_PLATFORM=OFF \
    -DRAC_BUILD_SHARED=OFF \
    -DZLIB_BUILD_SHARED=OFF \
    -DRAC_WASM_LLAMACPP=ON

echo "▶ Build wasm target"
# Use CMake's generator-agnostic --parallel, CAPPED (repo resource
# discipline: a bare --parallel spawns one heavy compiler per core and has
# OOM-crashed dev laptops). Override with RAC_BUILD_JOBS if needed.
# (Ninja rejects a bare `-j`,
# while Make accepts it). Lets CMake pick a sensible default job count.
# The concrete executable target for the llama.cpp Web package is
# racommons_llamacpp_wasm (see sdk/runanywhere-web/wasm/CMakeLists.txt
# rac_wasm_add_target NAME); it emits racommons-llamacpp.{js,wasm}. There is no
# umbrella `runanywhere_wasm` target — each npm package has its own per-backend
# executable target.
cmake --build "${BUILD_DIR}" --target racommons_llamacpp_wasm --parallel "${RAC_BUILD_JOBS:-2}"

mkdir -p "${DEST}"

JS_DST="${DEST}/${OUTPUT_NAME}.js"
WASM_DST="${DEST}/${OUTPUT_NAME}.wasm"

# The CMake target copies the package artifacts into ${DEST}. If an older build
# tree was configured before that hook existed, recover once from the build tree
# rather than leaving the repo root littered with a.out.*.
if [ ! -f "${JS_DST}" ]; then
    JS_SRC="$(find "${BUILD_DIR}" -maxdepth 6 -name "${OUTPUT_NAME}.js" | head -1 || true)"
    if [ -n "${JS_SRC}" ] && [ -f "${JS_SRC}" ]; then
        cp -v "${JS_SRC}" "${JS_DST}"
    fi
fi
if [ ! -f "${WASM_DST}" ]; then
    WASM_SRC="$(find "${BUILD_DIR}" -maxdepth 6 -name "${OUTPUT_NAME}.wasm" | head -1 || true)"
    if [ -n "${WASM_SRC}" ] && [ -f "${WASM_SRC}" ]; then
        cp -v "${WASM_SRC}" "${WASM_DST}"
    fi
fi

if [ ! -f "${JS_DST}" ]; then
    echo "error: ${OUTPUT_NAME}.js not produced" >&2
    exit 1
fi
if [ ! -f "${WASM_DST}" ]; then
    echo "error: ${OUTPUT_NAME}.wasm not produced" >&2
    exit 1
fi

rm -f "${REPO_ROOT}/a.out.js" "${REPO_ROOT}/a.out.wasm"

echo ""
echo "✓ WASM artifacts ready at: ${DEST}"
