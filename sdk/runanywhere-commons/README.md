# RunAnywhere Commons

Shared C/C++ layer providing the core module/service registry, event system, and backend wrappers for the RunAnywhere SDK.

## Overview

`runanywhere-commons` is a C/C++ library that provides:

- **Module Registry**: Dynamic registration and discovery of AI backends
- **Service Registry**: Priority-based service provider selection
- **Event System**: Cross-language event publishing and subscription
- **Platform Adapter**: Bridge for platform-specific operations (file, logging, storage)
- **Backend Wrappers**: C API wrappers for LlamaCPP, ONNX, and WhisperCPP backends

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Swift SDK Layer                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │ LlamaCPP    │  │ ONNX        │  │ WhisperCPP          │ │
│  │ Service     │  │ Services    │  │ Service             │ │
│  └──────┬──────┘  └──────┬──────┘  └──────────┬──────────┘ │
└─────────┼────────────────┼─────────────────────┼────────────┘
          │                │                     │
┌─────────┼────────────────┼─────────────────────┼────────────┐
│         │     C Bridge Modules (CRACommons, etc.)          │
└─────────┼────────────────┼─────────────────────┼────────────┘
          │                │                     │
┌─────────┼────────────────┼─────────────────────┼────────────┐
│         ▼                ▼                     ▼            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │RABackend    │  │RABackend    │  │RABackend            │ │
│  │LlamaCPP     │  │ONNX         │  │WhisperCPP           │ │
│  └──────┬──────┘  └──────┬──────┘  └──────────┬──────────┘ │
│         │                │                     │            │
│         └────────────────┼─────────────────────┘            │
│                          ▼                                  │
│              ┌───────────────────────┐                      │
│              │     RACommons         │                      │
│              │  • Module Registry    │                      │
│              │  • Service Registry   │                      │
│              │  • Event Publisher    │                      │
│              │  • Platform Adapter   │                      │
│              └───────────────────────┘                      │
│                    runanywhere-commons                      │
└─────────────────────────────────────────────────────────────┘
                          │
┌─────────────────────────┼───────────────────────────────────┐
│                         ▼                                   │
│              ┌───────────────────────┐                      │
│              │   runanywhere-core    │                      │
│              │  (llama.cpp, ONNX,    │                      │
│              │   whisper.cpp)        │                      │
│              └───────────────────────┘                      │
└─────────────────────────────────────────────────────────────┘
```

## XCFrameworks

| Framework | Size | Capabilities | Dependencies |
|-----------|------|--------------|--------------|
| RACommons | ~1-2 MB | Core registries, events, platform adapter | None |
| RABackendLlamaCPP | ~30 MB | LLM text generation (GGUF models) | RACommons |
| RABackendONNX | ~400 KB | STT, TTS, VAD (wrapper) | RACommons, onnxruntime.xcframework |
| onnxruntime.xcframework | ~48 MB | ONNX Runtime engine | (external) |

**Note:** `RABackendONNX` is a thin wrapper around Sherpa-ONNX. It requires `onnxruntime.xcframework` to be linked separately because:
- ONNX Runtime is large (~48 MB) and shouldn't bloat other backends
- Can be updated independently
- Different licensing (MIT)

## Building

### Prerequisites

- Xcode 15.2+
- CMake 3.16+
- Ninja (optional but recommended)

### Getting runanywhere-core

`runanywhere-commons` depends on `runanywhere-core` for low-level ML inference.

**Option 1: Download from runanywhere-binaries (CI/CD and remote builds)**
```bash
# Downloads latest version
./scripts/download-core.sh

# Or specify a version
./scripts/download-core.sh 1.0.0
```

This downloads the source to `third_party/runanywhere-core/`.

**Option 2: Local monorepo (development)**

If you have the monorepo structure:
```
runanywhere-all/
├── runanywhere-core/
└── sdks/sdk/runanywhere-commons/
```

CMake will automatically find it at `../../../runanywhere-core`.

### Build iOS XCFrameworks

```bash
cd sdks/sdk/runanywhere-commons

# If using downloaded core (not in monorepo)
./scripts/download-core.sh

# Build XCFrameworks
./scripts/build-ios.sh
```

Outputs to `dist/`:
- `RACommons.xcframework` (~1-2 MB)
- `RABackendLlamaCPP.xcframework` (~30 MB)
- `RABackendONNX.xcframework` (~400 KB)

**Note:** `RABackendONNX` requires `onnxruntime.xcframework` (~48 MB) to be linked separately.

### Build Android Libraries

```bash
./scripts/build-android.sh
```

## Usage in Swift

### Import C Bridge Modules

```swift
import CRACommons
import CRABackendLlamaCPP
```

### Initialize Commons

```swift
// Set up platform adapter
SwiftPlatformAdapter.shared.register()

// Initialize commons
var config = rac_config_t()
rac_init(&config)

// Register backends
rac_backend_llamacpp_register()
rac_backend_onnx_register()
```

### Create Services

```swift
var handle: rac_handle_t?
let result = rac_llm_llamacpp_create(modelPath, nil, &handle)
guard result == RAC_SUCCESS else {
    throw CommonsErrorMapping.toSDKError(result)!
}
```

## API Reference

### Core API (`rac_core.h`)

```c
rac_result_t rac_init(const rac_config_t* config);
void rac_shutdown(void);
rac_bool_t rac_is_initialized(void);
const rac_version_t* rac_get_version(void);
```

### Module Registry

```c
rac_result_t rac_module_register(const rac_module_info_t* info);
rac_result_t rac_module_unregister(const char* module_id);
rac_result_t rac_module_list(rac_module_info_t** out_modules, size_t* out_count);
```

### Service Registry

```c
rac_result_t rac_service_register_provider(const rac_service_provider_t* provider);
rac_handle_t rac_service_create(rac_capability_t capability, const rac_service_request_t* request);
```

### Events

```c
rac_event_subscription_t rac_event_subscribe(
    rac_event_category_t category,
    rac_event_callback_fn callback,
    void* user_data
);
void rac_event_track(const char* type, rac_event_category_t category,
                     rac_event_destination_t dest, const char* properties_json);
```

## Error Codes

Commons uses error codes in the range `-100` to `-999`:

| Range | Category |
|-------|----------|
| -100 to -199 | General errors |
| -200 to -299 | Module/Service registry |
| -300 to -399 | Backend errors |
| -400 to -499 | Model errors |
| -500 to -599 | Inference errors |
| -600 to -699 | Storage errors |
| -700 to -799 | Network errors (not supported) |

## License

Proprietary - RunAnywhere SDK
