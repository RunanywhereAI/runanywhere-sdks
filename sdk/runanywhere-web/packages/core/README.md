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

> **Current runtime status:** LLM is the only fully exercised browser E2E path in the current Web artifacts. VLM downloads and loads SmolVLM2 primary GGUF plus mmproj through the shared lifecycle, but Chrome/WebGPU inference is still blocked: `RunAnywhere.processImage(...)` reaches CLIP `encoding image slice...` and times out before token decode. STT, TTS, model-backed VAD, RAG, and VoiceAgent are blocked until ONNX Runtime and Sherpa-ONNX WASM static archives are present in `sdk/runanywhere-commons/third_party/*-wasm` and the unified RACommons WASM artifact exports the required backend symbols.

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
- Public Swift-shaped STT facade; real browser inference is blocked until ONNX/Sherpa WASM archives are linked
- Multiple model architectures: Whisper, Zipformer, Paraformer
- Batch transcription from Float32Array audio data
- Archive-based model loading (matching iOS/Android SDK approach)

### Text-to-Speech (TTS)
- Public Swift-shaped TTS facade; real browser synthesis is blocked until ONNX/Sherpa/Piper WASM archives are linked
- Multiple voice models with configurable parameters
- PCM audio output (Float32Array) with sample rate metadata

### Voice Activity Detection (VAD)
- Public Swift-shaped model-backed VAD facade; real Silero browser inference is blocked until ONNX/Sherpa WASM archives are linked
- Real-time speech/silence detection from audio streams
- Speech segment extraction with configurable thresholds
- Callback-based speech activity events

### Vision Language Models (VLM)
- Multimodal inference via llama.cpp with mtmd support
- Accepts RGB pixel data, base64, or file paths
- Loads through the shared C++ lifecycle with primary GGUF plus mmproj sidecar metadata
- Supports Qwen2-VL and other VLM architectures

### Voice Pipeline
- Public VoiceAgent facade for VAD -> STT -> LLM -> TTS orchestration; full browser runtime is blocked until speech backends are linked
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
- Structured logging via `RunAnywhere.logging`
- Event system via `RunAnywhere.events` for model lifecycle and SDK events

---

## System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **Browser** | Chrome 96+ / Edge 96+ | Chrome 120+ / Edge 120+ |
| **WebAssembly** | Required | Required |
| **SharedArrayBuffer** | For multi-threaded WASM | Requires Cross-Origin Isolation headers |
| **WebGPU + JSPI** | For GPU-accelerated llama.cpp/VLM paths | Chrome/Edge with `WebAssembly.promising` and `WebAssembly.Suspending` |
| **OPFS** | For persistent model storage | All modern browsers |
| **RAM** | 2GB | 4GB+ for larger models |
| **Storage** | Variable | Models: 40MB -- 4GB depending on model |

---

## Package Structure

The Web SDK is split into three npm packages so you only ship the backends you need:

