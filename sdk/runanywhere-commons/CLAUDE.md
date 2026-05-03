# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Core Principles

- Focus on **SIMPLICITY**, following Clean SOLID principles. Reusability, clean architecture, clear separation of concerns.
- Do NOT write ANY MOCK IMPLEMENTATION unless specified otherwise.
- DO NOT PLAN or WRITE any unit tests unless specified otherwise.
- Always use **structured types**, never use strings directly for consistency and scalability.
- When fixing issues focus on **SIMPLICITY** - do not add complicated logic unless necessary.
- Don't over plan it, always think **MVP**.

## C++ Specific Rules

- C++20 standard required (`CMAKE_CXX_STANDARD 20`)
- Google C++ Style Guide with project customizations (`.clang-format`: 4-space indent, 100-column limit)
- Run `./scripts/lint-cpp.sh` before committing; `./scripts/lint-cpp.sh --fix` to auto-fix
- Run `./scripts/lint-cpp.sh --tidy` for clang-tidy (requires `compile_commands.json` in a build dir)
- All public C API symbols prefixed with `rac_`; types suffixed `_t`; error codes `RAC_ERROR_*`; macros `RAC_*`

## Build Commands

```bash
# Desktop/macOS build (core only, no backends)
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build

# Build with all backends enabled
cmake -B build -DRAC_BUILD_BACKENDS=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build

# Build with tests
cmake -B build -DRAC_BUILD_TESTS=ON -DCMAKE_BUILD_TYPE=Debug
cmake --build build
ctest --test-dir build --output-on-failure

# Build with Solutions API (Protobuf + Abseil)
cmake -B build -DRAC_ENABLE_SOLUTIONS=ON
cmake --build build

# iOS build
./scripts/ios/download-onnx.sh           # Download ONNX Runtime xcframework
./scripts/ios/download-sherpa-onnx.sh    # Download Sherpa-ONNX xcframework
./scripts/build-ios.sh                   # Full build → dist/RACommons.xcframework
./scripts/build-ios.sh --skip-download   # Use cached deps
./scripts/build-ios.sh --backend llamacpp
./scripts/build-ios.sh --clean --package # Clean build + create ZIPs

# Android build
./scripts/android/download-sherpa-onnx.sh          # Download Sherpa-ONNX .so files
./scripts/build-android.sh                          # All backends, all ABIs
./scripts/build-android.sh llamacpp                 # LlamaCPP only
./scripts/build-android.sh onnx arm64-v8a           # Specific backend + ABI
./scripts/build-android.sh --check                  # Verify 16KB page alignment

# macOS / Linux / Windows dependency downloads
./scripts/macos/download-onnx.sh
./scripts/macos/download-sherpa-onnx.sh
./scripts/linux/download-sherpa-onnx.sh
scripts/windows/download-sherpa-onnx.bat
scripts/build-windows.bat

# Linting
./scripts/lint-cpp.sh            # Check formatting
./scripts/lint-cpp.sh --fix      # Auto-fix formatting
./scripts/lint-cpp.sh --tidy     # Static analysis (needs compile_commands.json)
```

## CMake Options

| Option | Default | Description |
|--------|---------|-------------|
| `RAC_BUILD_JNI` | OFF | JNI bridge for Android/JVM (`src/jni/`) |
| `RAC_BUILD_TESTS` | OFF | Unit tests (`tests/`) |
| `RAC_BUILD_SHARED` | OFF | Shared lib vs static archive |
| `RAC_BUILD_PLATFORM` | ON (Apple only) | Apple Foundation Models, System TTS, CoreML Diffusion |
| `RAC_BUILD_BACKENDS` | OFF | ML backend compilation |
| `RAC_BUILD_SERVER` | OFF | OpenAI-compatible HTTP server (`src/server/`, `tools/`) |
| `RAC_ENABLE_SOLUTIONS` | ON desktop, OFF mobile/WASM | Full Protobuf + Abseil Solutions API; OFF → stub returns `RAC_ERROR_FEATURE_NOT_AVAILABLE` |
| `RAC_STATIC_PLUGINS` | Forced ON for iOS/WASM | Static plugin linking vs `dlopen` at runtime |
| `RAC_REGENERATE_PROTO` | OFF | Re-run `idl/codegen/generate_cpp.sh` when `.proto` files change |
| `RAC_BACKEND_RAG` | ON (except Emscripten) | RAG pipeline OBJECT library folded into `rac_commons` |

