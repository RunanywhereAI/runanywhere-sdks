# RunAnywhere Flutter SDK API Reference

## RunAnywhere

Main entry point for the SDK.

### Static Methods

#### `initialize`

Initialize the SDK with API credentials.

```dart
static Future<void> initialize({
  required String apiKey,
  required String baseURL,
  SDKEnvironment environment = SDKEnvironment.production,
})
```

**Parameters:**
- `apiKey`: API key for authentication
- `baseURL`: Base URL for API requests
- `environment`: SDK environment (development, staging, production)

**Example:**
```dart
await RunAnywhere.initialize(
  apiKey: 'your-api-key',
  baseURL: 'https://api.runanywhere.ai',
  environment: SDKEnvironment.production,
);
```

#### `generate`

Generate text from a prompt.

```dart
static Future<GenerationResult> generate(
  String prompt, {
  RunAnywhereGenerationOptions? options,
})
```

**Returns:** `GenerationResult` with text, tokens used, and metrics

**Example:**
```dart
final result = await RunAnywhere.generate(
  'Write a poem',
  options: RunAnywhereGenerationOptions(
    maxTokens: 200,
    temperature: 0.8,
  ),
);
```

#### `generateStream`

Generate text with streaming support.

```dart
static Stream<String> generateStream(
  String prompt, {
  RunAnywhereGenerationOptions? options,
})
```

**Returns:** `Stream<String>` of tokens

**Example:**
```dart
final stream = RunAnywhere.generateStream('Tell a story');
await for (final token in stream) {
  print(token);
}
```

#### `chat`

Simple chat interface.

```dart
static Future<String> chat(String prompt)
```

**Returns:** Generated text as string

#### `generateStructuredOutput`

Generate structured output conforming to a type.

```dart
static Future<T> generateStructuredOutput<T>({
  required Type type,
  required String prompt,
  RunAnywhereGenerationOptions? options,
})
```

**Example:**
```dart
final profile = await RunAnywhere.generateStructuredOutput<UserProfile>(
  type: UserProfile,
  prompt: 'Create a user profile',
);
```

#### `loadModel`

Load a model for generation.

```dart
static Future<void> loadModel(String modelId)
```

#### `availableModels`

Get list of available models.

```dart
static Future<List<ModelInfo>> availableModels()
```

#### `currentModel`

Get currently loaded model.

```dart
static ModelInfo? get currentModel
```

### Properties

#### `isSDKInitialized`

Check if SDK is initialized.

```dart
static bool get isSDKInitialized
```

#### `events`

Access the event bus.

```dart
static EventBus get events
```

#### `serviceContainer`

Access the service container.

```dart
static ServiceContainer get serviceContainer
```

## GenerationResult

Result of text generation.

```dart
class GenerationResult {
  final String text;
  final int tokensUsed;
  final int latencyMs;
  final double savedAmount;
  final PerformanceMetrics performanceMetrics;
}
```

## RunAnywhereGenerationOptions

Options for text generation.

```dart
class RunAnywhereGenerationOptions {
  final int maxTokens;
  final double temperature;
  final bool stream;
}
```

## ModelInfo

Information about an AI model.

```dart
class ModelInfo {
  final String id;
  final String name;
  final LLMFramework framework;
  final ModelFormat format;
  final int size;
  final int memoryRequirement;
  final String? localPath;
  final String? downloadURL;
}
```

## EventBus

Central event bus for SDK events.

### Streams

- `initializationEvents`: SDK initialization events
- `generationEvents`: Text generation events
- `modelEvents`: Model loading/download events
- `voiceEvents`: Voice processing events
- `componentEvents`: Component lifecycle events
- `allEvents`: All SDK events

### Example

```dart
RunAnywhere.events.generationEvents.listen((event) {
  if (event is SDKGenerationEvent.completed) {
    print('Completed: ${event.response}');
  }
});
```

## SDKError

SDK error types.

```dart
class SDKError implements Exception {
  final String message;
  final SDKErrorType type;
}
```

### Error Types

- `notInitialized`: SDK not initialized
- `modelNotFound`: Model not found
- `generationFailed`: Generation failed
- `networkError`: Network error
- `timeout`: Operation timed out
- And more...

## ServiceContainer

Dependency injection container.

### Services

- `modelRegistry`: Model registry service
- `modelLoadingService`: Model loading service
- `generationService`: Text generation service
- `streamingService`: Streaming generation service
- `voiceCapabilityService`: Voice processing service
- `memoryService`: Memory management service
- `downloadService`: Model download service
- `analyticsService`: Analytics service

### Example

```dart
final container = RunAnywhere.serviceContainer;
final stats = container.memoryService.getMemoryStatistics();
```

## Generatable Protocol

Protocol for types that can be generated as structured output.

```dart
abstract class Generatable {
  static String get jsonSchema;
  static Map<String, dynamic>? get generationHints => null;
}
```

### Example

```dart
class QuizQuestion implements Generatable {
  final String question;
  final List<String> options;
  final int correctAnswer;

  static String get jsonSchema => '''
  {
    "type": "object",
    "properties": {
      "question": {"type": "string"},
      "options": {"type": "array", "items": {"type": "string"}},
      "correctAnswer": {"type": "integer"}
    }
  }
  ''';
}
```