| Package | Description | Includes |
|---------|-------------|----------|
| [`@runanywhere/web`](https://www.npmjs.com/package/@runanywhere/web) | Core SDK — lifecycle, logging, events, model management, storage | TypeScript only (no WASM) |
| [`@runanywhere/web-llamacpp`](https://www.npmjs.com/package/@runanywhere/web-llamacpp) | LLM, VLM, tool calling, structured output | llama.cpp RACommons WASM CPU/WebGPU artifacts |
| [`@runanywhere/web-onnx`](https://www.npmjs.com/package/@runanywhere/web-onnx) | STT, TTS, VAD registration shell | Requires ONNX/Sherpa RACommons WASM artifacts that are not vendored yet |

Install only what you need — `@runanywhere/web` is always required as the core.

---

## Installation

```bash
# Core + all backends
npm install @runanywhere/web @runanywhere/web-llamacpp @runanywhere/web-onnx

# LLM/VLM only (no speech)
npm install @runanywhere/web @runanywhere/web-llamacpp

# Speech only (no LLM)
npm install @runanywhere/web @runanywhere/web-onnx
```

### Serve WASM Files + Cross-Origin Isolation

WASM files are included in `@runanywhere/web-llamacpp`. `@runanywhere/web-onnx` registers against the same unified RACommons module once ONNX/Sherpa WASM archives are linked. Configure your bundler to serve backend WASM assets as static files.

> **Important:** Your server **must** set Cross-Origin Isolation headers for `SharedArrayBuffer` and multi-threaded WASM to work. Without these headers the SDK falls back to single-threaded mode, which is significantly slower. See [Cross-Origin Isolation Headers](#cross-origin-isolation-headers) for all platforms (Nginx, Vercel, Netlify, Cloudflare, AWS, Apache).

**Vite:**

```typescript
// vite.config.ts
export default defineConfig({
  assetsInclude: ['**/*.wasm'],
  server: {
    headers: {
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'credentialless',
    },
  },
  worker: { format: 'es' },
  optimizeDeps: {
    exclude: ['@runanywhere/web-llamacpp', '@runanywhere/web-onnx'],
  },
});
```

> **Warning (Vite users):** You **must** add `@runanywhere/web-llamacpp` and `@runanywhere/web-onnx` to `optimizeDeps.exclude`. Vite's dependency pre-bundling flattens packages into `.vite/deps/`, which breaks the relative `import.meta.url` paths the SDK uses to locate its WASM files. Without this exclusion, WASM loading will fail with a "Failed to fetch dynamically imported module" error. This is a known Vite limitation with npm packages that resolve static assets via `import.meta.url`.

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
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'credentialless',
    },
  },
};
```

> **Safari/iOS:** Safari does not support `credentialless` COEP. Use the COI service worker pattern shown in the [demo app](../../examples/web/RunAnywhereAI/) — it intercepts responses and injects `require-corp` headers at runtime.

---

## Quick Start

### 1. Initialize the SDK

```typescript
import { RunAnywhere, SDKEnvironment } from '@runanywhere/web';
import { LlamaCPP } from '@runanywhere/web-llamacpp';

await RunAnywhere.initialize({
  environment: SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
  debug: true,
});
await LlamaCPP.register();
// ONNX.register() is currently a shell until ONNX/Sherpa WASM archives are vendored.
```

### 2. Text Generation (LLM)

```typescript
await RunAnywhere.modelRegistry.registerModel({
  id: 'qwen2.5-0.5b',
  name: 'Qwen 2.5 0.5B',
  localPath: '/models/qwen2.5-0.5b-instruct-q4_0.gguf',
});
await RunAnywhere.loadModel({ modelId: 'qwen2.5-0.5b' });

const result = await RunAnywhere.generate({
  prompt: 'Explain quantum computing briefly.',
});
console.log(result.text);

const stream = await RunAnywhere.generateStream({
  prompt: 'Write a haiku about code.',
});
for await (const token of stream.stream) {
  process.stdout.write(token);
}
```

### 3. Speech-to-Text (STT)

```typescript
// Blocked in current artifacts: requires ONNX/Sherpa WASM static archives.
const result = await RunAnywhere.transcribe(audioFloat32Array, { sampleRate: 16000 });
console.log(result.text);
```

### 4. Text-to-Speech (TTS)

```typescript
// Blocked in current artifacts: requires ONNX/Sherpa/Piper WASM static archives.
const result = await RunAnywhere.synthesize('Hello from RunAnywhere!');
console.log(result.sampleRate, result.audioData.length);
```

### 5. Voice Activity Detection (VAD)

```typescript
// Blocked in current artifacts: model-backed Silero VAD requires ONNX/Sherpa WASM.
const result = await RunAnywhere.detectVoiceActivity(audioChunk, { sampleRate: 16000 });
console.log(result.isSpeech);
```

### 6. Vision Language Model (VLM)

```typescript
import { VLMImageFormat, VLMModelFamily } from '@runanywhere/web';

await RunAnywhere.modelRegistry.registerModel(smolVLM2ModelInfo);
await RunAnywhere.downloadModel({ modelId: 'smolvlm2-256m-video-instruct-q8_0' });
await RunAnywhere.loadModel({ modelId: 'smolvlm2-256m-video-instruct-q8_0' });
await RunAnywhere.visionLanguage.loadCurrentModel();

const result = await RunAnywhere.processImage(
  { format: VLMImageFormat.VLM_IMAGE_FORMAT_RAW_RGB, rawRgb: pixelData, width: 256, height: 256 },
  {
    prompt: 'Describe this image.',
    maxTokens: 100,
    temperature: 0.2,
    topP: 1,
    topK: 40,
    stopSequences: [],
    streamingEnabled: false,
    maxImageSize: 512,
    nThreads: 4,
    useGpu: true,
    modelFamily: VLMModelFamily.VLM_MODEL_FAMILY_QWEN2_VL,
    seed: 0,
    repetitionPenalty: 1,
    minP: 0,
    emitImageEmbeddings: false,
  },
);
console.log(result.text);
```

Current VLM validation status: Chrome/WebGPU loads SmolVLM2 and mmproj, then times out in CLIP image encoding before token decode. Treat real VLM inference as `BLOCKED` until that path returns text in browser E2E.

---

## Architecture

```
+---------------------------------------------+
|  TypeScript API                              |
|  RunAnywhere facade + namespaced APIs       |
|  textGeneration / stt / tts / vad / vlm     |
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

The Web SDK compiles the **same C++ core** (`runanywhere-commons`) used by the iOS and Android SDKs to WebAssembly via Emscripten. The llama.cpp LLM/VLM path is present in the current artifacts. The ONNX/Sherpa speech path is still gated by missing Web static archives and must not be claimed as runtime-ready until those archives are linked and exports are verified.

### Key Components

| Layer | Component | Description |
|-------|-----------|-------------|
| **Public** | `RunAnywhere` | Swift-shaped SDK lifecycle and namespace facade |
| **Public** | `RunAnywhere.textGeneration` | LLM text generation and streaming |
| **Public** | `RunAnywhere.stt` | Speech-to-text component lifecycle and transcription |
| **Public** | `RunAnywhere.tts` | Text-to-speech component lifecycle and synthesis |
| **Public** | `RunAnywhere.vad` | Voice activity detection component lifecycle and processing |
| **Public** | `RunAnywhere.visionLanguage` | Vision-language model inference |
| **Public** | `RunAnywhere.modelRegistry` | C++ model registry proto bridge |
| **Public** | `RunAnywhere.modelLifecycle` | C++ model lifecycle proto bridge |
| **Public** | `RunAnywhere.downloads` | C++ download workflow proto bridge |
| **Public** | `RunAnywhere.storage` | Browser storage helpers plus native storage analyzer bridge |
| **Internal** | `@runanywhere/web/internal` | Backend-only WASM, adapter, logging, and provider hooks |
| **Browser** | `@runanywhere/web/browser` | Audio/video capture, playback, file loading, and capability helpers |

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
|       |   |       +-- RunAnywhere+VisionLanguage.ts
|       |   |       +-- RunAnywhere+VoiceAgent.ts
|       |   |       +-- RunAnywhere+ToolCalling.ts
|       |   |       +-- RunAnywhere+StructuredOutput.ts
|       |   |       +-- RunAnywhere+ModelRegistry.ts
|       |   |       +-- RunAnywhere+ModelLifecycle.ts
|       |   |       +-- RunAnywhere+Storage.ts
|       |   |       +-- RunAnywhere+PluginLoader.ts
|       |   +-- Adapters/            # Proto-byte C ABI adapters
|       |   +-- runtime/             # Emscripten module singleton + proto bridge
|       |   +-- Foundation/         # Core infrastructure
|       |   |   +-- EventBus.ts
|       |   |   +-- SDKLogger.ts
|       |   +-- Infrastructure/     # Browser services
|       |   |   +-- AudioCapture.ts
|       |   |   +-- AudioPlayback.ts
|       |   |   +-- VideoCapture.ts
|       |   |   +-- DeviceCapabilities.ts
|       |   +-- types/              # Proto re-exports + Web-only I/O types
|       +-- tests/                  # Unit and type tests, outside SDK source
|       +-- dist/                   # TypeScript build output (generated)
|   +-- llamacpp/                   # @runanywhere/web-llamacpp backend shell
|   +-- onnx/                       # @runanywhere/web-onnx backend shell
+-- wasm/                           # Emscripten build system
|   +-- CMakeLists.txt
|   +-- src/wasm_exports.cpp
|   +-- platform/wasm_platform_shims.cpp
|   +-- scripts/
|       +-- build.sh                # Main WASM build script
|       +-- setup-emsdk.sh          # Emscripten SDK installer
|       +-- build.sh                # Unified RACommons WASM build
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
./wasm/scripts/build.sh --onnx              # Requires ONNX/Sherpa WASM static archives first
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
import { detectCapabilities } from '@runanywhere/web/browser';

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

Configure logging through the public `RunAnywhere.logging` namespace:

```typescript
import { RunAnywhere, LogLevel } from '@runanywhere/web';

RunAnywhere.logging.setLevel(LogLevel.Debug);
RunAnywhere.logging.setEnabled(true);
```

### Events

Subscribe to SDK lifecycle events:

```typescript
RunAnywhere.events.on('model.downloadProgress', (event) => {
  console.log(`Download: ${(event.progress * 100).toFixed(0)}%`);
});

RunAnywhere.events.on('model.loadCompleted', (event) => {
  console.log(`Model loaded: ${event.modelId}`);
});
```

---

## Error Handling

The SDK uses typed errors with error codes:

```typescript
import { SDKException, SDKErrorCode } from '@runanywhere/web';

try {
  await RunAnywhere.generate({ prompt: 'Hello' });
} catch (err) {
  if (err instanceof SDKException) {
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

## npm Packages

### `@runanywhere/web`

| Export | Description |
|--------|-------------|
| `RunAnywhere` | SDK lifecycle and Swift-shaped namespaces (`textGeneration`, `stt`, `tts`, `vad`, `voiceAgent`, `visionLanguage`, `modelRegistry`, `modelLifecycle`, `downloads`, `storage`, `pluginLoader`) |
| `LogLevel` | Public logging level enum for `RunAnywhere.logging` |
| `SDKException`, `SDKErrorCode`, `isSDKException` | Typed error hierarchy |
| Proto-derived types/enums | `SDKEnvironment`, `InferenceFramework`, `ModelCategory`, `VLMImageFormat`, `ToolDefinition`, `DownloadProgress`, and related generated types |
| `@runanywhere/web/browser` | Browser helpers: `AudioCapture`, `AudioPlayback`, `AudioFileLoader`, `VideoCapture`, `detectCapabilities`, `getDeviceInfo` |
| `@runanywhere/web/internal` | Backend-only adapter/runtime hooks, not an application API |

### `@runanywhere/web-llamacpp`

| Export | Description |
|--------|-------------|
| `LlamaCPP` | Registers the llama.cpp LLM/VLM RACommons WASM backend |
| `LifecycleVLMProvider` | Backend provider used by `RunAnywhere.processImage` after `RunAnywhere.loadModel` |

### `@runanywhere/web-onnx`

| Export | Description |
|--------|-------------|
| `ONNX` | Registers the ONNX/sherpa RACommons WASM backend for `RunAnywhere.stt`, `RunAnywhere.tts`, and `RunAnywhere.vad` |

---

## FAQ

### Does this work offline?

Yes. Once models are downloaded and cached in OPFS, the SDK works entirely offline. No server, API key, or network connection is needed for inference.

### Where are models stored?

Models are stored in the browser's Origin Private File System (OPFS), a sandboxed persistent storage API. Files persist across browser sessions but are origin-scoped and not accessible via the regular file system. If OPFS quota is exceeded, the SDK falls back to an in-memory cache for the current session.

### How large are the WASM files?

The Web SDK ships unified RACommons WASM artifacts from the backend packages. LLM/VLM and STT/TTS/VAD support are selected at build time with `npm run build:wasm -- --llamacpp --onnx --vlm --webgpu` and cached by the browser after download.

### Is my data private?

Yes. All inference runs entirely in the browser via WebAssembly. No data is sent to any server. Audio, text, and images never leave the device.

### Which browsers are supported?

Chrome 96+ and Edge 96+ are fully supported. Firefox 119+ works but lacks WebGPU. Safari 17+ has basic support but limited OPFS reliability. Mobile browsers have memory constraints that limit larger models.

### Can I use a custom model?

Yes for the current LLM/VLM path: GGUF-format models compatible with llama.cpp can work when memory and browser capabilities allow. STT/TTS/VAD model formats remain ONNX/Piper/Silero, but Web runtime support is blocked until ONNX/Sherpa WASM archives are linked.

---

## Troubleshooting

### "Failed to fetch dynamically imported module" / WASM not loading (Vite)

**Cause:** Vite pre-bundles npm dependencies into `.vite/deps/`, which breaks the relative `import.meta.url` paths used by `@runanywhere/web-llamacpp` and `@runanywhere/web-onnx` to locate their WASM files.

**Fix:** Add both packages to `optimizeDeps.exclude` in your `vite.config.ts`:

```typescript
optimizeDeps: {
  exclude: ['@runanywhere/web-llamacpp', '@runanywhere/web-onnx'],
},
```

### "SharedArrayBuffer is not defined"

**Cause:** Missing Cross-Origin Isolation headers.

**Fix:** Add the required headers to your server configuration. See [Cross-Origin Isolation Headers](#cross-origin-isolation-headers). The SDK will fall back to single-threaded mode if headers are missing.

### "Model failed to load"

**Cause:** CORS error, wrong file path, or corrupted download.

**Fix:** Ensure the model URL has proper CORS headers or serve from the same origin. Check the browser console for network errors. Try deleting the model from OPFS storage and re-downloading.

### "Out of memory" / tab crashes

**Cause:** Model too large for available browser memory.

**Fix:** Use smaller quantized models (Q4_0 instead of Q8_0). Close other browser tabs. On mobile, models larger than 1 GB may exceed available memory.

### VLM inference times out during image encoding

**Cause:** Current Chrome/WebGPU validation reaches CLIP `encoding image slice...` after prompt preparation and does not return before the 60s E2E timeout.

**Fix:** Treat VLM real inference as blocked until the WebGPU CLIP image-encoding path is fixed. Use smaller capture dimensions while debugging and keep Playwright traces from `RA_RUN_VLM_E2E=1 npm run test:browser -- tests/browser/vlm-generate.spec.ts --trace on`.

### OPFS storage not persisting

**Cause:** Browser may evict storage under memory pressure, or Incognito mode.

**Fix:** The SDK requests persistent storage automatically. Ensure you are not in Incognito/Private mode. Safari has known OPFS reliability issues.

---

## Known Limitations (Beta)

- Core unit/type tests, package build checks, browser smoke tests, and LLM browser E2E are covered by the Web validation workflow.
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
