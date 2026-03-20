# RunAnywhere Flutter SDK

Cross-platform Flutter SDK for on-device AI inference. Supports iOS and Android with native C++ backends via Dart FFI.

## Installation

### pubspec.yaml

```yaml
dependencies:
  # Core SDK (required)
  runanywhere: ^0.17.0

  # Backend modules (pick what you need)
  runanywhere_llamacpp: ^0.16.0   # LLM text generation (GGUF models)
  runanywhere_onnx: ^0.16.0       # STT, TTS, VAD (ONNX Runtime)
  runanywhere_genie: ^0.1.2       # Qualcomm NPU inference
```

## Platform Requirements

| Platform | Requirement |
|----------|-------------|
| Flutter | >= 3.10.0 |
| iOS | 13.0+ |
| macOS | 10.15+ |
| Android Min SDK | 24 |
| Dart | >= 3.0.0 |

## Quick Start

```dart
import 'package:runanywhere/runanywhere.dart';

// 1. Initialize SDK
await RunAnywhere.initialize(environment: SDKEnvironment.development);

// 2. Register backends
await LlamaCpp.register(priority: 100);
await ONNX.register(priority: 100);

// 3. Register a model
LlamaCpp.addModel(
  id: 'qwen3-4b-q4_k_m',
  name: 'Qwen3 4B',
  url: 'https://huggingface.co/.../Qwen3-4B-Q4_K_M.gguf',
  memoryRequirement: 2800000000,
);

// 4. Download and load
await for (final progress in RunAnywhereStorage.downloadModel('qwen3-4b-q4_k_m')) {
  print('${(progress.overallProgress * 100).toInt()}%');
}
await RunAnywhere.loadModel('qwen3-4b-q4_k_m');

// 5. Generate text
final response = await RunAnywhere.chat('Hello!');
print(response);
```

## Architecture

### Package Structure

```
runanywhere-flutter/
├── packages/
│   ├── runanywhere/              # Core SDK (RACommons FFI bindings)
│   │   ├── lib/
│   │   │   ├── core/             # Types, enums, NPU chip
│   │   │   ├── native/           # Dart FFI bridge to C++
│   │   │   ├── public/           # RunAnywhere class + extensions
│   │   │   └── runanywhere.dart  # Barrel export
│   │   ├── ios/                  # XCFramework (RACommons)
│   │   └── android/              # JNI libs (librac_commons.so)
│   ├── runanywhere_llamacpp/     # llama.cpp backend
│   │   ├── ios/                  # RABackendLLAMACPP.xcframework
│   │   └── android/              # librac_backend_llamacpp.so
│   └── runanywhere_onnx/         # ONNX Runtime backend
│       ├── ios/                  # RABackendONNX.xcframework + onnxruntime
│       └── android/              # librac_backend_onnx.so + libonnxruntime.so
```

### Native Library Loading

- **iOS**: `DynamicLibrary.executable()` — XCFrameworks statically linked
- **Android**: `DynamicLibrary.open('librac_commons.so')` — from jniLibs

---

## API Reference

### SDK Lifecycle

```dart
// Initialize
static Future<void> RunAnywhere.initialize({
  String? apiKey,
  String? baseURL,
  SDKEnvironment environment = SDKEnvironment.development,
})

// State
static bool get isSDKInitialized
static bool get isActive
static String get version
static SDKEnvironment? get environment
static EventBus get events
```

### Text Generation (LLM)

```dart
// Simple chat
static Future<String> RunAnywhere.chat(String prompt)

// Full generation with metrics
static Future<LLMGenerationResult> RunAnywhere.generate(
  String prompt, {
  LLMGenerationOptions? options,
})

// Streaming
static Future<LLMStreamingResult> RunAnywhere.generateStream(
  String prompt, {
  LLMGenerationOptions? options,
})

// Model management
static Future<void> RunAnywhere.loadModel(String modelId)
static Future<void> RunAnywhere.unloadModel()
static bool get isModelLoaded
static String? get currentModelId
```

**Generation Options:**
```dart
class LLMGenerationOptions {
  final int maxTokens;           // default: 100
  final double temperature;       // default: 0.8
  final double topP;             // default: 1.0
  final List<String> stopSequences;
  final bool streamingEnabled;
  final InferenceFramework? preferredFramework;
  final String? systemPrompt;
  final StructuredOutputConfig? structuredOutput;
}
```

