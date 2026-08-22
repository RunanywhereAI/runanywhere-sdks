# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this
repository. See the repo-root `AGENTS.md` first for cross-cutting rules (business-logic
layering, iOS-as-source-of-truth, workflow conventions) — this file adds only what is specific
to `core/`, the C/C++ commons library.

## C++ rules

- C++20 standard required (`CMAKE_CXX_STANDARD 20`).
- Google C++ Style Guide with project customizations (`.clang-format`: 4-space indent,
  100-column limit).
- All public C API symbols prefixed with `rac_`; types suffixed `_t`; error codes `RAC_ERROR_*`;
  macros `RAC_*`.
- Run `./scripts/lint-cpp.sh` before committing (see Build commands below for flags).

## Build commands

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
./scripts/build-ios.sh                   # Canonical Apple build + versioned packages

# Android build
./scripts/android/download-sherpa-onnx.sh          # Download Sherpa-ONNX .so files
for abi in arm64-v8a armeabi-v7a x86_64; do
  ./scripts/build-android.sh "$abi"                 # Complete public set for one ABI
done

# macOS / Linux / Windows dependency downloads
./scripts/macos/download-onnx.sh
./scripts/macos/download-sherpa-onnx.sh
./scripts/linux/download-sherpa-onnx.sh
scripts/windows/download-sherpa-onnx.bat
scripts/build-windows.bat

