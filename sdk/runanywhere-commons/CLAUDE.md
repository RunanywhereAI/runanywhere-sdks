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
1. **Infrastructure** - Logging, errors, events, service registry, model management
2. **RAC Services** - Public C APIs for LLM, STT, TTS, VAD (vtable-based abstraction)
3. **Backends** - ML inference backends (LlamaCPP, ONNX, WhisperCPP) in `src/backends/`
4. **Platform Services** - Apple Foundation Models, System TTS (iOS/macOS only)

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Swift/Kotlin SDKs                        │
└────────────────────────────┬────────────────────────────────┘
                             │ uses
┌────────────────────────────▼────────────────────────────────┐
│              RAC Public C API (rac_*)                       │
│   rac_llm_service.h, rac_stt_service.h, rac_tts_service.h   │
└────────────────────────────┬────────────────────────────────┘
                             │ dispatches via vtables
┌────────────────────────────▼────────────────────────────────┐
│                     Backends (src/backends/)                │
│   ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐     │
│   │  llamacpp/  │  │    onnx/    │  │   whispercpp/   │     │
│   │  LLM (GGUF) │  │ STT/TTS/VAD │  │   STT (GGML)    │     │
│   └─────────────┘  └─────────────┘  └─────────────────┘     │
└─────────────────────────────────────────────────────────────┘
```

## Key Concepts

### RAC Services (Single Abstraction Layer)
- Public C API with `rac_` prefix for cross-platform consumption
- Vtable-based polymorphism: `rac_llm_service_ops_t`, `rac_stt_service_ops_t`, etc.
- Service registry selects backend based on capability and model path
- **NO intermediate C++ capability layer** - backends implement RAC vtables directly

### Service Registry
- Priority-based provider selection
- `canHandle` pattern: providers declare what requests they can serve
- Factory functions create service instances on demand

### Module Registry
- Central registry for AI backend modules
- Modules declare capabilities (LLM, STT, TTS, VAD)
- Thread-safe singleton pattern

### Logging
- Single logging system: `RAC_LOG_INFO`, `RAC_LOG_ERROR`, `RAC_LOG_WARNING`, `RAC_LOG_DEBUG`
- Backends use RAC logger (include `rac/core/rac_logger.h`)
- Routes through platform adapter to native logging

## Directory Structure

```
runanywhere-commons/
├── include/rac/                # Public C headers
│   ├── core/                   # Error handling, logging, types
│   ├── features/               # LLM, STT, TTS, VAD service interfaces
│   ├── infrastructure/         # Registry, events, model management
│   └── backends/               # Backend-specific public headers (rac_llm_llamacpp.h, etc.)
├── src/
│   ├── core/                   # Core implementations
│   ├── features/               # Service implementations
│   ├── infrastructure/         # Registry, events, download, telemetry
│   └── backends/               # ML backend implementations
│       ├── llamacpp/           # LlamaCPP backend (GGUF models)
│       ├── onnx/               # ONNX backend (Sherpa-ONNX for STT/TTS/VAD)
│       └── whispercpp/         # WhisperCPP backend (GGML Whisper models)
├── cmake/                      # CMake modules
├── scripts/                    # Build scripts (unified)
│   ├── build-rac-commons.sh    # Build commons library
│   ├── build-backends.sh       # Build backends
│   ├── android/                # Android build scripts
│   └── ios/                    # iOS build scripts
└── exports/                    # Symbol visibility lists
```

## API Naming Convention

- All public symbols prefixed with `rac_` (RunAnywhere Commons)
- Error codes: `RAC_ERROR_*` (range -100 to -999)
- Types: `rac_*_t` (handles, structs, enums)
- Boolean: `RAC_TRUE` (1), `RAC_FALSE` (0)

## Building

```bash
# Build commons only
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build

# Build with backends
cmake -B build -DRAC_BUILD_BACKENDS=ON
cmake --build build

# Select specific backends
cmake -B build -DRAC_BUILD_BACKENDS=ON -DRAC_BACKEND_LLAMACPP=ON -DRAC_BACKEND_ONNX=OFF

# Build for iOS
./scripts/build-rac-commons.sh --ios

# Build backends for iOS
./scripts/build-backends.sh --ios

# Build for Android
./scripts/build-rac-commons.sh --android --abi arm64-v8a
```

## Outputs

- **Commons**: `librac_commons.a` (or `.so` for Android)
- **Backends**: `librac_backend_llamacpp.a`, `librac_backend_onnx.a`, `librac_backend_whispercpp.a`
- **iOS**: `dist/RACommons.xcframework`
- **Android**: `dist/android/jniLibs/{abi}/librac_*.so`

## Integration with SDKs

### Swift SDK
1. Swift imports `CRACommons` module
2. `SwiftPlatformAdapter` provides platform callbacks to C++
3. `CommonsErrorMapping` converts `rac_result_t` to `SDKError`
4. `EventBridge` subscribes to C++ events, republishes to Swift `EventBus`

### Kotlin SDK
1. JNI bridge: `librac_*_jni.so` for each backend
2. Platform adapter via JNI callbacks

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

### Adding a new capability interface
1. Add enum value to `rac_capability_t` in `rac_types.h`
2. Create interface header `include/rac/features/<cap>/<cap>_types.h`
3. Create service header `include/rac/features/<cap>/rac_<cap>_service.h`

## Testing

- Binary size checks in CI (see `size-check.yml`)
- Integration tests via platform SDKs
- Swift E2E tests verify full stack integration

## CI/CD

- **Build**: `.github/workflows/build-commons.yml`
- **Release**: `.github/workflows/release.yml` (triggered by `commons-v*` tags)
- **Size Check**: `.github/workflows/size-check.yml`
