# RunAnywhere Flutter SDK Architecture

## Overview

The RunAnywhere Flutter SDK follows the same modular, multi-backend architecture as the Swift SDK. It provides Speech-to-Text (STT), Text-to-Speech (TTS), Voice Activity Detection (VAD), LLM inference, and more through pluggable backend modules that consume native binaries from `runanywhere-core` via FFI.

---

## SDK Module Structure

```
┌─────────────────────────────────────────────────────────────────┐
│                    Flutter Package Products                      │
├─────────────────────────────────────────────────────────────────┤
│  runanywhere           │ Core SDK (required base)                │
│  runanywhere_onnx      │ ONNX Runtime backend (STT, TTS, VAD)    │
│  runanywhere_llamacpp  │ llama.cpp backend (future)              │
│  runanywhere_whisper   │ Native Whisper backend (future)         │
└─────────────────────────────────────────────────────────────────┘
```

> **Note**: Unlike Swift Package Manager which supports multiple products in a single package, Flutter packages are distributed separately. For the initial implementation, all backends are included in the main `runanywhere` package but organized into separate modules that can be optionally imported.

---

## Directory Layout

```
lib/
├── runanywhere.dart                    # Main barrel file (core only)
│
├── core/                               # Core SDK
│   ├── components/                     # Base component classes
│   ├── models/                         # Shared data models
│   ├── module_registry.dart            # Plugin registration system
│   └── protocols/                      # Service protocols/interfaces
│
├── components/                         # AI Components
│   ├── stt/                            # Speech-to-Text
│   ├── tts/                            # Text-to-Speech
│   ├── vad/                            # Voice Activity Detection
│   ├── llm/                            # Language Models
│   ├── vlm/                            # Vision-Language Models
│   ├── speaker_diarization/            # Speaker ID
│   └── voice_agent/                    # Full Voice Pipeline
│
├── foundation/                         # Foundation utilities
│   ├── configuration/                  # SDK settings
│   ├── dependency_injection/           # Service container
│   ├── logging/                        # Logging system
│   └── security/                       # Security utilities
│
├── public/                             # Public API
│   ├── runanywhere.dart                # Main SDK class
│   ├── configuration/                  # Public configuration
│   ├── events/                         # Event bus & SDK events
│   └── models/                         # Public models
│
└── backends/                           # Backend Modules (NEW)
    ├── backends.dart                   # Backend barrel file
    │
    ├── onnx/                           # ONNX Runtime Backend
    │   ├── onnx.dart                   # ONNX barrel file
    │   ├── onnx_adapter.dart           # Framework adapter
    │   ├── onnx_bridge.dart            # Native FFI bridge
    │   ├── services/                   # ONNX services
    │   │   ├── onnx_stt_service.dart
    │   │   ├── onnx_tts_service.dart
    │   │   ├── onnx_vad_service.dart
    │   │   └── onnx_llm_service.dart
    │   └── providers/                  # ONNX providers
    │       ├── onnx_stt_provider.dart
    │       ├── onnx_tts_provider.dart
    │       ├── onnx_vad_provider.dart
    │       └── onnx_llm_provider.dart
    │
    ├── llamacpp/                       # llama.cpp Backend (future)
    │   ├── llamacpp.dart
    │   ├── llamacpp_adapter.dart
    │   ├── llamacpp_bridge.dart
    │   ├── services/
    │   └── providers/
    │
    └── native/                         # Shared native utilities
        ├── ffi_types.dart              # FFI type definitions
        ├── platform_loader.dart        # Platform library loader
        └── native_backend.dart         # Low-level FFI wrapper
```

---

## How Backends Consume runanywhere-core

### Binary Distribution