# Linting
./scripts/lint-cpp.sh            # Check formatting
./scripts/lint-cpp.sh --fix      # Auto-fix formatting
./scripts/lint-cpp.sh --tidy     # Static analysis (needs compile_commands.json in a build dir)
```

## CMake options

| Option | Default | Description |
|--------|---------|-------------|
| `RAC_BUILD_JNI` | OFF | JNI bridge for Android/JVM (`src/jni/`) |
| `RAC_BUILD_TESTS` | OFF | Unit tests (`tests/`) |
| `RAC_BUILD_SHARED` | OFF | Shared lib vs static archive |
| `RAC_BUILD_PLATFORM` | ON (Apple only) | Apple Foundation Models, System TTS, CoreML Diffusion |
| `RAC_BUILD_BACKENDS` | OFF | ML backend compilation |
| `RAC_BUILD_SERVER` | OFF | OpenAI-compatible HTTP server (`src/server/`, `tools/`) |
| `RAC_ENABLE_SOLUTIONS` | Follows `RAC_ENABLE_PROTOBUF`; forced OFF under Emscripten | Full Protobuf + Abseil Solutions API; OFF makes the stub return `RAC_ERROR_FEATURE_NOT_AVAILABLE`. Mobile builds enable protobuf, so Solutions is ON there too. |
| `RAC_STATIC_PLUGINS` | Forced ON for iOS/WASM | Static plugin linking vs `dlopen` at runtime |
| `RAC_ENSURE_GENERATED_PROTO` | ON | Generate `src/generated/proto/` + `include/rac/rac_defaults_generated.h` at **configure** time when they are absent. Neither is tracked; this is what makes `cmake --preset …` work in a fresh clone, and what guarantees the shipped `rac_defaults_generated.h` exists before `install(DIRECTORY include/)`. Set OFF to assert "already generated" instead |
| `RAC_REGENERATE_PROTO` | OFF | Dev loop: re-run `idl/codegen/generate_cpp.sh` at **build** time when a `.proto` is newer than the output. Orthogonal to the option above, which only fires when the output is missing entirely |
| `RAC_BACKEND_RAG` | ON (except Emscripten) | RAG pipeline OBJECT library folded into `rac_commons` |

The full option set (per-backend `RAC_BACKEND_<NAME>` flags, `RAC_DESKTOP_ADAPTER`,
`RAC_BUILD_ELECTRON_ADDON`, `RAC_BUILD_PYTHON_MODULE`, `RAC_GPU_CUDA`, …) is in
`docs/DEVELOPMENT.md`.

`runanywhere-commons` (this directory) is a unified C/C++ library (C++20 internals, pure C API
surface) that sits between platform SDKs and ML inference backends (`../engines/`). It is the
single source of truth for business logic; platform SDKs are thin bridges. The repo-root
`AGENTS.md` covers the cross-platform layer diagram and the `rac_engine_vtable_t` v9 ABI at the
level every SDK needs; what follows here is `core/`-internal detail that needs multiple files
to piece together.

## Architecture

`rac_*_create()` calls `rac_plugin_find()` and dispatches through a vtable to the service layer
(`rac_*_service.cpp`), which looks the model up in the registry, resolves its framework, applies
an optional engine pin, and calls `rac_plugin_find[_for_engine]()`. The plugin registry
(`src/plugin/`) performs the ABI-versioned vtable handshake; the highest-priority plugin per
primitive wins, there is no scoring. Registration is static through
`RAC_STATIC_PLUGIN_REGISTER` or dynamic through `rac_registry_load_plugin` and `dlopen`.

### Two-layer feature pattern

Every AI capability follows the same two-layer design:

1. **Service layer** (`src/features/*/rac_*_service.cpp`): Thin dispatch. Looks up model in registry, resolves `rac_inference_framework_t` → optional engine-name pin, calls `rac_plugin_find()` (or `rac_plugin_find_for_engine()` when pinned) to get the highest-priority `rac_engine_vtable_t*`, calls `vt->*_ops->create()` to instantiate backend, wraps in a `rac_*_service_t{ops, impl, model_id}` struct.

2. **Component layer** (merged into `src/features/*/*_module.cpp`): Owns model lifecycle via `rac_lifecycle_t`, emits analytics events (`RAC_EVENT_*`), handles cancel, streams tokens/audio, exposes the public `rac_*_component_*()` API that platform SDKs call.

Feature-family classification, because not every capability fits one mold:

- Single-backend capabilities (`llm`, `stt`, `tts`, `vad`, `vlm`, `diffusion`, `embeddings`, `segmentation`) follow the Service+Component split above: each resolves a single `rac_engine_vtable_t*` and wraps it in a `rac_*_service_t`.
- Composed pipelines (`rag`, `voice_agent`) are intentionally different: they orchestrate other services and have no single backend vtable of their own, so they deliberately skip the service wrapper.
- VAD is a dual-backend special case: a plugin-provided model VAD service (e.g. sherpa Silero) plus a component-owned energy-VAD fallback. The component selects between them rather than always dispatching to one backend.

### Plugin ABI v9 (full history — the root `AGENTS.md` links here for this)

All backends publish a `rac_engine_vtable_t` (`include/rac/plugin/rac_engine_vtable.h`) with 10
active primitive slots and 7 reserved slots (the single source of truth for primitive slots is
the `RAC_PRIMITIVE_TABLE` X-macro in that header). A NULL primitive slot means not supported. An
ABI version mismatch (`metadata.abi_version != RAC_PLUGIN_API_VERSION`) is rejected at
registration. The current handshake is `RAC_PLUGIN_API_VERSION = 9u`: ABI v9 widened
`rac_llm_stream_callback_fn` with `tokens_in_delta` and added `get_stream_token_counts` on
`rac_llm_service_ops_t` (a NULL callback makes commons estimate counts and set
`TokenUsage.counts_estimated`). `RAC_PRIMITIVE_RERANK` (wire value 11, `rerank_ops`, promoted
from `reserved_slot_2` at the same binary offset) was revived as a first-class cross-encoder
reranking primitive in ABI v8. The original rerank slot (wire value 6, retired in ABI v4) stays
permanently retired — the revived primitive is a new wire value, never reuse 6.

Primitive enum → vtable field → who implements it today:

| Primitive | vtable field | Backends |
|-----------|-------------|----------|
| `RAC_PRIMITIVE_GENERATE_TEXT` | `llm_ops` | llamacpp, platform, qhexrt, neurt (Apple) |
| `RAC_PRIMITIVE_TRANSCRIBE` | `stt_ops` | sherpa, qhexrt |
| `RAC_PRIMITIVE_SYNTHESIZE` | `tts_ops` | sherpa, platform, qhexrt |
| `RAC_PRIMITIVE_DETECT_VOICE` | `vad_ops` | sherpa (Silero), energy-based (built-in) |
| `RAC_PRIMITIVE_EMBED` | `embedding_ops` | llamacpp, onnx |
| `RAC_PRIMITIVE_VLM` | `vlm_ops` | llamacpp, qhexrt |
| `RAC_PRIMITIVE_DIFFUSION` | `diffusion_ops` | neurt (Core ML, Apple), platform (Apple) |
| `RAC_PRIMITIVE_DIARIZE` | `diarization_ops` | onnx (Sortformer) |
| `RAC_PRIMITIVE_SEGMENT` | `segmentation_ops` | onnx |
| `RAC_PRIMITIVE_RERANK` | `rerank_ops` | llamacpp (rank-pooling GGUF) |

### Platform adapter inversion of control

`rac_platform_adapter_t` (`include/rac/core/rac_platform_adapter.h`) is the single struct through which all platform services enter C++. The platform SDK populates it before calling `rac_init()`:

- Mandatory: `file_exists`, `file_read`, `file_write`, `file_delete`, `secure_get/set/delete`, `log`, `now_ms`
- Optional, NULL-safe, each null-checked at the call site with a documented fallback: `get_memory_info`, `http_download/cancel`, `extract_archive` (currently unused, since commons extracts through built-in libarchive `rac_extract_archive_native` directly), `file_list_directory`, `is_non_empty_directory`, `get_vendor_id` (Apple-only)

`rac_init()` validates the adapter's `abi_version` + `struct_size` (rejecting a mismatch with `RAC_ERROR_ABI_VERSION_MISMATCH`) and all 9 mandatory slots above (returning `RAC_ERROR_ADAPTER_NOT_SET` if any is NULL); see `rac_core.cpp:151-195`. Optional slots are not enforced; each is null-checked before use with a documented fallback (e.g. Kotlin's JNI ships without `get_memory_info`, which is why it is Optional). There is no `track_error` slot.

### Swift callback pattern (Apple-only backends)

Foundation Models, System TTS, and CoreML Diffusion all use the same pattern:
1. Swift calls `rac_*_set_callbacks(&callback_struct)` to register function pointers
2. Swift calls `rac_backend_*_register()` which registers the vtable with the plugin registry
3. At runtime, vtable dispatch calls back into Swift through the stored function pointers

### Dual event system

1. Legacy struct-based (`rac_event_publish/subscribe/track` in `src/infrastructure/events/event_publisher.cpp`): category-keyed pub/sub with lock-copy-dispatch (snapshot subscribers under mutex, dispatch outside to prevent deadlock). Still live, used by `LifecycleManager` and the engine plugins (sherpa, llamacpp) to emit analytics breadcrumbs via `rac_event_track`.

2. Canonical proto (`rac::events::emit_*` in `src/core/events.cpp`, published through `src/infrastructure/events/sdk_event_publish.cpp`): builds `runanywhere.v1.SDKEvent` payloads carrying a **destination bitmask** (`EVENT_DESTINATION_PUBLIC` | `TELEMETRY` | `LOG`; `ALL` = PUBLIC\|TELEMETRY). `route()` fans out to the public proto stream, the telemetry manager, and an opt-in log breadcrumb. The former fixed analytics/public callback registry (`rac_analytics_event_emit`, `rac_event_get_destination`) was removed.

### Thread-safety patterns

- Meyers singleton for all global state (`SDKState`, `ModuleRegistryState`, `LoggerState`, plugin registry), which avoids static initialization order fiasco
- Lock-copy-dispatch in the event publisher prevents deadlock if callbacks re-enter
- Atomic cancel in the LLM component: `cancel_requested` is `std::atomic<bool>`, read without mutex in the token callback to avoid deadlock with the generating thread
- Lifecycle refcount pinning: `rac_lifecycle_acquire_service/release_service` prevents model unload during active inference; unload waits on `condition_variable` for refcount == 0
- VAD component backend selection: `rac_vad_component_*` routes model-backed operations through the selected plugin and falls back to the component-owned energy VAD when no model is loaded
- Energy VAD hot path: mean-square computed without sqrt (compares `mean_sq > threshold_sq`); 4-way loop unrolling; callbacks deferred outside lock

### Voice agent pipeline

Orchestrates VAD → STT → LLM → TTS with 8 pipeline states (`rac_audio_pipeline_state_t`):
`IDLE → LISTENING → PROCESSING_SPEECH → GENERATING_RESPONSE → PLAYING_TTS → COOLDOWN → IDLE`
(plus `WAITING_WAKEWORD` and `ERROR`). Microphone blocked during processing/TTS. 800ms cooldown after TTS. State transitions validated by `rac_audio_pipeline_is_valid_transition()`.

## Key subsystems

Full detail (mechanics, invariants, hard-won gotchas) is in
[`docs/reference/subsystems.md`](docs/reference/subsystems.md) — read it before touching any of
these, especially RAG, which has "do not relitigate" design rules:

- **Lifecycle Manager** (`src/core/capabilities/lifecycle_manager.cpp`): thin per-handle facade
  over the global `g_loaded` model store; every op is owner-scoped.
- **Model registry and paths** (`rac_model_registry_t`, `rac_model_paths_t`): paths follow
  `{base_dir}/RunAnywhere/Models/{framework}/{modelId}/`.
- **Download manager** (`rac_download_orchestrator.h`): orchestration only, stages
  DOWNLOADING → EXTRACTING → VALIDATING → COMPLETED; HTTP is platform-provided.
- **Error categories** (`rac_structured_error.h`): SDK-facing errors cross the ABI as
  `runanywhere.v1.SDKError` proto bytes; the old JSON/thread-local-last-error path is retired.
  Numeric error code ranges live in `docs/DEVELOPMENT.md#error-codes`.
