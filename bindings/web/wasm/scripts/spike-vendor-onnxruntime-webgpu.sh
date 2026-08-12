#!/usr/bin/env bash
# Thin alias → canonical WebGPU ORT vendor.
# Prefer: vendor-onnxruntime-wasm-webgpu.sh
#         (or: npm run vendor:wasm:onnxruntime-webgpu)
#
# Docs: bindings/web/docs/ONNX_WEBGPU.md
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/vendor-onnxruntime-wasm-webgpu.sh" "$@"
