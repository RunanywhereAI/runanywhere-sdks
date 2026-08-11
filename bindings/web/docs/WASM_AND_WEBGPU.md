# Why WASM *and* WebGPU?

Short answer: **WebGPU accelerates the math; WASM runs the engine that owns the model.**

```text
Browser tab
  TS facade → BackendWorker
                 │
                 ▼
        ┌─────────────────────┐
        │  WASM module        │  llama.cpp / ORT+Sherpa
        │  weights, graph,    │  C++ via Emscripten
        │  tokenizer, I/O     │
        └─────────┬───────────┘
                  │ ggml / ORT EP
                  ▼
        ┌─────────────────────┐
        │  WebGPU (GPU)       │  optional accelerator
        │  or CPU threads     │
        └─────────────────────┘
```

## Roles

| Layer | Job |
|-------|-----|
| **WASM** | Portable C++ runtime in the browser: load GGUF/ONNX, tokenize, session state, streaming callbacks, pthread pools, OPFS hydrate. Without this you rewrite the whole engine in JS. |
| **WebGPU** | Browser GPU API. llama.cpp’s ggml-webgpu (and eventually ORT’s WebGPU EP) submit shaders from *inside* that WASM. It does not replace the engine. |
| **BackendWorker** | DedicatedWorker so inference does not block the UI thread. Hosts the WASM heap. |

## Why not “just WebGPU”?

WebGPU alone has no Whisper/Piper/GGUF loader, no Sherpa transducer decoding, no llama.cpp sampling loop. Those live in C++. Compiling that C++ to WASM is how we share one codebase with iOS/Android/desktop.

Native mobile uses CoreML / NNAPI / Metal **from the same C++** via different EPs. On Web the EP is CPU (SIMD/threads) or WebGPU.

## Per-backend today

| Backend | WASM artifact | Accelerator |
|---------|---------------|-------------|
| LLM/VLM | `racommons-llamacpp` + `-webgpu` | WebGPU (ggml) when available |
| Speech / ONNX emb / RAG | `racommons-onnx-sherpa` + `-webgpu` twin | ORT WebGPU EP when probe succeeds; else CPU (+ threads). Same BackendWorker for speech + embeddings. |
| Diffusion / seg / diar | — | No browser engine yet |

Inspect live status: `RunAnywhere.runtime.modalities` / `RunAnywhere.runtime.speech`.
Release and vendor details: [ONNX_WEBGPU.md](./ONNX_WEBGPU.md).
