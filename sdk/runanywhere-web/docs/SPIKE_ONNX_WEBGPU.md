# Spike: ONNX/Sherpa WebGPU dual artifact

## Goal

Mirror the llama.cpp pattern for speech:

- CPU: `packages/onnx/wasm/racommons-onnx-sherpa.{js,wasm}`
- WebGPU: `packages/onnx/wasm/racommons-onnx-sherpa-webgpu.{js,wasm}`
- Worker selects WebGPU when `navigator.gpu` + `shader-f16` and the artifact exist

## Current status

| Layer | Status |
|-------|--------|
| SDK dual-artifact selection (`WorkerOnnxRuntime`) | Landed — `acceleration: 'auto'\|'cpu'\|'webgpu'` |
| CMake/`build.sh --onnx-webgpu` twin target | Landed — `RAC_WASM_ONNX_WEBGPU=1`, Asyncify + pthreads |
| Sherpa `provider` + thread knobs | Landed — `rac_sherpa_set_wasm_compute` |
| ORT WebGPU EP append | Landed in `rac_runtime_onnxrt.cpp` (named provider `"WebGPU"`) |
| ORT static archive with `--use_webgpu` | `vendor-onnxruntime-wasm-webgpu.sh` → `onnxruntime-wasm-webgpu/` |

## Vendor + rebuild

```bash
source sdk/runanywhere-web/emsdk/emsdk_env.sh   # Emscripten 6.0.2
./sdk/runanywhere-web/wasm/scripts/spike-vendor-onnxruntime-webgpu.sh
# or: ./sdk/runanywhere-web/wasm/scripts/vendor-onnxruntime-wasm-webgpu.sh

cd sdk/runanywhere-web
npm run build:wasm -- --onnx-webgpu --clean
ls -la packages/onnx/wasm/racommons-onnx-sherpa-webgpu.{js,wasm}
```

Notes:

- CPU archive at `onnxruntime-wasm/` is untouched (separate provenance).
- Speech keeps **pthreads** (Sherpa/ORT atomics ABI) and adds **Asyncify** for Dawn waits — unlike llama WebGPU which disables pthreads.
- `build.sh --onnx-webgpu` sets `-DRAC_ONNX_WASM_RUNTIME_DIR=.../onnxruntime-wasm-webgpu`.

## Validation

1. Example badge shows `Speech: WebGPU · worker` only when probe + artifact succeed.
2. Whisper Tiny STT wall time vs CPU twin.
3. Explicit `ONNX.register({ acceleration: 'webgpu' })` throws if the artifact is missing.
