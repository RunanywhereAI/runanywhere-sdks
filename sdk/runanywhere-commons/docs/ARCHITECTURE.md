# RunAnywhere Commons - Architecture

## Table of Contents

- [Overview](#overview)
- [Design Philosophy](#design-philosophy)
- [Layer Architecture](#layer-architecture)
- [Directory Structure](#directory-structure)
- [Core Components](#core-components)
- [Service Abstraction Layer](#service-abstraction-layer)
- [Backend Implementations](#backend-implementations)
- [Data Flow](#data-flow)
- [Concurrency Model](#concurrency-model)
- [Memory Management](#memory-management)
- [Event System](#event-system)
- [Platform Adapter](#platform-adapter)
- [Error Handling](#error-handling)
- [Extensibility](#extensibility)
- [Testing](#testing)
- [Design Decisions](#design-decisions)

---

## Overview

RunAnywhere Commons (`runanywhere-commons`) is the shared C++ foundation for the RunAnywhere SDK ecosystem. It provides a unified abstraction layer over multiple ML inference backends, enabling platform SDKs (Swift, Kotlin, Flutter) to access on-device AI capabilities through a consistent C API.

### Key Architectural Goals

1. **Cross-Platform Consistency** - Single C++ codebase, identical API semantics across iOS, Android, macOS, Linux
2. **Backend Agnosticism** - Pluggable backends registered at runtime; SDK code doesn't know which backend is used
3. **FFI Compatibility** - Pure C API surface for easy binding to Swift, Kotlin, Dart, and other languages
4. **Performance** - Minimal abstraction overhead; backends operate at native speed
5. **Modularity** - Separate XCFrameworks for each backend allows apps to include only what they need

---

## Design Philosophy

### Vtable-Based Polymorphism

Unlike traditional C++ virtual inheritance, all service abstractions use C-style vtables:

```c
// Service interface = struct with ops pointer + implementation handle
typedef struct rac_llm_service {
    const rac_llm_service_ops_t* ops;  // Function pointers
    void* impl;                         // Backend-specific handle
    const char* model_id;
} rac_llm_service_t;

// Operations vtable - each backend provides one
typedef struct rac_llm_service_ops {
    rac_result_t (*initialize)(void* impl, const char* model_path);
    rac_result_t (*generate)(void* impl, const char* prompt,
                             const rac_llm_options_t* options,
                             rac_llm_result_t* out_result);
    rac_result_t (*generate_stream)(void* impl, const char* prompt,
                                    const rac_llm_options_t* options,
                                    rac_llm_stream_callback_fn callback,
                                    void* user_data);
    rac_result_t (*cancel)(void* impl);
    void (*destroy)(void* impl);
} rac_llm_service_ops_t;
```

**Rationale:**
- No C++ RTTI or exceptions cross FFI boundaries
- Compatible with C FFI (Swift, JNI, Dart FFI)
- Backend can be statically or dynamically linked
- Service instance is a simple POD struct

### Priority-Based Provider Selection

Service creation mirrors Swift's `ServiceRegistry` pattern:

```c
// Provider declares capability + priority + canHandle function
rac_service_provider_t provider = {
    .name = "LlamaCPPService",
    .capability = RAC_CAPABILITY_TEXT_GENERATION,
    .priority = 100,
    .can_handle = llamacpp_can_handle,
    .create = llamacpp_create_service,
};
rac_service_register_provider(&provider);

// Service creation queries providers in priority order
// First provider where canHandle returns true creates the service
rac_service_create(RAC_CAPABILITY_TEXT_GENERATION, &request, &handle);
```

**Resolution Flow:**
1. Registry sorts providers by priority (higher first)
2. For each provider, call `can_handle(request)`
3. First provider returning `true` calls its `create` function
4. Created service handle returned to caller

---

## Layer Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        Platform SDK Layer                                │
│                                                                          │
│  ┌──────────────────┐  ┌──────────────────┐  ┌────────────────────────┐ │
│  │  Swift SDK       │  │  Kotlin SDK      │  │  Flutter SDK           │ │
│  │  (CRACommons)    │  │  (JNI Bridge)    │  │  (Dart FFI)            │ │
│  └────────┬─────────┘  └────────┬─────────┘  └───────────┬────────────┘ │
└───────────│──────────────────────│───────────────────────│──────────────┘
            │                      │                       │
            └──────────────────────┼───────────────────────┘
                                   │
                              C API (rac_*)
                                   │
┌──────────────────────────────────▼──────────────────────────────────────┐
│                      RAC Public API Layer                                │
│                                                                          │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐  ┌───────────┐ │
│  │ rac_llm.h     │  │ rac_stt.h     │  │ rac_tts.h     │  │ rac_vad.h │ │
│  │ LLM Service   │  │ STT Service   │  │ TTS Service   │  │ VAD Svc   │ │
│  └───────┬───────┘  └───────┬───────┘  └───────┬───────┘  └─────┬─────┘ │
│          │                  │                  │                │       │
│  ┌───────▼──────────────────▼──────────────────▼────────────────▼─────┐ │
│  │                    Service Registry                                 │ │
│  │            Priority-based provider selection                        │ │
│  │            canHandle → create → service handle                      │ │
│  └────────────────────────────────┬────────────────────────────────────┘ │
└───────────────────────────────────│─────────────────────────────────────┘
                                    │
                                    │ vtable dispatch
                                    │
┌───────────────────────────────────▼─────────────────────────────────────┐
│                         Backend Layer                                    │
│                                                                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐         │
│  │   LlamaCPP      │  │      ONNX       │  │   WhisperCPP    │         │
│  │   Backend       │  │     Backend     │  │    Backend      │         │
│  │                 │  │                 │  │                 │         │
│  │  • GGUF models  │  │  • STT (Sherpa) │  │  • STT (GGML)   │         │
│  │  • Metal GPU    │  │  • TTS (Piper)  │  │  • Multi-lang   │         │
│  │  • Streaming    │  │  • VAD (Silero) │  │  • Fast CPU     │         │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘         │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │                     Platform Backend (Apple only)                    ││
│  │   • Apple Foundation Models (LLM via Swift callbacks)               ││
│  │   • System TTS (AVSpeechSynthesizer via Swift callbacks)            ││
│  └─────────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │
┌───────────────────────────────────▼─────────────────────────────────────┐
│                    Infrastructure Layer                                  │
│                                                                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐ │
│  │   Logging   │  │   Events    │  │   Errors    │  │ Platform Adapter│ │
│  │   System    │  │   System    │  │  Handling   │  │   (Callbacks)   │ │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────────┘ │
│                                                                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────────────┐  │
│  │   Module    │  │   Model     │  │       Telemetry Manager         │  │
│  │  Registry   │  │  Registry   │  │  (Analytics events to SDK)      │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Directory Structure

```
runanywhere-commons/
├── include/rac/                    # Public C headers (rac_* prefix)
│   ├── core/                       # Core infrastructure
│   │   ├── rac_core.h              # Main SDK initialization
│   │   ├── rac_error.h             # Error codes (-100 to -999)
│   │   ├── rac_types.h             # Basic types, handles, strings
│   │   ├── rac_logger.h            # Logging interface
│   │   ├── rac_events.h            # Event system
│   │   ├── rac_platform_adapter.h  # Platform callbacks
│   │   └── capabilities/
│   │       └── rac_lifecycle.h     # Component lifecycle states
│   │
│   ├── features/                   # Service interfaces
│   │   ├── llm/                    # Large Language Models
│   │   │   ├── rac_llm_service.h   # LLM vtable interface
│   │   │   ├── rac_llm_types.h     # LLM data structures
│   │   │   └── rac_llm.h           # Public API wrapper
│   │   ├── stt/                    # Speech-to-Text
│   │   │   ├── rac_stt_service.h   # STT vtable interface
│   │   │   ├── rac_stt_types.h     # STT data structures
│   │   │   └── rac_stt.h           # Public API
│   │   ├── tts/                    # Text-to-Speech
│   │   │   ├── rac_tts_service.h   # TTS vtable interface
│   │   │   ├── rac_tts_types.h     # TTS data structures
│   │   │   └── rac_tts.h           # Public API
│   │   ├── vad/                    # Voice Activity Detection
│   │   │   ├── rac_vad_service.h   # VAD vtable interface
│   │   │   ├── rac_vad_types.h     # VAD data structures
│   │   │   └── rac_vad.h           # Public API
│   │   ├── voice_agent/            # Complete voice pipeline
│   │   │   └── rac_voice_agent.h   # STT+LLM+TTS+VAD orchestration
│   │   └── platform/               # Platform-specific backends
│   │       ├── rac_llm_platform.h  # Apple Foundation Models
│   │       └── rac_tts_platform.h  # Apple System TTS
│   │
│   ├── infrastructure/             # Support services
│   │   ├── model_management/       # Model registry and lifecycle
│   │   ├── network/                # Network types and endpoints
│   │   ├── device/                 # Device management
│   │   ├── storage/                # Storage analysis
│   │   └── telemetry/              # Analytics
│   │
│   └── backends/                   # Backend-specific public headers
│       ├── rac_llm_llamacpp.h      # LlamaCPP backend API
│       ├── rac_stt_whispercpp.h    # WhisperCPP backend API
│       ├── rac_stt_onnx.h          # ONNX STT API
│       ├── rac_tts_onnx.h          # ONNX TTS API
│       └── rac_vad_onnx.h          # ONNX VAD API
│
├── src/                            # Implementation files
│   ├── core/                       # Core implementations
│   ├── infrastructure/             # Infrastructure implementations
│   │   ├── registry/               # Module & service registries
│   │   ├── model_management/       # Model handling
│   │   ├── network/                # HTTP client, auth
│   │   └── telemetry/              # Telemetry manager
│   ├── features/                   # Feature implementations
│   │   ├── llm/                    # LLM component & service
│   │   ├── stt/                    # STT component & service
│   │   ├── tts/                    # TTS component & service
│   │   ├── vad/                    # VAD component & energy VAD
│   │   ├── voice_agent/            # Voice agent orchestration
│   │   └── platform/               # Platform backend stubs
│   ├── backends/                   # ML backend implementations
│   │   ├── llamacpp/               # LlamaCPP integration
│   │   ├── onnx/                   # ONNX/Sherpa-ONNX integration
│   │   └── whispercpp/             # WhisperCPP integration
│   └── jni/                        # JNI bridge for Android
│
├── cmake/                          # CMake modules
├── scripts/                        # Build automation
├── third_party/                    # Pre-built dependencies
├── dist/                           # Build outputs (xcframeworks)
├── CMakeLists.txt                  # Main CMake configuration
├── VERSION                         # Project version
└── VERSIONS                        # Dependency versions
```

---

## Core Components

### Initialization (rac_core.h)

The library must be initialized before use:

```c
// Required: Platform adapter with callbacks
rac_platform_adapter_t adapter = {
    .file_exists = my_file_exists,
    .file_read = my_file_read,
    .log = my_log_callback,
    .now_ms = my_get_time_ms,
    .user_data = my_context
};

rac_config_t config = {
    .platform_adapter = &adapter,
    .log_level = RAC_LOG_INFO,
    .log_tag = "MyApp"
};

rac_result_t result = rac_init(&config);
```

**Initialization Flow:**
1. Validate platform adapter (required callbacks)
2. Initialize logging system
3. Initialize module registry
4. Initialize service registry
5. Initialize model registry
6. Set initialized flag

### Module Registry

Backends register as modules declaring their capabilities:

```c
rac_module_info_t info = {
    .id = "llamacpp",
    .name = "LlamaCPP",
    .version = "1.0.0",
    .description = "LLM backend using llama.cpp",
    .capabilities = (rac_capability_t[]){RAC_CAPABILITY_TEXT_GENERATION},
    .num_capabilities = 1
};
rac_module_register(&info);
```

**Module Registry Responsibilities:**
- Track registered modules
- Query modules by capability
- Support runtime module discovery

### Service Registry

Services are created through registered providers:

```c
// Backend registers provider
rac_service_provider_t provider = {
    .name = "LlamaCPPService",
    .capability = RAC_CAPABILITY_TEXT_GENERATION,
    .priority = 100,
    .can_handle = llamacpp_can_handle,
    .create = llamacpp_create_service,
    .user_data = NULL
};
rac_service_register_provider(&provider);

// SDK creates service
rac_service_request_t request = {
    .identifier = "my-model",
    .capability = RAC_CAPABILITY_TEXT_GENERATION,
    .framework = RAC_FRAMEWORK_LLAMA_CPP,
    .model_path = "/path/to/model.gguf"
};

rac_handle_t service;
rac_service_create(RAC_CAPABILITY_TEXT_GENERATION, &request, &service);
```

**Provider Selection Algorithm:**
1. Filter providers by capability
2. Sort by priority (descending)
3. For each provider: if `can_handle(request)` → call `create(request)`
4. Return first successful service handle

### Logging System

Unified logging through platform adapter:

```c
// Logging macros
RAC_LOG_DEBUG("LLM.LlamaCpp", "Loading model: %s", model_path);
RAC_LOG_INFO("ServiceRegistry", "Provider registered: %s", name);
RAC_LOG_WARNING("VAD", "Energy threshold too low: %f", threshold);
RAC_LOG_ERROR("STT", "Transcription failed: %s", rac_error_message(result));

// Implementation routes to platform
void rac_log(rac_log_level_t level, const char* category, const char* message) {
    const rac_platform_adapter_t* adapter = rac_get_platform_adapter();
    if (adapter && adapter->log) {
        adapter->log(level, category, message, adapter->user_data);
    }
}
```

**Log Levels:**
- `RAC_LOG_TRACE` (0) - Verbose debugging
- `RAC_LOG_DEBUG` (1) - Debug information
- `RAC_LOG_INFO` (2) - General information
- `RAC_LOG_WARNING` (3) - Warnings
- `RAC_LOG_ERROR` (4) - Errors
- `RAC_LOG_FATAL` (5) - Fatal errors

---

## Service Abstraction Layer

### Service Interface Pattern

Each capability (LLM, STT, TTS, VAD) follows the same pattern:

```c
// 1. Types header (rac_<cap>_types.h)
typedef struct rac_<cap>_options { ... } rac_<cap>_options_t;
typedef struct rac_<cap>_result { ... } rac_<cap>_result_t;

// 2. Service interface (rac_<cap>_service.h)
typedef struct rac_<cap>_service_ops {
    rac_result_t (*initialize)(void* impl, ...);
    rac_result_t (*process)(void* impl, ...);
    void (*destroy)(void* impl);
} rac_<cap>_service_ops_t;

typedef struct rac_<cap>_service {
    const rac_<cap>_service_ops_t* ops;
    void* impl;
    const char* model_id;
} rac_<cap>_service_t;

// 3. Public API (rac_<cap>.h)
RAC_API rac_result_t rac_<cap>_create(const char* id, rac_handle_t* out);
RAC_API rac_result_t rac_<cap>_process(rac_handle_t h, ...);
RAC_API void rac_<cap>_destroy(rac_handle_t h);
```

### LLM Service

**Types:**
```c
typedef struct rac_llm_options {
    int32_t max_tokens;      // Maximum tokens to generate
    float temperature;       // Sampling temperature (0.0-2.0)
    float top_p;             // Nucleus sampling threshold
    int32_t top_k;           // Top-k sampling
    const char* system_prompt;
    rac_bool_t streaming_enabled;
} rac_llm_options_t;

typedef struct rac_llm_result {
    char* text;              // Generated text (owned)
    int32_t input_tokens;    // Prompt tokens
    int32_t output_tokens;   // Generated tokens
    double duration_ms;      // Generation time
    double tokens_per_second;
    double time_to_first_token_ms;
    char* thinking_content;  // Reasoning (if supported)
} rac_llm_result_t;
```

**Streaming Callback:**
```c
typedef rac_bool_t (*rac_llm_stream_callback_fn)(
    const char* token,       // Generated token
    rac_bool_t is_final,     // Is this the last token?
    void* user_data
);
// Return RAC_FALSE to stop generation
```

### STT Service

**Types:**
```c
typedef struct rac_stt_options {
    const char* language;    // Language code (e.g., "en")
    rac_bool_t detect_language;
    rac_bool_t enable_timestamps;
    int32_t sample_rate;     // Audio sample rate
} rac_stt_options_t;

typedef struct rac_stt_result {
    char* text;              // Transcribed text
    float confidence;        // 0.0-1.0
    const char* language;    // Detected language
    double duration_ms;      // Processing time
    // Word timestamps (optional)
} rac_stt_result_t;
```

### TTS Service

**Types:**
```c
typedef struct rac_tts_options {
    const char* voice;       // Voice identifier
    const char* language;    // Language code
    float rate;              // Speaking rate (0.5-2.0)
    float pitch;             // Voice pitch (0.5-2.0)
    int32_t sample_rate;     // Output sample rate
} rac_tts_options_t;

typedef struct rac_tts_result {
    void* audio_data;        // PCM audio (owned)
    size_t audio_size;       // Size in bytes
    double duration_seconds; // Audio duration
    int32_t sample_rate;     // Sample rate
} rac_tts_result_t;
```

### VAD Service

**Types:**
```c
typedef struct rac_vad_result {
    rac_bool_t has_speech;   // Speech detected
    float confidence;        // Detection confidence
    double speech_start_ms;  // Speech start time
    double speech_end_ms;    // Speech end time
} rac_vad_result_t;
```

---

## Backend Implementations

### LlamaCPP Backend

**Architecture:**
```
┌─────────────────────────────────────────────────────────────┐
│                    rac_llm_llamacpp.h                        │
│              Public API + Registration                       │
└────────────────────────────┬────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────┐
│               rac_backend_llamacpp_register.cpp              │
│     • Registers module with capabilities                     │
│     • Registers service provider                             │
│     • Implements can_handle (checks .gguf extension)         │
│     • Implements create (creates service with vtable)        │
└────────────────────────────┬────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────┐
│                  llamacpp_backend.cpp                        │
│     LlamaCppBackend class:                                   │
│     • initialize() - Init llama.cpp backend                  │
│     • cleanup() - Free resources                             │
│     LlamaCppTextGeneration class:                            │
│     • load_model() - Load GGUF model                         │
│     • generate() - Blocking generation                       │
│     • generate_stream() - Streaming generation               │
│     • cancel() - Abort generation                            │
└────────────────────────────┬────────────────────────────────┘
                             │
                    llama.cpp library
```

**Key Implementation Details:**

1. **Model Loading:**
   - Uses `llama_model_load_from_file()`
   - Auto-detects context size from model metadata
   - Configures GPU layers for Metal acceleration

2. **Text Generation:**
   - Tokenizes prompt with `common_tokenize()`
   - Applies chat template via `llama_chat_apply_template()`
   - Samples tokens with configurable sampler chain
   - Supports streaming via callback

3. **Cancellation:**
   - Atomic boolean flag checked in generation loop
   - Graceful abort with partial result

### ONNX Backend (Sherpa-ONNX)

**Architecture:**
```
┌─────────────────────────────────────────────────────────────┐
│    rac_stt_onnx.h    rac_tts_onnx.h    rac_vad_onnx.h      │
│              Public APIs for STT/TTS/VAD                    │
└────────────────────────────┬────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────┐
│               rac_backend_onnx_register.cpp                  │
│     • Registers ONNX module                                  │
│     • Registers STT, TTS, VAD providers                      │
│     • Implements vtables wrapping ONNX APIs                  │
└────────────────────────────┬────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────┐
│                    onnx_backend.cpp                          │
│     Wraps Sherpa-ONNX C API:                                 │
│     • STT: SherpaOnnxOfflineRecognizer                       │
│     • TTS: SherpaOnnxOfflineTts                              │
│     • VAD: SherpaOnnxVoiceActivityDetector                   │
└────────────────────────────┬────────────────────────────────┘
                             │
              Sherpa-ONNX + ONNX Runtime libraries
```

**Supported Models:**
- **STT**: Whisper, Zipformer, Paraformer
- **TTS**: VITS/Piper voices
- **VAD**: Silero VAD

### Platform Backend (Apple)

**Pattern:** C++ provides registration and vtable stubs; Swift provides actual implementation via callbacks.

```
┌─────────────────────────────────────────────────────────────┐
│              Swift SDK (RunAnywhere)                         │
│     Implements callbacks for Foundation Models + TTS         │
└────────────────────────────┬────────────────────────────────┘
                             │ sets callbacks
┌────────────────────────────▼────────────────────────────────┐
│    rac_llm_platform.h / rac_tts_platform.h                   │
│     • rac_platform_llm_set_callbacks()                       │
│     • rac_platform_tts_set_callbacks()                       │
└────────────────────────────┬────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────┐
│            rac_backend_platform_register.cpp                 │
│     • Registers "platform" module                            │
│     • Provider calls Swift callbacks via stored pointers     │
└─────────────────────────────────────────────────────────────┘
```

---

## Data Flow

### LLM Generation Flow

```
App calls RunAnywhere.generate(prompt)
            │
            ▼
    Swift SDK validates state
    Calls rac_llm_generate(handle, prompt, options, &result)
            │
            ▼
    rac_llm_generate() extracts service from handle
    Calls service->ops->generate(service->impl, prompt, options, &result)
            │
            ▼
    LlamaCPP vtable generate():
    1. Build chat-templated prompt
    2. Tokenize prompt
    3. Decode prompt tokens
    4. Sample generation loop:
       - Sample next token
       - Check stop conditions
       - Accumulate output
    5. Populate result struct
            │
            ▼
    Return to Swift
    Swift maps rac_llm_result_t → LLMGenerationResult
            │
            ▼
    Return to App
```

### Streaming Generation Flow

```
App calls RunAnywhere.generateStream(prompt)
            │
            ▼
    Swift SDK calls rac_llm_generate_stream()
    with Swift callback wrapper
            │
            ▼
    Backend generation loop:
    for each token:
        callback(token, is_final, user_data)
            │
            ▼
        Swift callback wrapper:
        - Maps token to Swift String
        - Yields to AsyncStream
            │
            ▼
        App receives token via AsyncStream
```

### Voice Agent Pipeline

```
Audio Input
    │
    ▼
┌───────────────┐
│      VAD      │ ──► Speech detected? No → Continue listening
│  (Energy/AI)  │
└───────┬───────┘
        │ Speech detected
        ▼
┌───────────────┐
│      STT      │ ──► Transcribe audio to text
│  (ONNX/Whisper)│
└───────┬───────┘
        │ Transcription
        ▼
┌───────────────┐
│      LLM      │ ──► Generate response
│  (LlamaCPP)   │
└───────┬───────┘
        │ Response text
        ▼
┌───────────────┐
│      TTS      │ ──► Synthesize speech
│  (ONNX/System)│
└───────┬───────┘
        │
        ▼
   Audio Output
```

---

## Concurrency Model

### Thread Safety

- **Service Registry**: Protected by `std::mutex`
- **Module Registry**: Protected by `std::mutex`
- **Backend State**: Each backend manages its own synchronization
- **Generation**: One generation per service handle at a time

### Cancellation

```c
// Atomic flag pattern
std::atomic<bool> cancel_requested_{false};

// In generation loop
while (generating) {
    if (cancel_requested_.load()) {
        break;  // Graceful exit
    }
    // ... sample next token
}

// Cancel API
void cancel() {
    cancel_requested_.store(true);
}
```

### Callback Invocation

- Callbacks invoked on the calling thread
- No async dispatch within C++ layer
- Platform SDKs handle async conversion (Swift actors, Kotlin coroutines)

---

## Memory Management

### Ownership Rules

1. **OUT parameters with `*` suffix**: Caller owns, must free
   ```c
   rac_llm_result_t result;  // Caller allocates struct
   rac_llm_generate(..., &result);
   // result.text is owned, must free with rac_llm_result_free(&result)
   ```

2. **Static strings**: Library owns, do not free
   ```c
   const char* msg = rac_error_message(code);  // Static, do not free
   ```

3. **Handles**: Created by library, destroyed by caller
   ```c
   rac_handle_t handle;
   rac_llm_create(..., &handle);
   // ... use handle ...
   rac_llm_destroy(handle);  // Required
   ```

### Memory Allocation

```c
// Library allocation functions
RAC_API void* rac_alloc(size_t size);
RAC_API void rac_free(void* ptr);
RAC_API char* rac_strdup(const char* str);

// Result free functions
RAC_API void rac_llm_result_free(rac_llm_result_t* result);
RAC_API void rac_stt_result_free(rac_stt_result_t* result);
RAC_API void rac_tts_result_free(rac_tts_result_t* result);
```

---

## Event System

### Event Types

```c
typedef enum rac_event_type {
    // LLM Events
    RAC_EVENT_LLM_MODEL_LOAD_STARTED = 100,
    RAC_EVENT_LLM_MODEL_LOAD_COMPLETED = 101,
    RAC_EVENT_LLM_GENERATION_STARTED = 110,
    RAC_EVENT_LLM_GENERATION_COMPLETED = 111,
    RAC_EVENT_LLM_FIRST_TOKEN = 113,

    // STT Events
    RAC_EVENT_STT_TRANSCRIPTION_STARTED = 210,
    RAC_EVENT_STT_TRANSCRIPTION_COMPLETED = 211,

    // TTS Events
    RAC_EVENT_TTS_SYNTHESIS_STARTED = 310,
    RAC_EVENT_TTS_SYNTHESIS_COMPLETED = 311,

    // VAD Events
    RAC_EVENT_VAD_SPEECH_STARTED = 402,
    RAC_EVENT_VAD_SPEECH_ENDED = 403,
} rac_event_type_t;
```

### Event Flow

```
C++ Component (e.g., LLM generation)
            │
            ▼
    rac_event_emit(type, &data)
            │
            ▼
    Platform callback (if registered)
            │
            ▼
    Swift EventBridge / Kotlin EventBus
            │
            ▼
    App event subscription
```

### Event Registration

```c
// Platform SDK registers callback
rac_result_t rac_events_set_callback(
    rac_event_callback_fn callback,
    void* user_data
);

// Callback signature
typedef void (*rac_event_callback_fn)(
    rac_event_type_t type,
    const rac_event_data_t* data,
    void* user_data
);
```

---

## Platform Adapter

### Required Callbacks

```c
typedef struct rac_platform_adapter {
    // File System (Required)
    rac_bool_t (*file_exists)(const char* path, void* user_data);

    // Logging (Required)
    void (*log)(rac_log_level_t level, const char* category,
                const char* message, void* user_data);

    // Time (Required)
    int64_t (*now_ms)(void* user_data);

    // Optional
    rac_result_t (*file_read)(...);
    rac_result_t (*file_write)(...);
    rac_result_t (*secure_get)(...);   // Keychain
    rac_result_t (*secure_set)(...);
    rac_result_t (*http_download)(...);
    rac_result_t (*extract_archive)(...);

    void* user_data;  // Passed to all callbacks
} rac_platform_adapter_t;
```

### Swift Implementation Example

```swift
// SwiftPlatformAdapter.swift
private func createPlatformAdapter() -> rac_platform_adapter_t {
    var adapter = rac_platform_adapter_t()

    adapter.file_exists = { path, userData in
        guard let path = path.map(String.init(cString:)) else { return RAC_FALSE }
        return FileManager.default.fileExists(atPath: path) ? RAC_TRUE : RAC_FALSE
    }

    adapter.log = { level, category, message, userData in
        guard let msg = message.map(String.init(cString:)) else { return }
        SDKLogger.shared.log(level: LogLevel(rawValue: level), message: msg)
    }

    adapter.now_ms = { userData in
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    return adapter
}
```

---

## Error Handling

### Error Code Structure

```c
// Success
#define RAC_SUCCESS ((rac_result_t)0)

// Error ranges
// -100 to -109: Initialization errors
#define RAC_ERROR_NOT_INITIALIZED       -100
#define RAC_ERROR_ALREADY_INITIALIZED   -101

// -110 to -129: Model errors
#define RAC_ERROR_MODEL_NOT_FOUND       -110
#define RAC_ERROR_MODEL_LOAD_FAILED     -111

// -130 to -149: Generation errors
#define RAC_ERROR_GENERATION_FAILED     -130
#define RAC_ERROR_CONTEXT_TOO_LONG      -132

// -400 to -499: Service errors
#define RAC_ERROR_NO_CAPABLE_PROVIDER   -422
```

### Error Details

```c
// Get error message
const char* msg = rac_error_message(result);

// Set detailed error context
rac_error_set_details("Model file not found at: /path/to/model.gguf");

// Get detailed error
const char* details = rac_error_get_details();
```

### Error Propagation

```c
rac_result_t my_function() {
    rac_result_t result = some_operation();
    if (RAC_FAILED(result)) {
        rac_error_set_details("Operation failed during my_function");
        return result;  // Propagate error code
    }
    return RAC_SUCCESS;
}
```

---

## Extensibility

### Adding a New Backend

1. **Create directory**: `src/backends/<name>/`

2. **Implement backend class**:
   ```cpp
   // <name>_backend.cpp
   class MyBackend {
       bool load_model(const std::string& path, const nlohmann::json& config);
       Result generate(const std::string& prompt, const Options& options);
   };
   ```

3. **Create RAC API wrapper**:
   ```c
   // rac_<cap>_<name>.h
   RAC_API rac_result_t rac_<cap>_<name>_create(..., rac_handle_t* out);
   RAC_API rac_result_t rac_<cap>_<name>_process(...);
   RAC_API void rac_<cap>_<name>_destroy(rac_handle_t handle);
   ```

4. **Implement vtable and registration**:
   ```cpp
   // rac_backend_<name>_register.cpp
   static const rac_<cap>_service_ops_t g_<name>_ops = {
       .initialize = ...,
       .process = ...,
       .destroy = ...
   };

   rac_result_t rac_backend_<name>_register() {
       // Register module
       // Register service provider with can_handle + create
   }
   ```

5. **Add to CMakeLists.txt**:
   ```cmake
   option(RAC_BACKEND_<NAME> "Build <name> backend" ON)
   if(RAC_BACKEND_<NAME>)
       add_subdirectory(src/backends/<name>)
   endif()
   ```

### Adding a New Capability

1. Create type definitions in `include/rac/features/<cap>/rac_<cap>_types.h`
2. Create service interface in `include/rac/features/<cap>/rac_<cap>_service.h`
3. Create public API in `include/rac/features/<cap>/rac_<cap>.h`
4. Add capability enum value to `rac_capability_t`
5. Implement service in `src/features/<cap>/`

---

## Testing

### Unit Testing

- Tests in `tests/` directory
- CMake option: `RAC_BUILD_TESTS=ON`
- Uses platform SDK integration tests for E2E validation

### Manual Testing

```bash
# Build with test support
cmake -B build -DRAC_BUILD_TESTS=ON
cmake --build build
ctest --test-dir build
```

### Integration Testing

Integration tests run through platform SDKs:
- Swift: `Tests/RunAnywhereTests/`
- Kotlin: `sdk/runanywhere-kotlin/src/test/`

---

## Design Decisions

### Why C API Instead of C++?

**Decision**: Pure C API surface with C++ implementation

**Rationale:**
- Swift/Kotlin FFI bindings work better with C
- No C++ name mangling issues
- Easier to maintain ABI stability
- Compatible with Dart FFI for Flutter

### Why Vtable Instead of Virtual Functions?

**Decision**: C-style vtables instead of C++ virtual inheritance

**Rationale:**
- No C++ RTTI needed at API boundaries
- POD structs are simpler for FFI
- Backend libraries can be statically linked without issues
- Explicit ownership model

### Why Priority-Based Provider Selection?

**Decision**: Multiple providers can register for same capability with priority

**Rationale:**
- Mirrors successful Swift SDK pattern
- Allows platform-specific optimizations (Apple FM for LLM on iOS)
- Graceful fallback if primary provider can't handle request
- Runtime flexibility without code changes

### Why Separate XCFrameworks?

**Decision**: RACommons + RABackendLLAMACPP + RABackendONNX as separate frameworks

**Rationale:**
- Apps include only what they need
- Significant binary size savings (82% for LLM-only apps)
- Independent versioning possible
- Matches App Store best practices

---

## See Also

- [README.md](./README.md) - Getting started guide
- [../CLAUDE.md](../CLAUDE.md) - AI context and coding guidelines
