# RunAnywhere React Native SDK

On-device AI for React Native. Run LLMs, Speech-to-Text, Text-to-Speech, and Voice AI locally with privacy-first, offline-capable inference.

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/React%20Native-0.74+-61DAFB?style=flat-square&logo=react&logoColor=white" alt="React Native 0.74+" /></a>
  <a href="#"><img src="https://img.shields.io/badge/iOS-17.0+-000000?style=flat-square&logo=apple&logoColor=white" alt="iOS 17.0+" /></a>
  <a href="#"><img src="https://img.shields.io/badge/Android-7.0+-3DDC84?style=flat-square&logo=android&logoColor=white" alt="Android 7.0+" /></a>
  <a href="#"><img src="https://img.shields.io/badge/TypeScript-5.2+-3178C6?style=flat-square&logo=typescript&logoColor=white" alt="TypeScript 5.2+" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue?style=flat-square" alt="License" /></a>
</p>

---

## Quick Links

- [Architecture Overview](#architecture-overview)
- [Quick Start](#quick-start)
- [API Reference](Docs/Documentation.md)
- [Sample App](../../examples/react-native/RunAnywhereAI/)
- [FAQ](#faq)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

---

## Features

### Large Language Models (LLM)
- On-device text generation with streaming support
- **LlamaCPP** backend for GGUF models (Llama 2, Mistral, SmolLM, Qwen, etc.)
- Metal GPU acceleration on iOS, CPU + NNAPI on Android
- System prompts and customizable generation parameters
- Support for thinking/reasoning models
- Token streaming with real-time callbacks

### Speech-to-Text (STT)
- Real-time and batch audio transcription
- Multi-language support with Whisper models via ONNX Runtime
- Word-level timestamps and confidence scores
- Voice Activity Detection (VAD) integration

### Text-to-Speech (TTS)
- Neural voice synthesis with Piper TTS
- System voices via platform TTS (AVSpeechSynthesizer / Android TTS)
- Streaming audio generation for long text
- Customizable voice, pitch, rate, and volume

### Voice Activity Detection (VAD)
- Energy-based speech detection with Silero VAD
- Configurable sensitivity thresholds
- Real-time audio stream processing

### Voice Agent Pipeline
- Full VAD → STT → LLM → TTS orchestration
- Complete voice conversation flow
- Push-to-talk and hands-free modes

### Infrastructure
- Native model registry, download, and lifecycle APIs with progress tracking
- Proto-byte SDK event stream decoded by the TypeScript facade
- Built-in analytics and telemetry
- Structured logging with multiple log levels
- Keychain-persisted device identity (iOS) / EncryptedSharedPreferences (Android)

---

## System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **React Native** | 0.71+ | 0.74+ |
| **iOS** | 17.0+ | 17.0+ |
| **Android** | API 24 (7.0+) | API 28+ |
| **Node.js** | 18+ | 20+ |
| **Xcode** | 15+ | 16+ |
| **Android Studio** | Hedgehog+ | Latest |
| **RAM** | 3GB | 6GB+ for 7B models |
| **Storage** | Variable | Models: 200MB–8GB |

Apple Silicon devices (M1/M2/M3, A14+) and Android devices with 6GB+ RAM are recommended. Metal GPU acceleration provides 3-5x speedup on iOS.

---

## Multi-Package Architecture

This SDK uses a modular multi-package architecture. Install only the packages you need:

| Package | Description | Required |
|---------|-------------|----------|
| `@runanywhere/core` | Core SDK facade, native lifecycle/event/model APIs, proto types | Yes |
| `@runanywhere/llamacpp` | LlamaCPP backend for LLM text generation (GGUF models) | For LLM |
| `@runanywhere/onnx` | ONNX Runtime backend for STT/TTS (Whisper, Piper) | For Voice |

---

## Installation

### Full Installation (All Features)

```bash
npm install @runanywhere/core @runanywhere/llamacpp @runanywhere/onnx
# or
yarn add @runanywhere/core @runanywhere/llamacpp @runanywhere/onnx
```

### Minimal Installation (LLM Only)

```bash
npm install @runanywhere/core @runanywhere/llamacpp
```

### Minimal Installation (STT/TTS Only)

```bash
npm install @runanywhere/core @runanywhere/onnx
```

### iOS Setup

```bash
cd ios && pod install && cd ..
```

### Android Setup

No additional setup required. Native libraries are automatically downloaded during the Gradle build.

---

## Quick Start

### 1. Initialize the SDK

```typescript
import {
  RunAnywhere,
  SDKEnvironment,
} from '@runanywhere/core';
import {
  CurrentModelRequest,
  ModelCategory,
  InferenceFramework,
  ModelArtifactType,
  ModelLoadRequest,
  ModelUnloadRequest,
  AudioFormat,
} from '@runanywhere/proto-ts/model_types';
import { STTLanguage } from '@runanywhere/proto-ts/stt_options';
import { LlamaCPP } from '@runanywhere/llamacpp';
import { ONNX } from '@runanywhere/onnx';

// Initialize SDK (development mode - no API key needed)
await RunAnywhere.initialize({
  environment: SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
});

async function drainModelDownload(modelId: string): Promise<void> {
  const iterator = RunAnywhere.downloadModel(modelId)[Symbol.asyncIterator]();
  let next = await iterator.next();
  while (!next.done) {
    const progress = next.value;
    console.log(`${modelId}: ${(progress.progress * 100).toFixed(1)}%`);
    next = await iterator.next();
  }
}

// Register LlamaCpp module and add LLM models. `register()` is async and
// returns `Promise<boolean>` — `false` means the native backend was not
// installed, so don't register Llama-backed models in that case.
const llamaRegistered = await LlamaCPP.register();
if (llamaRegistered) {
  await RunAnywhere.registerModel({
    id: 'smollm2-360m-q8_0',
    name: 'SmolLM2 360M Q8_0',
    url: 'https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf',
    framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
    memoryRequirement: 500_000_000,
  });
}

// Register ONNX module and add STT/TTS models. ONNX.register() is also async
// and returns `Promise<boolean>` — `false` means the native backend was not
// installed, so don't register Sherpa-backed models in that case.
const onnxRegistered = await ONNX.register();
if (onnxRegistered) {
  await RunAnywhere.registerModel({
    id: 'sherpa-onnx-whisper-tiny.en',
    name: 'Sherpa Whisper Tiny (ONNX)',
    url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz',
    framework: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
    modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
    artifactType: ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE,
    memoryRequirement: 75_000_000,
  });
}

console.log('SDK initialized');
```

### 2. Download & Load a Model

```typescript
// Download model with progress tracking
await drainModelDownload('smollm2-360m-q8_0');

// Load model into memory
const loadResult = await RunAnywhere.loadModel(ModelLoadRequest.fromPartial({
  modelId: 'smollm2-360m-q8_0',
  category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
}));
if (!loadResult.success) {
  throw new Error(loadResult.errorMessage || 'Model load failed');
}

// Check lifecycle state through the Swift-shaped currentModel API
const currentModel = await RunAnywhere.currentModel(
  CurrentModelRequest.fromPartial({
    category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    includeModelMetadata: false,
  })
);
const isLoaded = currentModel.found && currentModel.modelId.length > 0;
console.log('Model loaded:', isLoaded);
```

### 3. Generate Text

```typescript
const result = await RunAnywhere.generate(
  'Explain quantum computing in simple terms',
  {
    maxTokens: 200,
    temperature: 0.7,
    systemPrompt: 'You are a helpful assistant.',
  }
);

console.log('Response:', result.text);
console.log('Speed:', result.performanceMetrics.tokensPerSecond, 'tok/s');
console.log('Latency:', result.latencyMs, 'ms');
```

### 4. Streaming Generation

> Hermes caveat: `for await...of` does not work with NitroModules async iterables.
> Use the manual-iterator pattern below. See [Hermes streaming](#hermes-streaming)
> for details.

```typescript
const streamResult = await RunAnywhere.generateStream(
  'Write a short poem about AI',
  { maxTokens: 150 }
);

// Display tokens in real-time (manual iterator — Hermes-safe)
const iterator = streamResult.stream[Symbol.asyncIterator]();
while (true) {
  const { value, done } = await iterator.next();
  if (done) break;
  process.stdout.write(value);
}

// Get final metrics
const metrics = await streamResult.result;
console.log('\nSpeed:', metrics.performanceMetrics.tokensPerSecond, 'tok/s');
```

### 5. Speech-to-Text

```typescript
// Download and load STT model
await drainModelDownload('sherpa-onnx-whisper-tiny.en');
await RunAnywhere.loadModel(ModelLoadRequest.fromPartial({
  modelId: 'sherpa-onnx-whisper-tiny.en',
  category: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
}));

// Transcribe PCM/base64 audio bytes. Host apps own file reading.
const audioBase64 = await readAudioFileAsBase64(audioFilePath);
const result = await RunAnywhere.transcribe(audioBase64, {
  language: STTLanguage.STT_LANGUAGE_EN,
  audioFormat: AudioFormat.AUDIO_FORMAT_PCM,
  sampleRate: 16000,
});

console.log('Transcription:', result.text);
console.log('Confidence:', result.confidence);
```

### 6. Text-to-Speech

```typescript
// Download and load TTS model
await drainModelDownload('vits-piper-en_US-lessac-medium');
await RunAnywhere.loadModel(ModelLoadRequest.fromPartial({
  modelId: 'vits-piper-en_US-lessac-medium',
  category: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
}));

// Synthesize speech
const output = await RunAnywhere.synthesize(
  'Hello from the RunAnywhere SDK.',
  { rate: 1.0, pitch: 1.0, volume: 1.0 }
);

// output.audio contains base64-encoded float32 PCM
// output.sampleRate, output.numSamples, output.duration
```

---

## Hermes streaming

React Native's default JS engine (Hermes) does not support `for await...of`
with NitroModules-backed async iterables. Any SDK API that returns an
`AsyncIterable` must be consumed with a manual `Symbol.asyncIterator` loop:

```typescript
const stream = RunAnywhere.generateStream(prompt);
const iterator = stream[Symbol.asyncIterator]();
while (true) {
  const { value, done } = await iterator.next();
  if (done) break;
  // handle value
}
```

**Affected surfaces** (every public API that yields an `AsyncIterable`):

| Surface | Yields |
|---------|--------|
| `RunAnywhere.generateStream(prompt, options)` | `LLMStreamEvent` (`token`, `completed`, `failed`, ...) |
| `RunAnywhere.transcribe(audio, options)` / `transcribeStream(...)` | `STTStreamEvent` |
| `RunAnywhere.synthesize(text, options)` / `synthesizeStream(...)` | `TTSStreamEvent` (audio chunks) |
| `RunAnywhere.processImage(request)` | `VLMStreamEvent` (vision-language tokens) |
| `RunAnywhere.downloadModel(id, onProgress?)` (when used as an async iterable) | `DownloadProgress` |
| `RunAnywhere.voiceAgent.start(...)` | `VoiceEvent` |

`for await` only works on Node / JavaScriptCore on iOS when Hermes is disabled.
On Hermes-enabled apps (the default since RN 0.70), use the manual-iterator
pattern above or wrap it in a helper. Breaking from the loop with `break` or
`return` automatically cancels the native subscription.

---

## Architecture Overview

The RunAnywhere SDK follows a modular, provider-based architecture with a shared C++ core:

The iOS packaging and generated-code source of truth is
[`sdk/runanywhere-swift/ARCHITECTURE.md`](../runanywhere-swift/ARCHITECTURE.md),
especially the folder tree, generated proto code, and build/deployment
sections. React Native mirrors that native/proto-byte ownership instead of
owning model downloads, registry state, or native HTTP routing in JavaScript.

```
┌─────────────────────────────────────────────────────────────────┐
│                     Your React Native App                        │
├─────────────────────────────────────────────────────────────────┤
│              @runanywhere/core (TypeScript API)                  │
│  ┌──────────────┐  ┌───────────────┐  ┌──────────────────────┐  │
│  │ RunAnywhere  │  │ SDK Events    │  │ Native Model APIs    │  │
│  │ (public API) │  │ (proto bytes) │  │ (registry/download)  │  │
│  │              │  │               │  │                      │  │
│  └──────────────┘  └───────────────┘  └──────────────────────┘  │
├────────────┬─────────────────────────────────────┬──────────────┤
│            │                                     │              │
│  ┌─────────▼─────────┐             ┌────────────▼────────────┐ │
│  │ @runanywhere/     │             │  @runanywhere/onnx      │ │
│  │    llamacpp       │             │  (STT/TTS/VAD)          │ │
│  │  (LLM/GGUF)       │             │                         │ │
│  └─────────┬─────────┘             └────────────┬────────────┘ │
├────────────┼─────────────────────────────────────┼──────────────┤
│            │          Nitrogen/Nitro JSI         │              │
│            │          (Native Bridge Layer)      │              │
├────────────┼─────────────────────────────────────┼──────────────┤
│  ┌─────────▼──────────────────────────────────────▼───────────┐ │
│  │              runanywhere-commons (C++)                      │ │
│  │  ┌────────────────┐  ┌────────────────┐  ┌───────────────┐ │ │
│  │  │ RACommons      │  │ RABackend      │  │ ONNX + Sherpa │ │ │
│  │  │ (Core Engine)  │  │ LLAMACPP       │  │ backends      │ │ │
│  │  └────────────────┘  └────────────────┘  └───────────────┘ │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### Key Components

| Component | Description |
|-----------|-------------|
| **RunAnywhere** | Main SDK singleton providing all public methods |
| **SDK event stream** | Native proto-byte event stream for initialization, generation, model, and voice events |
| **Model lifecycle APIs** | TypeScript facade over native registry, download, import, delete, and load calls |
| **ServiceContainer** | Dependency injection for internal services |
| **Storage APIs** | Native storage and cache management exposed through `RunAnywhere` |
| **Proto adapters** | Generated protobuf types and byte adapters for cross-platform parity |

### Native Binaries

| Framework | Size | Provides |
|-----------|------|----------|
| `RACommons.xcframework` / `librac_commons.so` | package-owned | Core C++ commons, registry, storage, events, proto ABI |
| `RABackendLLAMACPP.xcframework` / `librac_backend_llamacpp.so` | package-owned | LLM/VLM backend registration for GGUF models |
| `RABackendONNX.xcframework` / `librac_backend_onnx.so` | package-owned | Generic ONNX backend binary |
| `RABackendSherpa.xcframework` / `librac_backend_sherpa.so` | package-owned | Sherpa-ONNX speech backend binary |

---

## Configuration

### SDK Initialization Parameters

```typescript
// Development mode (default) - no API key needed
await RunAnywhere.initialize({
  environment: SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
});

// Production mode - requires API key
await RunAnywhere.initialize({
  apiKey: '<YOUR_API_KEY>',
  baseURL: 'https://api.runanywhere.ai',
  environment: SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
});
```

### Environment Modes

| Environment | Description |
|-------------|-------------|
| `.Development` | Verbose logging, local backend, no auth required |
| `.Staging` | Testing with real services |
| `.Production` | Minimal logging, full authentication, telemetry |

### Generation Options

```typescript
const options: Partial<LLMGenerationOptions> = {
  maxTokens: 256,              // Maximum tokens to generate
  temperature: 0.7,            // Sampling temperature (0.0–2.0)
  topP: 0.95,                  // Top-p sampling parameter
  stopSequences: ['END'],      // Stop generation at these sequences
  systemPrompt: 'You are a helpful assistant.',
};
```

---

## Error Handling

The SDK provides structured error handling through `SDKException`:

```typescript
import { SDKException, ErrorCode, isSDKException } from '@runanywhere/core';

try {
  const response = await RunAnywhere.generate('Hello!');
} catch (error) {
  if (isSDKException(error)) {
    switch (error.code) {
      case ErrorCode.ERROR_CODE_NOT_INITIALIZED:
        console.log('SDK not initialized. Call RunAnywhere.initialize() first.');
        break;
      case ErrorCode.ERROR_CODE_MODEL_NOT_FOUND:
        console.log('Model not found. Download it first.');
        break;
      case ErrorCode.ERROR_CODE_INSUFFICIENT_MEMORY:
        console.log('Not enough memory. Try a smaller model.');
        break;
      default:
        console.log('Error:', error.message);
    }
  }
}
```

### Error Categories

| Category | Description |
|----------|-------------|
| `general` | General SDK errors |
| `llm` | LLM generation errors |
| `stt` | Speech-to-text errors |
| `tts` | Text-to-speech errors |
| `vad` | Voice activity detection errors |
| `voiceAgent` | Voice pipeline errors |
| `download` | Model download errors |
| `network` | Network-related errors |
| `authentication` | Auth and API key errors |

---

## Logging & Observability

### Configure Logging

The SDK ships its own structured logger. `SDKLogger` and `LogLevel` are part of
the internal subpath (`@runanywhere/core/internal`) and may change between
releases; for stable user code, prefer wiring console/your own logger and
subscribing to the EventBus stream below for observability.

```typescript
// Internal subpath — not part of the stable root surface.
import { LogLevel, SDKLogger } from '@runanywhere/core/internal';

// Set minimum log level
RunAnywhere.setLogLevel(LogLevel.Debug);  // debug, info, warning, error, fault

// Create a custom logger
const logger = new SDKLogger('MyApp');
logger.info('App started');
logger.debug('Debug info', { modelId: 'llama-2' });
```

### Subscribe to Events

```typescript
// Subscribe to generation events
const unsubscribe = RunAnywhere.events.onGeneration((event) => {
  switch (event.type) {
    case 'started':
      console.log('Generation started');
      break;
    case 'tokenGenerated':
      console.log('Token:', event.token);
      break;
    case 'completed':
      console.log('Done:', event.response.text);
      break;
    case 'failed':
      console.error('Error:', event.error);
      break;
  }
});

// Subscribe to model events
RunAnywhere.events.onModel((event) => {
  if (event.type === 'downloadProgress') {
    console.log(`Progress: ${(event.progress * 100).toFixed(1)}%`);
  }
});

// Unsubscribe when done
unsubscribe();
```

---

## Performance & Best Practices

### Model Selection

| Model Size | RAM Required | Use Case |
|------------|--------------|----------|
| 360M–500M (Q8) | ~500MB | Fast, lightweight chat |
| 1B–3B (Q4/Q6) | 1–2GB | Balanced quality/speed |
| 7B (Q4) | 4–5GB | High quality, slower |

### Memory Management

```typescript
// Unload models when not in use
await RunAnywhere.unloadModel(
  ModelUnloadRequest.fromPartial({
    category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    unloadAll: true,
  })
);

// Check storage before downloading
const storageInfo = await RunAnywhere.getStorageInfo();
if ((storageInfo?.device?.freeBytes ?? 0) > modelSize) {
  // Safe to download
}

// Clean up temporary files
await RunAnywhere.clearCache();
await RunAnywhere.cleanTempFiles();
```

### Best Practices

1. **Prefer streaming** for better perceived latency in chat UIs
2. **Unload unused models** to free device memory
3. **Handle errors gracefully** with user-friendly messages
4. **Test on target devices** — performance varies by hardware
5. **Use smaller models** for faster iteration during development
6. **Pre-download models** during onboarding for better UX

---

## Troubleshooting

### Model Download Fails

**Symptoms:** Download stuck or fails with network error

**Solutions:**
1. Check internet connection
2. Verify sufficient storage (need 2x model size for extraction)
3. Try on WiFi instead of cellular
4. Check if model URL is accessible

### Out of Memory

**Symptoms:** App crashes during model loading or inference

**Solutions:**
1. Use a smaller model (360M instead of 7B)
2. Unload unused models first with `RunAnywhere.unloadModel(ModelUnloadRequest.fromPartial(...))`
3. Close other memory-intensive apps
4. Test on device with more RAM

### Inference Too Slow

**Symptoms:** Generation takes 10+ seconds per token

**Solutions:**
1. Use Apple Silicon device for Metal acceleration (iOS)
2. Reduce `maxTokens` for shorter responses
3. Use quantized models (Q4 instead of Q8)
4. Check device thermal state

### Model Not Found After Download

**Symptoms:** `modelNotFound` error even though download completed

**Solutions:**
1. Refresh model registry: `await RunAnywhere.listModels()`
2. Check model path in storage
3. Delete and re-download the model

### Native Module Not Available

**Symptoms:** `Native module not available` error

**Solutions:**
1. Ensure `pod install` was run for iOS
2. Rebuild the app: `npx react-native run-ios` / `run-android`
3. Check that all packages are installed correctly
4. Reset Metro cache: `npx react-native start --reset-cache`

---

## FAQ

### Q: Do I need an internet connection?
**A:** Only for initial model download. Once downloaded, all inference runs 100% on-device with no network required.

### Q: How much storage do models need?
**A:** Varies by model:
- Small LLMs (360M–1B): 200MB–1GB
- Medium LLMs (3B–7B Q4): 2–5GB
- STT models: 50–200MB
- TTS voices: 20–100MB

### Q: Is user data sent to the cloud?
**A:** No. All inference happens on-device. Only anonymous analytics (latency, error rates) are collected in production mode, and this can be disabled.

### Q: Which devices are supported?
**A:** iOS 17.0+ (iPhone/iPad) and Android 7.0+ (API 24+). Modern devices with 6GB+ RAM are recommended for larger models.

### Q: Can I use custom models?
**A:** Yes, any GGUF model works with the LlamaCPP backend. ONNX models work for STT/TTS.

### Q: What's the difference between `chat()` and `generate()`?
**A:** `chat()` is a convenience method that returns just the text. `generate()` returns full metrics (tokens, latency, etc.).

---

## Local Development & Contributing

Contributions are welcome. This section explains how to set up your development environment to build the SDK from source and test your changes with the sample app.

### Prerequisites

- **Node.js** 18+
- **Xcode** 15+ (for iOS builds)
- **Android Studio** with NDK (for Android builds)
- **CMake** 3.21+

### First-Time Setup (Build from Source)

The SDK depends on native C++ libraries from `runanywhere-commons`. Native artifacts are built in the owning layer (`runanywhere-commons`) and then staged into each RN package by `scripts/package-sdk.sh`.

```bash
# 1. Clone the repository
git clone https://github.com/RunanywhereAI/runanywhere-sdks.git
cd runanywhere-sdks

# 2. Build native artifacts from runanywhere-commons (from repo root)
./sdk/runanywhere-swift/scripts/build-core-xcframework.sh   # iOS XCFrameworks → build/ios/
./scripts/build/build-core-android.sh       # Android .so files → build/android/

# 3. Stage the freshly built natives into the React Native packages
cd sdk/runanywhere-react-native
./scripts/package-sdk.sh --natives-from ../../build/native-artifacts

# 4. Install JavaScript dependencies (yarn workspaces)
yarn install
```

`package-sdk.sh --natives-from PATH` copies each binary into the package that owns it:
- `RACommons.xcframework` / `librac_commons.so` → `packages/core`
- `RABackendLLAMACPP.xcframework` / `librac_backend_llamacpp.so` → `packages/llamacpp`
- `RABackendONNX.xcframework` + `RABackendSherpa.xcframework` / matching `.so` files → `packages/onnx`

It then type-checks each package and produces `dist/sdk-rn/*.tgz` + `.sha256`.

**Per-package download alternative:** if you do not need to rebuild commons from source, each package exposes a download helper that pulls pre-built natives from a GitHub release into the right package directory:

```bash
# From sdk/runanywhere-react-native/
yarn core:download-ios          # or yarn core:download-android
yarn llamacpp:download-ios      # or yarn llamacpp:download-android
yarn onnx:download-ios          # or yarn onnx:download-android
```

### Understanding testLocal

The SDK has two native-binary consumption modes:

| Mode | Description |
|------|-------------|
| **Local** | Uses frameworks/JNI libs staged into package directories for development |
| **Packaged** | Published npm packages include package-owned natives; CocoaPods and Gradle consume them from the package directories |

Toggle local mode after staging natives:
- **iOS**: `yarn native:local` writes the `.testlocal` marker files in each package's `ios/` directory; `yarn native:remote` removes them.
- **Android**: set `RA_TEST_LOCAL=1` in your environment or `runanywhere.useLocalNatives=true` in `gradle.properties`.

### Testing with the React Native Sample App

The recommended way to test SDK changes is with the sample app:

```bash
# 1. Ensure SDK is set up (from previous step)

# 2. Navigate to the sample app
cd ../../examples/react-native/RunAnywhereAI

# 3. Install sample app dependencies
npm install

# 4. iOS: Install pods and run
cd ios && pod install && cd ..
npx react-native run-ios

# 5. Android: Run directly
npx react-native run-android
```

You can open the sample app in **VS Code** or **Cursor** for development.

The sample app's `package.json` uses workspace dependencies to reference the local SDK packages:

```
Sample App → Local RN SDK Packages → Local Frameworks/JNI libs
                                           ↑
                Staged by ./scripts/package-sdk.sh --natives-from PATH
```

### Development Workflow

**After modifying TypeScript SDK code:**

```bash
# Type check all packages
yarn typecheck

# Run ESLint
yarn lint

# Build all packages
yarn build
```

**After modifying runanywhere-commons (C++ code):**

```bash
# 1. Rebuild native artifacts in the owning layer (repo root)
./sdk/runanywhere-swift/scripts/build-core-xcframework.sh   # iOS
./scripts/build/build-core-android.sh       # Android

# 2. Re-stage them into the RN packages
cd sdk/runanywhere-react-native
./scripts/package-sdk.sh --natives-from ../../build/native-artifacts
```

### Packaging Reference

| Command | Description |
|---------|-------------|
| `./scripts/package-sdk.sh --natives-from PATH` | Stage iOS XCFrameworks + Android `.so` files from `PATH` into each owning package, type-check, and produce `dist/sdk-rn/*.tgz` + `.sha256` |
| `./scripts/package-sdk.sh --mode local\|ci` | Override packaging mode (default: auto-detect from `$CI`) |
| `yarn <core\|llamacpp\|onnx>:download-ios` | Download pre-built iOS natives from GitHub releases for that package |
| `yarn <core\|llamacpp\|onnx>:download-android` | Download pre-built Android `.so` files from GitHub releases for that package |
| `yarn native:local` / `yarn native:remote` | Toggle iOS `.testlocal` marker files for local-vs-published native consumption |

### Code Style

We use ESLint and Prettier for code formatting:

```bash
# Run linter
yarn lint

# Auto-fix linting issues
yarn lint:fix
```

### Pull Request Process

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes with tests
4. Ensure type checking passes: `yarn typecheck`
5. Run linter: `yarn lint`
6. Commit with a descriptive message
7. Push and open a Pull Request

### Reporting Issues

Open an issue on GitHub with:
- SDK version: `RunAnywhere.version`
- Platform (iOS/Android) and OS version
- Device model
- React Native version
- Steps to reproduce
- Expected vs actual behavior
- Relevant logs (with sensitive info redacted)

---

## Support

- **GitHub Issues**: [Report bugs](https://github.com/RunanywhereAI/runanywhere-sdks/issues)
- **Discord**: [Community](https://discord.gg/pxRkYmWh)
- **Email**: san@runanywhere.ai

---

## License

MIT License. See [LICENSE](../../LICENSE) for details.

---

## Related Documentation

- [API Reference](Docs/Documentation.md)
- [Sample App](../../examples/react-native/RunAnywhereAI/)
- [Swift SDK](../runanywhere-swift/)
- [Kotlin SDK](../runanywhere-kotlin/)
- [Flutter SDK](../runanywhere-flutter/)