**Generation Result:**
```dart
class LLMGenerationResult {
  final String text;
  final String? thinkingContent;
  final int tokensUsed;
  final String modelUsed;
  final double latencyMs;
  final double tokensPerSecond;
  final double? timeToFirstTokenMs;
  final int thinkingTokens;
  final int responseTokens;
}
```

**Streaming Result:**
```dart
class LLMStreamingResult {
  final Stream<String> stream;          // Token-by-token
  final Future<LLMGenerationResult> result;  // Final metrics
  final void Function() cancel;
}
```

### Speech-to-Text (STT)

```dart
static Future<String> RunAnywhere.transcribe(Uint8List audioData)
static Future<STTResult> RunAnywhere.transcribeWithResult(Uint8List audioData)
static Future<void> RunAnywhere.loadSTTModel(String modelId)
static Future<void> RunAnywhere.unloadSTTModel()
static bool get isSTTModelLoaded
```

### Text-to-Speech (TTS)

```dart
static Future<TTSResult> RunAnywhere.synthesize(
  String text, {
  double rate = 1.0,
  double pitch = 1.0,
  double volume = 1.0,
})
static Future<void> RunAnywhere.loadTTSVoice(String voiceId)
static Future<void> RunAnywhere.unloadTTSVoice()
static bool get isTTSVoiceLoaded
```

**TTS Result:**
```dart
class TTSResult {
  final Float32List samples;    // PCM audio samples
  final int sampleRate;
  final int durationMs;
  double get durationSeconds;
  int get numSamples;
}
```

### Vision Language Models (VLM)

```dart
// Simple
static Future<String> RunAnywhere.describeImage(
  VLMImage image, {
  String prompt = "What's in this image?",
})

static Future<String> RunAnywhere.askAboutImage(
  String question, {
  required VLMImage image,
})

// Full with metrics
static Future<VLMResult> RunAnywhere.processImage(
  VLMImage image, {
  required String prompt,
  int maxTokens = 2048,
  double temperature = 0.7,
})

// Streaming
static Future<VLMStreamingResult> RunAnywhere.processImageStream(
  VLMImage image, {
  required String prompt,
})

// Image construction
VLMImage.filePath(String path)
VLMImage.rgbPixels(Uint8List data, {required int width, required int height})
VLMImage.base64(String encoded)
```

### Voice Agent

```dart
// Start interactive voice session
static Future<VoiceSessionHandle> RunAnywhere.startVoiceSession({
  VoiceSessionConfig config = VoiceSessionConfig.defaultConfig,
})

// Session config
class VoiceSessionConfig {
  final double silenceDuration;    // default: 1.5s
  final double speechThreshold;    // default: 0.03
  final bool autoPlayTTS;          // default: true
  final bool continuousMode;       // default: true
}

// Session events (sealed class)
VoiceSessionStarted
VoiceSessionListening(double audioLevel)
VoiceSessionSpeechStarted
VoiceSessionProcessing
VoiceSessionTranscribed(String text)
VoiceSessionResponded(String text)
VoiceSessionSpeaking
VoiceSessionTurnCompleted(...)
VoiceSessionStopped
VoiceSessionError(String message)
```

### Tool Calling

```dart
// Register tools
static void RunAnywhereToolCalling.registerTool(
  ToolDefinition definition,
  ToolExecutor executor,
)

// Generate with tool use
static Future<ToolCallingResult> RunAnywhereToolCalling.generateWithTools(
  String prompt, {
  ToolCallingOptions? options,
})

// Tool definition
class ToolDefinition {
  final String name;
  final String description;
  final List<ToolParameter> parameters;
}

// Tool calling formats
ToolCallFormatName.defaultFormat  // JSON format
ToolCallFormatName.lfm2          // Pythonic format (for LFM2-Tool)
```

### Model Management

```dart
// Discovery
static Future<List<ModelInfo>> RunAnywhere.availableModels()

// Download with progress
static Stream<ModelDownloadProgress> RunAnywhereStorage.downloadModel(String modelId)

// Stages
enum ModelDownloadStage { downloading, extracting, validating, complete }
```

### NPU Chip Detection

```dart
// Detect Qualcomm NPU chipset (Android only)
static Future<NPUChip?> RunAnywhereDevice.getChip()

enum NPUChip {
  snapdragon8Elite('8elite', 'Snapdragon 8 Elite', 'SM8750', '8elite'),
  snapdragon8EliteGen5('8elite-gen5', 'Snapdragon 8 Elite Gen 5', 'SM8850', '8elite-gen5');

  String downloadUrl(String modelSlug, {String quant = 'w4a16'});
  static NPUChip? fromSocModel(String socModel);
}
```

