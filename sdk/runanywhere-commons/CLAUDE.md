# CLAUDE.md - AI Context for runanywhere-commons

## Core Principles

- Focus on **SIMPLICITY**, following Clean SOLID principles. Reusability, clean architecture, clear separation of concerns.
- Do NOT write ANY MOCK IMPLEMENTATION unless specified otherwise.
- DO NOT PLAN or WRITE any unit tests unless specified otherwise.
- Always use **structured types**, never use strings directly for consistency and scalability.
- When fixing issues focus on **SIMPLICITY** - do not add complicated logic unless necessary.
- Don't over plan it, always think **MVP**.

## C++ Specific Rules

- C++17 standard required
- Google C++ Style Guide with project customizations (see `.clang-format`)
- Run `./scripts/lint-cpp.sh` before committing
- Use `./scripts/lint-cpp.sh --fix` to auto-fix formatting issues
- All public symbols prefixed with `rac_` (RunAnywhere Commons)

## Project Overview

`runanywhere-commons` is a **unified** C/C++ library containing:
1. **Core Infrastructure** - Logging, errors, events, lifecycle management, SDK state
2. **RAC Services** - Public C APIs for LLM, STT, TTS, VAD (vtable-based abstraction)
3. **Backends** - ML inference backends (LlamaCPP, ONNX/Sherpa-ONNX, sd.cpp, WhisperCPP) in `src/backends/`
4. **Platform Services** - Apple Foundation Models, System TTS (iOS/macOS only)
5. **Infrastructure** - Model management, network services, device management, telemetry

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Swift/Kotlin SDKs                        │
└────────────────────────────┬────────────────────────────────┘
                             │ uses (CRACommons / JNI)
