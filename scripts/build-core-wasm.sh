#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# build-core-wasm.sh — wraps the wasm CMake preset (Emscripten toolchain),
# then copies the produced runanywhere_wasm.{js,wasm} artifacts into the
# Web SDK's dist tree.
#
# GAP 07 Phase 6 — see v2_gap_specs/GAP_07_SINGLE_ROOT_CMAKE.md.
#
# WASM uses RAC_STATIC_PLUGINS=ON (set by the preset) — engines link
# directly into the WASM module since dlopen is unavailable.
#
# Output:
#   sdk/runanywhere-web/packages/core/dist/wasm/runanywhere_wasm.{js,wasm}
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${REPO_ROOT}/sdk/runanywhere-web/packages/core/dist/wasm"

if [ -z "${EMSDK:-}" ]; then
    echo "error: EMSDK is not set. source emsdk_env.sh from your Emscripten install." >&2
    exit 1
fi

echo "▶ Configure wasm preset"
cmake --preset wasm

echo "▶ Build wasm preset"
cmake --build --preset wasm -- -j

mkdir -p "${DEST}"

BUILD_DIR="${REPO_ROOT}/build/wasm"
JS_SRC="${BUILD_DIR}/runanywhere_wasm.js"
WASM_SRC="${BUILD_DIR}/runanywhere_wasm.wasm"

# Some Emscripten layouts place artifacts under sdk/web/wasm/ inside the build
# tree — find them generically.
if [ ! -f "${JS_SRC}" ]; then
    JS_SRC="$(find "${BUILD_DIR}" -maxdepth 4 -name "runanywhere_wasm.js" | head -1 || true)"
fi
if [ ! -f "${WASM_SRC}" ]; then
    WASM_SRC="$(find "${BUILD_DIR}" -maxdepth 4 -name "runanywhere_wasm.wasm" | head -1 || true)"
fi

if [ -z "${JS_SRC}" ] || [ ! -f "${JS_SRC}" ]; then
    echo "error: runanywhere_wasm.js not produced" >&2
    exit 1
fi

cp -v "${JS_SRC}" "${DEST}/"
cp -v "${WASM_SRC}" "${DEST}/"

echo ""
echo "✓ WASM artifacts copied to: ${DEST}"
