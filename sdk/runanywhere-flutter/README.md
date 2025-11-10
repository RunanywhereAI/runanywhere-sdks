# RunAnywhere Flutter SDK

**Privacy-first, on-device AI SDK for Flutter** that brings powerful language models directly to your Flutter applications. RunAnywhere enables high-performance text generation, voice AI workflows, and structured outputs - all while keeping user data private and secure on-device.

## ✨ Features

### Core Capabilities
- 💬 **Text Generation** - High-performance on-device text generation with streaming support
- 🎙️ **Voice AI Pipeline** - Complete voice workflow with VAD, STT, LLM, and TTS components
- 📋 **Structured Outputs** - Type-safe JSON generation with schema validation
- 🏗️ **Model Management** - Automatic model discovery, downloading, and lifecycle management
- 📊 **Performance Analytics** - Real-time metrics with comprehensive event system
- 🎯 **Intelligent Routing** - Automatic on-device vs cloud decision making

### Technical Highlights
- 🔒 **Privacy-First** - All processing happens on-device by default
- 🚀 **Multi-Framework** - Support for GGUF, CoreML, TensorFlow Lite, WhisperKit, and more
- ⚡ **Native Performance** - Optimized for mobile platforms
- 🧠 **Smart Memory** - Automatic memory optimization and cleanup
- 📱 **Cross-Platform** - iOS, Android, Web, macOS, Linux, Windows
- 🎛️ **Component Architecture** - Modular components for flexible AI pipeline construction

## Requirements

- Flutter 3.9.2+
- Dart 3.9.2+
- iOS 16.0+ / Android API 21+

## Installation

Add RunAnywhere to your `pubspec.yaml`:

```yaml
dependencies:
  runanywhere_flutter:
    path: ../sdk/runanywhere-flutter  # Or use git URL when published
```

Then run:

```bash
flutter pub get
```

## Quick Start

### 1. Initialize the SDK

```dart
import 'package:runanywhere_flutter/runanywhere.dart';

// Development mode (recommended for getting started)
await RunAnywhere.initialize(
  apiKey: 'dev',           // Any string works in dev mode
  baseURL: 'localhost',   // Not used in dev mode
  environment: SDKEnvironment.development,
);
```

### 2. Generate Text

```dart
// Simple chat
final response = await RunAnywhere.chat('Hello, how are you?');
print(response);

// Generation with options
final options = RunAnywhereGenerationOptions(
  maxTokens: 150,
  temperature: 0.7,
);

final result = await RunAnywhere.generate(
  'Explain quantum computing in simple terms',
  options: options,
);

print('Response: ${result.text}');
print('Tokens: ${result.tokensUsed}');
print('Latency: ${result.latencyMs}ms');
```

### 3. Streaming Generation

```dart
// Stream tokens in real-time
final stream = RunAnywhere.generateStream(
  'Write a short story about AI',
  options: options,
);

await for (final token in stream) {
  print(token, terminator: '');
}
```

### 4. Voice Transcription

```dart
// Transcribe audio
final transcript = await RunAnywhere.transcribe(audioData);
print('Transcription: $transcript');
```

### 5. Model Management

```dart
// Load a model
await RunAnywhere.loadModel('smollm2-360m');

// List available models
final models = await RunAnywhere.availableModels();
for (final model in models) {
  print('Model: ${model.name}, ID: ${model.id}');
}
```

## Event System

Subscribe to SDK events:

```dart
// Subscribe to generation events
RunAnywhere.events.subscribe<SDKGenerationEvent>().listen((event) {
  if (event is SDKGenerationEvent.started) {
    print('Generation started: ${event.prompt}');
  } else if (event is SDKGenerationEvent.completed) {
    print('Generation completed: ${event.response}');
  }
});
```

## Architecture

The Flutter SDK follows the same 5-layer architecture as the Swift SDK:

1. **Public API Layer** - Clean, user-facing interface
2. **Capabilities Layer** - Feature-specific business logic
3. **Core Layer** - Shared domain models and protocols
4. **Data Layer** - Centralized data persistence and network operations
5. **Foundation Layer** - Cross-cutting utilities and platform extensions

## Development

### Building

```bash
# Build the SDK
flutter build

# Run tests
flutter test

# Analyze code
flutter analyze
```

## License

This project is licensed under the MIT License - see the [LICENSE](../../../LICENSE) file for details.

## 🙏 Acknowledgments

Built with ❤️ by the RunAnywhere team. The Flutter SDK architecture is based on the iOS Swift SDK implementation.
