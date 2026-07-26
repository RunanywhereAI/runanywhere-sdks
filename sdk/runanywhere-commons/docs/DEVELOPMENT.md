# RunAnywhere Commons — Development

Contributor guide for building, integrating, and extending the internal C/C++ core.

## Building

### CMake options

| Option | Default | Description |
|--------|---------|-------------|
| `RAC_BUILD_JNI` | OFF | Build JNI bridge for Android/JVM |
| `RAC_BUILD_TESTS` | OFF | Build unit tests |
| `RAC_BUILD_SHARED` | OFF | Build shared libraries (default: static) |
| `RAC_BUILD_PLATFORM` | ON | Build platform backend (Apple FM, System TTS) |
| `RAC_INCLUDE_LOCAL_DEV_CONFIG` | OFF | Compile the ignored local development credentials; local development only, never packaging |
| `RAC_BUILD_BACKENDS` | OFF | Build ML backends |
| `RAC_BACKEND_LLAMACPP` | ON | Build LlamaCPP backend (when BACKENDS=ON) |
| `RAC_BACKEND_ONNX` | ON | Build ONNX backend (when BACKENDS=ON) |
| `RAC_BACKEND_SHERPA` | ON | Build Sherpa-ONNX backend — offline STT/TTS/VAD (when BACKENDS=ON) |
| `RAC_BACKEND_CLOUD` | ON | Build cloud HTTP backend — online STT (when BACKENDS=ON) |

### Platform-specific builds

#### iOS / macOS

```bash
./scripts/build-ios.sh   # canonical Apple slice set and XCFramework packaging
```

#### Android

```bash
./scripts/build-android.sh arm64-v8a
./scripts/build-android.sh armeabi-v7a
./scripts/build-android.sh x86_64
```

Each invocation builds the complete public backend set for exactly one ABI, enforces native-library validation gates (including 16 KB ELF alignment), and creates `dist/RACommons-android-<abi>-v<version>.zip` plus its checksum.

### Build outputs

#### iOS/macOS

```
../runanywhere-swift/Binaries/
├── RACommons.xcframework
├── RABackendLLAMACPP.xcframework
├── RABackendONNX.xcframework
├── RABackendSherpa.xcframework
└── RABackendMLX.xcframework

dist/packages/<Framework>-ios-v<version>.zip
```

#### Android

```
dist/RACommons-android-<abi>-v<version>.zip
```

## API reference (C)

### Core

```c
rac_result_t rac_init(const rac_config_t* config);
void rac_shutdown(void);
rac_bool_t rac_is_initialized(void);
rac_version_t rac_get_version(void);

rac_result_t rac_plugin_register(const rac_engine_vtable_t* vtable);
rac_result_t rac_registry_load_plugin(const char* path);
rac_result_t rac_registry_unload_plugin(const char* name);
uint32_t     rac_plugin_api_version(void);

const rac_engine_vtable_t* rac_plugin_find(rac_primitive_t primitive);
const rac_engine_vtable_t* rac_plugin_find_for_engine(rac_primitive_t primitive,
                                                      const char* engine_name);
```

Engines register via `rac_plugin_register`; metadata.abi_version must equal `RAC_PLUGIN_API_VERSION`. Static builds use `RAC_STATIC_PLUGIN_REGISTER(<name>)`; shared builds expose the same entry symbol for `dlopen` via `rac_registry_load_plugin`.

### LLM, STT, TTS, VAD, Voice Agent

See headers under `include/rac/features/` and `include/rac/backends/`. Public primitive APIs resolve through the engine registry internally.

## Platform integration

### Swift

The Swift SDK integrates via the `CRACommons` module: C headers through a module map, `SwiftPlatformAdapter` for storage/logging callbacks, `CommonsErrorMapping` for errors, and `EventBridge` for analytics.

### Kotlin

The Kotlin SDK integrates via JNI bridge libraries (`librac_*_jni.so`), platform adapter callbacks, type marshaling, and coroutine wrappers.

### Platform adapter

Platform SDKs must provide a `rac_platform_adapter_t` with file I/O, secure storage, logging, time, and optional HTTP download / archive extraction callbacks. See `include/rac/core/rac_platform.h`.

## Dependencies

| Dependency | Purpose |
|------------|---------|
| llama.cpp | LLM inference (GGUF) |
| Sherpa-ONNX | STT/TTS/VAD via ONNX Runtime |
| ONNX Runtime | Neural network inference, embeddings |
| Protobuf / Abseil | Wire runtime |
| nlohmann/json | JSON parsing |
| libarchive | Model archive extraction |

Exact version pins live in the `VERSIONS` file and the repo-root `VERSION` file (currently **0.20.11**).

Load versions in scripts:

```bash
source scripts/load-versions.sh
echo "Using llama.cpp version: $LLAMACPP_VERSION"
```

Load versions in CMake:

```cmake
include(LoadVersions)
message(STATUS "ONNX Runtime version: ${RAC_ONNX_VERSION_IOS}")
```

## Error codes

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

## Contributing

See the main repository [CONTRIBUTING.md](../../../CONTRIBUTING.md).

- Follow Google C++ Style Guide with project customizations
- Run `./scripts/lint-cpp.sh --fix` before committing
- All public symbols use the `rac_` prefix
