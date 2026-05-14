# RunAnywhere Web Example — CLAUDE.md

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
| Chat | `views/chat.ts` | `RunAnywhere.textGeneration.generateStream`, `RunAnywhere.toolCalling` |
| Vision | `views/vision.ts` | `VideoCapture`, `RunAnywhere.visionLanguage` |
| Voice | `views/voice.ts` | `RunAnywhere.voiceAgent`, `AudioCapture`, stream adapters |
| Transcribe | `views/transcribe.ts` | `AudioCapture`, `RunAnywhere.stt.transcribeAuto`, internal STT adapter readiness |
| Speak | `views/speak.ts` | `RunAnywhere.tts.synthesizeAuto`, `AudioPlayback`, internal TTS adapter readiness |
| Documents | `views/documents.ts` | `RunAnywhere.rag` |
| Storage | `views/storage.ts` | `RunAnywhere.storage`, `RunAnywhere.modelRegistry`, `RunAnywhere.modelLifecycle` |
| Solutions | `views/solutions.ts` | `RunAnywhere.solutions` |
| Settings | `views/settings.ts` | local UI settings |

## Browser Requirements

The Vite dev server sets COOP/COEP headers for SharedArrayBuffer. Runtime WASM assets are copied from the SDK workspace when present:

- `racommons-llamacpp.wasm`
- `racommons-llamacpp-webgpu.wasm`

The legacy standalone `packages/onnx/wasm/sherpa/sherpa-onnx.wasm` bundle is no longer used. STT/TTS/VAD require the unified RACommons WASM build with ONNX enabled.

## Validation Standard

A passing build or app launch is only smoke validation. End-to-end modality validation requires browser launch, model download, model load, real inference, and reviewed logs/screenshots per `test_workflows/instructions/web/`.
