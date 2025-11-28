# RunAnywhere Flutter SDK

A privacy-first, on-device AI SDK for Flutter that brings powerful language models directly to your applications.

## Features

- 🤖 **On-Device AI**: Run language models directly on user devices
- 🔒 **Privacy-First**: All processing happens locally, no data leaves the device
- ⚡ **Fast & Efficient**: Optimized for mobile performance
- 🎯 **Structured Output**: Generate type-safe structured data from LLMs
- 📊 **Analytics**: Track generation performance (development mode)
- 💾 **Memory Management**: Automatic memory pressure handling
- 📥 **Model Management**: Download and manage AI models

## Installation

Add the SDK to your `pubspec.yaml`:

```yaml
dependencies:
  runanywhere_flutter:
    path: ../path/to/runanywhere-flutter
```

Or from pub.dev (when published):

```yaml
dependencies:
  runanywhere_flutter: ^0.15.8
```

## Quick Start

### 1. Initialize the SDK

```dart
import 'package:runanywhere/runanywhere.dart';

void main() async {
  await RunAnywhere.initialize(
    apiKey: 'your-api-key',
    baseURL: 'https://api.runanywhere.ai',
    environment: SDKEnvironment.production,
  );
}
```

### 2. Generate Text

```dart
// Simple text generation
final response = await RunAnywhere.chat('Hello, how are you?');
print(response);

// With options
final result = await RunAnywhere.generate(
  'Write a short story',
  options: RunAnywhereGenerationOptions(
    maxTokens: 500,
    temperature: 0.7,
  ),
);

print(result.text);
print('Tokens used: ${result.tokensUsed}');
```

### 3. Streaming Generation

```dart
final stream = RunAnywhere.generateStream(
  'Tell me a joke',
  options: RunAnywhereGenerationOptions(),
);

await for (final token in stream) {
  print(token);
}
```

### 4. Structured Output

```dart
// Define a Generatable type
class UserProfile implements Generatable {
  final String name;
  final int age;
  final String email;

  UserProfile({required this.name, required this.age, required this.email});

  static String get jsonSchema => '''
  {
    "type": "object",
    "properties": {
      "name": {"type": "string"},
      "age": {"type": "integer"},
      "email": {"type": "string"}
    },
    "required": ["name", "age", "email"]
  }
  ''';

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      name: json['name'] as String,
      age: json['age'] as int,
      email: json['email'] as String,
    );
  }
}

// Generate structured output
final profile = await RunAnywhere.generateStructuredOutput<UserProfile>(
  type: UserProfile,
  prompt: 'Create a user profile for John Doe, age 30',
);
```

### 5. Model Management

```dart
// Load a model
await RunAnywhere.loadModel('model-id');

// Get available models
final models = await RunAnywhere.availableModels();

// Get current model
final currentModel = RunAnywhere.currentModel;
```

### 6. Download Models

```dart
// Download a model with progress tracking
final downloadTask = await RunAnywhere.downloadModel('model-id');

await for (final progress in downloadTask.progress) {
  print('Download progress: ${progress.progress * 100}%');
}

final localPath = await downloadTask.result;
print('Model downloaded to: $localPath');
```

## Event-Driven API

The SDK provides an event bus for reactive programming:

```dart
// Listen to generation events
RunAnywhere.events.generationEvents.listen((event) {
  if (event is SDKGenerationEvent.completed) {
    print('Generation completed: ${event.response}');
  }
});

// Listen to model events
RunAnywhere.events.modelEvents.listen((event) {
  if (event is SDKModelEvent.loadCompleted) {
    print('Model loaded: ${event.modelId}');
  }
});
```

## Architecture

The SDK follows a modular, protocol-oriented architecture:

- **Core**: Base components, protocols, and types
- **Capabilities**: High-level services (generation, memory, analytics)
- **Components**: AI component implementations (LLM, STT, TTS)
- **Foundation**: Infrastructure (logging, security, device management)
- **Public**: Public API and configuration

## Error Handling

The SDK uses typed errors for better error handling:

```dart
try {
  await RunAnywhere.generate('prompt');
} on SDKError catch (e) {
  switch (e.type) {
    case SDKErrorType.modelNotFound:
      print('Model not found');
      break;
    case SDKErrorType.generationFailed:
      print('Generation failed');
      break;
    default:
      print('Error: ${e.message}');
  }
}
```

## Memory Management

The SDK automatically manages memory:

```dart
// Get memory statistics
final stats = RunAnywhere.serviceContainer.memoryService.getMemoryStatistics();
print('Total memory: ${stats.totalMemory}');
print('Model memory: ${stats.modelMemory}');
print('Available: ${stats.availableMemory}');
```

## Analytics

Analytics are automatically submitted in development mode:

```dart
// Analytics are submitted automatically after generation
// No manual tracking needed
```

## Platform Channels

The SDK uses platform channels for native functionality:

- Audio session management (iOS/Android)
- Microphone permissions
- Device capabilities
- Native model loading (when using native SDKs)

## Requirements

- Flutter SDK >= 3.0.0
- Dart >= 3.0.0
- iOS 13.0+ / Android API 21+

## License

See LICENSE file for details.

## Support

For issues and questions, please open an issue on GitHub.
