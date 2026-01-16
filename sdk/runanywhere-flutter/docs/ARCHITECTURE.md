# RunAnywhere Flutter SDK – Architecture

## 1. Overview

The RunAnywhere Flutter SDK is a production-grade, on-device AI SDK designed to provide modular, low-latency AI capabilities for Flutter applications on iOS and Android. The SDK follows a capability-based architecture with a **modular backend design** using `runanywhere-commons` (C++) for shared functionality and platform-specific bindings.

The architecture emphasizes:
- **Modular Backends**: Separate packages for each backend (LlamaCPP, ONNX) - only include what you need
- **C++ Commons Layer**: Shared C++ library (`runanywhere-commons`) handles backend registration, events, and common APIs
- **Dart Orchestration**: Dart SDK provides public APIs and coordinates native operations via FFI
- **Low Latency**: All inference runs on-device with Metal (iOS) and NEON (Android) acceleration
- **Lazy Initialization**: Network services and model discovery happen lazily on first use
- **Event-Driven Design**: Comprehensive event system for UI reactivity and analytics

---

## 2. Multi-Package Architecture

### 2.1 Package Structure

```
runanywhere-flutter/
├── packages/
│   ├── runanywhere/              # Core SDK (required)
│   │   ├── lib/
│   │   │   ├── public/           # Public API surface
│   │   │   ├── core/             # Core types, protocols
│   │   │   ├── features/         # LLM, STT, TTS, VAD implementations
│   │   │   ├── foundation/       # Configuration, DI, errors, logging
│   │   │   ├── infrastructure/   # Device, download, events, files
│   │   │   ├── data/             # Network layer
│   │   │   ├── native/           # FFI bindings to C++
│   │   │   └── capabilities/     # Voice session handling
│   │   ├── ios/                  # iOS plugin + RACommons.xcframework
│   │   └── android/              # Android plugin + JNI libraries
│   │
│   ├── runanywhere_llamacpp/     # LlamaCpp backend (LLM)
│   │   ├── lib/                  # Dart bindings + model registration
│   │   ├── ios/                  # RABackendLLAMACPP.xcframework
│   │   └── android/              # librac_backend_llamacpp.so
│   │
│   └── runanywhere_onnx/         # ONNX backend (STT/TTS/VAD)
│       ├── lib/                  # Dart bindings + model registration
│       ├── ios/                  # RABackendONNX.xcframework + onnxruntime
│       └── android/              # librac_backend_onnx.so + ONNX Runtime
│
├── melos.yaml                    # Multi-package management
├── scripts/                      # Build scripts
└── analysis_options.yaml         # Shared lint rules
```