- **Logging**: atomic level-check, no mutex on the hot path; per-environment default levels.
- **RAG** (`src/features/rag/`): USearch dense + BM25 sparse hybrid retrieval behind
  `rac_rag_*`; content-addressed embedding dedup; reranking is LLM-pointwise only today.

## Backend details

| Backend | Primitives | Models | Engine | Registration |
|---------|-----------|--------|--------|-------------|
| **llamacpp** | LLM, Embed, VLM, Rerank | GGUF (+ mmproj for VLM) | llama.cpp (FetchContent) + mtmd | `rac_backend_llamacpp_register()` (one plugin, no separate VLM registration) |
| **sherpa** | STT, TTS, VAD | ONNX | Sherpa-ONNX C API | `rac_backend_sherpa_register()` |
| **onnx** | Segment; Embed when RAG is enabled | ONNX | `runtimes/onnxrt` Session | `rac_plugin_entry_onnx()` |
| **qhexrt** | LLM, VLM, STT, TTS | QNN context bundle | QHexRT / Hexagon NPU | `rac_backend_qhexrt_register()` |
| **platform** | LLM, TTS, Diffusion (Apple) | builtin:// | Swift callbacks | `rac_backend_platform_register()` |

Backends themselves live one level up, in `../engines/<name>/`, not inside `core/`. To add a new
backend or a new capability primitive, follow `docs/ARCHITECTURE.md#extensibility` — it has the
current step-by-step (which has moved since backends were split out of `core/`; don't follow
older instructions that describe an in-tree `engines/` under `core/`).