┌────────────────────────────▼────────────────────────────────┐
│              RAC Public C API (rac_*)                       │
│   rac_llm_service.h, rac_stt_service.h, rac_tts_service.h   │
│   rac_vad_service.h, rac_voice_agent.h                      │
└────────────────────────────┬────────────────────────────────┘
                             │ dispatches via vtables
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
│   │   ├── rac_audio_utils.h       # Audio processing utilities
│   │   ├── rac_sdk_state.h         # SDK state management
│   │   ├── rac_structured_error.h  # Structured error handling
│   │   ├── rac_platform_adapter.h  # Platform callbacks
│   │   └── capabilities/
│   │       └── rac_lifecycle.h     # Component lifecycle states
│   ├── features/                   # Service interfaces
│   │   ├── llm/                    # Large Language Models
│   │   │   ├── rac_llm_service.h   # LLM vtable interface
│   │   │   ├── rac_llm_types.h     # LLM data structures
│   │   │   ├── rac_llm_component.h # Component lifecycle
│   │   │   ├── rac_llm_metrics.h   # Metrics collection
│   │   │   ├── rac_llm_analytics.h # Analytics integration
│   │   │   └── rac_llm.h           # Public API wrapper
│   │   ├── stt/                    # Speech-to-Text
│   │   │   ├── rac_stt_service.h   # STT vtable interface
│   │   │   ├── rac_stt_types.h     # STT data structures
│   │   │   ├── rac_stt_component.h # Component lifecycle
│   │   │   └── rac_stt.h           # Public API
│   │   ├── tts/                    # Text-to-Speech
│   │   │   ├── rac_tts_service.h   # TTS vtable interface
│   │   │   ├── rac_tts_types.h     # TTS data structures
│   │   │   ├── rac_tts_component.h # Component lifecycle
│   │   │   └── rac_tts.h           # Public API
│   │   ├── vad/                    # Voice Activity Detection
│   │   │   ├── rac_vad_service.h   # VAD vtable interface
│   │   │   ├── rac_vad_types.h     # VAD data structures
│   │   │   ├── rac_vad_energy.h    # Energy-based VAD (built-in)
│   │   │   └── rac_vad.h           # Public API
│   │   ├── voice_agent/            # Complete voice pipeline
│   │   │   └── rac_voice_agent.h   # STT+LLM+TTS+VAD orchestration
│   │   └── platform/               # Platform-specific backends
│   │       ├── rac_llm_platform.h  # Apple Foundation Models
│   │       └── rac_tts_platform.h  # Apple System TTS
│   ├── infrastructure/             # Support services
│   │   ├── model_management/       # Model registry and lifecycle
│   │   │   ├── rac_model_registry.h
│   │   │   ├── rac_model_types.h
│   │   │   ├── rac_model_paths.h
│   │   │   └── rac_download.h
│   │   ├── network/                # Network services
│   │   │   ├── rac_http_client.h
│   │   │   ├── rac_endpoints.h
│   │   │   ├── rac_environment.h
│   │   │   └── rac_auth_manager.h
│   │   ├── device/
│   │   │   └── rac_device_manager.h
│   │   ├── storage/
│   │   │   └── rac_storage_analyzer.h
│   │   └── telemetry/
│   │       └── rac_telemetry_manager.h
│   └── backends/                   # Backend-specific public headers
│       ├── rac_llm_llamacpp.h      # LlamaCPP backend API
│       ├── rac_diffusion_sdcpp.h   # sd.cpp Diffusion backend API
│       ├── rac_stt_whispercpp.h    # WhisperCPP backend API
│       ├── rac_stt_onnx.h          # ONNX STT API
│       ├── rac_tts_onnx.h          # ONNX TTS API
│       └── rac_vad_onnx.h          # ONNX VAD API
│
├── src/                            # Implementation files
│   ├── core/                       # Core implementations
│   │   ├── rac_core.cpp            # SDK initialization
│   │   ├── rac_error.cpp           # Error message mappings
│   │   ├── rac_logger.cpp          # Logging implementation
│   │   ├── rac_audio_utils.cpp     # Audio processing
│   │   ├── sdk_state.cpp           # SDK state management
│   │   └── capabilities/
│   │       └── lifecycle_manager.cpp
│   ├── infrastructure/             # Infrastructure implementations
│   │   ├── registry/
│   │   │   ├── service_registry.cpp
│   │   │   └── module_registry.cpp
│   │   ├── model_management/
│   │   │   ├── model_registry.cpp
│   │   │   ├── model_paths.cpp
│   │   │   └── model_strategy.cpp
│   │   ├── network/
│   │   │   ├── http_client.cpp
│   │   │   └── auth_manager.cpp
│   │   └── telemetry/
│   │       └── telemetry_manager.cpp
│   ├── features/                   # Feature implementations
│   │   ├── llm/
│   │   │   ├── llm_component.cpp
│   │   │   ├── rac_llm_service.cpp
│   │   │   └── llm_analytics.cpp
│   │   ├── stt/
│   │   │   ├── stt_component.cpp
│   │   │   └── rac_stt_service.cpp
│   │   ├── tts/
│   │   │   ├── tts_component.cpp
│   │   │   └── rac_tts_service.cpp
│   │   ├── vad/
│   │   │   ├── vad_component.cpp
│   │   │   └── energy_vad.cpp
│   │   ├── voice_agent/
│   │   │   └── voice_agent.cpp
│   │   └── platform/
│   │       ├── rac_llm_platform.cpp
│   │       ├── rac_tts_platform.cpp
│   │       └── rac_backend_platform_register.cpp
│   └── backends/                   # ML backend implementations
│       ├── llamacpp/
│       │   ├── llamacpp_backend.cpp
│       │   ├── rac_llm_llamacpp.cpp
│       │   ├── rac_backend_llamacpp_register.cpp
│       │   ├── jni/
│       │   │   └── rac_backend_llamacpp_jni.cpp
│       │   └── CMakeLists.txt
│       ├── onnx/
│       │   ├── onnx_backend.cpp
│       │   ├── rac_onnx.cpp
│       │   ├── rac_backend_onnx_register.cpp
│       │   ├── jni/
│       │   │   └── rac_backend_onnx_jni.cpp
│       │   └── CMakeLists.txt
│       ├── whispercpp/
│       │   ├── whispercpp_backend.cpp
│       │   ├── rac_stt_whispercpp.cpp
│       │   ├── rac_backend_whispercpp_register.cpp
│       │   ├── jni/
│       │   │   └── rac_backend_whispercpp_jni.cpp
│       │   └── CMakeLists.txt
│       └── jni/
│           └── runanywhere_commons_jni.cpp
│
├── cmake/                          # CMake modules
│   ├── FetchONNXRuntime.cmake
│   ├── ios.toolchain.cmake
│   └── LoadVersions.cmake
│
├── scripts/                        # Build automation
│   ├── build-ios.sh                # iOS build orchestration
│   ├── build-android.sh            # Android build orchestration
│   ├── lint-cpp.sh                 # C++ linting
│   ├── load-versions.sh            # Version loading utility
│   ├── ios/
│   │   ├── download-onnx.sh
│   │   └── download-sherpa-onnx.sh
│   └── android/
│       ├── download-sherpa-onnx.sh
│       └── generate-maven-package.sh
│
├── third_party/                    # Pre-built dependencies
│   ├── onnxruntime-ios/
│   ├── sherpa-onnx-ios/
│   └── sherpa-onnx-android/
│
├── dist/                           # Build outputs
│   ├── RACommons.xcframework
│   ├── RABackendLLAMACPP.xcframework
│   ├── RABackendONNX.xcframework
│   └── android/
│       └── jni/{abi}/librac_*.so
│
├── exports/                        # Symbol visibility lists
├── tests/                          # Unit tests
├── CMakeLists.txt                  # Main CMake configuration
├── VERSION                         # Project version
└── VERSIONS                        # Centralized dependency versions
```

## Key Concepts

### Vtable-Based Service Abstraction

Each service uses a vtable pattern for polymorphic dispatch:

```c
// Example: LLM Service Vtable
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