### 2.2 Layer Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                      Your Flutter Application                     │
├─────────────────────────────────────────────────────────────────┤
│                    RunAnywhere Flutter SDK                        │
│  ┌─────────────┐  ┌────────────────┐  ┌─────────────────────┐  │
│  │ RunAnywhere │  │   EventBus     │  │   ModelRegistry     │  │
│  │ (Public API)│  │   (Events)     │  │   (Discovery)       │  │
│  └─────────────┘  └────────────────┘  └─────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                    DartBridge (FFI Layer)                         │
│  ┌─────────────┐  ┌────────────────┐  ┌─────────────────────┐  │
│  │DartBridgeLLM│  │ DartBridgeSTT  │  │   DartBridgeTTS     │  │
│  └─────────────┘  └────────────────┘  └─────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                  runanywhere-commons (C++)                        │
│  ┌─────────────┐  ┌────────────────┐  ┌─────────────────────┐  │
│  │ModuleRegistry│ │ServiceRegistry │  │   EventPublisher    │  │
│  └─────────────┘  └────────────────┘  └─────────────────────┘  │
├────────────┬─────────────┬──────────────────────────────────────┤
│  LlamaCPP  │    ONNX     │        (Future Backends...)          │
│  Backend   │   Backend   │                                       │
└────────────┴─────────────┴──────────────────────────────────────┘
```

### 2.3 Binary Size Composition

| Package | iOS Size | Android Size | Provides |
|---------|----------|--------------|----------|
| `runanywhere` | ~5MB | ~3MB | Core SDK, registries, events |
| `runanywhere_llamacpp` | ~15-25MB | ~10-15MB | LLM capability (GGUF) |
| `runanywhere_onnx` | ~50-70MB | ~40-60MB | STT, TTS, VAD (ONNX) |

### 2.4 App Configuration Scenarios

| App Configuration | iOS Total | Android Total | Use Case |
|-------------------|-----------|---------------|----------|
| LLM only | ~20-30MB | ~13-18MB | Chat apps without voice |
| STT/TTS only | ~55-75MB | ~43-63MB | Voice apps without LLM |
| Full (all) | ~70-100MB | ~53-78MB | Complete AI features |

---

## 3. Core SDK Structure

### 3.1 Public API Layer (`lib/public/`)

```
public/
├── runanywhere.dart              # Main entry point (RunAnywhere class)
├── configuration/
│   └── sdk_environment.dart      # SDKEnvironment enum
├── errors/
│   └── errors.dart               # SDKError, error codes
├── events/
│   ├── event_bus.dart            # EventBus singleton
│   └── sdk_event.dart            # SDKEvent base class
├── extensions/
│   ├── runanywhere_frameworks.dart   # Framework extensions
│   ├── runanywhere_logging.dart      # Logging extensions
│   └── runanywhere_storage.dart      # Storage extensions
└── types/
    ├── types.dart                # Re-exports all types
    ├── capability_types.dart     # STTCapability, TTSCapability
    ├── configuration_types.dart  # SDKInitParams
    ├── download_types.dart       # DownloadProgress, DownloadProgressState
    ├── generation_types.dart     # LLMGenerationOptions, LLMGenerationResult
    ├── message_types.dart        # ChatMessage types
    └── voice_agent_types.dart    # VoiceSession types
```

### 3.2 Core Types Layer (`lib/core/`)

```
core/
├── models/
│   └── audio_format.dart         # AudioFormat enum
├── module/
│   └── runanywhere_module.dart   # RunAnywhereModule protocol
├── protocols/
│   └── component/
│       ├── component.dart        # Component protocol
│       └── component_configuration.dart
└── types/
    ├── component_state.dart      # ComponentState enum
    ├── model_types.dart          # ModelInfo, ModelCategory, InferenceFramework
    ├── sdk_component.dart        # SDKComponent enum (llm, stt, tts, vad)
    └── storage_types.dart        # StorageInfo, StoredModel
```

### 3.3 Features Layer (`lib/features/`)

```
features/
├── llm/
│   └── structured_output/
│       ├── generatable.dart      # Generatable mixin
│       ├── generation_hints.dart # GenerationHints
│       ├── stream_accumulator.dart
│       ├── stream_token.dart
│       ├── structured_output.dart
│       └── structured_output_handler.dart
├── stt/
│   └── services/
│       └── audio_capture_manager.dart
├── tts/
│   ├── services/
│   │   └── audio_playback_manager.dart
│   └── system_tts_service.dart   # Fallback to flutter_tts
└── vad/
    ├── simple_energy_vad.dart    # Energy-based VAD
    └── vad_configuration.dart    # VADConfiguration
```

### 3.4 Native Bridge Layer (`lib/native/`)

```
native/
├── dart_bridge.dart              # Main bridge coordinator
├── dart_bridge_device.dart       # Device info bridge
├── dart_bridge_llm.dart          # LLM operations bridge
├── dart_bridge_model_paths.dart  # Model path resolution
├── dart_bridge_model_registry.dart # Model registry bridge
├── dart_bridge_stt.dart          # STT operations bridge
├── dart_bridge_tts.dart          # TTS operations bridge
├── dart_bridge_voice_agent.dart  # Voice agent bridge
├── native_backend.dart           # NativeBackend class
├── platform_loader.dart          # Platform-specific loading
├── ffi_types.dart                # FFI type definitions
└── ... (additional bridge files)
```

---

## 4. Core Components & Responsibilities

### 4.1 RunAnywhere (Public API)

**Purpose**: Single entry point for all SDK operations as a static class.

**Location**: `lib/public/runanywhere.dart`

**Key Responsibilities**:
- SDK initialization with environment configuration
- Model management (register, download, load, unload, delete)
- Text generation (chat, generate, generateStream)
- Speech operations (transcribe, synthesize)
- Voice agent session management
- Storage and analytics info

**Pattern**: All public methods delegate to DartBridge for native operations.

```dart
class RunAnywhere {
  // Initialization
  static Future<void> initialize({...}) async { ... }

