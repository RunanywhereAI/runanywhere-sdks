#!/usr/bin/env bash
# Spike entrypoint → real WebGPU ORT vendor (separate tree from CPU archive).
#
# Stages:
#   sdk/runanywhere-commons/third_party/onnxruntime-wasm-webgpu/
#
# See docs/SPIKE_ONNX_WEBGPU.md.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/vendor-onnxruntime-wasm-webgpu.sh" "$@"
