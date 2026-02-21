# @runanywhere/web-onnx

Speech-to-Text (STT), Text-to-Speech (TTS), and Voice Activity Detection (VAD) backend for the [RunAnywhere Web SDK](https://www.npmjs.com/package/@runanywhere/web) — powered by [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) compiled to WebAssembly.

> **Note:** This package uses [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) (not generic ONNX Runtime). Sherpa-onnx is a speech-focused inference engine that runs ONNX models optimized for STT (Whisper, Zipformer, Paraformer), TTS (Piper), and VAD (Silero).

> **Peer dependency:** Requires [`@runanywhere/web`](https://www.npmjs.com/package/@runanywhere/web) `>=0.1.0-beta.0`

## Installation

```bash
npm install @runanywhere/web @runanywhere/web-onnx
```

## Quick Start

```typescript
import { RunAnywhere } from '@runanywhere/web';
import { ONNX, STT, STTModelType, TTS, VAD, SpeechActivity } from '@runanywhere/web-onnx';

// 1. Initialize core SDK
await RunAnywhere.initialize({ environment: 'development' });

// 2. Register the ONNX backend
await ONNX.register();

// 3. Speech-to-Text
await STT.loadModel({
  modelId: 'whisper-tiny',
  type: STTModelType.Whisper,
  modelFiles: { encoder: '/models/encoder.onnx', decoder: '/models/decoder.onnx', tokens: '/models/tokens.txt' },
  sampleRate: 16000,
});
const result = await STT.transcribe(audioFloat32Array);
console.log(result.text);

// 4. Text-to-Speech
await TTS.loadVoice({
  voiceId: 'piper-en',
  modelPath: '/models/piper-en.onnx',
  tokensPath: '/models/tokens.txt',
  dataDir: '/models/espeak-ng-data',
});
const speech = await TTS.synthesize('Hello from RunAnywhere!');
// speech.audioData is Float32Array, speech.sampleRate is the sample rate

// 5. Voice Activity Detection
await VAD.initialize({ modelPath: '/models/silero_vad.onnx' });
VAD.onSpeechActivity((activity) => {
  if (activity === SpeechActivity.Ended) {
    const segment = VAD.popSpeechSegment();
    if (segment) console.log(`Speech: ${segment.samples.length} samples`);
  }
});
```

## Capabilities

| Feature | Class | Description |
|---------|-------|-------------|
| **Speech-to-Text** | `STT` | Offline recognition via Whisper, Zipformer, and Paraformer architectures |
| **Text-to-Speech** | `TTS` | Neural voice synthesis via Piper TTS with multiple voice models |
| **Voice Activity Detection** | `VAD` | Real-time speech/silence detection with Silero VAD |
| **Audio Capture** | `AudioCapture` | Microphone input via Web Audio API |
| **Audio Playback** | `AudioPlayback` | Audio output via Web Audio API |
| **Audio File Loader** | `AudioFileLoader` | Load and decode audio files for transcription |

## WASM Files

This package includes pre-built sherpa-onnx WASM binaries:

| File | Description |
|------|-------------|
| `wasm/sherpa/sherpa-onnx.wasm` | Sherpa-ONNX runtime (~12 MB) |
| `wasm/sherpa/sherpa-onnx-asr.js` | ASR (speech recognition) helper |
| `wasm/sherpa/sherpa-onnx-tts.js` | TTS (synthesis) helper |
| `wasm/sherpa/sherpa-onnx-vad.js` | VAD (voice activity) helper |
| `wasm/sherpa/sherpa-onnx-glue.js` | Emscripten glue code |

The sherpa-onnx WASM is loaded lazily — only when STT, TTS, or VAD is first used.

Configure your bundler to serve these as static assets — see the [main SDK README](https://www.npmjs.com/package/@runanywhere/web) for Vite/Webpack examples.

> **Warning (Vite):** You must add `@runanywhere/web-onnx` to [`optimizeDeps.exclude`](https://vite.dev/config/dep-optimization-options#optimizedeps-exclude) in your `vite.config.ts`. Vite's pre-bundling breaks the `import.meta.url` paths the SDK uses to locate WASM files. See the [main SDK README](https://www.npmjs.com/package/@runanywhere/web#serve-wasm-files--cross-origin-isolation) for the full Vite config.

## Cross-Origin Isolation

Multi-threaded WASM requires `SharedArrayBuffer`, which needs Cross-Origin Isolation headers:

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: credentialless
```

See the [main SDK docs](https://www.npmjs.com/package/@runanywhere/web#cross-origin-isolation-headers) for platform-specific configuration.

## License

Apache 2.0
