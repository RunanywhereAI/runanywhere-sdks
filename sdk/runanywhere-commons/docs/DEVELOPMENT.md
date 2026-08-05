# RunAnywhere Commons — Development

Contributor guide for building, integrating, and extending the internal C/C++ core.

## Building

### CMake options

| Option | Default | Description |
|--------|---------|-------------|
| `RAC_BUILD_JNI` | OFF | Build JNI bridge for Android/JVM |
| `RAC_BUILD_TESTS` | OFF | Build unit tests |
| `RAC_BUILD_SHARED` | OFF | Build shared libraries (default: static archive) |
| `RAC_BUILD_PLATFORM` | ON (Apple only) | Build platform backend (Apple FM, System TTS, Core ML diffusion) |
| `RAC_BUILD_BACKENDS` | OFF | Build ML backends |
| `RAC_BACKEND_LLAMACPP` | ON | Build LlamaCPP backend (when BACKENDS=ON) |
| `RAC_BACKEND_ONNX` | ON | Build ONNX backend (when BACKENDS=ON) |
| `RAC_BACKEND_RAG` | ON (except Emscripten) | Build the RAG pipeline (USearch vector search) |
| `RAC_ENABLE_SOLUTIONS` | ON desktop, OFF mobile/WASM | Solutions API (needs Protobuf + Abseil); OFF returns `RAC_ERROR_FEATURE_NOT_AVAILABLE` |
| `RAC_STATIC_PLUGINS` | Forced ON for iOS/WASM | Static plugin linking instead of `dlopen` |
| `RAC_BUILD_SERVER` | OFF | OpenAI-compatible HTTP server (`src/server/`) |
| `RAC_DESKTOP_ADAPTER` | OFF | Desktop platform adapter plus libcurl HTTP transport (rcli, server, Playground) |
| `RAC_BUILD_ELECTRON_ADDON` | OFF | The `runanywhere-electron` N-API `.node` addon |
| `RAC_BUILD_PYTHON_MODULE` | OFF | The `runanywhere-python` pybind11 extension |
| `RAC_GPU_CUDA` | OFF | Build llama.cpp with the CUDA backend (NVIDIA; needs the CUDA toolkit) |
| `RAC_REGENERATE_PROTO` | OFF | Re-run `idl/codegen/generate_cpp.sh` when `.proto` files change |
| `RAC_INCLUDE_LOCAL_DEV_CONFIG` | OFF | Compile the git-ignored local development credentials; never for packaging |

Per-engine `RAC_BACKEND_<NAME>` options are declared by each engine's own `CMakeLists.txt`, not centrally: `RAC_BACKEND_SHERPA` (ON), `RAC_BACKEND_CLOUD` (ON), `RAC_BACKEND_MLX` (ON, Apple), `RAC_BACKEND_NEURT` (Apple), and `RAC_BACKEND_QHEXRT` (OFF; private prebuilt archive). Each engine self-gates with a `return()` guard, so `engines/` descends into all of them unconditionally.

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
├── RABackendNeuRT.xcframework
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
