# RunAnywhere Commons

**runanywhere-commons** is a unified C/C++ library that serves as the foundation for the RunAnywhere SDK ecosystem. It provides the core infrastructure, service abstraction layer, and ML backend integrations that power on-device AI capabilities across iOS, Android, macOS, and Linux platforms.

---

## Table of Contents

- [Overview](#overview)
- [Key Features](#key-features)
- [Architecture Overview](#architecture-overview)
- [Supported Capabilities](#supported-capabilities)
- [Backend Integrations](#backend-integrations)
- [Getting Started](#getting-started)
- [Building](#building)
- [API Reference](#api-reference)
- [Platform Integration](#platform-integration)
- [Dependencies](#dependencies)
- [Version Management](#version-management)

---

## Overview

RunAnywhere Commons is the shared C++ layer that sits between platform SDKs (Swift, Kotlin, Flutter) and ML inference backends (LlamaCPP, ONNX/Sherpa-ONNX, WhisperCPP). It provides:

- **Unified C API** - All public functions use the `rac_` prefix and follow a consistent vtable-based abstraction pattern
- **Backend Abstraction** - Multiple ML backends can be registered and selected at runtime based on model requirements
- **Service Registry** - Priority-based provider selection matching the Swift SDK's `ServiceRegistry` pattern
- **Cross-Platform Support** - Single codebase targeting iOS, Android, macOS, and Linux
- **Platform Services** - Native integration with Apple Foundation Models and System TTS on Apple platforms

### Design Principles

- **C++ Core, C API Surface** - C++20 internally, pure C API for FFI compatibility
- **Vtable-Based Polymorphism** - No C++ virtual inheritance at API boundaries
- **Priority-Based Dispatch** - Service providers register with priority; first capable handler wins
- **Lazy Initialization** - Services created on-demand, not at startup
- **Single Source of Truth** - Events, analytics, and state managed centrally in C++

---

## Key Features

### Core Infrastructure
- **Logging System** - Platform-bridged logging with categories (`RAC_LOG_INFO`, `RAC_LOG_ERROR`)
- **Error Handling** - Comprehensive error codes (-100 to -999 range) with detailed messages
- **Event System** - Cross-platform analytics events emitted from C++ to platform SDKs
- **Memory Management** - Consistent allocation/deallocation patterns (`rac_alloc`, `rac_free`)

### Service Layer
- **Module Registry** - Backend modules register capabilities at startup
- **Service Registry** - Priority-based factory pattern for service creation
- **Lifecycle Management** - Consistent state machine for component lifecycle
- **Model Registry** - Central model metadata and path management

### AI Capabilities
- **LLM (Text Generation)** - Streaming and batch generation with metrics
- **STT (Speech-to-Text)** - Real-time and batch transcription
- **TTS (Text-to-Speech)** - High-quality speech synthesis
- **VAD (Voice Activity Detection)** - Energy-based voice detection
- **Voice Agent** - Orchestrated pipeline (VAD → STT → LLM → TTS)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Swift/Kotlin SDKs                        │
│              (RunAnywhere, RunAnywhereKotlin)               │
└────────────────────────────┬────────────────────────────────┘
                             │ C API (rac_*)
┌────────────────────────────▼────────────────────────────────┐
│              RAC Public C API (rac_*)                       │
│   rac_llm_service.h, rac_stt_service.h, rac_tts_service.h   │
│   rac_vad_service.h, rac_voice_agent.h                      │
└────────────────────────────┬────────────────────────────────┘
                             │ vtable dispatch
┌────────────────────────────▼────────────────────────────────┐
│              Service & Module Registry                       │
│   - Priority-based provider selection                        │
│   - canHandle pattern for capability matching                │
│   - Lazy service instantiation                               │
└────────────────────────────┬────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────┐
│                     Backends (src/backends/)                │
│   ┌─────────────┐  ┌─────────────────┐  ┌───────────────┐   │
│   │  llamacpp/  │  │      onnx/      │  │  whispercpp/  │   │
│   │  LLM (GGUF) │  │ STT/TTS/VAD     │  │  STT (GGML)   │   │
│   │  Metal GPU  │  │ (Sherpa-ONNX)   │  │  Whisper.cpp  │   │
│   └─────────────┘  └─────────────────┘  └───────────────┘   │
│                                                              │
│   ┌─────────────────────────────────────────────────────┐   │
│   │                  platform/                           │   │
│   │   Apple Foundation Models (LLM) + System TTS         │   │
│   │   (Swift callbacks, iOS/macOS only)                  │   │
│   └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## Supported Capabilities

| Capability | Description | Backends |
|------------|-------------|----------|
| **TEXT_GENERATION** | LLM text generation with streaming | LlamaCPP, Platform (Apple FM) |
| **STT** | Speech-to-text transcription | ONNX (Sherpa), WhisperCPP |
| **TTS** | Text-to-speech synthesis | ONNX (Sherpa), Platform (System TTS) |
| **VAD** | Voice activity detection | ONNX (Silero), Built-in (Energy-based) |
| **VOICE_AGENT** | Full voice pipeline orchestration | Composite (STT+LLM+TTS+VAD) |

---

## Backend Integrations

### LlamaCPP Backend
- **Capability**: LLM text generation
- **Model Format**: GGUF (quantized models)
- **GPU Acceleration**: Metal (iOS/macOS), CPU NEON (Android)
- **Features**: Streaming generation, chat templates, cancellation
- **Header**: `include/rac/backends/rac_llm_llamacpp.h`

```c
// Create and load a GGUF model
rac_handle_t handle;
rac_llm_llamacpp_create("/path/to/model.gguf", NULL, &handle);

// Generate text with streaming
rac_llm_options_t options = RAC_LLM_OPTIONS_DEFAULT;
options.max_tokens = 256;
options.temperature = 0.7f;

rac_llm_llamacpp_generate_stream(handle, "Hello, world!", &options,
    token_callback, user_data);
```

### ONNX Backend (via Sherpa-ONNX)
- **Capabilities**: STT, TTS, VAD
- **Model Format**: ONNX
- **Supported Models**: Whisper, Zipformer, Paraformer (STT); VITS/Piper (TTS); Silero (VAD)
- **Headers**: `rac_stt_onnx.h`, `rac_tts_onnx.h`, `rac_vad_onnx.h`

```c
// Create STT service
rac_handle_t stt;
rac_stt_onnx_create("/path/to/whisper", NULL, &stt);

// Transcribe audio
rac_stt_result_t result;
rac_stt_onnx_transcribe(stt, audio_samples, num_samples, NULL, &result);
printf("Transcription: %s\n", result.text);
```

### WhisperCPP Backend
- **Capability**: STT (speech-to-text)
- **Model Format**: GGML (quantized Whisper models)
- **Features**: Fast CPU inference, multiple languages
- **Header**: `include/rac/backends/rac_stt_whispercpp.h`

### Platform Backend (Apple-only)
- **Capabilities**: LLM (Apple Foundation Models), TTS (System TTS)
- **Pattern**: C++ provides vtable registration, Swift provides actual implementation via callbacks
- **Features**: On-device Apple Intelligence models, system voices
- **Headers**: `rac_llm_platform.h`, `rac_tts_platform.h`

---

## Getting Started

### Prerequisites

- **CMake** 3.22 or higher
- **C++20** compatible compiler (Clang, GCC, MSVC)
- **Platform-specific**: Xcode 15+ (iOS/macOS), Android NDK r25+ (Android)

### Quick Start

```bash
# Clone the repository
cd runanywhere-all/sdks/sdk/runanywhere-commons

# Configure and build (macOS/Linux)
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build

# Build with backends
cmake -B build -DRAC_BUILD_BACKENDS=ON
cmake --build build
```

### Basic Usage

```c
#include "rac/core/rac_core.h"
#include "rac/features/llm/rac_llm_service.h"

// Initialize the library
rac_config_t config = {
    .platform_adapter = &my_platform_adapter,
    .log_level = RAC_LOG_INFO,
    .log_tag = "MyApp"
};
rac_init(&config);

// Register backends
rac_backend_llamacpp_register();
rac_backend_onnx_register();

// Create an LLM service
rac_handle_t llm;
rac_llm_create("my-model-id", &llm);

// Generate text
rac_llm_result_t result;
rac_llm_generate(llm, "Hello!", NULL, &result);
printf("Response: %s\n", result.text);

// Cleanup
rac_llm_result_free(&result);
rac_llm_destroy(llm);
rac_shutdown();
```

---

## Building

### CMake Options

| Option | Default | Description |
|--------|---------|-------------|
| `RAC_BUILD_JNI` | OFF | Build JNI bridge for Android/JVM |
| `RAC_BUILD_TESTS` | OFF | Build unit tests |
| `RAC_BUILD_SHARED` | OFF | Build shared libraries (default: static) |
| `RAC_BUILD_PLATFORM` | ON | Build platform backend (Apple FM, System TTS) |
| `RAC_BUILD_BACKENDS` | OFF | Build ML backends |
| `RAC_BACKEND_LLAMACPP` | ON | Build LlamaCPP backend (when BACKENDS=ON) |
| `RAC_BACKEND_ONNX` | ON | Build ONNX backend (when BACKENDS=ON) |
| `RAC_BACKEND_WHISPERCPP` | OFF | Build WhisperCPP backend (when BACKENDS=ON) |

### Platform-Specific Builds

#### iOS
```bash
./scripts/build-ios.sh                    # Full build
./scripts/build-ios.sh --skip-download    # Use cached dependencies
./scripts/build-ios.sh --backend llamacpp # Specific backend only
./scripts/build-ios.sh --package          # Create XCFramework ZIPs
```

#### Android
```bash
./scripts/build-android.sh                     # All backends, all ABIs
./scripts/build-android.sh llamacpp            # LlamaCPP only
./scripts/build-android.sh onnx arm64-v8a      # Specific backend + ABI
./scripts/build-android.sh --check             # Verify 16KB alignment
```

### Build Outputs

#### iOS/macOS
```
dist/
├── RACommons.xcframework              # Core library
├── RABackendLLAMACPP.xcframework      # LLM backend
└── RABackendONNX.xcframework          # STT/TTS/VAD backend
```

#### Android
```
dist/android/
├── jni/{abi}/                         # JNI libraries
│   ├── librac_commons_jni.so
│   ├── librac_backend_llamacpp_jni.so
│   └── librac_backend_onnx_jni.so
└── onnx/{abi}/                        # ONNX runtime
    └── libonnxruntime.so
```

---

## API Reference

### Core API

```c
// Initialization
rac_result_t rac_init(const rac_config_t* config);
void rac_shutdown(void);
rac_bool_t rac_is_initialized(void);
rac_version_t rac_get_version(void);

// Module Registration
rac_result_t rac_module_register(const rac_module_info_t* info);
rac_result_t rac_module_unregister(const char* module_id);
rac_result_t rac_module_list(const rac_module_info_t** out_modules, size_t* out_count);

// Service Creation
rac_result_t rac_service_register_provider(const rac_service_provider_t* provider);
rac_result_t rac_service_create(rac_capability_t capability,
                                const rac_service_request_t* request,
                                rac_handle_t* out_handle);
```

### LLM Service

```c
rac_result_t rac_llm_create(const char* model_id, rac_handle_t* out_handle);
rac_result_t rac_llm_generate(rac_handle_t handle, const char* prompt,
                              const rac_llm_options_t* options, rac_llm_result_t* out_result);
rac_result_t rac_llm_generate_stream(rac_handle_t handle, const char* prompt,
                                     const rac_llm_options_t* options,
                                     rac_llm_stream_callback_fn callback, void* user_data);
rac_result_t rac_llm_cancel(rac_handle_t handle);
void rac_llm_destroy(rac_handle_t handle);
```

### STT Service

```c
rac_result_t rac_stt_create(const char* model_path, rac_handle_t* out_handle);
rac_result_t rac_stt_transcribe(rac_handle_t handle, const void* audio_data, size_t audio_size,
                                const rac_stt_options_t* options, rac_stt_result_t* out_result);
rac_result_t rac_stt_transcribe_stream(rac_handle_t handle, const void* audio_data,
                                       size_t audio_size, const rac_stt_options_t* options,
                                       rac_stt_stream_callback_t callback, void* user_data);
void rac_stt_destroy(rac_handle_t handle);
```

### TTS Service

```c
rac_result_t rac_tts_create(const char* voice_id, rac_handle_t* out_handle);
rac_result_t rac_tts_synthesize(rac_handle_t handle, const char* text,
                                const rac_tts_options_t* options, rac_tts_result_t* out_result);
rac_result_t rac_tts_stop(rac_handle_t handle);
void rac_tts_destroy(rac_handle_t handle);
```

### VAD Service

```c
rac_result_t rac_vad_create(rac_handle_t* out_handle);
rac_result_t rac_vad_start(rac_handle_t handle);
rac_result_t rac_vad_stop(rac_handle_t handle);
rac_result_t rac_vad_process_samples(rac_handle_t handle, const float* samples,
                                     size_t num_samples, rac_bool_t* out_is_speech);
void rac_vad_destroy(rac_handle_t handle);
```

### Voice Agent

```c
rac_result_t rac_voice_agent_create_standalone(rac_voice_agent_handle_t* out_handle);
rac_result_t rac_voice_agent_load_stt_model(rac_voice_agent_handle_t handle,
                                            const char* model_path, const char* model_id,
                                            const char* model_name);
rac_result_t rac_voice_agent_load_llm_model(rac_voice_agent_handle_t handle,
                                            const char* model_path, const char* model_id,
                                            const char* model_name);
rac_result_t rac_voice_agent_load_tts_voice(rac_voice_agent_handle_t handle,
                                            const char* voice_path, const char* voice_id,
                                            const char* voice_name);
rac_result_t rac_voice_agent_process_voice_turn(rac_voice_agent_handle_t handle,
                                                const void* audio_data, size_t audio_size,
                                                rac_voice_agent_result_t* out_result);
void rac_voice_agent_destroy(rac_voice_agent_handle_t handle);
```

---

## Platform Integration

### Swift SDK Integration

The Swift SDK (`runanywhere-swift`) integrates via the `CRACommons` module:

1. Swift imports C headers via module map
2. `SwiftPlatformAdapter` provides platform callbacks (storage, logging)
3. `CommonsErrorMapping` converts `rac_result_t` to Swift `SDKError`
4. `EventBridge` subscribes to C++ events, republishes to Swift `EventBus`

### Kotlin SDK Integration

The Kotlin SDK (`runanywhere-kotlin`) integrates via JNI:

1. JNI bridge libraries: `librac_*_jni.so`
2. Platform adapter implemented via JNI callbacks
3. Type marshaling between Java and C types
4. Coroutine-based async wrappers around blocking C calls

### Platform Adapter

Platform SDKs must provide a `rac_platform_adapter_t` with callbacks for:

```c
typedef struct rac_platform_adapter {
    // File operations
    rac_bool_t (*file_exists)(const char* path, void* user_data);
    rac_result_t (*file_read)(const char* path, void** out_data, size_t* out_size, void* user_data);
    rac_result_t (*file_write)(const char* path, const void* data, size_t size, void* user_data);

    // Secure storage
    rac_result_t (*secure_get)(const char* key, char** out_value, void* user_data);
    rac_result_t (*secure_set)(const char* key, const char* value, void* user_data);

    // Logging
    void (*log)(rac_log_level_t level, const char* category, const char* message, void* user_data);

    // Time
    int64_t (*now_ms)(void* user_data);

    // Optional: HTTP download, archive extraction
    // ...

    void* user_data;
} rac_platform_adapter_t;
```

---

## Dependencies

### External Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| **llama.cpp** | b7650 | LLM inference engine |
| **Sherpa-ONNX** | 1.12.18+ | STT/TTS/VAD via ONNX Runtime |
| **ONNX Runtime** | 1.17.1+ | Neural network inference |
| **nlohmann/json** | 3.11.3 | JSON parsing |

### Binary Outputs

| Framework | Size | Provides |
|-----------|------|----------|
| `RACommons.xcframework` | ~2MB | Core infrastructure, registries, events |
| `RABackendLLAMACPP.xcframework` | ~15-25MB | LLM capability (GGUF models) |
| `RABackendONNX.xcframework` | ~50-70MB | STT, TTS, VAD (ONNX models) |

---

## Version Management

All versions are centralized in the `VERSIONS` file:

```bash
PROJECT_VERSION=1.0.0
IOS_DEPLOYMENT_TARGET=13.0
ANDROID_MIN_SDK=24
ONNX_VERSION_IOS=1.17.1
SHERPA_ONNX_VERSION_IOS=1.12.18
LLAMACPP_VERSION=b7650
```

Load versions in scripts:
```bash
source scripts/load-versions.sh
echo "Using llama.cpp version: $LLAMACPP_VERSION"
```

Load versions in CMake:
```cmake
include(LoadVersions)
message(STATUS "ONNX Runtime version: ${ONNX_VERSION_IOS}")
```

---

## Error Codes

Error codes are organized by range:

| Range | Category |
|-------|----------|
| 0 | Success |
| -100 to -109 | Initialization errors |
| -110 to -129 | Model errors |
| -130 to -149 | Generation errors |
| -150 to -179 | Network errors |
| -180 to -219 | Storage errors |
| -220 to -229 | Hardware errors |
| -230 to -249 | Component state errors |
| -250 to -279 | Validation errors |
| -280 to -299 | Audio errors |
| -300 to -319 | Language/Voice errors |
| -400 to -499 | Module/Service errors |
| -600 to -699 | Backend errors |
| -700 to -799 | Event errors |

---

## Contributing

See the main repository [CONTRIBUTING.md](../../CONTRIBUTING.md) for guidelines.

### Code Style

- Follow Google C++ Style Guide with project customizations
- Run `./scripts/lint-cpp.sh --fix` before committing
- All public symbols use `rac_` prefix

---

## License

See [LICENSE](../../LICENSE) for details.