**Usage:**
```dart
final chip = await RunAnywhereDevice.getChip();
if (chip != null) {
  final url = chip.downloadUrl('qwen3-4b');  // default w4a16
  final url2 = chip.downloadUrl('qwen2.5-7b-instruct', quant: 'w8a16');
}
```

### Frameworks Registration

```dart
// Query available frameworks
static Future<List<InferenceFramework>> RunAnywhereFrameworks.getRegisteredFrameworks()
static Future<bool> RunAnywhereFrameworks.isFrameworkAvailable(InferenceFramework framework)
static Future<List<ModelInfo>> RunAnywhereFrameworks.modelsForFramework(InferenceFramework framework)
```

### Event Bus

```dart
// Subscribe to SDK events
RunAnywhere.events.events.listen((SDKEvent event) {
  // handle event
});

// Event categories
enum EventCategory {
  sdk, llm, stt, tts, vad, voice, model, device, network, storage, error, rag
}
```

---

## Core Types

### Inference Frameworks

```dart
enum InferenceFramework {
  onnx,             // ONNX Runtime — STT, TTS, VAD, embeddings
  llamaCpp,         // llama.cpp — LLM, VLM (GGUF models)
  genie,            // Qualcomm Genie — NPU inference
  foundationModels, // Apple Foundation Models
  systemTTS,        // System TTS
  fluidAudio,
  builtIn,
  none,
  unknown,
}
```

### Model Categories

```dart
enum ModelCategory {
  language,
  speechRecognition,
  speechSynthesis,
  vision,
  imageGeneration,
  multimodal,
  audio,
  embedding,
}
```

### SDK Environments

```dart
enum SDKEnvironment {
  development,  // Local dev, debug logging
  staging,      // Testing with real services
  production,   // Live environment
}
```

### Error Handling

```dart
class SDKError implements Exception {
  final String message;
  final SDKErrorType type;
  final Object? underlyingError;
  final ErrorContext? context;

  // 40+ factory constructors:
  SDKError.notInitialized()
  SDKError.modelNotFound(modelId)
  SDKError.generationFailed(message)
  SDKError.networkError(message)
  // ... etc
}
```

---

## Build System

### Development Setup

```bash
cd sdk/runanywhere-flutter

# First-time setup (builds native libs)
./scripts/build-flutter.sh --setup

# After C++ changes
./scripts/build-flutter.sh --local --rebuild-commons

# Switch to remote mode (use pre-built libs)
./scripts/build-flutter.sh --remote
```

### Running the Example App

```bash
cd examples/flutter/RunAnywhereAI
flutter pub get
flutter run  # Android
# iOS:
cd ios && pod install && cd ..
flutter run
```

### Monorepo Management

Uses [Melos](https://melos.invertase.dev/) for workspace management:

```bash
melos bootstrap        # Install all dependencies
melos run analyze      # Run dart analyze on all packages
melos run test         # Run tests on all packages
```

### Native Library Modes

```bash
# Local development (build from source)
RA_TEST_LOCAL=1 flutter run

# Remote mode (download pre-built)
# Default behavior — downloads from GitHub releases
```

---

## Genie NPU Models

Available on HuggingFace (`runanywhere/genie-npu-models`):

| Model | Slug | Quant | Chips | Size |
|-------|------|-------|-------|------|
| Qwen3 4B | `qwen3-4b` | w4a16 | Gen 5 | 2.5 GB |
| Llama 3.2 1B | `llama3.2-1b-instruct` | w4a16 | Both | 1.3 GB |
| SEA-LION v3.5 8B | `sea-lion3.5-8b-instruct` | w4a16 | Both | 4.5 GB |
| Qwen 2.5 7B | `qwen2.5-7b-instruct` | w8a16 | 8 Elite | 3.9 GB |

**Registering Genie models:**
```dart
if (Genie.isAvailable) {
  await Genie.register(priority: 200);
  final chip = await RunAnywhereDevice.getChip();
  if (chip != null) {
    Genie.addModel(
      id: 'qwen3-4b-npu-${chip.identifier}',
      name: 'Qwen3 4B (NPU - ${chip.displayName})',
      url: chip.downloadUrl('qwen3-4b'),
      memoryRequirement: 2800000000,
    );
  }
}
```