typedef struct rac_llm_service {
    const rac_llm_service_ops_t* ops;  // Function pointers
    void* impl;                         // Backend-specific handle
    const char* model_id;
} rac_llm_service_t;
```

**Key principle:** Backends implement vtables directly - NO intermediate C++ capability layer.

### Service Registry

- Priority-based provider selection
- `canHandle` pattern: providers declare what requests they can serve
- Factory functions create service instances on demand

```
Client: rac_llm_create("model-id")
  → ServiceRegistry queries all LLM providers
  → First provider returning canHandle=true creates service
  → Service wraps backend handle + vtable
  → Return to client
```

### Module Registry

- Central registry for AI backend modules
- Modules declare capabilities: LLM, STT, TTS, VAD
- Thread-safe singleton pattern

### Capabilities Enumeration

```c
typedef enum rac_capability {
    RAC_CAPABILITY_UNKNOWN = 0,
    RAC_CAPABILITY_TEXT_GENERATION = 1,  // LLM
    RAC_CAPABILITY_EMBEDDINGS = 2,
    RAC_CAPABILITY_STT = 3,              // Speech-to-Text
    RAC_CAPABILITY_TTS = 4,              // Text-to-Speech
    RAC_CAPABILITY_VAD = 5,              // Voice Activity Detection
    RAC_CAPABILITY_DIARIZATION = 6,      // Speaker Diarization
} rac_capability_t;
```

### Component Lifecycle States

```c
typedef enum rac_lifecycle_state {
    RAC_LIFECYCLE_STATE_UNINITIALIZED,
    RAC_LIFECYCLE_STATE_INITIALIZING,
    RAC_LIFECYCLE_STATE_READY,
    RAC_LIFECYCLE_STATE_LOADING,
    RAC_LIFECYCLE_STATE_LOADED,
    RAC_LIFECYCLE_STATE_ERROR,
    RAC_LIFECYCLE_STATE_DESTROYING,
} rac_lifecycle_state_t;
```

### Logging

- Single logging system: `RAC_LOG_INFO`, `RAC_LOG_ERROR`, `RAC_LOG_WARNING`, `RAC_LOG_DEBUG`
- Backends use RAC logger (include `rac/core/rac_logger.h`)
- Routes through platform adapter to native logging (NSLog, Logcat)

## API Naming Convention

| Category | Pattern | Example |
|----------|---------|---------|
| All public symbols | `rac_` prefix | `rac_llm_create()` |
| Error codes | `RAC_ERROR_*` | `RAC_ERROR_MODEL_NOT_FOUND` |
| Types | `rac_*_t` | `rac_handle_t`, `rac_llm_options_t` |
| Boolean | `RAC_TRUE` / `RAC_FALSE` | `rac_bool_t` |
| Components | `rac_*_component_*` | `rac_llm_component_initialize()` |
| Backends | `rac_backend_*` | `rac_backend_llamacpp_register()` |

## Error Code Ranges

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

## Backend Details

### LlamaCPP Backend

- **Capability:** LLM text generation
- **Models:** GGUF format (quantized models)
- **Inference Engine:** llama.cpp (fetched via FetchContent)
- **GPU Acceleration:** Metal (iOS/macOS), CPU NEON (Android)
- **Public API:** `include/rac/backends/rac_llm_llamacpp.h`
- **Registration:** `rac_backend_llamacpp_register()`

### ONNX Backend (via Sherpa-ONNX)

- **Capabilities:** STT, TTS, VAD
- **Models:** ONNX format
- **Framework:** Sherpa-ONNX C API
- **Public APIs:** `rac_stt_onnx.h`, `rac_tts_onnx.h`, `rac_vad_onnx.h`
- **Registration:** `rac_backend_onnx_register()`

### sd.cpp Diffusion Backend

- **Capability:** Diffusion image generation (text-to-image, img2img, inpainting)
- **Models:** .safetensors, .gguf, .ckpt (SD 1.5, SD 2.1, SDXL, SD3, FLUX)
- **Inference Engine:** stable-diffusion.cpp + ggml (fetched via FetchContent)
- **GPU Acceleration:** Metal (iOS/macOS), Vulkan (Android), CPU fallback
- **Public API:** `include/rac/backends/rac_diffusion_sdcpp.h`
- **Registration:** `rac_backend_sdcpp_register()`
- **Build:** `./scripts/build-android.sh sdcpp arm64-v8a` (auto-configures Vulkan)
- **Priority:** 90 (below CoreML's 100, so CoreML wins on Apple for .mlmodelc models)

### WhisperCPP Backend

- **Capability:** STT (speech-to-text)
- **Models:** GGML format (quantized Whisper)
- **Inference Engine:** whisper.cpp (fetched via FetchContent)
- **Public API:** `include/rac/backends/rac_stt_whispercpp.h`
- **Registration:** `rac_backend_whispercpp_register()`

### Platform Backend (Apple-only)

- **Capabilities:** LLM (Apple Foundation Models), TTS (System TTS)
- **Implementation:** Swift callbacks (no C++ inference)
- **Pattern:** C++ provides vtable registration, Swift provides callbacks
- **Public APIs:** `rac_llm_platform.h`, `rac_tts_platform.h`
- **Registration:** `rac_backend_platform_register()`

```c
// Swift registers callbacks for platform backends
rac_platform_llm_set_callbacks(callbacks);
rac_backend_platform_register();
```

## Building

### CMake Options

```cmake
RAC_BUILD_JNI              # Enable JNI bridge (Android/JVM)
RAC_BUILD_TESTS            # Build unit tests
RAC_BUILD_SHARED           # Shared libraries (default: static)
RAC_BUILD_PLATFORM         # Platform backend (Apple only, ON by default)
RAC_BUILD_BACKENDS         # ML backend compilation (OFF by default)
  RAC_BACKEND_LLAMACPP     # LlamaCPP backend
  RAC_BACKEND_ONNX         # ONNX backend
  RAC_BACKEND_WHISPERCPP   # WhisperCPP backend
