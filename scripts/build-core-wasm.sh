#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 RunAnywhere AI, Inc.
#
# Build the v2 core + engines as a single WASM module for the Web SDK.
# Requires the Emscripten SDK (emsdk); source `emsdk_env.sh` before
# running. Outputs to build/wasm/.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${ROOT}/build/wasm"
OUT_DIR="${ROOT}/sdk/web/dist/wasm"

if ! command -v emcmake >/dev/null 2>&1; then
    echo "emcmake not found. Source emsdk_env.sh from your emsdk install." >&2
    exit 1
fi

echo "=== Configure =========================================="
emcmake cmake -S "${ROOT}" -B "${BUILD_DIR}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DRA_BUILD_TESTS=OFF \
    -DRA_BUILD_TOOLS=OFF \
    -DRA_BUILD_ENGINES=ON \
    -DRA_BUILD_SOLUTIONS=ON \
    -DRA_BUILD_SERVER=OFF \
    -DRA_BUILD_HTTP_CLIENT=OFF \
    -DRA_BUILD_MODEL_DOWNLOADER=OFF \
    -DRA_BUILD_EXTRACTION=OFF \
    -DRA_DISABLE_JNI_BRIDGE=ON

echo "=== Build =============================================="
cmake --build "${BUILD_DIR}" --target runanywhere_wasm --parallel

echo "=== Copy to sdk/web/dist/wasm/ ========================="
mkdir -p "${OUT_DIR}"
cp -v "${BUILD_DIR}/sdk/web/wasm/runanywhere_wasm.js"    "${OUT_DIR}/"
cp -v "${BUILD_DIR}/sdk/web/wasm/runanywhere_wasm.wasm"  "${OUT_DIR}/"

echo "✓ WASM build complete → ${OUT_DIR}"
