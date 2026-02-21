# RunAnywhere Web SDK

On-device AI for the browser. Run LLMs, Speech-to-Text, Text-to-Speech, Vision, and Voice AI locally via WebAssembly -- private, offline-capable, zero server dependencies.

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/WebAssembly-Powered-654FF0?style=flat-square&logo=webassembly&logoColor=white" alt="WebAssembly" /></a>
  <a href="#"><img src="https://img.shields.io/badge/TypeScript-5.6+-3178C6?style=flat-square&logo=typescript&logoColor=white" alt="TypeScript 5.6+" /></a>
  <a href="#"><img src="https://img.shields.io/badge/Chrome-96+-4285F4?style=flat-square&logo=googlechrome&logoColor=white" alt="Chrome 96+" /></a>
  <a href="#"><img src="https://img.shields.io/badge/Node.js-18+-339933?style=flat-square&logo=node.js&logoColor=white" alt="Node.js 18+" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache%202.0-blue?style=flat-square" alt="License" /></a>
</p>

> **Beta (v0.1.0)** -- This is an early release for testing and feedback. The API surface is stable but may change before v1.0. Not yet recommended for production deployments without thorough testing.

---

## Quick Links

- [Architecture Overview](#architecture)
- [Quick Start](#quick-start)
- [Building from Source](#building-from-source)
- [Browser Requirements](#browser-requirements)
- [Cross-Origin Isolation Headers](#cross-origin-isolation-headers)
- [Demo App](#demo-app)
- [FAQ](#faq)
- [Troubleshooting](#troubleshooting)

---

## Features

### Large Language Models (LLM)
- On-device text generation with streaming support
- llama.cpp backend compiled to WASM (Llama, Mistral, Qwen, SmolLM, and other GGUF models)
- Configurable system prompts, temperature, top-k/top-p, and max tokens
- Token streaming with real-time callbacks and cancellation

### Speech-to-Text (STT)
- Offline speech recognition via whisper.cpp and sherpa-onnx (WASM)
- Multiple model architectures: Whisper, Zipformer, Paraformer
- Batch transcription from Float32Array audio data
- Archive-based model loading (matching iOS/Android SDK approach)

### Text-to-Speech (TTS)
- Neural voice synthesis via sherpa-onnx Piper TTS (WASM)
- Multiple voice models with configurable parameters
- PCM audio output (Float32Array) with sample rate metadata

### Voice Activity Detection (VAD)
- Silero VAD model via sherpa-onnx (WASM)
- Real-time speech/silence detection from audio streams
- Speech segment extraction with configurable thresholds
- Callback-based speech activity events

### Vision Language Models (VLM)
- Multimodal inference via llama.cpp with mtmd support
- Accepts RGB pixel data, base64, or file paths
- Runs in a dedicated Web Worker to keep the UI responsive
- Supports Qwen2-VL and other VLM architectures

### Voice Pipeline
- Full VAD -> STT -> LLM (streaming) -> TTS orchestration
- Callback-driven state transitions (transcription, generation, synthesis)
- Cancellation support for in-progress generation

### Tool Calling and Structured Output
- Function calling with typed tool definitions and parameter schemas
- JSON schema-guided structured generation
- Hermes-style and generic tool calling formats

### Embeddings
- On-device vector embedding generation
- Configurable normalization and pooling strategies
- Single-text and batch embedding support

### Infrastructure
- Persistent model storage via Origin Private File System (OPFS)
- Automatic LRU eviction when storage quota is exceeded
- In-memory fallback cache for quota-exceeded scenarios
- Model download with progress tracking and multi-file support
- Browser capability detection (WebGPU, SharedArrayBuffer, OPFS)
- Structured logging with configurable log levels via `SDKLogger`
- Event system via `EventBus` for model lifecycle and SDK events

---

## System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **Browser** | Chrome 96+ / Edge 96+ | Chrome 120+ / Edge 120+ |
| **WebAssembly** | Required | Required |
| **SharedArrayBuffer** | For multi-threaded WASM | Requires Cross-Origin Isolation headers |
| **WebGPU** | For GPU-accelerated diffusion | Chrome 120+ |
| **OPFS** | For persistent model storage | All modern browsers |
| **RAM** | 2GB | 4GB+ for larger models |
| **Storage** | Variable | Models: 40MB -- 4GB depending on model |

---

## Package Structure

The Web SDK is a single npm package. Unlike native SDKs (iOS, Android, React Native, Flutter) which use separate packages per backend, the Web SDK compiles all inference backends into a single WebAssembly binary. Backend selection happens at WASM build time, not at the package level.

```
@runanywhere/web           -- TypeScript API + pre-built WASM (all backends)
```

The pre-built WASM includes llama.cpp (LLM/VLM), whisper.cpp (STT), and sherpa-onnx (TTS/VAD). Developers who need a smaller WASM binary with specific backends can [build from source](#building-from-source) with selective flags.

---

## Installation

```bash
npm install @runanywhere/web
```

### Serve WASM Files + Cross-Origin Isolation

The package includes pre-built WASM files in `node_modules/@runanywhere/web/wasm/`. Configure your bundler to serve these as static assets.

> **Important:** Your server **must** set Cross-Origin Isolation headers for `SharedArrayBuffer` and multi-threaded WASM to work. Without these headers the SDK falls back to single-threaded mode, which is significantly slower. See [Cross-Origin Isolation Headers](#cross-origin-isolation-headers) for all platforms (Nginx, Vercel, Netlify, Cloudflare, AWS, Apache).

**Vite:**

```typescript
// vite.config.ts
export default defineConfig({
  assetsInclude: ['**/*.wasm'],
  server: {
    headers: {
      // Required for SharedArrayBuffer / multi-threaded WASM
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'credentialless',
    },
  },
});
```

**Webpack:**

```javascript
// webpack.config.js
module.exports = {
  module: {
    rules: [
      { test: /\.wasm$/, type: 'asset/resource' },
    ],
  },
  devServer: {
    headers: {
      // Required for SharedArrayBuffer / multi-threaded WASM
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'credentialless',
    },
  },
};
```

> **Safari/iOS:** Safari does not support `credentialless` COEP. Use the COI service worker pattern shown in the [demo app](../../examples/web/RunAnywhereAI/) — it intercepts responses and injects `require-corp` headers at runtime. See `public/coi-serviceworker.js` and the `ensureCrossOriginIsolation()` call in `src/main.ts`.

---

## Quick Start

### 1. Initialize the SDK

```typescript
import { RunAnywhere } from '@runanywhere/web';

await RunAnywhere.initialize({ environment: 'development', debug: true });
```

### 2. Text Generation (LLM)

```typescript
import { TextGeneration } from '@runanywhere/web';

// Load a GGUF model
await TextGeneration.loadModel('/models/qwen2.5-0.5b-instruct-q4_0.gguf', 'qwen2.5-0.5b');

// Generate
const result = await TextGeneration.generate('Explain quantum computing briefly.');
console.log(result.text);

// Stream tokens
for await (const token of TextGeneration.generateStream('Write a haiku about code.')) {
  process.stdout.write(token);
}
```

### 3. Speech-to-Text (STT)

```typescript
import { STT } from '@runanywhere/web';

await STT.loadModel({
  modelId: 'whisper-tiny',
  type: STTModelType.Whisper,
  modelFiles: { encoder: '/models/encoder.onnx', decoder: '/models/decoder.onnx', tokens: '/models/tokens.txt' },
  sampleRate: 16000,
});

const result = await STT.transcribe(audioFloat32Array);
console.log(result.text);
```

### 4. Text-to-Speech (TTS)

```typescript
import { TTS } from '@runanywhere/web';

await TTS.loadVoice({
  voiceId: 'piper-en',
  modelPath: '/models/piper-en.onnx',
  tokensPath: '/models/tokens.txt',
  dataDir: '/models/espeak-ng-data',
});

const result = await TTS.synthesize('Hello from RunAnywhere!');
// result.audioData is Float32Array, result.sampleRate is the sample rate
```

### 5. Voice Activity Detection (VAD)

```typescript
import { VAD, SpeechActivity } from '@runanywhere/web';

await VAD.initialize({ modelPath: '/models/silero_vad.onnx' });

VAD.onSpeechActivity((activity) => {
  if (activity === SpeechActivity.Ended) {
    const segment = VAD.popSpeechSegment();
    if (segment) console.log(`Speech: ${segment.samples.length} samples`);
  }
});

// Feed audio chunks from microphone
VAD.processSamples(audioChunk);
```

### 6. Vision Language Model (VLM)

```typescript
import { VLM, VLMImageFormat } from '@runanywhere/web';

await VLM.loadModel('/models/qwen2-vl.gguf', '/models/mmproj.gguf', 'qwen2-vl');

const result = await VLM.process(
  { format: VLMImageFormat.RGB, rgbPixels: pixelData, width: 256, height: 256 },
  'Describe this image.',
  { maxTokens: 100 },
);
console.log(result.text);
```

---

## Architecture

```
+---------------------------------------------+
|  TypeScript API                              |
|  RunAnywhere / TextGeneration / STT / TTS   |
|  VAD / VLM / VoicePipeline / Embeddings     |
+---------------------------------------------+
|  WASMBridge + PlatformAdapter               |
|  (Emscripten addFunction / ccall / cwrap)   |
+---------------------------------------------+
|  RACommons C++ (compiled to WASM)           |
|   - Service Registry   - Event System       |
|   - Model Management   - Lifecycle          |
+---------------------------------------------+
|  Inference Backends (WASM)                  |
|   - llama.cpp  (LLM / VLM)                 |
|   - whisper.cpp (STT)                       |
|   - sherpa-onnx (TTS / VAD)                |
+---------------------------------------------+
```

The Web SDK compiles the **same C++ core** (`runanywhere-commons`) used by the iOS and Android SDKs to WebAssembly via Emscripten. The inference engines (llama.cpp, whisper.cpp, sherpa-onnx) are the same native code running in the browser, with identical vtable dispatch, service registry, and event system.

### Key Components

| Layer | Component | Description |
|-------|-----------|-------------|
| **Public** | `RunAnywhere` | SDK lifecycle (initialize, shutdown, device capabilities) |
| **Public** | `TextGeneration` | LLM text generation and streaming |
| **Public** | `STT` | Speech-to-text transcription |
| **Public** | `TTS` | Text-to-speech synthesis |
| **Public** | `VAD` | Voice activity detection |
| **Public** | `VLM` | Vision-language model inference |
| **Public** | `VoicePipeline` | STT -> LLM -> TTS orchestration |
| **Public** | `ToolCalling` | Function calling with typed definitions |
| **Public** | `StructuredOutput` | JSON schema-guided generation |
| **Public** | `Embeddings` | Vector embedding generation |
| **Foundation** | `WASMBridge` | Emscripten module loader and C interop |
| **Foundation** | `SDKLogger` | Structured logging with configurable levels |
| **Foundation** | `EventBus` | Typed event system for SDK lifecycle events |
| **Foundation** | `SDKError` | Typed error hierarchy with error codes |
| **Infrastructure** | `ModelManager` | Model download, storage, and loading orchestration |
| **Infrastructure** | `OPFSStorage` | Persistent storage via Origin Private File System |
| **Infrastructure** | `AudioCapture` | Microphone capture with Web Audio API |
| **Infrastructure** | `VideoCapture` | Camera capture and frame extraction |
| **Infrastructure** | `AudioPlayback` | Audio playback via Web Audio API |
| **Infrastructure** | `VLMWorkerBridge` | Web Worker bridge for off-main-thread VLM inference |

---

## Project Structure

```
sdk/runanywhere-web/
+-- packages/
|   +-- core/                       # @runanywhere/web npm package
|       +-- src/
|       |   +-- Public/             # Public API
|       |   |   +-- RunAnywhere.ts
|       |   |   +-- Extensions/
|       |   |       +-- RunAnywhere+TextGeneration.ts
|       |   |       +-- RunAnywhere+STT.ts
|       |   |       +-- RunAnywhere+TTS.ts
|       |   |       +-- RunAnywhere+VAD.ts
|       |   |       +-- RunAnywhere+VLM.ts
|       |   |       +-- RunAnywhere+VoiceAgent.ts
|       |   |       +-- RunAnywhere+VoicePipeline.ts
|       |   |       +-- RunAnywhere+ToolCalling.ts
|       |   |       +-- RunAnywhere+StructuredOutput.ts
|       |   |       +-- RunAnywhere+Embeddings.ts
|       |   |       +-- RunAnywhere+Diffusion.ts
|       |   |       +-- RunAnywhere+ModelManagement.ts
|       |   +-- Foundation/         # Core infrastructure
|       |   |   +-- WASMBridge.ts
|       |   |   +-- PlatformAdapter.ts
|       |   |   +-- EventBus.ts
|       |   |   +-- SDKLogger.ts
|       |   |   +-- ErrorTypes.ts
|       |   |   +-- SherpaONNXBridge.ts
|       |   +-- Infrastructure/     # Browser services
|       |   |   +-- ModelManager.ts
|       |   |   +-- ModelDownloader.ts
|       |   |   +-- ModelRegistry.ts
|       |   |   +-- OPFSStorage.ts
|       |   |   +-- AudioCapture.ts
|       |   |   +-- AudioPlayback.ts
|       |   |   +-- VideoCapture.ts
|       |   |   +-- VLMWorkerBridge.ts
|       |   |   +-- DeviceCapabilities.ts
|       |   |   +-- ArchiveUtility.ts
|       |   +-- types/              # Shared type definitions
|       +-- wasm/                   # WASM build output (generated)
|       +-- dist/                   # TypeScript build output (generated)
+-- wasm/                           # Emscripten build system
|   +-- CMakeLists.txt
|   +-- src/wasm_exports.cpp
|   +-- platform/wasm_platform_shims.cpp
|   +-- scripts/
|       +-- build.sh                # Main WASM build script
|       +-- setup-emsdk.sh          # Emscripten SDK installer
|       +-- build-sherpa-onnx.sh    # Sherpa-ONNX WASM build
+-- package.json                    # Workspace root
+-- tsconfig.base.json
```

---

## Building from Source

Building from source is only required if you want to modify the C++ core or build a custom WASM binary with specific backends. Pre-built WASM files are included in the npm package.

### Prerequisites

- [Emscripten SDK](https://emscripten.org/docs/getting_started/downloads.html) v5.0.0+
- Node.js 18+
- CMake 3.22+

### Setup Emscripten

```bash
# One-time setup
./wasm/scripts/setup-emsdk.sh
source ~/emsdk/emsdk_env.sh
```

### Build WASM

```bash
# All backends (LLM + STT + TTS/VAD) -- produces racommons.wasm (~3.6 MB)
./wasm/scripts/build.sh --all-backends

# Individual backends
./wasm/scripts/build.sh --llamacpp          # LLM only (llama.cpp)
./wasm/scripts/build.sh --whispercpp        # STT only (whisper.cpp)
./wasm/scripts/build.sh --onnx              # TTS/VAD only (sherpa-onnx)
./wasm/scripts/build.sh --llamacpp --vlm    # LLM + VLM (llama.cpp + mtmd)

# WebGPU-accelerated build
./wasm/scripts/build.sh --webgpu

# Debug build with pthreads
./wasm/scripts/build.sh --debug --pthreads --all-backends

# Clean rebuild
./wasm/scripts/build.sh --clean --all-backends
```

Build outputs are copied to `packages/core/wasm/`.

### Build TypeScript

```bash
cd sdk/runanywhere-web
npm install
npm run build:ts
```

Output: `packages/core/dist/index.js` and `packages/core/dist/index.d.ts`.

### Typecheck

```bash
cd packages/core && npx tsc --noEmit
```

---

## Browser Requirements

| Feature | Required | Fallback |
|---------|----------|----------|
| WebAssembly | Yes | N/A |
| SharedArrayBuffer | For pthreads (multi-threaded) | Single-threaded mode |
| Cross-Origin Isolation | For SharedArrayBuffer | Single-threaded mode |
| WebGPU | For Diffusion backend | N/A (Diffusion unavailable) |
| OPFS | For persistent model storage | MEMFS (volatile, models re-downloaded each session) |
| Web Audio API | For microphone capture / playback | N/A |

Use `detectCapabilities()` to check browser support at runtime:

```typescript
import { detectCapabilities } from '@runanywhere/web';

const caps = await detectCapabilities();
console.log('Cross-Origin Isolated:', caps.isCrossOriginIsolated);
console.log('SharedArrayBuffer:', caps.hasSharedArrayBuffer);
console.log('WebGPU:', caps.hasWebGPU);
console.log('OPFS:', caps.hasOPFS);
```

---

## Cross-Origin Isolation Headers

For multi-threaded WASM (pthreads), your server must set two HTTP headers on every response:

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

These headers enable `SharedArrayBuffer`, which is required for multi-threaded WASM. Without them, `crossOriginIsolated` will be `false` and the SDK falls back to single-threaded mode.

**Note:** `require-corp` means all sub-resources (images, scripts, fonts, iframes) must either be same-origin or include a `Cross-Origin-Resource-Policy: cross-origin` header. Plan accordingly for CDN assets.

### Configuration by Platform

<details>
<summary>Nginx</summary>

```nginx
server {
    listen 443 ssl;
    server_name app.example.com;

    add_header Cross-Origin-Opener-Policy "same-origin" always;
    add_header Cross-Origin-Embedder-Policy "require-corp" always;

    types {
        application/wasm wasm;
    }

    location ~* \.wasm$ {
        add_header Cross-Origin-Opener-Policy "same-origin" always;
        add_header Cross-Origin-Embedder-Policy "require-corp" always;
        add_header Cache-Control "public, max-age=31536000, immutable";
    }
}
```
</details>

<details>
<summary>Vercel</summary>

```json
{
  "headers": [
    {
      "source": "/(.*)",
      "headers": [
        { "key": "Cross-Origin-Opener-Policy", "value": "same-origin" },
        { "key": "Cross-Origin-Embedder-Policy", "value": "require-corp" }
      ]
    }
  ]
}
```
</details>

<details>
<summary>Netlify</summary>

```toml
[[headers]]
  for = "/*"
  [headers.values]
    Cross-Origin-Opener-Policy = "same-origin"
    Cross-Origin-Embedder-Policy = "require-corp"
```
</details>

<details>
<summary>Cloudflare Pages</summary>

Create a `_headers` file in the project root:

```
/*
  Cross-Origin-Opener-Policy: same-origin
  Cross-Origin-Embedder-Policy: require-corp
```
</details>

<details>
<summary>CloudFront (AWS)</summary>

Add a **Response Headers Policy** with:
- `Cross-Origin-Opener-Policy: same-origin`
- `Cross-Origin-Embedder-Policy: require-corp`

Or use a CloudFront Function:

```javascript
function handler(event) {
  var response = event.response;
  var headers = response.headers;
  headers['cross-origin-opener-policy'] = { value: 'same-origin' };
  headers['cross-origin-embedder-policy'] = { value: 'require-corp' };
  return response;
}
```
</details>

<details>
<summary>Apache (.htaccess)</summary>

```apache
<IfModule mod_headers.c>
    Header always set Cross-Origin-Opener-Policy "same-origin"
    Header always set Cross-Origin-Embedder-Policy "require-corp"
</IfModule>

AddType application/wasm .wasm
```
</details>

<details>
<summary>Vite (development)</summary>

```typescript
export default defineConfig({
  server: {
    headers: {
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'credentialless',
    },
  },
});
```
</details>

---

## Configuration

### SDK Initialization

```typescript
await RunAnywhere.initialize({
  environment: 'development',  // 'development' | 'staging' | 'production'
  debug: true,                 // Enable verbose logging
});
```

### Logging

The SDK uses `SDKLogger` for all internal logging. Configure log level and enable/disable:

```typescript
import { SDKLogger, LogLevel } from '@runanywhere/web';

SDKLogger.level = LogLevel.Debug;    // Trace | Debug | Info | Warning | Error | Fatal
SDKLogger.enabled = true;           // Toggle all SDK logging
```

### Events

Subscribe to SDK lifecycle events:

```typescript
import { EventBus } from '@runanywhere/web';

EventBus.shared.on('model.downloadProgress', (event) => {
  console.log(`Download: ${(event.data.progress * 100).toFixed(0)}%`);
});

EventBus.shared.on('model.loadCompleted', (event) => {
  console.log(`Model loaded: ${event.data.modelId}`);
});
```

---

## Error Handling

The SDK uses typed errors with error codes:

```typescript
import { SDKError, SDKErrorCode } from '@runanywhere/web';

try {
  await TextGeneration.generate('Hello');
} catch (err) {
  if (err instanceof SDKError) {
    switch (err.code) {
      case SDKErrorCode.NotInitialized:
        console.error('SDK not initialized');
        break;
      case SDKErrorCode.ModelNotLoaded:
        console.error('No model loaded');
        break;
      default:
        console.error(`SDK error [${err.code}]: ${err.message}`);
    }
  }
}
```

---

## Demo App

A full-featured example application is included at `examples/web/RunAnywhereAI/`. It demonstrates all SDK capabilities across seven tabs: Chat, Vision, Voice, Transcribe, Speak, Storage, and Settings.

```bash
cd examples/web/RunAnywhereAI
npm install
npm run dev
```

The demo app runs on Vite with Cross-Origin Isolation headers pre-configured.

---

## npm Package

```
@runanywhere/web
```

### Published Exports

| Export | Description |
|--------|-------------|
| `RunAnywhere` | SDK lifecycle (initialize, shutdown, capabilities) |
| `TextGeneration` | LLM text generation and streaming |
| `STT` | Speech-to-text transcription |
| `TTS` | Text-to-speech synthesis |
| `VAD` | Voice activity detection |
| `VLM` | Vision-language model inference |
| `VoicePipeline` | STT -> LLM -> TTS orchestration |
| `VoiceAgent` | Complete voice agent with C API pipeline |
| `ToolCalling` | Function calling with typed tool definitions |
| `StructuredOutput` | JSON schema-guided generation |
| `Embeddings` | Vector embedding generation |
| `Diffusion` | Image generation (WebGPU, scaffold) |
| `AudioCapture` | Microphone capture via Web Audio API |
| `AudioPlayback` | Audio playback via Web Audio API |
| `VideoCapture` | Camera capture and frame extraction |
| `ModelManager` | Advanced model download/storage/loading |
| `OPFSStorage` | Low-level OPFS persistence |
| `VLMWorkerBridge` | Web Worker bridge for VLM inference |
| `SDKLogger` | Structured logging |
| `SDKError` | Typed error hierarchy |
| `EventBus` | SDK event system |
| `detectCapabilities` | Browser feature detection |

---

## FAQ

### Does this work offline?

Yes. Once models are downloaded and cached in OPFS, the SDK works entirely offline. No server, API key, or network connection is needed for inference.

### Where are models stored?

Models are stored in the browser's Origin Private File System (OPFS), a sandboxed persistent storage API. Files persist across browser sessions but are origin-scoped and not accessible via the regular file system. If OPFS quota is exceeded, the SDK falls back to an in-memory cache for the current session.

### How large are the WASM files?

The core `racommons.wasm` is approximately 3.6 MB (all backends). The sherpa-onnx WASM (for TTS/VAD) is approximately 12 MB and is loaded separately only when needed. These are downloaded once and cached by the browser.

### Is my data private?

Yes. All inference runs entirely in the browser via WebAssembly. No data is sent to any server. Audio, text, and images never leave the device.

### Which browsers are supported?

Chrome 96+ and Edge 96+ are fully supported. Firefox 119+ works but lacks WebGPU. Safari 17+ has basic support but limited OPFS reliability. Mobile browsers have memory constraints that limit larger models.

### Can I use a custom model?

Yes. Any GGUF-format model compatible with llama.cpp works for LLM/VLM. STT models use ONNX format via whisper.cpp or sherpa-onnx. TTS models use Piper ONNX format.

---

## Troubleshooting

### "SharedArrayBuffer is not defined"

**Cause:** Missing Cross-Origin Isolation headers.

**Fix:** Add the required headers to your server configuration. See [Cross-Origin Isolation Headers](#cross-origin-isolation-headers). The SDK will fall back to single-threaded mode if headers are missing.

### "Model failed to load"

**Cause:** CORS error, wrong file path, or corrupted download.

**Fix:** Ensure the model URL has proper CORS headers or serve from the same origin. Check the browser console for network errors. Try deleting the model from OPFS storage and re-downloading.

### "Out of memory" / tab crashes

**Cause:** Model too large for available browser memory.

**Fix:** Use smaller quantized models (Q4_0 instead of Q8_0). Close other browser tabs. On mobile, models larger than 1 GB may exceed available memory.

### VLM inference is slow

**Cause:** CLIP image encoding is computationally expensive in WASM.

**Fix:** Use smaller capture dimensions (256x256 is recommended). The VLM runs in a dedicated Web Worker so the UI remains responsive during inference.

### OPFS storage not persisting

**Cause:** Browser may evict storage under memory pressure, or Incognito mode.

**Fix:** The SDK requests persistent storage automatically. Ensure you are not in Incognito/Private mode. Safari has known OPFS reliability issues.

---

## Known Limitations (Beta)

- No test suite yet (planned for v0.2.0)
- No model hash verification on download
- WASM memory allocations in some extension methods lack guaranteed cleanup via `finally` blocks (low probability, planned fix)
- VLM inference is single-threaded (one frame at a time)
- No streaming TTS (audio returns all-at-once)
- Safari OPFS support is unreliable
- Mobile browsers have limited memory for large models

---

## Contributing

See the repository [Contributing Guide](../../CONTRIBUTING.md) for details.

```bash
# Clone and set up
git clone https://github.com/RunanywhereAI/runanywhere-sdks.git
cd runanywhere-sdks/sdk/runanywhere-web

# Install dependencies
npm install

# Build TypeScript
npm run build:ts

# Run the demo app
cd ../../examples/web/RunAnywhereAI
npm install
npm run dev
```

---

## Support

- **Discord:** [Join our community](https://discord.gg/N359FBbDVd)
- **GitHub Issues:** [Report bugs or request features](https://github.com/RunanywhereAI/runanywhere-sdks/issues)
- **Email:** founders@runanywhere.ai

---

## License

Apache 2.0 -- see [LICENSE](../../LICENSE) for details.