## Version management

All *dependency* versions (llama.cpp, ONNX Runtime, etc. — distinct from the SDK release version
in the repo-root `core/VERSION`) are centralized in the `VERSIONS` file. Consumed three ways:
- **Shell**: `source scripts/load-versions.sh` → exports `$LLAMACPP_VERSION`, `$ONNX_VERSION_IOS`, etc.
- **CMake**: `include(LoadVersions)` → sets cache variables `RAC_<KEY>` and bare `<KEY>`
- **Windows**: `for /f` parsing in `.bat` scripts

## Symbol visibility

- **Apple**: `exports/RACommons.exports` lists the curated `_rac_*` symbols (run
  `scripts/validation/commons/check_rac_api_exports.sh` **from the repo root** — unlike the other
  scripts on this page, it does not live under `core/` — to see current drift vs. `RAC_API`-decorated
  headers); applied via `-exported_symbols_list`
- **Android**: Currently `-fvisibility=default` (all symbols exported) as workaround; TODO(v0.21) to annotate all public functions with `RAC_API`
- **Shared builds**: Global `-fvisibility=hidden` + `RAC_API` attribute (`__attribute__((visibility("default")))` / `__declspec(dllexport)`) on public C functions

## Build outputs

**Apple**: XCFrameworks under `../bindings/swift/Binaries/`; versioned reproducible archives under `dist/packages/`.