  // LLM Operations
  static Future<String> chat(String prompt) async { ... }
  static Future<LLMGenerationResult> generate(String prompt, {...}) async { ... }
  static Future<LLMStreamingResult> generateStream(String prompt, {...}) async { ... }

  // STT Operations
  static Future<String> transcribe(Uint8List audioData) async { ... }

  // TTS Operations
  static Future<TTSResult> synthesize(String text, {...}) async { ... }

  // Voice Agent
  static Future<VoiceSessionHandle> startVoiceSession({...}) async { ... }

  // Model Management
  static Future<List<ModelInfo>> availableModels() async { ... }
  static Stream<DownloadProgress> downloadModel(String modelId) async* { ... }
  static Future<void> loadModel(String modelId) async { ... }
}
```

### 4.2 DartBridge (FFI Layer)

**Purpose**: Coordinates all FFI calls to C++ native libraries.

**Location**: `lib/native/dart_bridge*.dart`

**Sub-components**:

| Bridge | Purpose |
|--------|---------|
| `DartBridgeLLM` | LLM model loading, generation, streaming |
| `DartBridgeSTT` | STT model loading, transcription |
| `DartBridgeTTS` | TTS voice loading, synthesis |
| `DartBridgeModelRegistry` | Model discovery, registration |
| `DartBridgeModelPaths` | Model path resolution |
| `DartBridgeDevice` | Device info retrieval |
| `DartBridgeVoiceAgent` | Voice pipeline orchestration |

**Pattern**: Each bridge manages its own native handle and state.

```dart
class DartBridgeLLM {
  String? _currentModelId;
  bool get isLoaded => _currentModelId != null;

  Future<void> loadModel(String path, String modelId, String name) async {
    final result = _bindings.rac_llm_component_load_model(path, modelId, name);
    if (result != RacResultCode.success) {
      throw NativeBackendException('Failed to load model');
    }
    _currentModelId = modelId;
  }

  Stream<String> generateStream(String prompt, {...}) async* {
    // Yields tokens as they're generated
  }
}
```

### 4.3 Module System

**Purpose**: Pluggable backend modules that provide AI capabilities.

**Protocol**: `RunAnywhereModule` (in `lib/core/module/`)

```dart
abstract class RunAnywhereModule {
  String get moduleId;
  String get moduleName;
  Set<SDKComponent> get capabilities;
  int get defaultPriority;
  InferenceFramework get inferenceFramework;
}
```

**Registration Flow**:
1. App imports module package (`runanywhere_llamacpp`)
2. App calls `LlamaCpp.register()`
3. Module calls C++ `rac_backend_*_register()` via FFI
4. Backend registers its service providers with C++ registry
5. SDK routes operations to registered backends

### 4.4 Event System

**Purpose**: Unified event routing for UI reactivity and analytics.

**Key Types**:
- `EventBus`: Singleton providing public event stream
- `SDKEvent`: Base class for all events
- Various event types (SDKInitializationStarted, SDKModelEvent, etc.)

**Pattern**:
```dart
class EventBus {
  static final EventBus shared = EventBus._();
  final StreamController<SDKEvent> _controller =
      StreamController<SDKEvent>.broadcast();

  Stream<SDKEvent> get events => _controller.stream;

