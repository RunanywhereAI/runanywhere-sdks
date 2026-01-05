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

`runanywhere-commons` is a **standalone** C/C++ infrastructure library for the RunAnywhere SDK.

It provides:
- Logging, error handling, and event tracking
- Service registry and provider infrastructure
- Model management (download strategies, storage)
- Platform backend (Apple Foundation Models, System TTS) - iOS/macOS only

**IMPORTANT**: Backends (LlamaCPP, ONNX, WhisperCPP) are in `runanywhere-core`, not here.
The dependency direction is: `runanywhere-core` → `runanywhere-commons` (not the other way around).

## Key Concepts

### Service Registry
- Priority-based provider selection
- `canHandle` pattern: providers declare what requests they can serve
- Factory functions create service instances on demand

### Module Registry
- Central registry for AI backend modules
- Modules declare capabilities (LLM, STT, TTS, VAD)
- Thread-safe singleton pattern

### Event System
- Category-based subscription (SDK, Model, LLM, STT, TTS, Voice, etc.)
- Destinations: public (EventBus), analytics, or both
- Events bridged to Swift via `EventBridge.swift`

### Platform Adapter
- C interface for platform-specific operations
- Swift provides: file I/O, Keychain storage, logging, clock
- HTTP intentionally NOT supported (stays in Swift for security)

## Directory Structure

```
runanywhere-commons/
├── include/rac/         # Public C headers
│   ├── core/           # Error handling, logging, types
│   ├── features/       # LLM, STT, TTS, VAD interfaces
│   └── infrastructure/ # Registry, events, model management
├── src/
│   ├── core/           # Initialization, error handling, memory
│   ├── features/       # Service implementations
│   └── infrastructure/ # Registry, events, download, telemetry
├── cmake/              # CMake modules
├── scripts/            # Build scripts
└── exports/            # Symbol visibility lists
```

## API Naming Convention

- All public symbols prefixed with `rac_` (RunAnywhere Commons)
- Error codes: `RAC_ERROR_*` (range -100 to -999)
- Types: `rac_*_t` (handles, structs, enums)
- Boolean: `RAC_TRUE` (1), `RAC_FALSE` (0)

## Building

```bash
# Build for both iOS and Android
./scripts/build-rac-commons.sh --all

# iOS only
./scripts/build-rac-commons.sh --ios

# Android only
./scripts/build-rac-commons.sh --android --abi arm64-v8a

# Create release packages
./scripts/build-rac-commons.sh --all --package
```

## Outputs

- **iOS**: `dist/RACommons.xcframework`
- **Android**: `dist/android/jniLibs/{abi}/librac_commons.so`
- **Packages**: `dist/packages/RACommons-{platform}-v{version}.zip`

## Integration with SDKs

### Swift SDK
1. Swift imports `CRACommons` module
2. `SwiftPlatformAdapter` provides platform callbacks to C++
3. `CommonsErrorMapping` converts `rac_result_t` to `SDKError`
4. `EventBridge` subscribes to C++ events, republishes to Swift `EventBus`

### Kotlin SDK
1. JNI bridge: `librac_commons_jni.so`
2. Platform adapter via JNI callbacks

## Common Tasks

### Adding a new error code
1. Add `#define RAC_ERROR_*` to `rac_error.h` (within -100 to -999)
2. Add case to `rac_error_message()` in `rac_error.cpp`
3. Add mapping in platform SDK error converters

### Adding a new event category
1. Add enum value to `rac_event_category_t`
2. Update event publisher and subscribers

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
