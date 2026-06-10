# RunAnywhere Web Example — AGENTS.md

## Overview

This is the browser validation app for the Web SDK. It consumes the Swift-aligned public facade from `@runanywhere/web`, backend registration packages from `@runanywhere/web-llamacpp` and `@runanywhere/web-onnx`, and browser helpers from `@runanywhere/web/browser`.

The example may break when the SDK facade changes; update it to the latest API rather than preserving old compatibility imports.

## Commands

Run from `examples/web/RunAnywhereAI/`.

```bash
npm run typecheck
npm run build
npm run dev -- --host 127.0.0.1
```

## SDK Surfaces By View

| Tab | View File | Current SDK Surface |
| --- | --- | --- |
| Chat | `views/chat.ts` | `RunAnywhere.generateStream`, `RunAnywhere.generateWithTools` |
| Vision | `views/vision.ts` | `VideoCapture`, `RunAnywhere.loadModel`, `RunAnywhere.visionLanguage.loadCurrentModel`, `RunAnywhere.processImage` |
| Voice | `views/voice.ts` | Placeholder until STT/VAD/TTS ONNX/Sherpa artifacts are linked |
| Transcribe | `views/transcribe.ts` | `AudioCapture`, `RunAnywhere.transcribe` once ONNX/Sherpa artifacts are linked |
| Speak | `views/speak.ts` | `RunAnywhere.synthesize`, `AudioPlayback` once ONNX/Sherpa artifacts are linked |
| Documents | `views/documents.ts` | `RunAnywhere.ragIngest`, `RunAnywhere.ragQuery`, RAG diagnostics |
| Storage | `views/storage.ts` | `RunAnywhere.storage`, `RunAnywhere.modelRegistry`, `RunAnywhere.loadModel` |
| Solutions | `views/solutions.ts` | `RunAnywhere.solutions` |
| Settings | `views/settings.ts` | local UI settings |

## Browser Requirements

The Vite dev server sets COOP/COEP headers for SharedArrayBuffer. Runtime WASM assets are copied from the SDK workspace when present — there are now **three independent WASM artifacts** across three packages:

| WASM artifact | Owning package | Loaded by | Used by views |
| --- | --- | --- | --- |
| `racommons.{js,wasm}` | `@runanywhere/web` (core) | `RunAnywhere.initialize()` | All views (commons facade state) |
| `racommons-llamacpp.{js,wasm}` (CPU) | `@runanywhere/web-llamacpp` | `LlamaCPP.register()` | Chat, Vision, Documents (RAG embeddings) |
| `racommons-llamacpp-webgpu.{js,wasm}` (WebGPU) | `@runanywhere/web-llamacpp` | `LlamaCPP.register({ acceleration: 'webgpu' })` — runtime capability check picks one | Chat, Vision (when WebGPU+JSPI available) |
| `racommons-onnx-sherpa.{js,wasm}` | `@runanywhere/web-onnx` | `ONNX.register()` | Voice, Transcribe, Speak |

The legacy `packages/onnx/wasm/sherpa/sherpa-onnx.wasm` standalone bundle has been deleted. STT/TTS/VAD now run through the proto-byte adapters in `@runanywhere/web` core against the registered Sherpa vtable inside `racommons-onnx-sherpa.wasm` — there is no separate standalone speech provider path.

## Validation Standard

A passing build or app launch is only smoke validation. End-to-end modality validation requires browser launch, model download, model load, real inference, and reviewed logs/screenshots per `test_workflows/instructions/web/`.