## Project Overview

`runanywhere-commons` is a unified C/C++ library (C++20 internals, pure C API surface) that sits between platform SDKs (Swift, Kotlin, Web/WASM) and ML inference backends. It is the single source of truth for business logic — platform SDKs are thin bridges.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│               Swift / Kotlin / Web SDKs                         │
│         (CRACommons module map / JNI / Emscripten ccall)        │
└──────────────────────────┬──────────────────────────────────────┘
                           │ C API (rac_*)
┌──────────────────────────▼──────────────────────────────────────┐
│  Component Layer  (rac_*_component_*)                            │
│  Owns lifecycle, emits analytics, exposes clean public API       │
│  LLM | STT | TTS | VAD | VLM | Diffusion | Embeddings          │
└──────────────────────────┬──────────────────────────────────────┘
                           │ rac_*_create() → plugin route → vtable dispatch
┌──────────────────────────▼──────────────────────────────────────┐
│  Service Layer  (rac_*_service.cpp)                              │
│  Looks up model in registry → resolves framework → pins plugin   │
│  name → calls rac_plugin_route() → gets rac_engine_vtable_t*    │
└──────────────────────────┬──────────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────────┐
│  Plugin Registry + Engine Router  (src/plugin/, src/router/)     │
│  ABI-versioned vtable handshake (RAC_PLUGIN_API_VERSION = 3u)    │
│  Priority scoring: base priority + runtime bonus + format bonus  │
│  + pinned-engine bonus. Static (RAC_STATIC_PLUGIN_REGISTER) or   │
│  dynamic (rac_registry_load_plugin / dlopen).                    │
└──────────────────────────┬──────────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────────┐
│                    Engine Plugins                                 │
│  llamacpp (LLM+VLM) | onnx (STT+TTS+VAD+Embed+WakeWord)        │
│  whispercpp (STT) | whisperkit-coreml (STT, Apple)               │
│  metalrt (LLM+STT+TTS+VLM, Apple) | platform (Apple FM+TTS+Diff)│
└─────────────────────────────────────────────────────────────────┘
```

### Two-Layer Feature Pattern

Every AI capability follows the same two-layer design:

1. **Service layer** (`src/features/*/rac_*_service.cpp`): Thin dispatch. Looks up model in registry, resolves `rac_inference_framework_t` → plugin name string, calls `rac_plugin_route()` to get the highest-scoring `rac_engine_vtable_t*`, calls `vt->*_ops->create()` to instantiate backend, wraps in a `rac_*_service_t{ops, impl, model_id}` struct.

2. **Component layer** (`src/features/*/llm_component.cpp` etc.): Owns model lifecycle via `rac_lifecycle_t`, emits analytics events (`RAC_EVENT_*`), handles cancel, streams tokens/audio, exposes the public `rac_*_component_*()` API that platform SDKs call.

### Unified Plugin ABI (v3)

All backends publish a `rac_engine_vtable_t` (`include/rac/plugin/rac_engine_vtable.h`) with slots for 8 primitives:

| Primitive | vtable field | Backends |
|-----------|-------------|----------|
| `RAC_PRIMITIVE_GENERATE_TEXT` | `llm_ops` | llamacpp, platform, metalrt |
| `RAC_PRIMITIVE_TRANSCRIBE` | `stt_ops` | onnx, whispercpp, whisperkit-coreml, metalrt |
| `RAC_PRIMITIVE_SYNTHESIZE` | `tts_ops` | onnx, platform, metalrt |
| `RAC_PRIMITIVE_DETECT_VOICE` | `vad_ops` | onnx (Silero), energy-based (built-in) |
| `RAC_PRIMITIVE_EMBED` | `embedding_ops` | onnx |
| `RAC_PRIMITIVE_RERANK` | `rerank_ops` | (reserved) |
| `RAC_PRIMITIVE_VLM` | `vlm_ops` | llamacpp-vlm, metalrt |
| `RAC_PRIMITIVE_DIFFUSION` | `diffusion_ops` | platform (CoreML) |

NULL slot = "not supported." ABI version mismatch → immediate rejection at registration.

### Platform Adapter Inversion-of-Control

`rac_platform_adapter_t` (`include/rac/core/rac_platform_adapter.h`) is the single struct through which all platform services enter C++. The platform SDK populates it before calling `rac_init()`:

- **Mandatory**: `file_exists`, `file_read`, `file_write`, `file_delete`, `secure_get/set/delete`, `log`, `now_ms`, `get_memory_info`
- **Optional (NULL-safe)**: `http_download/cancel`, `extract_archive` (falls back to libarchive), `track_error` (Sentry hook)

All file I/O, secure storage, HTTP, and logging pass through this struct. C++ code never calls platform APIs directly.

### Swift Callback Pattern (Apple-only backends)

Foundation Models, System TTS, CoreML Diffusion, and WhisperKit CoreML all use the same pattern:
1. Swift calls `rac_*_set_callbacks(&callback_struct)` to register function pointers
2. Swift calls `rac_backend_*_register()` which registers the vtable with the plugin registry
3. At runtime, vtable dispatch calls back into Swift through the stored function pointers

### Dual Event System

1. **Lower-level** (`rac_event_publish/subscribe` in `src/infrastructure/events/event_publisher.cpp`): Subscription model with lock-copy-dispatch pattern (snapshot subscribers under mutex, dispatch outside to prevent deadlock). Used by `LifecycleManager` for load/unload events.

2. **Higher-level** (`rac_analytics_event_emit` in `src/core/events.cpp`): Two fixed callbacks — analytics (telemetry) and public (app developer). Events routed by destination: `PUBLIC_ONLY` (streaming updates), `ANALYTICS_ONLY` (VAD, network), `ALL` (everything else).

### Thread Safety Patterns

- **Meyers singleton** for all global state (`SDKState`, `ModuleRegistryState`, `LoggerState`, plugin registry) — avoids static initialization order fiasco
- **Lock-copy-dispatch** in event publisher — prevents deadlock if callbacks re-enter
- **Atomic cancel** in LLM component — `cancel_requested` is `std::atomic<bool>`, read without mutex in the token callback to avoid deadlock with the generating thread
- **Lifecycle refcount pinning** — `rac_lifecycle_acquire_service/release_service` prevents model unload during active inference; unload waits on `condition_variable` for refcount == 0
- **Lock-free VAD path** in voice agent — `rac_voice_agent_detect_speech()` uses `in_flight` atomic counter instead of mutex for real-time audio; `destroy()` spins on `in_flight > 0` after setting `is_shutting_down`
- **Energy VAD hot path** — mean-square computed without sqrt (compares `mean_sq > threshold_sq`); 4-way loop unrolling; callbacks deferred outside lock

### Voice Agent Pipeline

Orchestrates VAD → STT → LLM → TTS with 8 pipeline states (`rac_audio_pipeline_state_t`):
`IDLE → LISTENING → PROCESSING_SPEECH → GENERATING_RESPONSE → PLAYING_TTS → COOLDOWN → IDLE`
(plus `WAITING_WAKEWORD` and `ERROR`). Microphone blocked during processing/TTS. 800ms cooldown after TTS. State transitions validated by `rac_audio_pipeline_is_valid_transition()`.

## Key Subsystems

### Lifecycle Manager (`src/core/capabilities/lifecycle_manager.cpp`)

Ports Swift's `ManagedLifecycle.swift`. States: `IDLE → LOADING → LOADED → FAILED`. Handles auto-unload of previous model when loading a new one (waits for refcount == 0), tracks load metrics (count, total time, failures). `current_service` is `std::atomic<rac_handle_t>` for lock-free cancel reads.

### Model Registry & Paths

- `rac_model_registry_t` — CRUD for model metadata; `discover_downloaded()` scans filesystem; `refresh()` combines remote catalog + local rescan + orphan pruning
- `rac_model_paths_t` — All paths follow `{base_dir}/RunAnywhere/Models/{framework}/{modelId}/`
- `rac_lora_registry_t` — LoRA adapter entries with compatible model ID matching
- `rac_model_assignment_t` — Fetches device-assigned models from backend API with cache

### Download Manager (`include/rac/infrastructure/download/rac_download.h`)

Orchestration (not HTTP transport). Stages: `DOWNLOADING` (0-80%) → `EXTRACTING` (80-95%) → `VALIDATING` (95-99%) → `COMPLETED` (100%). HTTP delegated to `rac_http_download` (platform adapter).

### Structured Error Tracking (`include/rac/core/rac_structured_error.h`)

`rac_error_log_and_track()` / `RAC_RETURN_TRACKED_ERROR(code, category, msg)` — creates structured error with stack trace, logs it, serializes to JSON, sends to `adapter->track_error()` (Sentry), stores as thread-local last error, returns error code.

### Logging

Atomic level-check on hot path (no mutex). `RAC_LOG_TRACE/DEBUG/INFO/WARNING/ERROR/FATAL` macros skip `vsnprintf` entirely when level is filtered. Pre-init: falls back to stderr. Per-environment defaults: dev=DEBUG, staging=INFO, prod=WARNING.

## Error Code Ranges

| Range | Category |
|-------|----------|
| 0 | Success |
| -100 to -109 | Initialization |
| -110 to -129 | Model |
| -130 to -149 | Generation |
| -150 to -179 | Network |
| -180 to -219 | Storage |
| -220 to -229 | Hardware |
| -230 to -249 | Component state |
| -250 to -279 | Validation |
| -280 to -299 | Audio |
| -300 to -319 | Language/Voice |
| -400 to -499 | Module/Service |
| -600 to -699 | Backend |
| -700 to -799 | Event |

Add new codes to `rac_error.h`, add case to `rac_error_message()` in `rac_error.cpp`, add mapping in platform SDK error converters.

## Backend Details

| Backend | Primitives | Models | Engine | Registration |
|---------|-----------|--------|--------|-------------|
| **llamacpp** | LLM | GGUF | llama.cpp (FetchContent) | `rac_backend_llamacpp_register()` |
| **llamacpp-vlm** | VLM | GGUF + mmproj | llama.cpp mtmd | `rac_backend_llamacpp_vlm_register()` |
| **onnx** | STT, TTS, VAD | ONNX | Sherpa-ONNX C API | `rac_backend_onnx_register()` |
| **onnx-embeddings** | Embed | ONNX | Sherpa-ONNX | `rac_backend_onnx_embeddings_register()` |
| **onnx-wakeword** | WakeWord | ONNX | openWakeWord | `rac_backend_wakeword_onnx_register()` |
| **whispercpp** | STT | GGML .bin | whisper.cpp (FetchContent) | `rac_backend_whispercpp_register()` |
| **whisperkit-coreml** | STT (Apple) | .mlmodelc | WhisperKit (Swift) | `rac_backend_whisperkit_coreml_register()` |
| **metalrt** | LLM, STT, TTS, VLM (Apple) | MetalRT | Metal | `rac_backend_metalrt_register()` |
| **platform** | LLM, TTS, Diffusion (Apple) | builtin:// | Swift callbacks | `rac_backend_platform_register()` |

**GGML symbol conflict**: LlamaCPP and WhisperCPP both use GGML. If linked together, symbol conflicts occur. Use ONNX Whisper for STT when also using LlamaCPP, or build with symbol prefixing.

## Version Management

All versions centralized in `VERSIONS` file. Consumed three ways:
- **Shell**: `source scripts/load-versions.sh` → exports `$LLAMACPP_VERSION`, `$ONNX_VERSION_IOS`, etc.
- **CMake**: `include(LoadVersions)` → sets cache variables `RAC_<KEY>` and bare `<KEY>`
- **Windows**: `for /f` parsing in `.bat` scripts

## Symbol Visibility

- **Apple**: `exports/RACommons.exports` lists ~484 curated `_rac_*` symbols; applied via `-exported_symbols_list`
- **Android**: Currently `-fvisibility=default` (all symbols exported) as workaround; TODO(v0.21) to annotate all public functions with `RAC_API`
- **Shared builds**: Global `-fvisibility=hidden` + `RAC_API` attribute (`__attribute__((visibility("default")))` / `__declspec(dllexport)`) on public C functions

## Build Outputs

**iOS**: `dist/RACommons.xcframework`, `dist/RABackendLLAMACPP.xcframework`, `dist/RABackendONNX.xcframework`

**Android**: `dist/android/jni/{abi}/librac_commons_jni.so` + per-backend JNI `.so` files. 16KB page alignment required for Play Store (Android 15+).

**JNI separation**: `librac_commons_jni.so` links only `rac_commons` (no backends). Each backend ships its own JNI `.so` that calls `rac_backend_*_register()`. Mirrors iOS XCFramework separation.

## Testing

Tests are in `tests/` with a custom minimalist runner (not GoogleTest, except RAG tests). Many tests require specific backends to be built:

```bash
# Build and run all tests
cmake -B build -DRAC_BUILD_TESTS=ON -DCMAKE_BUILD_TYPE=Debug
cmake --build build
ctest --test-dir build --output-on-failure

