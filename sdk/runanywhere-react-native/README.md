# RunAnywhere React Native SDK

On-device AI with intelligent routing between on-device and cloud execution for optimal cost and privacy.

> **📖 Architecture Documentation**: See [MULTI_PACKAGE_ARCHITECTURE.md](./MULTI_PACKAGE_ARCHITECTURE.md) for comprehensive multi-package structure and implementation details.

## Multi-Package Architecture

This SDK uses a modular multi-package architecture. Install only the packages you need:

| Package | Description |
|---------|-------------|
| `@runanywhere/core` | Core SDK infrastructure and public API (required) |
| `@runanywhere/native` | Native bridge with Nitro bindings (peer dependency of core) |
| `@runanywhere/llamacpp` | LlamaCpp backend for LLM text generation |
| `@runanywhere/onnx` | ONNX Runtime backend for STT/TTS |

## Installation

### Full Installation (All Features)

```bash
npm install @runanywhere/core @runanywhere/native @runanywhere/llamacpp @runanywhere/onnx
# or
yarn add @runanywhere/core @runanywhere/native @runanywhere/llamacpp @runanywhere/onnx
```

### Minimal Installation (LLM Only)

```bash
npm install @runanywhere/core @runanywhere/native @runanywhere/llamacpp
```

### Minimal Installation (STT/TTS Only)

```bash
npm install @runanywhere/core @runanywhere/native @runanywhere/onnx
```

### iOS Setup

```bash
cd ios && pod install
```

### Android Setup

No additional setup required. The module will be automatically linked.

## Quick Start

```typescript
// Import from the modular packages
import { RunAnywhere, SDKEnvironment, ModelCategory } from '@runanywhere/core';
import { LlamaCPP } from '@runanywhere/llamacpp';
import { ONNX, ModelArtifactType } from '@runanywhere/onnx';

// Initialize the SDK
await RunAnywhere.initialize({
  apiKey: 'your-api-key',
  baseURL: 'https://api.runanywhere.com',
  environment: SDKEnvironment.Development,
});

// Register LlamaCpp module and add models
LlamaCPP.register();
LlamaCPP.addModel({
  id: 'smollm2-360m-q8_0',
  name: 'SmolLM2 360M Q8_0',
  url: 'https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf',
  memoryRequirement: 500_000_000,
});

// Register ONNX module and add STT/TTS models
ONNX.register();
ONNX.addModel({
  id: 'sherpa-onnx-whisper-tiny.en',
  name: 'Sherpa Whisper Tiny (ONNX)',
  url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz',
  modality: ModelCategory.SpeechRecognition,
  artifactType: ModelArtifactType.TarGzArchive,
  memoryRequirement: 75_000_000,
});

// Simple chat
const response = await RunAnywhere.chat('Hello, how are you?');
console.log(response);

// With options
const result = await RunAnywhere.generate('Explain quantum computing', {
  maxTokens: 200,
  temperature: 0.7,
});
console.log('Text:', result.text);
console.log('Tokens:', result.tokensUsed);
```

## Features

- **Text Generation**: Simple chat and advanced generation with options
- **Streaming**: Real-time token streaming for responsive UI
- **Voice**: Speech-to-text and text-to-speech capabilities
- **Model Management**: Download, load, and manage AI models
- **Events**: Subscribe to SDK events for real-time updates
- **Cross-Platform**: iOS and Android support
- **Modular**: Install only the backends you need

## API Reference

### Initialization

```typescript
import { RunAnywhere, SDKEnvironment } from '@runanywhere/core';

// Initialize SDK
await RunAnywhere.initialize({
  apiKey: string,
  baseURL: string,
  environment?: SDKEnvironment, // default: Production
});

// Check initialization state
const isInit = await RunAnywhere.isInitialized();
const isActive = RunAnywhere.isActive;

// Reset SDK
await RunAnywhere.reset();
```

### Text Generation

```typescript
// Simple chat
const response = await RunAnywhere.chat('Hello!');

// With options
const result = await RunAnywhere.generate('Prompt', {
  maxTokens: 100,
  temperature: 0.7,
  systemPrompt: 'You are a helpful assistant.',
});

// Streaming
RunAnywhere.generateStream('Tell me a story', undefined, (token) => {
  process.stdout.write(token);
});
```

### Model Management

```typescript
// List available models
const models = await RunAnywhere.getAvailableModels();

// Load a model
await RunAnywhere.loadModel('llama-3.2-1b');

// Check if model is loaded
const isLoaded = await RunAnywhere.isModelLoaded();

// Download a model (with progress events)
RunAnywhere.events.onModel((event) => {
  if (event.type === 'downloadProgress') {
    console.log(`Progress: ${event.progress * 100}%`);
  }
});
await RunAnywhere.downloadModel('llama-3.2-1b');
```

### Voice

```typescript
// Load STT model
await RunAnywhere.loadSTTModel('whisper-base');

// Transcribe audio
const result = await RunAnywhere.transcribe(audioBase64);
console.log('Transcript:', result.text);

// Load TTS model
await RunAnywhere.loadTTSModel('en-US-default');

// Synthesize speech
const audioData = await RunAnywhere.synthesize('Hello, world!', {
  voice: 'en-US-default',
  rate: 1.0,
});
```

### Events

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
      console.log('Done:', event.response);
      break;
    case 'failed':
      console.error('Error:', event.error);
      break;
  }
});

// Unsubscribe when done
unsubscribe();
```

### Conversation

```typescript
// Multi-turn conversation
const conversation = RunAnywhere.conversation();

const response1 = await conversation.send('Hello!');
const response2 = await conversation.send('What did I just say?');

console.log(conversation.history);
conversation.clear();
```

## Types

The SDK exports all TypeScript types for full type safety:

```typescript
import {
  // Enums
  SDKEnvironment,
  ExecutionTarget,
  LLMFramework,
  ModelCategory,
  ModelFormat,

  // Interfaces
  GenerationResult,
  GenerationOptions,
  ModelInfo,
  STTResult,
  TTSConfiguration,

  // Events
  SDKGenerationEvent,
  SDKModelEvent,
  SDKVoiceEvent,

  // Errors
  SDKError,
  SDKErrorCode,
} from '@runanywhere/core';
```

## Requirements

- React Native 0.71+
- iOS 15.1+
- Android API 24+

## Development Setup

After cloning the repository:

```bash
cd sdk/runanywhere-react-native

# Install dependencies
yarn install

# Build all packages
yarn build
```

### Native Binaries

Native binaries (XCFramework for iOS, .so libraries for Android) are **automatically downloaded** from [runanywhere-binaries](https://github.com/RunanywhereAI/runanywhere-binaries) releases:

- **iOS**: Downloaded during `pod install` via the podspec's `prepare_command`
- **Android**: Downloaded during Gradle's `preBuild` phase via `downloadNativeLibs` task

The version is controlled by `native-version.txt` in the native package.

### Local Development (Build from Source)

To build native libraries locally and test the SDK end-to-end:

```bash
# First-time setup (builds iOS + Android native libs)
./scripts/build-react-native.sh --setup
```

See `./scripts/build-react-native.sh --help` for all options.

### Build Commands

```bash
# iOS
cd examples/react-native/RunAnywhereAI/ios
pod install
cd ..
npx react-native run-ios

# Android
cd examples/react-native/RunAnywhereAI
npx react-native run-android
```

## License

MIT
