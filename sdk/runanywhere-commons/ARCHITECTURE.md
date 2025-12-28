# RunAnywhere Commons Architecture

## Overview

`runanywhere-commons` is a modular C++ library that provides the shared business logic for the RunAnywhere SDK. It serves as the foundation layer that all platform SDKs (Swift, Kotlin, React Native, Flutter) build upon.

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Platform SDKs (Thin Wrappers)                   │
├───────────────┬───────────────┬─────────────────┬───────────────────┤
│  Swift SDK    │  Kotlin SDK   │  React Native   │    Flutter        │
│  (iOS/macOS)  │  (Android)    │                 │                   │
└───────┬───────┴───────┬───────┴────────┬────────┴─────────┬─────────┘
        │               │                │                  │
        └───────────────┴────────────────┴──────────────────┘
                                │
                    ┌───────────▼───────────┐
                    │  runanywhere-commons  │
                    │    (C++ Business      │
                    │       Logic)          │
                    └───────────┬───────────┘
                                │
                    ┌───────────▼───────────┐
                    │   runanywhere-core    │
                    │    (ML Inference)     │
                    └───────────────────────┘
```

## Design Principles

### 1. iOS SDK as Source of Truth

⚠️ **CRITICAL**: The iOS Swift SDK (`runanywhere-swift`) is the source of truth for all implementations. When implementing features in C++:

- Read the Swift implementation first
- Copy the logic directly without modifications
- Do NOT add custom features or "improvements"
- Match the Swift interface as closely as possible

### 2. Thin Platform Wrappers

Platform SDKs are thin wrappers around the C++ layer:

- Swift actors/classes wrap C handles
- Async/await bridges to C callbacks
- Type conversions (Swift ↔ C)
- Platform-specific integrations only (UI, audio capture/playback)

### 3. Business Logic in C++

All business logic resides in the C++ layer:

- Lifecycle management
- Model loading/unloading
- Generation/transcription/synthesis orchestration
- Metrics collection (TTFT, tokens/sec)
- Event publishing
- Download orchestration (HTTP delegated to platform)
- Model registry

## Directory Structure

```
runanywhere-commons/
├── include/rac/
│   ├── core/                          # Core types and platform adapter
│   │   ├── rac_types.h               # Base types (rac_bool_t, rac_result_t)
│   │   ├── rac_error.h               # Error codes (-100 to -999)
│   │   ├── rac_core.h                # Initialization API
│   │   ├── rac_platform_adapter.h    # Platform callbacks interface
│   │   └── capabilities/
│   │       └── rac_lifecycle.h       # Lifecycle state machine
│   │
│   ├── features/
│   │   ├── llm/                      # LLM capability
│   │   │   ├── rac_llm_types.h      # LLM data types
│   │   │   ├── rac_llm_service.h    # Low-level service API
│   │   │   ├── rac_llm_component.h  # High-level component API
│   │   │   └── rac_llm_metrics.h    # Streaming metrics (TTFT)
│   │   │
│   │   ├── stt/                      # STT capability
│   │   │   ├── rac_stt_types.h
│   │   │   ├── rac_stt_service.h
│   │   │   └── rac_stt_component.h
│   │   │
│   │   ├── tts/                      # TTS capability
│   │   │   ├── rac_tts_types.h
│   │   │   ├── rac_tts_service.h
│   │   │   └── rac_tts_component.h
│   │   │
│   │   ├── vad/                      # VAD capability
│   │   │   ├── rac_vad_types.h
│   │   │   ├── rac_vad_service.h
│   │   │   ├── rac_vad_component.h
│   │   │   └── rac_vad_energy.h     # Energy-based VAD
│   │   │
│   │   └── voice_agent/              # Voice Agent orchestration
│   │       └── rac_voice_agent.h
│   │
│   └── infrastructure/
│       ├── events/
│       │   └── rac_events.h          # Event publishing system
│       │
│       ├── download/
│       │   └── rac_download.h        # Download orchestration
│       │
│       └── model_management/
│           └── rac_model_registry.h  # Model metadata registry
│
├── src/                              # Implementations
│   ├── core/
│   ├── features/
│   └── infrastructure/
│
├── backends/                         # Backend modules
│   ├── llamacpp/                    # LlamaCpp backend
│   ├── onnx/                        # ONNX Runtime backend
│   └── whispercpp/                  # WhisperCpp backend
│
├── exports/                          # Symbol export files
│   ├── RACommons.exports
│   ├── RABackendLlamaCPP.exports
│   ├── RABackendONNX.exports
│   └── RABackendWhisperCPP.exports
│
└── scripts/                          # Build scripts
    ├── build-ios.sh
    ├── build-android.sh
    └── lint-cpp.sh