# Run a single test
./build/tests/test_core
./build/tests/test_engine_router
./build/tests/test_llm_thinking

# Tests requiring backends (must enable the backend)
cmake -B build -DRAC_BUILD_TESTS=ON -DRAC_BUILD_BACKENDS=ON -DRAC_BACKEND_LLAMACPP=ON
cmake --build build
./build/tests/test_llm

# Plugin loader tests only work in SHARED plugin mode (not iOS/WASM)
```

Key test categories: core infrastructure, plugin registry/routing, graph scheduler pipeline, LLM streaming/thinking/tool-calling, proto event dispatch, and per-backend integration tests.

## CI/CD

- **Build**: `.github/workflows/build-commons.yml` — macOS, iOS, Android parallel builds + lint
- **Release**: `.github/workflows/release.yml` — triggered by `commons-v*` tags; publishes to `RunanywhereAI/runanywhere-binaries`
- **Size Check**: `.github/workflows/size-check.yml` — xcframework must stay under 3 MB

## Common Tasks

### Adding a new backend

1. Create engine plugin directory
2. Implement vtable ops directly (NO intermediate C++ capability layer)
3. Create plugin entry function returning `const rac_engine_vtable_t*` with correct `abi_version = RAC_PLUGIN_API_VERSION`
4. Add `capability_check` callback if platform-specific (return non-zero to refuse registration)
5. Use `RAC_STATIC_PLUGIN_REGISTER(name)` for static linking or expose `rac_plugin_entry_<name>` symbol for dlopen
6. Add JNI wrapper in `jni/` subdirectory for Android
7. Add to CMakeLists.txt with `RAC_BACKEND_*` option

### Adding a new capability interface

1. Add `RAC_PRIMITIVE_*` value to `rac_primitive_t` in `rac_primitive.h`
2. Add corresponding `*_ops` slot to `rac_engine_vtable_t`
3. Create headers in `include/rac/features/<cap>/`: `*_types.h`, `rac_*_service.h` (vtable), `rac_*_component.h` (lifecycle)
4. Create implementations in `src/features/<cap>/`
5. Add symbols to `exports/RACommons.exports`