Native binaries from `runanywhere-core` are distributed via [runanywhere-binaries](https://github.com/RunanywhereAI/runanywhere-binaries):

| Platform | Format | Location |
|----------|--------|----------|
| iOS | XCFramework | `ios/Frameworks/RunAnywhereCore.xcframework` |
| Android | Shared libs | `android/src/main/jniLibs/{abi}/` |

### FFI Bridge Layer

The `NativeBackend` class wraps the C API from `runanywhere-core/src/bridge/runanywhere_bridge.h`:

```dart
// Low-level FFI binding
final backend = NativeBackend();
backend.create('onnx');  // Create ONNX backend

// Load STT model
backend.loadSttModel('/path/to/model', modelType: 'whisper');

// Transcribe audio
final result = backend.transcribe(audioSamples, sampleRate: 16000);

// Cleanup
backend.dispose();
```

---

## Multi-Backend Architecture

### Provider Pattern

Each AI capability uses a provider pattern for pluggable backends:

```
┌──────────────────────────────────────────────────────────────┐
│                      ModuleRegistry                           │
│  ┌─────────────┬─────────────┬─────────────┬──────────────┐ │
│  │STTProviders │TTSProviders │VADProviders │LLMProviders  │ │
│  │  priority   │  priority   │  priority   │  priority    │ │
│  └─────────────┴─────────────┴─────────────┴──────────────┘ │
└──────────────────────────────────────────────────────────────┘
                              │
         ┌────────────────────┼────────────────────┐
         ↓                    ↓                    ↓
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ONNXSTTProvider  │  │ LlamaCppProvider │  │ SystemTTSProvider│
│  priority: 100  │  │  priority: 90   │  │   priority: 50  │
└─────────────────┘  └─────────────────┘  └─────────────────┘
```

### Service Provider Protocols

```dart
/// Provider for Speech-to-Text services
abstract class STTServiceProvider {
  String get name;
  bool canHandle({String? modelId});
  Future<STTService> createSTTService(dynamic configuration);
}

/// Provider for Text-to-Speech services
abstract class TTSServiceProvider {
  String get name;
  String get version;
  bool canHandle({String? modelId});
  Future<TTSService> createTTSService(dynamic configuration);
}

/// Provider for Voice Activity Detection services
abstract class VADServiceProvider {
  String get name;
  bool canHandle({String? modelId});
  Future<VADService> createVADService(dynamic configuration);
}

/// Provider for Language Model services
abstract class LLMServiceProvider {
  String get name;
  bool canHandle({String? modelId});
  Future<LLMService> createLLMService(dynamic configuration);
}
```

### ModuleRegistry (Plugin System)

```dart
class ModuleRegistry {
  static final ModuleRegistry shared = ModuleRegistry._();

  final List<_PrioritizedProvider<STTServiceProvider>> _sttProviders = [];
  final List<_PrioritizedProvider<TTSServiceProvider>> _ttsProviders = [];
  // ... other providers

  /// Register a Speech-to-Text provider with priority
  void registerSTT(STTServiceProvider provider, {int priority = 100}) {
    _sttProviders.add(_PrioritizedProvider(provider: provider, priority: priority));
    _sttProviders.sort((a, b) => b.priority.compareTo(a.priority));
  }

  /// Get an STT provider for the specified model (returns highest priority match)
  STTServiceProvider? sttProvider({String? modelId}) {
    if (modelId != null) {
      return _sttProviders
          .firstWhere((p) => p.provider.canHandle(modelId: modelId))
          .provider;
    }
    return _sttProviders.firstOrNull?.provider;
  }
}
```

### Unified Framework Adapter

Each backend implements `UnifiedFrameworkAdapter` for multi-modal support:

```dart
/// Adapter interface for framework backends
abstract class UnifiedFrameworkAdapter {
  /// The framework this adapter provides
  LLMFramework get framework;

  /// Supported modalities (STT, TTS, LLM, etc.)
  Set<FrameworkModality> get supportedModalities;

  /// Supported model formats
  List<ModelFormat> get supportedFormats;

  /// Check if this adapter can handle a model
  bool canHandle(ModelInfo model);

  /// Create a service for the given modality
  dynamic createService(FrameworkModality modality);

  /// Load a model for the given modality
  Future<dynamic> loadModel(ModelInfo model, FrameworkModality modality);

  /// Called when adapter is registered - register providers
  void onRegistration();
}
```

---

## Backend Module Pattern

### ONNX Backend Example

```dart
// lib/backends/onnx/onnx.dart

/// ONNX Runtime backend for RunAnywhere.
///
/// Provides STT, TTS, VAD capabilities via runanywhere-core.
///
/// ## Usage
///
/// ```dart
/// import 'package:runanywhere/backends/onnx/onnx.dart';
///
/// // Initialize the ONNX backend
/// await OnnxBackend.initialize();
///
/// // Now use STT, TTS, VAD through the standard RunAnywhere API
/// final stt = await RunAnywhere.createSTTService();
/// ```
library runanywhere_onnx;

export 'onnx_adapter.dart';
export 'services/onnx_stt_service.dart';
export 'services/onnx_tts_service.dart';
export 'services/onnx_vad_service.dart';

// Auto-registration when imported
class OnnxBackend {
  static bool _initialized = false;

  /// Initialize the ONNX backend and register providers.
  static Future<bool> initialize({int priority = 100}) async {
    if (_initialized) return true;

    final adapter = OnnxAdapter();
    adapter.onRegistration(priority: priority);
    _initialized = true;
    return true;
  }

  /// Check if ONNX backend is available
  static bool get isAvailable => NativeBackend.tryCreate() != null;
}
```

### Backend Adapter

```dart
// lib/backends/onnx/onnx_adapter.dart

class OnnxAdapter implements UnifiedFrameworkAdapter {
  late final NativeBackend _backend;

  @override
  LLMFramework get framework => LLMFramework.onnx;

  @override
  Set<FrameworkModality> get supportedModalities => {
    FrameworkModality.voiceToText,
    FrameworkModality.textToVoice,
    FrameworkModality.voiceActivityDetection,
  };

  @override
  List<ModelFormat> get supportedFormats => [ModelFormat.onnx, ModelFormat.ort];

  @override
  bool canHandle(ModelInfo model) {
    return model.compatibleFrameworks.contains(LLMFramework.onnx) &&
           supportedModalities.contains(model.modality);
  }

  @override
  dynamic createService(FrameworkModality modality) {
    switch (modality) {
      case FrameworkModality.voiceToText:
        return OnnxSTTService(_backend);
      case FrameworkModality.textToVoice:
        return OnnxTTSService(_backend);
      case FrameworkModality.voiceActivityDetection:
        return OnnxVADService(_backend);
      default:
        return null;
    }
  }

  @override
  void onRegistration({int priority = 100}) {
    _backend = NativeBackend();
    _backend.create('onnx');

    final registry = ModuleRegistry.shared;
    registry.registerSTT(OnnxSTTServiceProvider(_backend), priority: priority);
    registry.registerTTS(OnnxTTSServiceProvider(_backend), priority: priority);
    registry.registerVAD(OnnxVADServiceProvider(_backend), priority: priority);
  }
}
```

---

## Component Architecture

### STT (Speech-to-Text)

```dart
/// Core STT service protocol
abstract class STTService {
  Future<void> initialize({String? modelPath});
  Future<STTTranscriptionResult> transcribe({
    required List<int> audioData,
    required STTOptions options,
  });
  bool get isReady;
  bool get supportsStreaming;
  Future<void> cleanup();
}

/// STT configuration
class STTConfiguration {
  final String? modelId;
  final String language;
  final int sampleRate;
  final bool enablePunctuation;
  final bool enableTimestamps;
  final bool useGPU;

  const STTConfiguration({
    this.modelId,
    this.language = 'en-US',
    this.sampleRate = 16000,
    this.enablePunctuation = true,
    this.enableTimestamps = false,
    this.useGPU = true,
  });
}

/// STT result
class STTTranscriptionResult {
  final String transcript;
  final double? confidence;
  final String? language;
  final List<TimestampInfo>? timestamps;
  final List<AlternativeTranscription>? alternatives;
}
```

### TTS (Text-to-Speech)

```dart
/// Core TTS service protocol
abstract class TTSService {
  Future<void> initialize();
  Future<List<int>> synthesize({
    required String text,
    required TTSOptions options,
  });
  bool get isSynthesizing;
  List<String> get availableVoices;
  void stop();
  Future<void> cleanup();
}

/// TTS configuration
class TTSConfiguration {
  final String? voice;
  final String language;
  final double rate;
  final double pitch;
  final double volume;
  final AudioFormat audioFormat;

  const TTSConfiguration({
    this.voice,
    this.language = 'en-US',
    this.rate = 1.0,
    this.pitch = 1.0,
    this.volume = 1.0,
    this.audioFormat = AudioFormat.pcmFloat32,
  });
}
```

### VAD (Voice Activity Detection)

```dart
/// Core VAD service protocol
abstract class VADService {
  Future<void> initialize({String? modelPath});
  Future<VADResult> process(List<int> audioData);
  void reset();
  bool get isReady;
  Future<void> cleanup();
}

/// VAD result
class VADResult {
  final bool isSpeech;
  final double probability;
  final bool isEndOfSpeech;
  final Duration? speechStartTime;
  final Duration? speechEndTime;
}
```

---

## Voice Agent Pipeline

The VoiceAgentComponent orchestrates the full voice AI pipeline:

```
┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐
│   VAD   │ → │   STT   │ → │   LLM   │ → │   TTS   │
│ Detect  │    │Transcribe│   │ Process │    │Synthesize│
│ Speech  │    │  Audio  │    │  Text   │    │  Audio  │
└─────────┘    └─────────┘    └─────────┘    └─────────┘
     ↓              ↓              ↓              ↓
 isSpeech      "Hello"       "Hi there"      [audio]
```

```dart
class VoiceAgentComponent {
  final VADComponent _vad;
  final STTComponent _stt;
  final LLMComponent _llm;
  final TTSComponent _tts;
  final EventBus _eventBus;

  Stream<VoiceAgentEvent> process(Stream<List<int>> audioStream) async* {
    await for (final audioChunk in audioStream) {
      // 1. VAD: Check for speech
      final vadResult = await _vad.process(audioChunk);
      if (!vadResult.isSpeech) continue;

      yield VoiceAgentEvent.speechDetected();

      // 2. When speech ends, transcribe
      if (vadResult.isEndOfSpeech) {
        final transcription = await _stt.transcribe(speechBuffer);
        yield VoiceAgentEvent.transcriptionComplete(transcription.text);

        // 3. Process with LLM
        final response = await _llm.generate(transcription.text);
        yield VoiceAgentEvent.responseGenerated(response);

        // 4. Synthesize response
        final audio = await _tts.synthesize(response);
        yield VoiceAgentEvent.audioGenerated(audio);
      }
    }
  }
}
```

---

## Usage Examples

### Basic Usage (Core + ONNX)

```dart
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere/backends/onnx/onnx.dart';

void main() async {
  // Initialize ONNX backend
  await OnnxBackend.initialize();

  // Create STT service (uses highest priority provider)
  final stt = await RunAnywhere.createSTTService(
    configuration: STTConfiguration(
      language: 'en-US',
      enableTimestamps: true,
    ),
  );

  // Transcribe audio
  final result = await stt.transcribe(
    audioData: audioBytes,
    options: STTOptions(language: 'en'),
  );

  print('Transcription: ${result.transcript}');

  // Cleanup
  await stt.cleanup();
}
```

### Multiple Backends

```dart
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere/backends/onnx/onnx.dart';
import 'package:runanywhere/backends/llamacpp/llamacpp.dart'; // Future

void main() async {
  // Initialize multiple backends with priorities
  await OnnxBackend.initialize(priority: 100);  // STT, TTS, VAD
  await LlamaCppBackend.initialize(priority: 90);  // LLM

  // ONNX will be used for STT (priority 100)
  final stt = await RunAnywhere.createSTTService();

  // LlamaCpp will be used for LLM
  final llm = await RunAnywhere.createLLMService();
}
```

### Manual Backend Selection

```dart
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere/backends/onnx/onnx.dart';

void main() async {
  await OnnxBackend.initialize();

  // Get specific provider by model
  final provider = ModuleRegistry.shared.sttProvider(modelId: 'sherpa-whisper-onnx');
  final stt = await provider!.createSTTService(STTConfiguration());

  // Or use the adapter directly
  final adapter = OnnxAdapter();
  final service = adapter.createService(FrameworkModality.voiceToText);
}
```

---

## Comparison: Swift vs Flutter

| Aspect | Swift SDK | Flutter SDK |
|--------|-----------|-------------|
| **Package Distribution** | SPM products | Single package with modules |
| **Backend Import** | `import RunAnywhereONNX` | `import 'backends/onnx/onnx.dart'` |
| **Native Bridge** | XCFramework + C headers | FFI + shared libs |
| **Provider Pattern** | ✅ Same | ✅ Same |
| **ModuleRegistry** | ✅ Same | ✅ Same |
| **UnifiedFrameworkAdapter** | ✅ Same | ✅ Same |
| **Auto-registration** | `ONNXAdapter.onRegistration()` | `OnnxBackend.initialize()` |

---

## Future Backends

### llama.cpp Backend

```dart
// lib/backends/llamacpp/llamacpp.dart
class LlamaCppBackend {
  static Future<bool> initialize({int priority = 90}) async {
    final adapter = LlamaCppAdapter();
    adapter.onRegistration(priority: priority);
    return true;
  }
}

class LlamaCppAdapter implements UnifiedFrameworkAdapter {
  @override
  LLMFramework get framework => LLMFramework.llamaCpp;

  @override
  Set<FrameworkModality> get supportedModalities => {
    FrameworkModality.textToText,
  };

  @override
  List<ModelFormat> get supportedFormats => [ModelFormat.gguf, ModelFormat.ggml];
}
```

### When llama.cpp is Added to runanywhere-core

```
runanywhere-core/
├── src/backends/
│   ├── onnx/           # Existing
│   └── llamacpp/       # New backend
│       ├── llamacpp_backend.h
│       └── llamacpp_backend.cpp

Distribution:
└── dist/
    ├── RunAnywhereCore.xcframework      # Includes all backends
    └── jniLibs/{abi}/librunanywhere_bridge.so
```

---

## Summary

The RunAnywhere Flutter SDK provides:

1. **Modular Architecture**: Separate backend modules (ONNX, llama.cpp, etc.)
2. **Provider Pattern**: Pluggable STT/TTS/VAD/LLM implementations
3. **FFI Consumption**: Native C++ from runanywhere-core via Dart FFI
4. **Multi-Backend Support**: Priority-based backend selection
5. **Full Voice Pipeline**: VAD → STT → LLM → TTS orchestration
6. **Clean Protocols**: Service interfaces matching Swift SDK
7. **Configuration System**: Comprehensive options for each component
8. **Swift Parity**: Mirrors the Swift SDK architecture for consistency
