# RunAnywhere Flutter SDK – API Reference

Complete API documentation for the RunAnywhere Flutter SDK.

---

## Table of Contents

1. [Core API](#core-api)
   - [RunAnywhere](#runanywhere)
2. [Model Types](#model-types)
   - [ModelInfo](#modelinfo)
   - [ModelCategory](#modelcategory)
   - [ModelFormat](#modelformat)
   - [InferenceFramework](#inferenceframework)
3. [Generation Types](#generation-types)
   - [LLMGenerationOptions](#llmgenerationoptions)
   - [LLMGenerationResult](#llmgenerationresult)
   - [LLMStreamingResult](#llmstreamingresult)
   - [STTResult](#sttresult)
   - [TTSResult](#ttsresult)
4. [Download Types](#download-types)
   - [DownloadProgress](#downloadprogress)
   - [DownloadProgressState](#downloadprogressstate)
5. [Voice Agent Types](#voice-agent-types)
   - [VoiceSessionHandle](#voicesessionhandle)
   - [VoiceSessionConfig](#voicesessionconfig)
   - [VoiceSessionEvent](#voicesessionevent)
   - [VoiceAgentComponentStates](#voiceagentcomponentstates)
6. [Event System](#event-system)
   - [EventBus](#eventbus)
   - [SDKEvent](#sdkevent)
7. [Error Handling](#error-handling)
   - [SDKError](#sdkerror)
8. [Backend Modules](#backend-modules)
   - [LlamaCpp](#llamacpp)
   - [Onnx](#onnx)
9. [Configuration](#configuration)
   - [SDKEnvironment](#sdkenvironment)

---

## Core API

### RunAnywhere

The main entry point for all SDK operations. All methods are static.

**Import:**
```dart
import 'package:runanywhere/runanywhere.dart';
```

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `version` | `String` | SDK version string |
| `isSDKInitialized` | `bool` | Whether SDK has been initialized |
| `isActive` | `bool` | Whether SDK is initialized and ready |
| `environment` | `SDKEnvironment?` | Current environment |
| `events` | `EventBus` | Event bus for SDK events |
| `currentModelId` | `String?` | Currently loaded LLM model ID |
| `isModelLoaded` | `bool` | Whether an LLM model is loaded |
| `currentSTTModelId` | `String?` | Currently loaded STT model ID |
| `isSTTModelLoaded` | `bool` | Whether an STT model is loaded |
| `currentTTSVoiceId` | `String?` | Currently loaded TTS voice ID |
| `isTTSVoiceLoaded` | `bool` | Whether a TTS voice is loaded |
| `isVoiceAgentReady` | `bool` | Whether all voice components are ready |

#### Initialization

##### `initialize()`

Initialize the SDK with optional configuration.

```dart
static Future<void> initialize({
  String? apiKey,
  String? baseURL,
  SDKEnvironment environment = SDKEnvironment.development,
})
```

**Parameters:**
- `apiKey` – API key for production mode (optional for development)
- `baseURL` – Base URL for API calls (optional for development)
- `environment` – SDK environment (defaults to development)

**Example:**
```dart
// Development mode (no API key needed)
await RunAnywhere.initialize();

// Production mode
await RunAnywhere.initialize(
  apiKey: 'your-api-key',
  baseURL: 'https://api.runanywhere.ai',
  environment: SDKEnvironment.production,
);
```

---

#### Model Management

##### `availableModels()`

Get all available models from the registry.

```dart
static Future<List<ModelInfo>> availableModels()
```

**Returns:** List of `ModelInfo` objects for all registered models.

**Example:**
```dart
final models = await RunAnywhere.availableModels();
for (final model in models) {
  print('${model.name}: ${model.isDownloaded ? "Downloaded" : "Not downloaded"}');
}
```

##### `registerModel()`

Register a model with the SDK.

```dart
static ModelInfo registerModel({
  String? id,
  required String name,
  required Uri url,
  required InferenceFramework framework,
  ModelCategory modality = ModelCategory.language,
  ModelArtifactType? artifactType,
  int? memoryRequirement,
  bool supportsThinking = false,
})
```

**Parameters:**
- `id` – Unique model ID (auto-generated from name if not provided)
- `name` – Human-readable model name
- `url` – Download URL for the model
- `framework` – Inference framework (e.g., `InferenceFramework.llamaCpp`)
- `modality` – Model category (default: `language`)
- `artifactType` – Artifact type (auto-inferred from URL if not provided)
- `memoryRequirement` – Memory requirement in bytes
- `supportsThinking` – Whether model supports thinking tokens

**Example:**
```dart
RunAnywhere.registerModel(
  id: 'my-model',
  name: 'My Custom Model',
  url: Uri.parse('https://example.com/model.gguf'),
  framework: InferenceFramework.llamaCpp,
  memoryRequirement: 500000000,
);
```

##### `downloadModel()`

Download a model by ID.

```dart
static Stream<DownloadProgress> downloadModel(String modelId)
```

**Parameters:**
- `modelId` – ID of the model to download

**Returns:** Stream of `DownloadProgress` objects.

**Example:**
```dart
await for (final progress in RunAnywhere.downloadModel('my-model')) {
  print('Progress: ${(progress.percentage * 100).toStringAsFixed(1)}%');
  if (progress.state.isCompleted) break;
}
```

##### `loadModel()`

Load an LLM model by ID.

```dart
static Future<void> loadModel(String modelId)
```

**Parameters:**
- `modelId` – ID of the model to load

**Throws:** `SDKError` if model not found or not downloaded.

**Example:**
```dart
await RunAnywhere.loadModel('smollm2-360m-q8_0');
print('Model loaded: ${RunAnywhere.isModelLoaded}');
```

##### `unloadModel()`

Unload the currently loaded LLM model.

```dart
static Future<void> unloadModel()
```

##### `deleteStoredModel()`

Delete a stored model from disk.

```dart
static Future<void> deleteStoredModel(String modelId)
```

---

#### LLM Generation

##### `chat()`

Simple text generation – returns only the generated text.

```dart
static Future<String> chat(String prompt)
```

**Parameters:**
- `prompt` – Input prompt for generation

**Returns:** Generated text response.

**Example:**
```dart
final response = await RunAnywhere.chat('Hello, how are you?');
print(response);
```

##### `generate()`

Full text generation with metrics.

```dart
static Future<LLMGenerationResult> generate(
  String prompt, {
  LLMGenerationOptions? options,
})
```

**Parameters:**
- `prompt` – Input prompt for generation
- `options` – Generation options (optional)

**Returns:** `LLMGenerationResult` with text and metrics.

**Example:**
```dart
final result = await RunAnywhere.generate(
  'Explain quantum computing in simple terms',
  options: LLMGenerationOptions(maxTokens: 200, temperature: 0.7),
);
print('Response: ${result.text}');
print('Tokens: ${result.tokensUsed}');
print('Latency: ${result.latencyMs}ms');
```

##### `generateStream()`

Streaming text generation.

```dart
static Future<LLMStreamingResult> generateStream(
  String prompt, {
  LLMGenerationOptions? options,
})
```

**Parameters:**
- `prompt` – Input prompt for generation
- `options` – Generation options (optional)

**Returns:** `LLMStreamingResult` containing stream, result future, and cancel function.

**Example:**
```dart
final result = await RunAnywhere.generateStream('Tell me a story');

// Consume tokens as they arrive
await for (final token in result.stream) {
  stdout.write(token);  // Real-time output
}

// Get final metrics
final metrics = await result.result;
print('\nTokens: ${metrics.tokensUsed}');

// Or cancel early if needed
// result.cancel();
```

##### `cancelGeneration()`

Cancel ongoing generation.

```dart
static Future<void> cancelGeneration()
```

---

#### Speech-to-Text (STT)

##### `loadSTTModel()`

Load an STT model by ID.

```dart
static Future<void> loadSTTModel(String modelId)
```

##### `unloadSTTModel()`

Unload the currently loaded STT model.

```dart
static Future<void> unloadSTTModel()
```

##### `transcribe()`

Transcribe audio data to text.

```dart
static Future<String> transcribe(Uint8List audioData)
```

**Parameters:**
- `audioData` – Raw audio bytes (PCM16 at 16kHz mono expected)

**Returns:** Transcribed text.

**Example:**
```dart
final text = await RunAnywhere.transcribe(audioBytes);
print('Transcription: $text');
```

##### `transcribeWithResult()`

Transcribe audio data with detailed result.

```dart
static Future<STTResult> transcribeWithResult(Uint8List audioData)
```

**Returns:** `STTResult` with text, confidence, and metadata.

**Example:**
```dart
final result = await RunAnywhere.transcribeWithResult(audioBytes);
print('Text: ${result.text}');
print('Confidence: ${result.confidence}');
print('Language: ${result.language}');
```

---

#### Text-to-Speech (TTS)

##### `loadTTSVoice()`

Load a TTS voice by ID.

```dart
static Future<void> loadTTSVoice(String voiceId)
```

##### `unloadTTSVoice()`

Unload the currently loaded TTS voice.

```dart
static Future<void> unloadTTSVoice()
```

##### `synthesize()`

Synthesize speech from text.

```dart
static Future<TTSResult> synthesize(
  String text, {
  double rate = 1.0,
  double pitch = 1.0,
  double volume = 1.0,
})
```

**Parameters:**
- `text` – Text to synthesize
- `rate` – Speech rate (0.5 to 2.0, default 1.0)
- `pitch` – Speech pitch (0.5 to 2.0, default 1.0)
- `volume` – Speech volume (0.0 to 1.0, default 1.0)

**Returns:** `TTSResult` with audio samples and metadata.

**Example:**
```dart
final result = await RunAnywhere.synthesize('Hello world');
print('Samples: ${result.samples.length}');
print('Sample rate: ${result.sampleRate} Hz');
print('Duration: ${result.durationSeconds}s');
```

---

#### Voice Agent

##### `startVoiceSession()`

Start a voice session with audio capture, VAD, and full voice pipeline.

```dart
static Future<VoiceSessionHandle> startVoiceSession({
  VoiceSessionConfig config = VoiceSessionConfig.defaultConfig,
})
```

**Parameters:**
- `config` – Voice session configuration (optional)

**Returns:** `VoiceSessionHandle` to control the session.

**Prerequisites:** STT, LLM, and TTS models must be loaded.

**Example:**
```dart
final session = await RunAnywhere.startVoiceSession();

session.events.listen((event) {
  if (event is VoiceSessionListening) {
    print('Audio level: ${event.audioLevel}');
  } else if (event is VoiceSessionTranscribed) {
    print('User said: ${event.text}');
  } else if (event is VoiceSessionResponded) {
    print('AI response: ${event.text}');
  } else if (event is VoiceSessionTurnCompleted) {
    print('Turn completed');
  }
});

// Later...
session.stop();
```

##### `getVoiceAgentComponentStates()`

Get the current state of all voice agent components.

```dart
static VoiceAgentComponentStates getVoiceAgentComponentStates()
```

**Returns:** `VoiceAgentComponentStates` with STT, LLM, and TTS states.

##### `cleanupVoiceAgent()`

Cleanup voice agent resources.

```dart
static void cleanupVoiceAgent()
```

---

#### Storage Information

##### `getStorageInfo()`

Get storage information including device storage, app storage, and downloaded models.

```dart
static Future<StorageInfo> getStorageInfo()
```

**Returns:** `StorageInfo` with storage metrics.

##### `getDownloadedModelsWithInfo()`

Get downloaded models with their file sizes.

```dart
static Future<List<StoredModel>> getDownloadedModelsWithInfo()
```

---

#### Lifecycle

##### `reset()`

Reset SDK state (for testing or reinitialization).

```dart
static void reset()
```

---

## Model Types

### ModelInfo

Information about a model.

**Properties:**

| Property | Type | Description |
|----------|------|-------------|
| `id` | `String` | Unique model identifier |
| `name` | `String` | Human-readable name |
| `category` | `ModelCategory` | Model category |
| `format` | `ModelFormat` | Model format |
| `framework` | `InferenceFramework` | Inference framework |
| `downloadURL` | `Uri?` | Download URL |
| `localPath` | `Uri?` | Local path (if downloaded) |
| `artifactType` | `ModelArtifactType` | Artifact type |
| `downloadSize` | `int?` | Download size in bytes |
| `contextLength` | `int?` | Context length (for LLMs) |
| `supportsThinking` | `bool` | Whether model supports thinking tokens |
| `description` | `String?` | Model description |
| `isDownloaded` | `bool` | Whether model is downloaded |
| `isAvailable` | `bool` | Whether model is available for use |
| `isBuiltIn` | `bool` | Whether model is built-in |

### ModelCategory

Model category/type.

```dart
enum ModelCategory {
  language,           // Language Model (LLM)
  speechRecognition,  // Speech-to-Text
  speechSynthesis,    // Text-to-Speech
  vision,             // Vision Model
  imageGeneration,    // Image Generation
  multimodal,         // Multimodal
  audio,              // Audio Processing
}
```

### ModelFormat

Supported model formats.

```dart
enum ModelFormat {
  onnx,    // ONNX format
  ort,     // ONNX Runtime format
  gguf,    // GGUF format (llama.cpp)
  bin,     // Binary format
  unknown,
}
```

### InferenceFramework

Inference frameworks/runtimes.

```dart
enum InferenceFramework {
  onnx,              // ONNX Runtime
  llamaCpp,          // llama.cpp
  foundationModels,  // Foundation Models
  systemTTS,         // System TTS
  fluidAudio,        // FluidAudio
  builtIn,           // Built-in
  none,
  unknown,
}
```

---

## Generation Types

### LLMGenerationOptions

Options for LLM text generation.

```dart
class LLMGenerationOptions {
  final int maxTokens;          // Maximum tokens to generate (default: 100)
  final double temperature;     // Randomness (default: 0.8)
  final double topP;           // Nucleus sampling (default: 1.0)
  final List<String> stopSequences;  // Stop sequences
  final bool streamingEnabled;  // Enable streaming
  final InferenceFramework? preferredFramework;
  final String? systemPrompt;   // System prompt
}
```

**Example:**
```dart
const options = LLMGenerationOptions(
  maxTokens: 200,
  temperature: 0.7,
  systemPrompt: 'You are a helpful assistant.',
);
```

### LLMGenerationResult

Result of LLM text generation.

**Properties:**

| Property | Type | Description |
|----------|------|-------------|
| `text` | `String` | Generated text |
| `thinkingContent` | `String?` | Thinking content (if model supports it) |
| `inputTokens` | `int` | Number of input tokens |
| `tokensUsed` | `int` | Number of output tokens |
| `modelUsed` | `String` | Model ID used |
| `latencyMs` | `double` | Total latency in milliseconds |
| `framework` | `String?` | Framework used |
| `tokensPerSecond` | `double` | Generation speed |
| `timeToFirstTokenMs` | `double?` | Time to first token |
| `thinkingTokens` | `int` | Thinking tokens count |
| `responseTokens` | `int` | Response tokens count |

### LLMStreamingResult

Result of streaming LLM generation.

**Properties:**

| Property | Type | Description |
|----------|------|-------------|
| `stream` | `Stream<String>` | Stream of tokens |
| `result` | `Future<LLMGenerationResult>` | Final result future |
| `cancel` | `void Function()` | Cancel function |

### STTResult

Result of STT transcription.

**Properties:**

| Property | Type | Description |
|----------|------|-------------|
| `text` | `String` | Transcribed text |
| `confidence` | `double` | Confidence score (0.0 to 1.0) |
| `durationMs` | `int` | Audio duration in milliseconds |
| `language` | `String?` | Detected language |

### TTSResult

Result of TTS synthesis.

**Properties:**

| Property | Type | Description |
|----------|------|-------------|
| `samples` | `Float32List` | Audio samples (PCM float) |
| `sampleRate` | `int` | Sample rate in Hz |
| `durationMs` | `int` | Duration in milliseconds |
| `durationSeconds` | `double` | Duration in seconds |
| `numSamples` | `int` | Number of samples |

---

## Download Types

### DownloadProgress

Download progress information.

**Properties:**

| Property | Type | Description |
|----------|------|-------------|
| `bytesDownloaded` | `int` | Bytes downloaded |
| `totalBytes` | `int` | Total bytes |
| `state` | `DownloadProgressState` | Current state |
| `stage` | `DownloadProgressStage` | Current stage |
| `overallProgress` | `double` | Progress 0.0 to 1.0 |
| `percentage` | `double` | Alias for overallProgress |

### DownloadProgressState

Download state enum.

```dart
enum DownloadProgressState {
  downloading,  // Currently downloading
  completed,    // Download completed
  failed,       // Download failed
  cancelled,    // Download cancelled
}
```

**Helper properties:**
- `isCompleted` – Whether download completed successfully
- `isFailed` – Whether download failed

---

## Voice Agent Types

### VoiceSessionHandle

Handle to control an active voice session.

**Properties:**

| Property | Type | Description |
|----------|------|-------------|
| `config` | `VoiceSessionConfig` | Session configuration |
| `events` | `Stream<VoiceSessionEvent>` | Event stream |
| `isRunning` | `bool` | Whether session is running |
| `isProcessing` | `bool` | Whether processing audio |

**Methods:**

##### `start()`

Start the voice session.

```dart
Future<void> start()
```

##### `stop()`

Stop the voice session.

```dart
void stop()
```

##### `sendNow()`

Force process current audio (push-to-talk mode).

```dart
Future<void> sendNow()
```

##### `feedAudio()`

Feed audio data to the session (for external audio sources).

```dart
void feedAudio(Uint8List data, double audioLevel)
```

##### `dispose()`

Dispose resources.

```dart
Future<void> dispose()
```

### VoiceSessionConfig

Configuration for voice session behavior.

```dart
class VoiceSessionConfig {
  final double silenceDuration;   // Seconds before processing (default: 1.5)
  final double speechThreshold;   // Audio level threshold (default: 0.03)
  final bool autoPlayTTS;         // Auto-play TTS response (default: true)
  final bool continuousMode;      // Resume listening after TTS (default: true)
}
```

**Example:**
```dart
final config = VoiceSessionConfig(
  silenceDuration: 2.0,      // Wait 2 seconds of silence
  speechThreshold: 0.1,      // Higher threshold for noisy environments
  autoPlayTTS: true,
  continuousMode: true,
);

final session = await RunAnywhere.startVoiceSession(config: config);
```

### VoiceSessionEvent

Events emitted during a voice session.

| Event | Description |
|-------|-------------|
| `VoiceSessionStarted` | Session started and ready |
| `VoiceSessionListening` | Listening with audio level |
| `VoiceSessionSpeechStarted` | Speech detected |
| `VoiceSessionProcessing` | Processing audio |
| `VoiceSessionTranscribed` | Got transcription |
| `VoiceSessionResponded` | Got LLM response |
| `VoiceSessionSpeaking` | Playing TTS |
| `VoiceSessionTurnCompleted` | Complete turn result |
| `VoiceSessionStopped` | Session stopped |
| `VoiceSessionError` | Error occurred |

**Example:**
```dart
session.events.listen((event) {
  switch (event) {
    case VoiceSessionListening(:final audioLevel):
      updateMeter(audioLevel);
    case VoiceSessionTranscribed(:final text):
      showUserText(text);
    case VoiceSessionResponded(:final text):
      showAssistantText(text);
    case VoiceSessionTurnCompleted(:final transcript, :final response):
      addToHistory(transcript, response);
    case VoiceSessionError(:final message):
      showError(message);
    default:
      break;
  }
});
```

### VoiceAgentComponentStates

States of all voice agent components.

**Properties:**

| Property | Type | Description |
|----------|------|-------------|
| `stt` | `ComponentLoadState` | STT component state |
| `llm` | `ComponentLoadState` | LLM component state |
| `tts` | `ComponentLoadState` | TTS component state |
| `isFullyReady` | `bool` | All components loaded |
| `hasAnyLoaded` | `bool` | Any component loaded |

---

## Event System

### EventBus

Central event bus for SDK-wide event distribution.

**Access:**
```dart
final events = RunAnywhere.events;
```

**Streams:**

| Stream | Type | Description |
|--------|------|-------------|
| `allEvents` | `Stream<SDKEvent>` | All SDK events |
| `initializationEvents` | `Stream<SDKInitializationEvent>` | Init events |
| `generationEvents` | `Stream<SDKGenerationEvent>` | LLM events |
| `modelEvents` | `Stream<SDKModelEvent>` | Model events |
| `voiceEvents` | `Stream<SDKVoiceEvent>` | Voice events |
| `storageEvents` | `Stream<SDKStorageEvent>` | Storage events |
| `deviceEvents` | `Stream<SDKDeviceEvent>` | Device events |

**Example:**
```dart
RunAnywhere.events.allEvents.listen((event) {
  print('Event: ${event.type}');
});

RunAnywhere.events.modelEvents.listen((event) {
  if (event is SDKModelLoadCompleted) {
    print('Model loaded: ${event.modelId}');
  }
});
```

### SDKEvent

Base class for all SDK events.

**Properties:**

| Property | Type | Description |
|----------|------|-------------|
| `id` | `String` | Unique event ID |
| `type` | `String` | Event type string |
| `category` | `EventCategory` | Event category |
| `timestamp` | `DateTime` | When event occurred |
| `sessionId` | `String?` | Optional session ID |
| `properties` | `Map<String, String>` | Event properties |

**Event Categories:**

| Category | Events |
|----------|--------|
| `sdk` | Initialization, configuration |
| `llm` | Generation events |
| `stt` | Transcription events |
| `tts` | Synthesis events |
| `vad` | Voice activity detection |
| `voice` | Voice session events |
| `model` | Model load/download events |
| `device` | Device registration |
| `storage` | Cache/storage events |
| `error` | Error events |

---

## Error Handling

### SDKError

SDK error with code and message.

**Factory Methods:**

| Method | Description |
|--------|-------------|
| `SDKError.notInitialized()` | SDK not initialized |
| `SDKError.validationFailed(message)` | Validation error |
| `SDKError.modelNotFound(message)` | Model not found |
| `SDKError.modelNotDownloaded(message)` | Model not downloaded |
| `SDKError.modelLoadFailed(modelId, message)` | Model load failed |
| `SDKError.generationFailed(message)` | Generation failed |
| `SDKError.componentNotReady(message)` | Component not ready |
| `SDKError.sttNotAvailable(message)` | STT not available |
| `SDKError.ttsNotAvailable(message)` | TTS not available |
| `SDKError.voiceAgentNotReady(message)` | Voice agent not ready |

**Example:**
```dart
try {
  await RunAnywhere.loadModel('nonexistent');
} on SDKError catch (e) {
  print('Error: ${e.message}');
  print('Code: ${e.code}');
}
```

---

## Backend Modules

### LlamaCpp

LlamaCpp backend module for LLM text generation.

**Import:**
```dart
import 'package:runanywhere_llamacpp/runanywhere_llamacpp.dart';
```

##### `register()`

Register the LlamaCpp backend.

```dart
static Future<void> register({int priority = 100})
```

##### `addModel()`

Add an LLM model to the registry.

```dart
static void addModel({
  required String id,
  required String name,
  required String url,
  int memoryRequirement = 0,
  bool supportsThinking = false,
})
```

**Example:**
```dart
await LlamaCpp.register();

LlamaCpp.addModel(
  id: 'smollm2-360m-q8_0',
  name: 'SmolLM2 360M Q8_0',
  url: 'https://huggingface.co/.../SmolLM2-360M.Q8_0.gguf',
  memoryRequirement: 500000000,
);
```

### Onnx

ONNX backend module for STT, TTS, and VAD.

**Import:**
```dart
import 'package:runanywhere_onnx/runanywhere_onnx.dart';
```

##### `register()`

Register the ONNX backend.

```dart
static Future<void> register({int priority = 100})
```

##### `addModel()`

Add an ONNX model to the registry.

```dart
static void addModel({
  required String id,
  required String name,
  required String url,
  required ModelCategory modality,
  int memoryRequirement = 0,
})
```

**Example:**
```dart
await Onnx.register();

// Add STT model
Onnx.addModel(
  id: 'sherpa-onnx-whisper-tiny.en',
  name: 'Whisper Tiny English',
  url: 'https://github.com/.../sherpa-onnx-whisper-tiny.en.tar.gz',
  modality: ModelCategory.speechRecognition,
  memoryRequirement: 75000000,
);

// Add TTS model
Onnx.addModel(
  id: 'vits-piper-en_US-amy-medium',
  name: 'Piper Amy (English)',
  url: 'https://github.com/.../vits-piper-en_US-amy-medium.tar.gz',
  modality: ModelCategory.speechSynthesis,
  memoryRequirement: 50000000,
);
```

---

## Configuration

### SDKEnvironment

SDK environment enum.

```dart
enum SDKEnvironment {
  development,  // Development mode (no API key needed)
  staging,      // Staging environment
  production,   // Production environment
}
```

**Properties:**
- `description` – Human-readable description

---

## Complete Example

```dart
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_llamacpp/runanywhere_llamacpp.dart';
import 'package:runanywhere_onnx/runanywhere_onnx.dart';

Future<void> main() async {
  // 1. Initialize SDK
  await RunAnywhere.initialize();

  // 2. Register backends
  await LlamaCpp.register();
  await Onnx.register();

  // 3. Add models
  LlamaCpp.addModel(
    id: 'smollm2',
    name: 'SmolLM2 360M',
    url: 'https://huggingface.co/.../SmolLM2-360M.Q8_0.gguf',
    memoryRequirement: 500000000,
  );

  Onnx.addModel(
    id: 'whisper-tiny',
    name: 'Whisper Tiny',
    url: 'https://github.com/.../sherpa-onnx-whisper-tiny.en.tar.gz',
    modality: ModelCategory.speechRecognition,
    memoryRequirement: 75000000,
  );

  Onnx.addModel(
    id: 'piper-amy',
    name: 'Piper Amy',
    url: 'https://github.com/.../vits-piper-en_US-amy-medium.tar.gz',
    modality: ModelCategory.speechSynthesis,
    memoryRequirement: 50000000,
  );

  // 4. Download models
  await for (final p in RunAnywhere.downloadModel('smollm2')) {
    print('LLM: ${(p.percentage * 100).toStringAsFixed(1)}%');
    if (p.state.isCompleted) break;
  }

  await for (final p in RunAnywhere.downloadModel('whisper-tiny')) {
    print('STT: ${(p.percentage * 100).toStringAsFixed(1)}%');
    if (p.state.isCompleted) break;
  }

  await for (final p in RunAnywhere.downloadModel('piper-amy')) {
    print('TTS: ${(p.percentage * 100).toStringAsFixed(1)}%');
    if (p.state.isCompleted) break;
  }

  // 5. Load models
  await RunAnywhere.loadModel('smollm2');
  await RunAnywhere.loadSTTModel('whisper-tiny');
  await RunAnywhere.loadTTSVoice('piper-amy');

  // 6. Use LLM
  final response = await RunAnywhere.chat('Hello!');
  print('AI: $response');

  // 7. Use Voice Agent
  if (RunAnywhere.isVoiceAgentReady) {
    final session = await RunAnywhere.startVoiceSession();

    session.events.listen((event) {
      if (event is VoiceSessionTurnCompleted) {
        print('User: ${event.transcript}');
        print('AI: ${event.response}');
      }
    });

    // Run for a while...
    await Future.delayed(Duration(seconds: 30));
    session.stop();
  }
}
```

---

## See Also

- [README.md](README.md) – Getting started guide
- [Flutter Starter Example](https://github.com/RunanywhereAI/flutter-starter-example) – Minimal starter project

## Packages on pub.dev

- [runanywhere](https://pub.dev/packages/runanywhere) – Core SDK
- [runanywhere_llamacpp](https://pub.dev/packages/runanywhere_llamacpp) – LLM backend
- [runanywhere_onnx](https://pub.dev/packages/runanywhere_onnx) – STT/TTS/VAD backend