  void publish(SDKEvent event) {
    _controller.add(event);
  }
}
```

### 4.5 Model Management

**Purpose**: Model discovery, registration, download, and persistence.

**Key Types**:
- `ModelInfo`: Immutable model metadata
- `ModelDownloadService`: Download with progress and extraction
- `DartBridgeModelRegistry`: C++ registry bridge

**Model Flow**:
1. Models registered via `RunAnywhere.registerModel()` or `LlamaCpp.addModel()`
2. Registration saves to C++ global registry
3. Download handled by `ModelDownloadService`
4. After download, `localPath` is set in registry
5. Load operations use resolved path from registry

---

## 5. Data & Control Flow

### 5.1 Scenario: Text Generation Request

**App calls**: `await RunAnywhere.chat('Hello!')`

**Flow**:

```
1. RunAnywhere.chat(prompt)
   ├─ Validates SDK is initialized
   ├─ Checks DartBridge.llm.isLoaded
   └─ Calls DartBridge.llm.generate(prompt, options)

2. DartBridge.llm.generate()
   ├─ Calls FFI: rac_llm_component_generate(prompt, maxTokens, temp)
   ├─ C++ processes request via registered LlamaCPP backend
   ├─ Returns LLMGenerationResult with text and metrics
   └─ Publishes SDKModelEvent.generationCompleted

3. Events Published:
   └─ SDKModelEvent (captured by EventBus subscribers)
```

### 5.2 Scenario: Streaming Generation

**App calls**: `await RunAnywhere.generateStream('Write a poem')`

**Flow**:

```
1. RunAnywhere.generateStream(prompt, options)
   ├─ Creates StreamController<String>.broadcast()
   ├─ Calls DartBridge.llm.generateStream(prompt, options)
   └─ Returns LLMStreamingResult(stream, result future, cancel fn)

2. DartBridge.llm.generateStream()
   ├─ Calls FFI: rac_llm_component_generate_stream_start()
   ├─ Polls for tokens in isolate/async loop
   ├─ Yields tokens to StreamController
   └─ Completes when generation ends or cancelled

3. App consumes:
   await for (final token in result.stream) {
     updateUI(token);  // Real-time token display
   }
   final metrics = await result.result;  // Final stats
```

### 5.3 Scenario: Model Loading

**App calls**: `await RunAnywhere.loadModel('smollm2-360m-q8_0')`

**Flow**:

```
1. RunAnywhere.loadModel(modelId)
   ├─ Validates SDK initialized
   ├─ Gets model from availableModels()
   ├─ Verifies model.localPath is set (downloaded)
   ├─ Resolves actual file path via DartBridge.modelPaths
   └─ Calls DartBridge.llm.loadModel(resolvedPath, modelId, name)

2. DartBridge.llm.loadModel()
   ├─ Unloads current model if any
   ├─ Calls FFI: rac_llm_component_load_model(path, id, name)
   ├─ C++ LlamaCPP backend loads GGUF model
   └─ Updates _currentModelId on success

3. Events Published:
   ├─ SDKModelEvent.loadStarted(modelId)
   └─ SDKModelEvent.loadCompleted(modelId) or loadFailed
```

### 5.4 Scenario: Voice Agent Turn

**App calls**: `session.processVoiceTurn(audioData)`

**Flow**:

```
1. VoiceSessionHandle receives audio
   ├─ Validates voice agent is ready (STT + LLM + TTS loaded)
   └─ Calls DartBridge.voiceAgent.processVoiceTurn(audioData)

2. DartBridge.voiceAgent.processVoiceTurn()
   ├─ Step 1: STT - rac_stt_component_transcribe(audioData) → text
   ├─ Step 2: LLM - rac_llm_component_generate(text) → response
   ├─ Step 3: TTS - rac_tts_component_synthesize(response) → audio
   └─ Returns VoiceAgentProcessResult

3. Session emits events:
   ├─ VoiceSessionTranscribed(text)
   ├─ VoiceSessionResponded(response)
   └─ VoiceSessionTurnCompleted(transcript, response, audio)
