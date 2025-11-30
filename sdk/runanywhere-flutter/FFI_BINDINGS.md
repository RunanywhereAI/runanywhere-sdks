# Flutter SDK - Native FFI Bindings Requirements

This document outlines the native FFI (Foreign Function Interface) bindings required from the `runanywhere-core` module to enable full on-device AI inference in the Flutter SDK.

## Overview

The Flutter SDK architecture is designed with a **provider pattern** where native implementations (ONNX Runtime, llama.cpp, etc.) register themselves via `ModuleRegistry`. The SDK logic (interfaces, data models, configurations) is complete in Dart, but actual inference requires native bindings.

## Required FFI Bindings

### 1. LLM (Language Model) Provider

**Purpose**: On-device text generation using llama.cpp or ONNX models

**Required C API Functions**:
```c
// Model lifecycle
void* llm_load_model(const char* model_path, LLMConfig* config);
void llm_unload_model(void* model_handle);
bool llm_is_model_loaded(void* model_handle);

// Generation
LLMResult* llm_generate(
    void* model_handle,
    const char* prompt,
    LLMGenerationOptions* options
);

// Streaming generation (callback-based)
void llm_generate_stream(
    void* model_handle,
    const char* prompt,
    LLMGenerationOptions* options,
    void (*on_token)(const char* token, void* user_data),
    void* user_data
);

// Cleanup
void llm_free_result(LLMResult* result);
```

**Dart FFI Wrapper**:
```dart
class LlamaCppProvider implements LLMServiceProvider {
  @override
  String get name => 'llama.cpp';

  @override
  bool canHandle({String? modelId}) {
    // Check for .gguf model files
    return modelId?.endsWith('.gguf') ?? false;
  }

  @override
  Future<LLMService> createLLMService(dynamic configuration) async {
    return LlamaCppService(configuration as LLMConfiguration);
  }
}
```

**Registration**:
```dart
// In app initialization
import 'package:runanywhere_llamacpp/runanywhere_llamacpp.dart';

ModuleRegistry.shared.registerLLM(LlamaCppProvider(), priority: 100);
```

---

### 2. STT (Speech-to-Text) Provider

**Purpose**: On-device speech transcription using Whisper (via whisper.cpp or ONNX)

**Required C API Functions**:
```c
// Model lifecycle
void* stt_load_model(const char* model_path, STTConfig* config);
void stt_unload_model(void* model_handle);
bool stt_is_model_ready(void* model_handle);

// Batch transcription
STTResult* stt_transcribe(
    void* model_handle,
    const int16_t* audio_data,
    int audio_length,
    STTOptions* options
);

// Streaming transcription (for live mode)
void* stt_stream_start(void* model_handle, STTOptions* options);
void stt_stream_feed(void* stream_handle, const int16_t* audio_chunk, int chunk_length);
STTPartialResult* stt_stream_get_partial(void* stream_handle);
STTResult* stt_stream_finalize(void* stream_handle);

// Cleanup
void stt_free_result(STTResult* result);
```

**Dart FFI Wrapper**:
```dart
class WhisperProvider implements STTServiceProvider {
  @override
  String get name => 'WhisperKit';

  @override
  bool canHandle({String? modelId}) {
    return modelId?.contains('whisper') ?? true;
  }

  @override
  Future<STTService> createSTTService(dynamic configuration) async {
    return WhisperService(configuration as STTConfiguration);
  }
}
```

**Registration**:
```dart
ModuleRegistry.shared.registerSTT(WhisperProvider(), priority: 100);
```

---

### 3. TTS (Text-to-Speech) Provider

**Purpose**: On-device speech synthesis (optional - system TTS fallback exists)

**Required C API Functions**:
```c
// Model lifecycle
void* tts_load_model(const char* model_path, TTSConfig* config);
void tts_unload_model(void* model_handle);

// Synthesis
TTSResult* tts_synthesize(
    void* model_handle,
    const char* text,
    TTSOptions* options
);

// Streaming synthesis
void tts_synthesize_stream(
    void* model_handle,
    const char* text,
    TTSOptions* options,
    void (*on_audio_chunk)(const int16_t* audio, int length, void* user_data),
    void* user_data
);

// Voice enumeration
const char** tts_get_voices(void* model_handle, int* count);

// Cleanup
void tts_free_result(TTSResult* result);
```

