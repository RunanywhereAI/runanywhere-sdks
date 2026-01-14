# RunAnywhere React Native SDK

On-device AI for React Native. Run LLMs, Speech-to-Text, Text-to-Speech, and Voice AI locally with privacy-first, offline-capable inference.

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/React%20Native-0.74+-61DAFB?style=flat-square&logo=react&logoColor=white" alt="React Native 0.74+" /></a>
  <a href="#"><img src="https://img.shields.io/badge/iOS-15.1+-000000?style=flat-square&logo=apple&logoColor=white" alt="iOS 15.1+" /></a>
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
- Automatic model discovery and download with progress tracking
- Comprehensive event system via `EventBus`
- Built-in analytics and telemetry
- Structured logging with multiple log levels
- Keychain-persisted device identity (iOS) / EncryptedSharedPreferences (Android)

---

## System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **React Native** | 0.71+ | 0.74+ |
| **iOS** | 15.1+ | 17.0+ |
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
| `@runanywhere/core` | Core SDK infrastructure, public API, events, model registry | Yes |
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
import { RunAnywhere, SDKEnvironment, ModelCategory } from '@runanywhere/core';
import { LlamaCPP } from '@runanywhere/llamacpp';
import { ONNX, ModelArtifactType } from '@runanywhere/onnx';

// Initialize SDK (development mode - no API key needed)
await RunAnywhere.initialize({
  environment: SDKEnvironment.Development,
});

// Register LlamaCpp module and add LLM models
LlamaCPP.register();
await LlamaCPP.addModel({
  id: 'smollm2-360m-q8_0',
  name: 'SmolLM2 360M Q8_0',
  url: 'https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf',
  memoryRequirement: 500_000_000,
});

// Register ONNX module and add STT/TTS models
ONNX.register();
await ONNX.addModel({
  id: 'sherpa-onnx-whisper-tiny.en',
  name: 'Sherpa Whisper Tiny (ONNX)',
  url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz',
  modality: ModelCategory.SpeechRecognition,
  artifactType: ModelArtifactType.TarGzArchive,
  memoryRequirement: 75_000_000,
});

console.log('SDK initialized');
```

### 2. Download & Load a Model

```typescript
// Download model with progress tracking
await RunAnywhere.downloadModel('smollm2-360m-q8_0', (progress) => {
  console.log(`Download: ${(progress.progress * 100).toFixed(1)}%`);
});

// Load model into memory
const modelInfo = await RunAnywhere.getModelInfo('smollm2-360m-q8_0');
if (modelInfo?.localPath) {
  await RunAnywhere.loadModel(modelInfo.localPath);
}

// Check if model is loaded
const isLoaded = await RunAnywhere.isModelLoaded();
console.log('Model loaded:', isLoaded);
```

### 3. Generate Text

```typescript
// Simple chat
const response = await RunAnywhere.chat('What is the capital of France?');
console.log(response);  // "Paris is the capital of France."

// With options
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

```typescript
const streamResult = await RunAnywhere.generateStream(
  'Write a short poem about AI',
  { maxTokens: 150 }
);

// Display tokens in real-time
for await (const token of streamResult.stream) {
  process.stdout.write(token);
}

// Get final metrics
const metrics = await streamResult.result;
console.log('\nSpeed:', metrics.performanceMetrics.tokensPerSecond, 'tok/s');
```

### 5. Speech-to-Text

```typescript
// Download and load STT model
await RunAnywhere.downloadModel('sherpa-onnx-whisper-tiny.en');
const sttModel = await RunAnywhere.getModelInfo('sherpa-onnx-whisper-tiny.en');
await RunAnywhere.loadSTTModel(sttModel.localPath, 'whisper');

// Transcribe audio file
const result = await RunAnywhere.transcribeFile(audioFilePath, {
  language: 'en',
});

console.log('Transcription:', result.text);
console.log('Confidence:', result.confidence);
```

### 6. Text-to-Speech

```typescript
// Download and load TTS model
await RunAnywhere.downloadModel('vits-piper-en_US-lessac-medium');
const ttsModel = await RunAnywhere.getModelInfo('vits-piper-en_US-lessac-medium');
await RunAnywhere.loadTTSModel(ttsModel.localPath, 'piper');

// Synthesize speech
const output = await RunAnywhere.synthesize(
  'Hello from the RunAnywhere SDK.',
  { rate: 1.0, pitch: 1.0, volume: 1.0 }
);

// output.audio contains base64-encoded float32 PCM
// output.sampleRate, output.numSamples, output.duration
```

---

## Architecture Overview

The RunAnywhere SDK follows a modular, provider-based architecture with a shared C++ core:

```
┌─────────────────────────────────────────────────────────────────┐
│                     Your React Native App                        │
├─────────────────────────────────────────────────────────────────┤
│              @runanywhere/core (TypeScript API)                  │
│  ┌──────────────┐  ┌───────────────┐  ┌──────────────────────┐  │
│  │ RunAnywhere  │  │  EventBus     │  │  ModelRegistry       │  │
│  │ (public API) │  │  (events,     │  │  (model discovery,   │  │
│  │              │  │   callbacks)  │  │   download, storage) │  │
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
│  │  │ RACommons      │  │ RABackend      │  │ RABackendONNX │ │ │
│  │  │ (Core Engine)  │  │ LLAMACPP       │  │ (Sherpa-ONNX) │ │ │
│  │  └────────────────┘  └────────────────┘  └───────────────┘ │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### Key Components

| Component | Description |
|-----------|-------------|
| **RunAnywhere** | Main SDK singleton providing all public methods |
| **EventBus** | Event subscription system for SDK events (initialization, generation, model, voice) |
| **ModelRegistry** | Manages model metadata, discovery, and download tracking |
| **ServiceContainer** | Dependency injection for internal services |
| **FileSystem** | Cross-platform file operations for model storage |
| **DownloadService** | Model download with progress, resume, and extraction |

### Native Binaries

| Framework | Size | Provides |
|-----------|------|----------|
| `RACommons.xcframework` / `librac_commons.so` | ~2MB | Core C++ commons, registries, events |
| `RABackendLLAMACPP.xcframework` / `librunanywhere_llamacpp.so` | ~15-25MB | LLM capability (GGUF models) |
| `RABackendONNX.xcframework` / `librunanywhere_onnx.so` | ~50-70MB | STT, TTS, VAD (ONNX models) |

For detailed architecture documentation, see [ARCHITECTURE.md](ARCHITECTURE.md).

---

## Configuration

### SDK Initialization Parameters

```typescript
// Development mode (default) - no API key needed
await RunAnywhere.initialize({
  environment: SDKEnvironment.Development,
});

