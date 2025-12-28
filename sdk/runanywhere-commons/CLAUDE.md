# CLAUDE.md - AI Context for runanywhere-commons

## Project Overview

`runanywhere-commons` is a C/C++ library that provides shared infrastructure for the RunAnywhere SDK. It bridges `runanywhere-core` (the AI inference engine) with platform SDKs (Swift, Kotlin).

## Key Concepts

### Module Registry
- Central registry for AI backend modules (LlamaCPP, ONNX, WhisperCPP)
- Modules declare capabilities (LLM, STT, TTS, VAD)
- Thread-safe singleton pattern

### Service Registry
- Priority-based provider selection
- `canHandle` pattern: providers declare what requests they can serve
- Factory functions create service instances on demand

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
├── include/              # Public C headers (rac_*.h)
├── src/
│   ├── core/            # Initialization, error handling, memory
│   ├── registry/        # Module and service registries
│   └── events/          # Event publisher
├── backends/
│   ├── llamacpp/        # LLM backend wrapper
│   ├── onnx/            # STT/TTS/VAD backend wrapper
│   └── whispercpp/      # STT backend wrapper
├── exports/             # Symbol visibility lists
├── cmake/               # CMake modules
└── scripts/             # Build scripts
```

## API Naming Convention

- All public symbols prefixed with `rac_` (RunAnywhere Commons)
- Error codes: `RAC_ERROR_*` (range -100 to -999)
- Types: `rac_*_t` (handles, structs, enums)
- Boolean: `RAC_TRUE` (1), `RAC_FALSE` (0)

## Building

```bash
# iOS XCFrameworks
./scripts/build-ios.sh

# Android .so files
./scripts/build-android.sh
```

## Integration with Swift SDK

1. Swift imports C bridge modules (`CRACommons`, `CRABackendLlamaCPP`, etc.)
2. `SwiftPlatformAdapter` provides platform callbacks to C++
3. `CommonsErrorMapping` converts `rac_result_t` to `SDKError`
4. `EventBridge` subscribes to C++ events, republishes to Swift `EventBus`

## Common Tasks

### Adding a new backend
1. Create `backends/<name>/CMakeLists.txt`
2. Create header `backends/<name>/include/rac_<cap>_<name>.h`
3. Implement wrapper in `backends/<name>/src/`
4. Add registration function `rac_backend_<name>_register()`
5. Add exports file `exports/RABackend<Name>.exports`

### Adding a new capability
1. Add enum value to `rac_capability_t` in `rac_types.h`
2. Create generic capability header `include/rac_<cap>.h`
3. Update backend wrappers to expose the capability

### Adding a new error code
1. Add `#define RAC_ERROR_*` to `rac_error.h` (within -100 to -999)
2. Add case to `rac_error_message()` in `rac_error.cpp`
3. Add mapping in `CommonsErrorMapping.swift`

## Testing Considerations

- Unit tests in `tests/` (currently skipped)
- Swift E2E tests verify full stack integration
- Binary size checks in CI (see `size-check.yml`)

## Known Limitations

- WhisperCPP + LlamaCPP: GGML symbol conflicts if linked together
- HTTP not supported in platform adapter (by design)
- Android support is scaffolded but not fully tested