```

### Build Commands

```bash
# Desktop/macOS build
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build

# Build with backends
cmake -B build -DRAC_BUILD_BACKENDS=ON
cmake --build build

# iOS build (uses scripts)
./scripts/build-ios.sh                    # Full build
./scripts/build-ios.sh --skip-download    # Use cached deps
./scripts/build-ios.sh --backend llamacpp # Specific backend
./scripts/build-ios.sh --clean            # Clean build
./scripts/build-ios.sh --package          # Create ZIPs

# Android build
./scripts/build-android.sh                     # All backends, all ABIs
./scripts/build-android.sh llamacpp            # LlamaCPP only
./scripts/build-android.sh onnx arm64-v8a      # Specific backend + ABI
./scripts/build-android.sh --check             # Verify 16KB alignment

# Linting
./scripts/lint-cpp.sh            # Check formatting
./scripts/lint-cpp.sh --fix      # Auto-fix issues
```

### Version Management

All versions are centralized in the `VERSIONS` file:

```
PROJECT_VERSION=1.0.0
IOS_DEPLOYMENT_TARGET=13.0
ANDROID_MIN_SDK=24
ONNX_VERSION_IOS=1.17.1
SHERPA_ONNX_VERSION_IOS=1.12.18
LLAMACPP_VERSION=b7658
```

Usage:
- Shell scripts: `source scripts/load-versions.sh`
- CMake: `include(LoadVersions)`

## Outputs

### iOS/macOS

```
dist/
├── RACommons.xcframework              # Core library
├── RABackendLLAMACPP.xcframework      # LLM backend
└── RABackendONNX.xcframework          # STT/TTS/VAD backend
```

### Android

```
dist/android/
├── jni/{abi}/                         # JNI libraries
│   ├── librac_commons_jni.so
│   ├── librac_backend_llamacpp_jni.so
│   ├── librac_backend_onnx_jni.so
│   └── librac_backend_whispercpp_jni.so
├── onnx/{abi}/                        # ONNX runtime
│   ├── libonnxruntime.so
│   └── libsherpa-onnx.so
└── llamacpp/{abi}/                    # LlamaCPP static lib
    └── libllama.a
