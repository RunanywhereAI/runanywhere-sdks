# Speech / ONNX WebGPU

CPU + WebGPU twins for browser speech (STT/TTS/VAD) and ONNX embeddings.
Honest accel: publish `webgpu` only when ORT `AppendExecutionProvider("WebGPU")` succeeds.

| | CPU | WebGPU |
|--|-----|--------|
| ORT archive | `third_party/onnxruntime-wasm/` | `third_party/onnxruntime-wasm-webgpu/` |
| Vendor script | `wasm/scripts/vendor-onnxruntime-wasm.sh` | `wasm/scripts/vendor-onnxruntime-wasm-webgpu.sh` |
| WASM out | `racommons-onnx-sherpa.{js,wasm}` | `racommons-onnx-sherpa-webgpu.{js,wasm}` |

Separate trees keep provenance (`webgpu=on` only on the GPU archive) and ORT build caches from colliding. One script with a `--webgpu` flag would work; twins match the llama pattern.

WebGPU vendor also stages Dawn emdawn JS under `onnxruntime-wasm-webgpu/emdawn/` so the ORT source `build/` tree can be deleted after vendoring without breaking `--onnx-webgpu` links.

`ONNX.register({ acceleration: 'auto'|'cpu'|'webgpu', threads })` — badge `×N` is pthread/intra-op threads (clamped 1–8), not multiple GPUs. Default example uses `threads: 2`.

**Do not regress:** WebGPU twin must compile `rac_runtime_onnxrt` with `RAC_ONNXRT_EP_WEBGPU_ENABLED` (onnxrt CMakeLists). Never `#define RAC_ONNXRT_EP_WEBGPU` (enum collision). Final-wasm `COMPILE_DEFS` alone is not enough.

## Build / release

```bash
# from bindings/web
source emsdk/emsdk_env.sh
npm run vendor:wasm:speech          # CPU ORT + WebGPU ORT + Sherpa
npm run build:wasm:all              # includes --onnx-webgpu

# demo (github.com/RunanywhereAI/runanywhere-web, cloned alongside this repo)
cd ../runanywhere-web && npm run release:build
```

Gate: both speech WASM pairs non-empty; demo `release.sh` requires the WebGPU pair in `dist`; browser COI shows `Speech`/`Embeddings: WebGPU` and `ONNX.lastFallbackReason == null` (or `__RUNANYWHERE_ONNX_DIAG__`). Forced `'webgpu'` must throw if the twin/probe is broken.

Thread soak (optional): measure wall time / `Aborted()` at threads 1/2/4 on Whisper Tiny, Canary, Nemotron under COOP/COEP.
