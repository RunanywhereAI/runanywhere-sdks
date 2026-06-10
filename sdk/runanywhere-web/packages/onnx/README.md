# @runanywhere/web-onnx

Speech-to-Text (STT), Text-to-Speech (TTS), and Voice Activity Detection (VAD) backend for the [RunAnywhere Web SDK](https://www.npmjs.com/package/@runanywhere/web).

> **Backend availability:** Real STT/TTS/VAD runtime support requires ONNX Runtime and Sherpa-ONNX WASM static archives to be present under `sdk/runanywhere-commons/third_party/*-wasm` when the `racommons-onnx-sherpa.wasm` artifact this package ships is built. Until `_rac_backend_onnx_register` and `_rac_backend_sherpa_register` exist in that artifact, `ONNX.register()` reports `BackendNotAvailable` and STT/TTS/VAD calls stay unavailable.

> **Peer dependency:** Requires [`@runanywhere/web`](https://www.npmjs.com/package/@runanywhere/web) `>=0.19.13 <1`. This package does not depend on `@runanywhere/web-llamacpp` — it owns its own dedicated `racommons-onnx-sherpa.{js,wasm}` artifact.

## Installation

```bash
npm install @runanywhere/web @runanywhere/web-onnx
```

This package ships its own `racommons-onnx-sherpa.{js,wasm}` artifact under `wasm/`. There is no shared WASM module between backends; each per-package WASM is a self-contained Emscripten module.

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

This package publishes its own dedicated `wasm/racommons-onnx-sherpa.{js,wasm}` artifact. Build it from the web SDK root:

```bash
cd sdk/runanywhere-web
npm run build:wasm -- --onnx
```

The artifact is loaded by `SherpaONNXBridge` via `import.meta.url` from this package's own `wasm/` directory; configure your bundler to serve `wasm/racommons-onnx-sherpa.{js,wasm}` as static assets. See the [main SDK README](https://www.npmjs.com/package/@runanywhere/web) for Vite/Webpack examples.

## Cross-Origin Isolation

Multi-threaded WASM requires `SharedArrayBuffer`, which needs Cross-Origin Isolation headers:

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: credentialless
```

See the [main SDK docs](https://www.npmjs.com/package/@runanywhere/web#cross-origin-isolation-headers) for platform-specific configuration.

## License

Apache 2.0