```

ABIs: `arm64-v8a` (primary), `x86_64`, `armeabi-v7a`, `x86`

## Integration with SDKs

### Swift SDK

1. Swift imports `CRACommons` module
2. `SwiftPlatformAdapter` provides platform callbacks (storage, logging)
3. `CommonsErrorMapping` converts `rac_result_t` to `SDKError`
4. `EventBridge` subscribes to C++ events, republishes to Swift `EventBus`

### Kotlin SDK

1. JNI bridge: `librac_*_jni.so` for each backend
2. Platform adapter via JNI callbacks
3. Type marshaling between Java and C

## Common Tasks

### Adding a new error code

1. Add `#define RAC_ERROR_*` to `rac_error.h` (within -100 to -999)
2. Add case to `rac_error_message()` in `rac_error.cpp`
3. Add mapping in platform SDK error converters

### Adding a new backend

1. Create directory under `src/backends/`
2. Implement internal C++ class (no capability inheritance needed)
3. Create RAC API wrapper implementing vtable ops
4. Create registration file with `can_handle` and `create_service` functions
5. Add to CMakeLists.txt with `RAC_BACKEND_*` option
6. Add JNI wrapper in `jni/` subdirectory for Android support

### Adding a new capability interface

1. Add enum value to `rac_capability_t` in `rac_types.h`
2. Create interface headers in `include/rac/features/<cap>/`:
   - `<cap>_types.h` - Data structures
   - `rac_<cap>_service.h` - Vtable and service interface
   - `rac_<cap>_component.h` - Component lifecycle
   - `rac_<cap>.h` - Public API wrapper
3. Create implementations in `src/features/<cap>/`

## Voice Agent Pattern

The voice agent orchestrates a complete voice pipeline:

```cpp
struct rac_voice_agent {
    bool is_configured;
    bool owns_components;
    rac_handle_t llm_handle;
    rac_handle_t stt_handle;
    rac_handle_t tts_handle;
    rac_handle_t vad_handle;
    std::mutex mutex;  // Thread safety
};
```

**Pipeline Flow:**
1. VAD detects voice activity
2. STT transcribes speech to text
3. LLM generates response
4. TTS synthesizes audio output
5. Events published at each stage

## Testing

- Binary size checks in CI (see `size-check.yml`)
- Integration tests via platform SDKs
- Swift E2E tests verify full stack integration

## CI/CD

- **Build**: `.github/workflows/build-commons.yml`
- **Release**: `.github/workflows/release.yml` (triggered by `commons-v*` tags)
- **Size Check**: `.github/workflows/size-check.yml`

## Platform-Specific Notes

### iOS/macOS

- Metal GPU acceleration for LlamaCPP
- Apple Accelerate framework for BLAS
- ARM NEON vectorization
- Deployment target: iOS 13.0

### Android

- ARM NEON for vectorization
- 16KB page alignment required for Play Store
- NDK toolchain for cross-compilation
- Min SDK: 24
