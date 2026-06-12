# RunAnywhere Flutter SDK – API Reference

> Updated: 2026-05-13. This API reference is being kept aligned with the
> current Flutter implementation plan while code is in progress. It should not
> be read as a final validation report until Flutter Android and iOS E2E pass.

Public API documentation for the RunAnywhere Flutter SDK.

All entry points hang off the `RunAnywhere` static namespace. Each capability
is a static property on that namespace, so usage looks like
`RunAnywhere.<capability>.<method>(...)`.

```dart
import 'package:runanywhere/runanywhere.dart';
```

---

## Table of Contents

1. [Entry Point — `RunAnywhere`](#entry-point--runanywhere)
2. [Capabilities](#capabilities)
   - [`llm` — Language Model](#llm--language-model)
   - [`stt` — Speech-to-Text](#stt--speech-to-text)
   - [`tts` — Text-to-Speech](#tts--text-to-speech)
   - [`vad` — Voice Activity Detection](#vad--voice-activity-detection)
   - [`vlm` — Vision Language Model](#vlm--vision-language-model)
   - [`voice` — Voice Agent](#voice--voice-agent)
   - [`models` — Model Registry](#models--model-registry)
   - [`downloads` — Downloads + Storage](#downloads--downloads--storage)
   - [`tools` — Tool Calling](#tools--tool-calling)
   - [`rag` — Retrieval-Augmented Generation](#rag--retrieval-augmented-generation)
   - [`solutions` — Solution YAML Runner](#solutions--solution-yaml-runner)
   - [`hardware` — Hardware Info](#hardware--hardware-info)
3. [Backend Modules](#backend-modules)
4. [Proto-Generated Types](#proto-generated-types)
5. [Errors](#errors)
6. [Events](#events)
7. [Configuration](#configuration)

---

## Entry Point — `RunAnywhere`

```dart
abstract final class RunAnywhere {
  // Lifecycle
  static bool get isInitialized;
  static bool get isActive;
  static bool get areServicesReady;
  static String get version;
  static SDKEnvironment? get environment;

  // Identity (set after authentication)
  static String get deviceId;
  static String? get userId;
  static String? get organizationId;
  static bool get isAuthenticated;

  // Capability accessors
  static RunAnywhereLLM            get llm;
  static RunAnywhereSTT            get stt;
  static RunAnywhereTTS            get tts;
  static RunAnywhereVAD            get vad;
  static RunAnywhereVLM            get vlm;
  static RunAnywhereVLM            get visionLanguage;
  static RunAnywhereVoice          get voice;
  static RunAnywhereModels         get models;
  static RunAnywhereModelLifecycle get modelLifecycle;
  static RunAnywhereDownloads      get downloads;
  static RunAnywhereTools          get tools;
  static RunAnywhereRAG            get rag;
  static RunAnywhereSolutions      get solutions;
  static RunAnywhereEmbeddings     get embeddings;
  static RunAnywhereLoRACapability get lora;
  static RunAnywhereHardware       get hardware;
  static RunAnywherePluginLoader   get pluginLoader;

  // Convenience model-state accessors
  static bool get isLLMModelLoaded;
  static bool get isSTTModelLoaded;
  static bool get isTTSVoiceLoaded;
  static bool get isVADModelLoaded;
  static Future<ModelInfo?> get currentLLMModel;

  // SDK event stream (proto-typed)
  static EventBus get events;
}
```

### `initialize`

Two-phase init: Phase 1 (sync — load lib, register adapter, configure logging,
`rac_sdk_init_phase1_proto`) runs immediately; Phase 2 (`rac_sdk_init_phase2_proto`,
device registration + auth) runs in the background.

```dart
Future<void> initialize({
  String? apiKey,
  String? baseURL,
  SDKEnvironment environment = SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
});
```

Offline inference works without Phase 2 completing. Call `completeServicesInitialization()`
to wait for Phase 2 if you need authentication or device registration to be done.

```dart
await RunAnywhere.initialize();  // development mode

await RunAnywhere.initialize(
  apiKey: '<YOUR_API_KEY>',
  baseURL: 'https://api.runanywhere.ai',
  environment: SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
);
```

---

## Capabilities

### `llm` — Language Model

```dart
class RunAnywhereLLM {
  bool get isLoaded;
  String? get currentModelId;

  Future<void> load(String modelId);
  Future<void> unload();

  Future<LLMGenerationResult> generate(String prompt, LLMGenerationOptions options);
  Stream<LLMStreamEvent>      generateStream(String prompt, LLMGenerationOptions options);

  Future<void> cancel();
}
```

```dart
await RunAnywhere.llm.load('smollm2-360m-q8_0');

// Non-streaming
final result = await RunAnywhere.llm.generate(
  'Explain quantum computing.',
  LLMGenerationOptions(maxTokens: 200, temperature: 0.7),
);

// Streaming
final stream = RunAnywhere.llm.generateStream(
  'Tell me a story.',
  LLMGenerationOptions(maxTokens: 150),
);
await for (final event in stream) {
  if (event.isFinal) break;
  if (event.token.isNotEmpty) stdout.write(event.token);
}
```

### `stt` — Speech-to-Text

```dart
class RunAnywhereSTT {
  bool get isLoaded;

  Future<void> load(String modelId);
  Future<void> unload();

  Future<STTOutput>          transcribe(Uint8List audio, [STTOptions? options]);
  Stream<STTPartialResult>   transcribeStream(Uint8List audio, [STTOptions? options]);
}
```

Audio: PCM16, 16 kHz mono. `STTOutput` is proto-typed (`text`, `confidence`, `segments`,
`detectedLanguage`).

```dart
await RunAnywhere.stt.load('sherpa-onnx-whisper-tiny.en');
final result = await RunAnywhere.stt.transcribe(audioBytes);
print(result.text);
```

### `tts` — Text-to-Speech

```dart
class RunAnywhereTTS {
  bool get isLoaded;

  Future<void> loadVoice(String voiceId);
  Future<void> unloadVoice();

  Future<TTSOutput>       synthesize(String text, [TTSOptions? options]);
  Future<TTSSpeakResult>  speak(String text, [TTSOptions? options]);
  Future<void>            stopSynthesis();
}
```

```dart
await RunAnywhere.tts.loadVoice('vits-piper-en_US-lessac-medium');
final result = await RunAnywhere.tts.synthesize(
  'Hello world.',
  TTSOptions(rate: 1.0, pitch: 1.0),
);
// result.audio = PCM16 Uint8List; result.sampleRate = 22050 typically
```

### `vad` — Voice Activity Detection

```dart
class RunAnywhereVAD {
  bool get isModelLoaded;
  Future<void> loadModel(String modelId);
  Future<void> unloadModel();
  Future<VADResult> process(Uint8List audioChunk, [VADOptions? options]);
}
```

### `vlm` — Vision Language Model

```dart
class RunAnywhereVLM {
  bool get isLoaded;
  Future<void> load(String modelId);
  Future<void> unload();

  Stream<VLMStreamEvent> processImageStream(VLMImage image, String prompt, [VLMOptions? options]);
}
```

Multimodal models (e.g. SmolVLM, Qwen2-VL) accept an image + text prompt and stream
tokenized responses.

### `voice` — Voice Agent

End-to-end voice pipeline: VAD → STT → LLM → TTS.

```dart
class RunAnywhereVoice {
  Future<void>              initializeWithLoadedModels();
  Stream<VoiceEvent>        eventStream();    // proto-typed events
  Future<void>              start();
  Future<void>              stop();
}
```

`VoiceEvent` has oneof payload: `state`, `vad`, `userSaid`, `assistantToken`, `audio`, `error`.

```dart
await RunAnywhere.stt.load('sherpa-onnx-whisper-tiny.en');
await RunAnywhere.llm.load('smollm2-360m-q8_0');
await RunAnywhere.tts.loadVoice('vits-piper-en_US-lessac-medium');
await RunAnywhere.voice.initializeWithLoadedModels();

final sub = RunAnywhere.voice.eventStream().listen((e) {
  if (e.hasUserSaid())        print('User: ${e.userSaid.text}');
  if (e.hasAssistantToken())  stdout.write(e.assistantToken.text);
});

await RunAnywhere.voice.start();
// ... later
await RunAnywhere.voice.stop();
await sub.cancel();
```

### `models` — Model Registry

```dart
class RunAnywhereModels {
  ModelInfo register({
    required String id,
    required String name,
    required Uri url,
    required InferenceFramework framework,
    ModelCategory modality = ModelCategory.MODEL_CATEGORY_LANGUAGE,
    ArchiveArtifact? artifactType,
    int? memoryRequirement,
    bool supportsThinking = false,
  });

  ModelInfo registerMultiFile({
    required String id,
    required String name,
    required List<ModelFileDescriptor> files,
    required InferenceFramework framework,
    ModelCategory modality = ModelCategory.MODEL_CATEGORY_LANGUAGE,
    int? memoryRequirement,
  });

  Future<List<ModelInfo>> available();
}
```

Single-file:

```dart
RunAnywhere.models.register(
  id: 'smollm2-360m-q8_0',
  name: 'SmolLM2 360M Q8_0',
  url: Uri.parse('https://huggingface.co/.../SmolLM2-360M.Q8_0.gguf'),
  framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
  memoryRequirement: 500000000,
);
```

Multi-file (VLM with `mmproj` companion, RAG embeddings with vocab.txt, etc.):

```dart
RunAnywhere.models.registerMultiFile(
  id: 'qwen2-vl-2b-instruct-q4_k_m',
  name: 'Qwen2-VL 2B Instruct',
  files: [
    ModelFileDescriptor(filename: 'Qwen2-VL-2B-Instruct-Q4_K_M.gguf', url: '...', isRequired: true),
    ModelFileDescriptor(filename: 'mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf', url: '...', isRequired: true),
  ],
  framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
  modality: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
  memoryRequirement: 1800000000,
);
```

### `downloads` — Downloads + Storage

```dart
class RunAnywhereDownloads {
  Stream<DownloadProgress>        start(String modelId);
  Future<void>                    cancel(String modelId);
  Future<void>                    delete(String modelId);
  Future<List<StoredModel>>       list();
  Future<StorageInfo>             getStorageInfo();
}
```

```dart
final stream = RunAnywhere.downloads.start('smollm2-360m-q8_0');
await for (final p in stream) {
  final pct = (p.stageProgress * 100).clamp(0.0, 100.0);
  print('${p.stage}: ${pct.toStringAsFixed(1)}%');
  if (p.stage == DownloadStage.DOWNLOAD_STAGE_COMPLETED) break;
}
```

### `tools` — Tool Calling

```dart
class RunAnywhereTools {
  void register({required String name, required String description, required Map<String, Object?> parametersSchema, required Future<Object?> Function(Map<String, Object?>) handler});
  Future<ToolCallResult> generateWithTools(String prompt, {ToolCallFormatNames? format});
}
```

### `rag` — Retrieval-Augmented Generation

```dart
class RunAnywhereRAG {
  Future<String> createPipeline({required String embeddingModelId, RAGConfiguration? configuration});
  Future<void>   ingest(String pipelineId, List<RAGDocument> documents);
  Stream<RAGStreamEvent> query(String pipelineId, String prompt, {int topK = 4});
  Future<void>   destroyPipeline(String pipelineId);
}
```

### `solutions` — Solution YAML Runner

```dart
class RunAnywhereSolutions {
  Future<SolutionResult> run({required String yaml});
}
```

### `hardware` — Hardware Info

```dart
class RunAnywhereHardware {
  Future<HardwareProfile> getProfile();
  Future<ChipEnum>         getChipEnum();
}
```

---

## Backend Modules

Backends are separate Flutter packages that register engine vtables with the C++
core. Register them before downloading/loading models.

### `LlamaCpp` — `package:runanywhere_llamacpp/runanywhere_llamacpp.dart`

LLM + VLM via GGUF / llama.cpp.

```dart
await LlamaCpp.register();   // registers llamacpp + llamacpp_vlm vtables
```

### `Onnx` — `package:runanywhere_onnx/runanywhere_onnx.dart`

STT (Whisper / Zipformer / Paraformer), TTS (Piper / VITS), VAD (Silero) via Sherpa-ONNX.

```dart
await Onnx.register();
```

### `Genie` — `package:runanywhere_genie/runanywhere_genie.dart`

Qualcomm Genie NPU LLM is currently deferred. Do not treat missing Genie
coverage as an active Flutter gap unless the deferred-backends policy changes.

```dart
// Deferred backend; registration is out of scope for the current Flutter pass.
```

### `RAGModule`

```dart
await RAGModule.register();   // enables RAG capability
```

---

## Proto-Generated Types

All public API types are protobuf-generated from `idl/*.proto`. They live under
`lib/generated/` and are re-exported through `runanywhere_protos.dart`.

| Type | Proto enum values |
|------|-------------------|
| `SDKEnvironment` | `SDK_ENVIRONMENT_DEVELOPMENT`, `SDK_ENVIRONMENT_STAGING`, `SDK_ENVIRONMENT_PRODUCTION` |
| `InferenceFramework` | `INFERENCE_FRAMEWORK_LLAMA_CPP`, `INFERENCE_FRAMEWORK_SHERPA`, `INFERENCE_FRAMEWORK_ONNX`, `INFERENCE_FRAMEWORK_SYSTEM_TTS`, ... |
| `ModelCategory` | `MODEL_CATEGORY_LANGUAGE`, `MODEL_CATEGORY_SPEECH_RECOGNITION`, `MODEL_CATEGORY_SPEECH_SYNTHESIS`, `MODEL_CATEGORY_MULTIMODAL`, `MODEL_CATEGORY_EMBEDDING`, `MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION`, ... |
| `DownloadStage` | `DOWNLOAD_STAGE_UNSPECIFIED`, `DOWNLOAD_STAGE_DOWNLOADING`, `DOWNLOAD_STAGE_EXTRACTING`, `DOWNLOAD_STAGE_COMPLETED` |
| `ArchiveType` | `ARCHIVE_TYPE_NONE`, `ARCHIVE_TYPE_TAR_GZ`, `ARCHIVE_TYPE_TAR_BZ2`, `ARCHIVE_TYPE_ZIP` |
| `ArchiveStructure` | `ARCHIVE_STRUCTURE_DIRECTORY_BASED`, `ARCHIVE_STRUCTURE_FLAT` |

Never hand-edit enum values — modify the `.proto` and regenerate.

---

## Errors

All SDK errors surface as `SDKException` — a proto-backed unified error type with
40+ factory constructors (e.g., `SDKException.notInitialized`, `SDKException.modelNotFound`,
`SDKException.componentNotReady`, `SDKException.downloadFailed`, ...).

```dart
try {
  await RunAnywhere.llm.load('nonexistent');
} on SDKException catch (e) {
  print('Error [${e.errorCode}]: ${e.message}');
}
```

`SDKException.errorCode` is a proto enum (`SDKErrorCode`) — branch on it instead
of string-matching messages.

---

## Events

Subscribe to SDK-level lifecycle events:

```dart
RunAnywhere.events.allEvents.listen((event) {
  // event is proto-typed SDKEvent with oneof payload (init/model/download/...)
  print(event);
});
```

The event stream is a pure `dart:async` broadcast stream. (`rxdart` is not a dependency.)

---

## Configuration

### Environment

```dart
enum SDKEnvironment {
  SDK_ENVIRONMENT_DEVELOPMENT,  // local-only, verbose logging, no auth
  SDK_ENVIRONMENT_STAGING,      // real services for testing
  SDK_ENVIRONMENT_PRODUCTION,   // minimal logging, full auth, telemetry
}
```

### Generation Options

```dart
LLMGenerationOptions(
  maxTokens: 256,
  temperature: 0.7,
  topP: 0.95,
  stopSequences: ['END'],
  systemPrompt: 'You are a helpful assistant.',
  jsonSchema: '{...}',     // optional, for structured output
);
```

### STT / TTS / VAD / VLM Options

Each capability has a proto-typed options struct: `STTOptions`, `TTSOptions`,
`VADOptions`, `VLMOptions`. Fields are documented in the generated `.pb.dart` files.

---

## Imports

A single barrel imports everything:

```dart
import 'package:runanywhere/runanywhere.dart';
```

This re-exports the SDK entry point, all capability classes, proto-generated types,
events, and configuration.

Backend modules each export their own `register()`:

```dart
import 'package:runanywhere_llamacpp/runanywhere_llamacpp.dart';
import 'package:runanywhere_onnx/runanywhere_onnx.dart';
```

---

## Versioning

- Canonical SDK version: `RunAnywhere.version` (currently `0.19.13`).
- Native commons version: vendored `RACommons` build (`0.1.6`).
- llama.cpp engine: `b7199`.
- ONNX Runtime: `1.23.2`.

All four Flutter packages share the same version, bumped together via the
root `scripts/release/sync-versions.sh`.