```

## API Layers

### Low-Level Service API (`rac_*_service.h`)

Direct bindings to `runanywhere-core` backends. Used by the component layer.

```c
// Example: LLM Service
rac_result_t rac_llm_create(rac_llm_handle_t* handle);
rac_result_t rac_llm_initialize(rac_llm_handle_t handle, const char* model_path, const rac_llm_config_t* config);
rac_result_t rac_llm_generate(rac_llm_handle_t handle, const char* prompt, const rac_llm_options_t* options, rac_llm_result_t** result);
void rac_llm_destroy(rac_llm_handle_t handle);
```

### High-Level Component API (`rac_*_component.h`)

Components add lifecycle management, state tracking, and error handling on top of services.

```c
// Example: LLM Component
rac_result_t rac_llm_component_create(rac_llm_component_handle_t* handle);
rac_result_t rac_llm_component_initialize(rac_llm_component_handle_t handle, const char* model_id, const rac_llm_component_config_t* config);
rac_result_t rac_llm_component_is_ready(rac_llm_component_handle_t handle, rac_bool_t* is_ready);
rac_result_t rac_llm_component_generate(rac_llm_component_handle_t handle, const char* prompt, const rac_llm_options_t* options, rac_llm_result_t** result);
void rac_llm_component_destroy(rac_llm_component_handle_t handle);
```

## Platform Adapter

The platform adapter is how the C++ layer communicates with platform-specific services:

```c
typedef struct rac_platform_adapter {
    // File system
    rac_bool_t (*file_exists)(const char* path, void* user_data);
    rac_result_t (*file_read)(const char* path, void** data, size_t* size, void* user_data);
    rac_result_t (*file_write)(const char* path, const void* data, size_t size, void* user_data);

    // Secure storage
    rac_result_t (*secure_get)(const char* key, char** value, void* user_data);
    rac_result_t (*secure_set)(const char* key, const char* value, void* user_data);

    // Logging
    void (*log)(rac_log_level_t level, const char* category, const char* message, void* user_data);

    // Clock
    int64_t (*now_ms)(void* user_data);

    // HTTP Download (delegated to platform)
    rac_result_t (*http_download)(...);

    // Archive extraction (delegated to platform)
    rac_result_t (*extract_archive)(...);

    void* user_data;
} rac_platform_adapter_t;
```

## Error Codes

```c
// runanywhere-core errors: 0 to -99 (ra_*)
// runanywhere-commons errors: -100 to -999 (rac_*)

// General errors: -100 to -199
#define RAC_ERROR_UNKNOWN           (-100)
#define RAC_ERROR_INVALID_ARGUMENT  (-101)
#define RAC_ERROR_NOT_INITIALIZED   (-104)
#define RAC_ERROR_NOT_FOUND         (-113)

// LLM errors: -200 to -299
// STT errors: -300 to -399
// TTS errors: -400 to -499
// VAD errors: -500 to -599
// Download errors: -600 to -699
// Model registry errors: -700 to -799
```

## Swift Integration Example

```swift
// Swift wrapper is a thin actor around C handles
public actor LLMCapability {
    private var handle: rac_llm_component_handle_t?

    public func loadModel(_ modelId: String) async throws {
        if handle == nil {
            var newHandle: rac_llm_component_handle_t?
            let result = rac_llm_component_create(&newHandle)
            guard result == RAC_SUCCESS else { throw SDKError.llm(.modelLoadFailed) }
            handle = newHandle
        }

        let result = modelId.withCString { ptr in
            rac_llm_component_initialize(handle, ptr, nil)
        }
        guard result == RAC_SUCCESS else { throw SDKError.llm(.modelLoadFailed) }
    }

    public func generate(_ prompt: String) async throws -> LLMGenerationResult {
        var result: UnsafeMutablePointer<rac_llm_result_t>?
        let generateResult = prompt.withCString { ptr in
            rac_llm_component_generate(handle, ptr, nil, &result)
        }
        // Convert C result to Swift struct...
    }
}
```

## Building

### macOS (Development)

```bash
cd runanywhere-commons
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Debug
cmake --build .
```

### iOS XCFrameworks

```bash
cd runanywhere-commons
./scripts/build-ios.sh
# Output: dist/RACommons.xcframework, dist/RABackendLlamaCPP.xcframework, etc.
```

### Android

```bash
cd runanywhere-commons
./scripts/build-android.sh
# Output: dist/android/*.so
```

## Symbol Exports

Each XCFramework has a corresponding exports file listing public symbols:

- `exports/RACommons.exports` - Core and capability APIs
- `exports/RABackendLlamaCPP.exports` - LlamaCpp backend
- `exports/RABackendONNX.exports` - ONNX Runtime backend
- `exports/RABackendWhisperCPP.exports` - WhisperCpp backend