// Production mode - requires API key
await RunAnywhere.initialize({
  apiKey: '<YOUR_API_KEY>',
  baseURL: 'https://api.runanywhere.ai',
  environment: SDKEnvironment.Production,
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
const options: GenerationOptions = {
  maxTokens: 256,              // Maximum tokens to generate
  temperature: 0.7,            // Sampling temperature (0.0–2.0)
  topP: 0.95,                  // Top-p sampling parameter
  stopSequences: ['END'],      // Stop generation at these sequences
  systemPrompt: 'You are a helpful assistant.',
};
```

---

## Error Handling

The SDK provides structured error handling through `SDKError`:

```typescript
import { SDKError, SDKErrorCode, isSDKError } from '@runanywhere/core';

try {
  const response = await RunAnywhere.generate('Hello!');
} catch (error) {
  if (isSDKError(error)) {
    switch (error.code) {
      case SDKErrorCode.notInitialized:
        console.log('SDK not initialized. Call RunAnywhere.initialize() first.');
        break;
      case SDKErrorCode.modelNotFound:
        console.log('Model not found. Download it first.');
        break;
      case SDKErrorCode.insufficientMemory:
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

```typescript
import { LogLevel, SDKLogger } from '@runanywhere/core';

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
await RunAnywhere.unloadModel();

// Check storage before downloading
const storageInfo = await RunAnywhere.getStorageInfo();
if (storageInfo.freeSpace > modelSize) {
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
2. Unload unused models first with `RunAnywhere.unloadModel()`
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
1. Refresh model registry: `await RunAnywhere.getAvailableModels()`
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
**A:** iOS 15.1+ (iPhone/iPad) and Android 7.0+ (API 24+). Modern devices with 6GB+ RAM are recommended for larger models.

### Q: Can I use custom models?
**A:** Yes, any GGUF model works with the LlamaCPP backend. ONNX models work for STT/TTS.

### Q: What's the difference between `chat()` and `generate()`?
**A:** `chat()` is a convenience method that returns just the text. `generate()` returns full metrics (tokens, latency, etc.).

---

## Contributing

Contributions are welcome. The easiest way to get started is to run the React Native sample app with local SDK changes.

### First-Time Setup

```bash
# 1. Clone the repository
git clone https://github.com/RunanywhereAI/runanywhere-sdks.git
cd runanywhere-sdks

# 2. Navigate to the React Native SDK
cd sdk/runanywhere-react-native

# 3. Run first-time setup (builds native frameworks and installs dependencies)
# This downloads dependencies and builds:
#   - RACommons (core infrastructure)
#   - RABackendLLAMACPP (LLM backend)
#   - RABackendONNX (STT/TTS/VAD backend)
./scripts/build-react-native.sh --setup

# 4. Install JavaScript dependencies
yarn install
```

First-time setup takes 10-20 minutes depending on your machine (mostly building C++ native code). After that, incremental builds are faster.

### Testing with the Sample App

The best way to test SDK changes is with the React Native sample app:

```bash
# 1. Ensure SDK is built (from previous step)
cd sdk/runanywhere-react-native
./scripts/build-react-native.sh --setup

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

The sample app demonstrates the SDK features:
- AI Chat with streaming
- Speech-to-Text transcription
- Text-to-Speech synthesis
- Voice Assistant pipeline
- Model management

### After Making Changes to runanywhere-commons (C++ Core)

If you modify the C++ commons layer:

```bash
cd sdk/runanywhere-react-native
./scripts/build-react-native.sh --local --rebuild-commons
```

### Build Script Options

| Command | Description |
|---------|-------------|
| `--setup` | First-time setup: downloads deps, builds all frameworks |
| `--local` | Use local frameworks from built output |
| `--remote` | Use remote frameworks from GitHub releases |
| `--rebuild-commons` | Rebuild runanywhere-commons from source |
| `--ios` | Build for iOS only |
| `--android` | Build for Android only |
| `--clean` | Clean build artifacts before building |

### Development Workflow

```bash
# After making TypeScript changes
yarn typecheck  # Type check all packages
yarn lint       # Run ESLint
yarn build      # Build all packages

# After making native changes
./scripts/build-react-native.sh --local --rebuild-commons

# Run tests in sample app
cd examples/react-native/RunAnywhereAI
npm run ios  # or android
```

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

- [Architecture](ARCHITECTURE.md)
- [API Reference](Docs/Documentation.md)
- [Sample App](../../examples/react-native/RunAnywhereAI/)
- [Swift SDK](../runanywhere-swift/)
- [Kotlin SDK](../runanywhere-kotlin/)
- [Flutter SDK](../runanywhere-flutter/)