**Note**: TTS has a fallback to `SystemTTSService` which uses Flutter's `flutter_tts` package. Native TTS is optional.

---

## Data Structures

### LLMConfig
```c
typedef struct {
    int context_length;      // Max context window (default: 2048)
    bool use_gpu;           // Use GPU acceleration if available
    int cache_size_mb;      // Token cache size in MB
    float temperature;      // Default temperature
    int max_tokens;         // Default max tokens
    const char* quantization; // Q4_0, Q4_K_M, Q8_0, F16, etc.
} LLMConfig;
```

### LLMGenerationOptions
```c
typedef struct {
    int max_tokens;
    float temperature;
    float top_p;
    const char** stop_sequences;
    int stop_sequences_count;
    const char* system_prompt;
} LLMGenerationOptions;
```

### LLMResult
```c
typedef struct {
    char* text;
    int prompt_tokens;
    int completion_tokens;
    float generation_time_ms;
    const char* finish_reason; // "completed", "max_tokens", "stop_sequence"
} LLMResult;
```

### STTConfig
```c
typedef struct {
    const char* language;    // "en", "es", "fr", etc.
    int sample_rate;         // Audio sample rate (default: 16000)
    bool enable_punctuation;
    bool enable_timestamps;
    bool use_gpu;
} STTConfig;
```

### STTResult
```c
typedef struct {
    char* transcript;
    float confidence;
    const char* detected_language;
    STTTimestamp* timestamps;
    int timestamp_count;
    float processing_time_ms;
    float audio_length_ms;
} STTResult;
```

---

## Platform-Specific Considerations

### iOS
- Use XCFramework built from `runanywhere-core`
- Metal acceleration for GPU inference
- CoreML integration for Apple Neural Engine

### Android
- Use JNI wrapper or direct FFI to .so libraries
- Vulkan/OpenCL for GPU acceleration
- NNAPI integration for Android Neural Networks

### Common
- Shared C API across platforms
- Platform-specific GPU backends abstracted in core

---

## Implementation Priority

### Phase 1: LLM Provider (High Priority)
1. llama.cpp FFI bindings for GGUF model loading
2. Token streaming support
3. Basic generation with configurable parameters

### Phase 2: STT Provider (High Priority)
1. Whisper FFI bindings for audio transcription
2. Batch transcription support
3. Live streaming transcription

### Phase 3: TTS Provider (Medium Priority)
1. ONNX TTS model support (optional)
2. Streaming audio synthesis
3. Voice enumeration

---

## Integration Example

Once FFI bindings are available, register providers in app initialization:

```dart
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_core/runanywhere_core.dart'; // FFI bindings

void main() async {
  // Register native providers
  RunAnywhereCoreFFI.registerProviders();
  // This internally calls:
  // - ModuleRegistry.shared.registerLLM(LlamaCppProvider())
  // - ModuleRegistry.shared.registerSTT(WhisperProvider())
  // - ModuleRegistry.shared.registerTTS(ONNXTTSProvider()) // optional

  // Initialize SDK
  await RunAnywhere.initialize(
    apiKey: 'your-api-key',
    baseURL: 'https://api.runanywhere.ai',
    environment: SDKEnvironment.development,
  );

  // Load model
  await RunAnywhere.loadModel('llama-3.2-1b.gguf');

  // Generate text
  final result = await RunAnywhere.generate('Hello, world!');
  print(result.text);
}
```

---

## Current Status

| Component | Dart Interface | FFI Bindings | Provider |
|-----------|---------------|--------------|----------|
| LLM | ✅ Complete | ❌ Pending | ❌ Pending |
| STT | ✅ Complete | ❌ Pending | ❌ Pending |
| TTS | ✅ Complete | ❌ Pending | ✅ SystemTTS fallback |
| VAD | ✅ Complete | N/A | ✅ SimpleEnergyVAD |

---

## Notes

- The Flutter SDK is architecturally ready to accept native providers
- All interfaces, configurations, and data models match the iOS Swift SDK
- FFI bindings should be provided as a separate package (e.g., `runanywhere_core_ffi`)
- System fallbacks exist for TTS (flutter_tts) and VAD (energy-based detection)