```

---

## 6. Concurrency & Threading Model

### 6.1 Isolate Usage

Flutter's single-threaded UI model requires careful handling of CPU-intensive operations:

- **FFI calls** run on the platform thread (iOS main, Android main/JNI)
- **Long operations** (model loading, inference) block the calling thread
- **Streaming** uses async polling with `Future.microtask`/`Timer`

### 6.2 Async Patterns

| Pattern | Usage |
|---------|-------|
| `async/await` | All public API methods |
| `Stream` | Streaming generation, download progress |
| `StreamController.broadcast()` | Token streams, event bus |
| `Completer` | Bridging callbacks to futures |

### 6.3 Native Thread Safety

- C++ backends handle their own threading
- FFI calls are serialized by Dart
- Model state protected by single-threaded access pattern

---

## 7. Dependencies & Boundaries

### 7.1 Core Package Dependencies

| Dependency | Purpose |
|------------|---------|
| `ffi` | Foreign Function Interface for C++ |
| `http` | Network requests |
| `rxdart` | Advanced stream operations |
| `path_provider` | App directory paths |
| `shared_preferences` | Preferences storage |
| `flutter_secure_storage` | Secure data storage |
| `sqflite` | Local database |
| `device_info_plus` | Device information |
| `archive` | Model extraction (tar.bz2, zip) |
| `flutter_tts` | System TTS fallback |
| `record` | Audio recording |
| `audioplayers` | Audio playback |
| `permission_handler` | Permission management |

### 7.2 Backend Dependencies

**LlamaCpp Package**:
- `runanywhere` (core SDK)
- `ffi` (FFI bindings)

**ONNX Package**:
- `runanywhere` (core SDK)
- `ffi` (FFI bindings)
- `http` (download strategy)
- `archive` (model extraction)

### 7.3 Native Binary Dependencies

| Platform | Libraries |
|----------|-----------|
| **iOS** | RACommons.xcframework, RABackendLLAMACPP.xcframework, RABackendONNX.xcframework, onnxruntime.xcframework |
| **Android** | librunanywhere_jni.so, librac_backend_llamacpp.so, librac_backend_onnx.so, libonnxruntime.so, libc++_shared.so, libomp.so |

---

## 8. Extensibility Points

### 8.1 Creating a New Backend Module

1. Create a new Flutter package
2. Add `runanywhere` as dependency
3. Implement C++ backend with standard RAC API
4. Create Dart bindings via FFI
5. Implement registration:

```dart
class MyBackend implements RunAnywhereModule {
  static final MyBackend _instance = MyBackend._internal();

  @override
  String get moduleId => 'my-backend';

  @override
  Set<SDKComponent> get capabilities => {SDKComponent.llm};

  static Future<void> register() async {
    final bindings = MyBackendBindings();
    bindings.rac_backend_mybackend_register();
    _isRegistered = true;
  }

  static void addModel({required String name, required String url}) {
    RunAnywhere.registerModel(
      name: name,
      url: Uri.parse(url),
      framework: InferenceFramework.myBackend,
    );
  }
}
```

### 8.2 Custom Download Strategies

Implement custom download logic for special model sources:

```dart
class MyCustomDownloadStrategy implements DownloadStrategy {
  @override
  bool canHandle(Uri url) => url.host == 'my-custom-host.com';

