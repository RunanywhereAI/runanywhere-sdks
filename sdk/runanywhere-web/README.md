# RunAnywhere Web SDK

On-device AI inference in the browser, powered by WebAssembly.

The Web SDK compiles the same C++ core (`runanywhere-commons`) used by the iOS and Android SDKs to WebAssembly via Emscripten. This means the **exact same inference engines** (llama.cpp, whisper.cpp, sherpa-onnx) run in the browser with the same vtable dispatch, service registry, and event system.

## Features

| Capability | Backend | Status |
|-----------|---------|--------|
| **LLM** (text generation) | llama.cpp → WASM | Ready |
| **STT** (speech-to-text) | whisper.cpp → WASM | Ready |
| **TTS** (text-to-speech) | sherpa-onnx → WASM | Ready |
| **VAD** (voice activity) | energy-based + Silero → WASM | Ready |
| **VLM** (vision-language) | llama.cpp mtmd → WASM | Ready |
| **Structured Output** | JSON extraction/validation | Ready |
| **Voice Agent** | VAD→STT→LLM→TTS pipeline | Ready |
| **Diffusion** | ONNX Runtime Web (WebGPU) | Scaffold |

## Quick Start

```typescript
import { RunAnywhere, TextGeneration, STT, TTS, VAD, VLM } from '@runanywhere/web';

// Initialize
await RunAnywhere.initialize({ debug: true });

// Text generation
await TextGeneration.loadModel('/models/llama-3.2-1b-q4.gguf', 'llama-3.2-1b');
const result = await TextGeneration.generate('Explain quantum computing');
console.log(result.text);

// Speech-to-text
await STT.loadModel('/models/whisper-base.bin', 'whisper-base');
const transcription = await STT.transcribe(audioFloat32Array);
console.log(transcription.text);

// Text-to-speech
await TTS.loadVoice('/models/piper-en.onnx', 'piper-en');
const audio = await TTS.synthesize('Hello, world!');
// audio.audioData is Float32Array of PCM samples

// Voice activity detection
await VAD.initialize({ energyThreshold: 0.02 });
const isSpeech = VAD.processSamples(audioChunk);

// Vision-language model
await VLM.loadModel('/models/qwen2-vl.gguf', '/models/mmproj.gguf', 'qwen2-vl');
const description = await VLM.process(
  { format: VLMImageFormat.Base64, base64Data: imageBase64 },
  'Describe this image',
);
```

## Architecture

```
┌─────────────────────────────────────────────┐
│  TypeScript API                              │
│  RunAnywhere / TextGeneration / STT / TTS   │
├─────────────────────────────────────────────┤
│  WASMBridge + PlatformAdapter               │
│  (Emscripten addFunction / ccall / cwrap)   │
├─────────────────────────────────────────────┤
│  RACommons C++ (compiled to WASM)           │
│  • Service Registry  • Event System         │
│  • Model Management  • Lifecycle            │
├─────────────────────────────────────────────┤
│  Inference Backends (WASM)                  │
│  • llama.cpp (LLM/VLM)                     │
│  • whisper.cpp (STT)                        │
│  • sherpa-onnx (TTS/VAD)                   │
└─────────────────────────────────────────────┘
```

## Project Structure

```
sdk/runanywhere-web/
├── packages/
│   └── core/                     # @runanywhere/web npm package
│       ├── src/
│       │   ├── Public/           # Public API
│       │   │   ├── RunAnywhere.ts
│       │   │   └── Extensions/
│       │   │       ├── RunAnywhere+TextGeneration.ts
│       │   │       ├── RunAnywhere+STT.ts
│       │   │       ├── RunAnywhere+TTS.ts
│       │   │       ├── RunAnywhere+VAD.ts
│       │   │       ├── RunAnywhere+VLM.ts
│       │   │       ├── RunAnywhere+VoiceAgent.ts
│       │   │       ├── RunAnywhere+StructuredOutput.ts
│       │   │       ├── RunAnywhere+Diffusion.ts
│       │   │       └── RunAnywhere+ModelManagement.ts
│       │   ├── Foundation/       # Core infrastructure
│       │   │   ├── WASMBridge.ts
│       │   │   ├── PlatformAdapter.ts
│       │   │   ├── EventBus.ts
│       │   │   ├── SDKLogger.ts
│       │   │   └── ErrorTypes.ts
│       │   ├── Infrastructure/   # Browser services
│       │   │   ├── AudioCapture.ts
│       │   │   ├── AudioPlayback.ts
│       │   │   ├── OPFSStorage.ts
│       │   │   └── DeviceCapabilities.ts
│       │   └── types/            # Shared type definitions
│       ├── wasm/                 # WASM build output (generated)
│       └── dist/                 # TypeScript build output (generated)
├── wasm/                         # Emscripten build system
│   ├── CMakeLists.txt
│   ├── src/wasm_exports.cpp
│   ├── platform/wasm_platform_shims.cpp
│   └── scripts/
│       ├── build.sh
│       └── setup-emsdk.sh
├── package.json                  # Workspace root
└── tsconfig.base.json
```

## Building

### Prerequisites

- [Emscripten SDK](https://emscripten.org/docs/getting_started/downloads.html) (v3.1.51+)
- Node.js 18+
- CMake 3.22+

### Setup Emscripten

```bash
./wasm/scripts/setup-emsdk.sh
source <emsdk-path>/emsdk_env.sh
```

### Build WASM Module

```bash
# Core only (no inference backends)
./wasm/scripts/build.sh

# With llama.cpp for LLM
./wasm/scripts/build.sh --llamacpp

# With whisper.cpp for STT
./wasm/scripts/build.sh --whispercpp

# With sherpa-onnx for TTS/VAD
./wasm/scripts/build.sh --onnx

# All backends
./wasm/scripts/build.sh --all-backends

# Debug build with pthreads
./wasm/scripts/build.sh --debug --pthreads --all-backends
```

### Build TypeScript

```bash
npm install
npm run build:ts
```

### Typecheck

```bash
cd packages/core && npx tsc --noEmit
```

## Browser Requirements

| Feature | Required | Fallback |
|---------|----------|----------|
| WebAssembly | Yes | N/A |
| SharedArrayBuffer | For pthreads | Single-threaded mode |
| Cross-Origin Isolation | For pthreads | Disable pthreads |
| WebGPU | For Diffusion | N/A (Diffusion unavailable) |
| OPFS | For persistent storage | MEMFS (volatile) |
| Web Audio API | For mic/speaker | N/A |

### Cross-Origin Isolation Headers

For pthreads (multi-threaded WASM), your server must send:

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

## Demo App

See `examples/web/RunAnywhereAI/` for a Vite-based demo app with capability detection.

```bash
cd examples/web/RunAnywhereAI
npm install
npm run dev
```

## npm Package

```
@runanywhere/web
```

Published exports:
- `RunAnywhere` - SDK lifecycle
- `TextGeneration` - LLM text generation
- `STT` - Speech-to-text
- `TTS` - Text-to-speech
- `VAD` - Voice activity detection
- `VLM` - Vision-language models
- `VoiceAgent` - Full voice pipeline
- `StructuredOutput` - JSON schema-guided generation
- `Diffusion` - Image generation (WebGPU)
- `ModelManagement` - Model download/storage
- `AudioCapture` / `AudioPlayback` - Browser audio
- `OPFSStorage` - Persistent model storage
- `detectCapabilities` - Browser feature detection
