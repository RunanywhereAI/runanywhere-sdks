# @runanywhere/web-onnx

Speech-to-Text (STT), Text-to-Speech (TTS), and Voice Activity Detection (VAD) backend for the [RunAnywhere Web SDK](https://www.npmjs.com/package/@runanywhere/web) — powered by [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) compiled to WebAssembly.

> **Note:** This package uses [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) (not generic ONNX Runtime). Sherpa-onnx is a speech-focused inference engine that runs ONNX models optimized for STT (Whisper, Zipformer, Paraformer), TTS (Piper), and VAD (Silero).

> **Peer dependency:** Requires [`@runanywhere/web`](https://www.npmjs.com/package/@runanywhere/web) `>=0.19.13 <1`

## Installation

```bash
npm install @runanywhere/web @runanywhere/web-onnx
```

## Quick Start

```typescript
import { RunAnywhere } from '@runanywhere/web';
import { ONNX } from '@runanywhere/web-onnx';

// 1. Initialize core SDK
await RunAnywhere.initialize({ environment: 'development' });

// 2. Register the ONNX backend
await ONNX.register();

// 3. Speech-to-Text through the core facade
const transcript = await RunAnywhere.stt.transcribeAuto(audioFloat32Array, {
  modelPath: '/models/whisper-tiny.onnx',
  modelId: 'whisper-tiny',
});
console.log(transcript.text);

// 4. Text-to-Speech
const speech = await RunAnywhere.tts.synthesizeAuto('Hello from RunAnywhere!', {
  voicePath: '/models/piper-en.onnx',
  voiceId: 'piper-en',
});
// speech.audioData is Float32Array, speech.sampleRate is the sample rate

// 5. Voice Activity Detection
const vad = await RunAnywhere.vad.detectVoiceAuto(audioFloat32Array, {
  modelPath: '/models/silero_vad.onnx',
});
console.log(vad);
```

## Capabilities

| Feature | Class | Description |
|---------|-------|-------------|
| **Speech-to-Text** | `RunAnywhere.stt` | Offline recognition through the RACommons STT proto ABI |
| **Text-to-Speech** | `RunAnywhere.tts` | Neural voice synthesis through the RACommons TTS proto ABI |
| **Voice Activity Detection** | `RunAnywhere.vad` | Speech/silence detection through the RACommons VAD proto ABI |

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