  @override
  Stream<DownloadProgress> download(String modelId, Uri url, String destPath) async* {
    // Custom download implementation
  }
}
```

### 8.3 Event Subscriptions

Apps can subscribe to SDK events for custom handling:

```dart
RunAnywhere.events.events.listen((event) {
  if (event is SDKModelEvent) {
    analytics.track('model_event', {'type': event.type});
  }
});
```

---

## 9. Build System

### 9.1 Build Script

The `scripts/build-flutter.sh` handles all native library building:

| Flag | Action |
|------|--------|
| `--setup` | Full first-time setup |
| `--local` | Use locally built libraries |
| `--remote` | Use GitHub releases |
| `--rebuild-commons` | Rebuild C++ commons |
| `--ios` | iOS only |
| `--android` | Android only |
| `--clean` | Clean before build |

### 9.2 Native Library Sources

Libraries come from `runanywhere-commons`:
- Built via CMake for each platform
- iOS: XCFrameworks with device + simulator slices
- Android: JNI libraries for arm64-v8a, armeabi-v7a, x86_64

### 9.3 Melos Workflow

Multi-package management via melos:

```bash
melos bootstrap     # Install all package dependencies
melos analyze       # Run flutter analyze on all packages
melos format        # Run dart format on all packages
melos test          # Run tests on all packages
melos clean         # Clean all packages
```

---

## 10. Known Trade-offs & Design Rationale

### 10.1 Static Class vs Instance

**Choice**: `RunAnywhere` is a static class, not instantiable.

**Rationale**:

Advantages:
- Simple, discoverable API (`RunAnywhere.generate()`)
- Singleton-like without explicit initialization

Trade-offs:
- Harder to support multiple SDK instances
- Global state complicates testing

### 10.2 FFI vs Platform Channels

**Choice**: Direct FFI to C++ instead of MethodChannel.

**Rationale**:

Advantages:
- Lower latency (no serialization overhead)
- Direct memory access for audio/binary data
- Consistent with iOS/Android native SDKs

Trade-offs:
- More complex error handling
- Platform-specific binary management

### 10.3 Thin Backend Wrappers

**Choice**: Backend packages (llamacpp, onnx) are thin wrappers.

**Rationale**:

Advantages:
- All logic lives in C++ (shared with Swift/Kotlin)
- Dart layer just registers and delegates
- Consistent behavior across all platforms

Trade-offs:
- Debugging requires native tooling

### 10.4 Lazy Model Discovery

**Choice**: Model discovery runs on first `availableModels()` call.

**Rationale**:

Advantages:
- Fast SDK initialization
- Models can be registered before discovery

Trade-offs:
- First `availableModels()` call is slower

---

## 11. Future Considerations

### 11.1 Potential Improvements

- **Compute Isolates**: Move inference to separate isolate
- **Model Caching**: LRU cache for multiple loaded models
- **Streaming TTS**: Token-by-token speech synthesis
- **Background Download**: Download models while app is backgrounded

### 11.2 Platform Expansions

- **Web Support**: WebAssembly backend (experimental)
- **Desktop**: macOS/Windows/Linux support
- **Wear OS**: Minimal SDK for wearables

---

## 12. Appendix: Key Types Reference

### Public Types

| Type | Description |
|------|-------------|
| `RunAnywhere` | Main entry point, all public SDK methods |
| `LLMGenerationResult` | Text generation result with metrics |
| `LLMGenerationOptions` | Options for text generation |
| `LLMStreamingResult` | Stream + result for streaming generation |
| `STTResult` | Transcription result with confidence |
| `TTSResult` | Synthesis result with audio samples |
| `ModelInfo` | Model metadata (id, name, category, path) |
| `DownloadProgress` | Download progress with state |
| `VoiceSessionHandle` | Voice session controller |
| `SDKEnvironment` | Environment enum |
| `SDKError` | SDK error with code and message |

### Internal Types

| Type | Description |
|------|-------------|
| `DartBridge` | FFI coordination |
| `DartBridgeLLM` | LLM native bridge |
| `DartBridgeSTT` | STT native bridge |
| `DartBridgeTTS` | TTS native bridge |
| `DartBridgeModelRegistry` | Model registry bridge |
| `ModelDownloadService` | Download management |
| `EventBus` | Event publishing |
| `SDKLogger` | Logging utility |

### Protocols

| Protocol | Description |
|----------|-------------|
| `RunAnywhereModule` | Backend module contract |
| `SDKEvent` | Base event protocol |

### Backend Modules

| Module | Package | Capabilities |
|--------|---------|--------------|
| LlamaCpp | `runanywhere_llamacpp` | LLM |
| ONNX | `runanywhere_onnx` | STT, TTS, VAD |