**Android**: one versioned `dist/RACommons-android-{abi}-v{version}.zip` plus checksum per invocation. The archive contains the public core, LlamaCPP, and ONNX/Sherpa native sets for that ABI. 16 KB ELF alignment is enforced before packaging.

**Linux**: `scripts/build-linux.sh` drives the `linux-release` preset and stages every produced
`.so` into `dist/linux/{lib,include}`, which `release.yml` tars as
`RACommons-linux-x86_64-v{version}.tar.gz`. Run `scripts/linux/download-sherpa-onnx.sh` first or
sherpa builds as a **non-routable stub** — that omission shipped a hollow Linux sherpa carrier
through 0.20.25.

**Windows** (`scripts/build-windows.bat` → the `windows-x64-shared-release` preset):
`dist/windows/x64/lib` must contain `rac_commons.dll` + its import `.lib`, each enabled backend's
`rac_backend_<id>.dll` **and** its `runanywhere_<id>.dll` carrier (the carrier is mandatory on
Windows — `GetProcAddress` does not walk dependents), plus the vendor runtimes `onnxruntime.dll`,
`onnxruntime_providers_shared.dll` and `sherpa-onnx-c-api.dll`; headers under
`dist/windows/x64/include/rac/**`. Packaged as `RACommons-windows-x64-v{version}.zip`.

Two hard rules here, both learned the expensive way:

1. **Configure from the REPO ROOT, never `core/`.** `core/CMakeLists.txt` is a standalone
   `project(RunAnywhereCommons)` that never calls `add_subdirectory(engines)` — only the
   repo-root `CMakeLists.txt` does. Configuring `core/` creates *no engine targets at all*.
2. **Never hardcode per-backend output paths, and never `if exist`-guard a staging copy.** The old
   script copied from `build/.../src/backends/<id>/Release/`, a layout that stopped existing when
   the engines moved to top-level `engines/`. Guarded copies turned that into six silent no-ops,
   so `RACommons-windows-x64` shipped `rac_commons.lib` + headers and **zero engines** for
   multiple releases while CI stayed green. Stage by glob and fail closed on any missing
   artifact, as `build-linux.sh` does.

Run `scripts/windows/download-sherpa-onnx.bat` before building, or sherpa is a non-routable stub
and the script will (now) refuse to package.

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
./build/tests/test_engine_vtable

# Tests requiring backends (must enable the backend)
cmake -B build -DRAC_BUILD_TESTS=ON -DRAC_BUILD_BACKENDS=ON -DRAC_BACKEND_LLAMACPP=ON
cmake --build build
./build/tests/test_llm

# Plugin loader tests only work in SHARED plugin mode (not iOS/WASM)
```

Key test categories: core infrastructure, plugin registry/routing, graph scheduler pipeline, LLM streaming/thinking/tool-calling, proto event dispatch, and per-backend integration tests.

## CI/CD

This directory carries its own `.github/workflows/` (distinct from the repo-root ones):
- Build: `build-commons.yml` runs macOS, iOS, and Android builds in parallel plus lint
- Release: `release.yml` is triggered by `commons-v*` tags and publishes to `RunanywhereAI/runanywhere-binaries`
- Size check: `size-check.yml` holds the xcframework under 3 MB
