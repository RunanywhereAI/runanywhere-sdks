# RunAnywhere React Native SDK

On-device AI with intelligent routing between on-device and cloud execution for optimal cost and privacy.

> **📖 Complete Documentation**: See [STATUS.md](./STATUS.md) for comprehensive status, architecture, Swift SDK alignment, and implementation details.

## Installation

```bash
npm install @runanywhere/react-native-sdk
# or
yarn add @runanywhere/react-native-sdk
```

### iOS Setup

```bash
cd ios && pod install
```

### Android Setup

No additional setup required. The module will be automatically linked.

## Quick Start

```typescript
import { RunAnywhere, SDKEnvironment } from '@runanywhere/react-native-sdk';

// Initialize the SDK
await RunAnywhere.initialize({
  apiKey: 'your-api-key',
  baseURL: 'https://api.runanywhere.com',
  environment: SDKEnvironment.Production,
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
console.log('Speed:', result.performanceMetrics.tokensPerSecond, 'tok/s');
```

## Features

- **Text Generation**: Simple chat and advanced generation with options
- **Streaming**: Real-time token streaming for responsive UI
- **Voice**: Speech-to-text and text-to-speech capabilities
- **Model Management**: Download, load, and manage AI models
- **Events**: Subscribe to SDK events for real-time updates
- **Cross-Platform**: iOS and Android support

## API Reference

### Initialization

```typescript
// Initialize SDK
await RunAnywhere.initialize({
  apiKey: string,
  baseURL: string,
  environment?: SDKEnvironment, // default: Production
});

// Check initialization state
const isInit = await RunAnywhere.isInitialized();
const isActive = await RunAnywhere.isActive();

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
  topP: 1.0,
  systemPrompt: 'You are a helpful assistant.',
});

// Streaming
const unsubscribe = RunAnywhere.events.onGeneration((event) => {
  if (event.type === 'tokenGenerated') {
    process.stdout.write(event.token);
  }
});
const sessionId = await RunAnywhere.generateStream('Tell me a story');
```

### Model Management

```typescript
// List available models
const models = await RunAnywhere.availableModels();

// Load a model
await RunAnywhere.loadModel('llama-3.2-1b');

// Get current model
const current = await RunAnywhere.currentModel();

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
  ComponentState,

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
} from '@runanywhere/react-native-sdk';
```

## Requirements

- React Native 0.71+
- iOS 14.0+
- Android API 24+

## Development Setup

After cloning the repository, you need to generate the Nitrogen binding files before building:

```bash
cd sdk/runanywhere-react-native

# Install dependencies
npm install

# Generate Nitrogen bindings (REQUIRED before first build)
npm run nitrogen
```

### What is Nitrogen?

Nitrogen is the code generator for [NitroModules](https://github.com/margelo/react-native-nitro-modules) - a high-performance native module system for React Native. It generates:

- **C++ bridge code** - Type-safe bindings between JS and native
- **Swift/Kotlin code** - Platform-specific implementations
- **Autolinking files** - For CocoaPods and Gradle integration

The generated files are in `nitrogen/generated/` and are gitignored (auto-generated on each machine).

### Native Binaries

Native binaries (XCFramework for iOS, .so libraries for Android) are **automatically downloaded** from [runanywhere-binaries](https://github.com/RunanywhereAI/runanywhere-binaries) releases:

- **iOS**: Downloaded during `pod install` via the podspec's `prepare_command`
- **Android**: Downloaded during Gradle's `preBuild` phase via `downloadNativeLibs` task

The version is controlled by `native-version.txt` in the SDK root.

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
