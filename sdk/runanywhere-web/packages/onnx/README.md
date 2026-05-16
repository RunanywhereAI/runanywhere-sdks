# @runanywhere/web-onnx

Speech-to-Text (STT), Text-to-Speech (TTS), and Voice Activity Detection (VAD) backend registration shell for the [RunAnywhere Web SDK](https://www.npmjs.com/package/@runanywhere/web).

> **Current blocker:** This package does not publish a standalone speech WASM bundle. It registers against the unified RACommons WASM module, and real STT/TTS/VAD runtime support requires ONNX Runtime and Sherpa-ONNX/Piper/eSpeak WASM static archives to be present under `sdk/runanywhere-commons/third_party/*-wasm` before building. Until `_rac_backend_onnx_register` and `_rac_backend_sherpa_register` exist in the active artifact, these APIs correctly report backend unavailable.

> **Peer dependencies:**
> - Required: [`@runanywhere/web`](https://www.npmjs.com/package/@runanywhere/web) `>=0.19.13 <1`
> - Required for the default WASM artifact: [`@runanywhere/web-llamacpp`](https://www.npmjs.com/package/@runanywhere/web-llamacpp) `>=0.19.13 <1` (declared as an optional peer; see "WASM Files" below for the standalone-artifact alternative)

## Installation

```bash
npm install @runanywhere/web @runanywhere/web-llamacpp @runanywhere/web-onnx
```

`@runanywhere/web-llamacpp` ships the unified RACommons WASM artifact that this package's backend registration shell loads by default. Apps that pre-register `LlamaCPP` (or pass an explicit `wasmUrl` to `ONNX.register()`) can omit it.

## Quick Start

```typescript
import { RunAnywhere } from '@runanywhere/web';
import { ONNX } from '@runanywhere/web-onnx';

// 1. Initialize core SDK
await RunAnywhere.initialize({ environment: 'development' });

// 2. Register the ONNX backend
await ONNX.register();

// 3. Speech-to-Text through the Swift-shaped core facade
const transcript = await RunAnywhere.transcribe(audioFloat32Array, {
  modelPath: '/models/whisper-tiny.onnx',
  modelId: 'whisper-tiny',
});
console.log(transcript.text);

// 4. Text-to-Speech
const speech = await RunAnywhere.synthesize('Hello from RunAnywhere!', {
  voicePath: '/models/piper-en.onnx',
  voiceId: 'piper-en',
});
// speech.audioData is Float32Array, speech.sampleRate is the sample rate

// 5. Voice Activity Detection
const vad = await RunAnywhere.detectVoiceActivity(audioFloat32Array, {
  modelPath: '/models/silero_vad.onnx',
});
console.log(vad);
```

## Capabilities

| Feature | Class | Description |
|---------|-------|-------------|
| **Speech-to-Text** | `RunAnywhere.transcribe` | Offline recognition through the RACommons STT proto ABI once ONNX/Sherpa exports exist |
| **Text-to-Speech** | `RunAnywhere.synthesize` | Neural voice synthesis through the RACommons TTS proto ABI once ONNX/Sherpa/Piper exports exist |
| **Voice Activity Detection** | `RunAnywhere.detectVoiceActivity` | Model-backed speech/silence detection through the RACommons VAD proto ABI once ONNX/Sherpa exports exist |

## WASM Files

This package no longer publishes a standalone `wasm/sherpa` bundle. It registers the ONNX backend against the same RACommons WASM module used by the core proto adapters. Build that module with ONNX enabled:

```bash
cd sdk/runanywhere-web
npm run build:wasm -- --llamacpp --onnx
```

## Cross-Origin Isolation

Multi-threaded WASM requires `SharedArrayBuffer`, which needs Cross-Origin Isolation headers:

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: credentialless
```

See the [main SDK docs](https://www.npmjs.com/package/@runanywhere/web#cross-origin-isolation-headers) for platform-specific configuration.

## License

Apache 2.0
