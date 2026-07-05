# runanywhere-commons (C/C++ core)

## Info

Global rules: see repo-root AGENTS.md.

Unified C/C++ library (C++20 internals, pure C ABI surface) that owns all AI business logic. Platform SDKs (Swift, Kotlin, Flutter, RN, Web, rcli) are thin bridges that call down through `rac_*` functions. This directory is also the CMake root for all native builds (`CMakeLists.txt`, `CMakePresets.json`, `engines/`, `runtimes/`, `tests/`, `tools/`).

Naming rules: public C symbols `rac_*`, types `_t`, error codes `RAC_ERROR_*`, macros `RAC_*`. Google C++ style via `.clang-format` (4-space indent, 100 cols).

Layers (top-down):
1. **Component layer** (`src/features/*/*_module.cpp`, `rac_*_component_*` API) — lifecycle, analytics events, cancel, streaming; what SDKs call.
2. **Service layer** (`src/features/*/rac_*_service.cpp`) — registry lookup → framework resolve → optional engine pin → `rac_plugin_find[_for_engine]()` → vtable dispatch.
3. **Plugin registry** (`src/plugin/`) — vtable handshake at `RAC_PLUGIN_API_VERSION = 4u`; plain priority order, highest wins, no scoring. Static (`RAC_STATIC_PLUGIN_REGISTER`) or dynamic (`rac_registry_load_plugin`/dlopen; forced static on iOS/WASM).
4. **Engine plugins** (`engines/`, see its AGENTS.md) + **runtime adapters** (`runtimes/`, see its AGENTS.md).

Plugin ABI v4: `rac_engine_vtable_t` has 7 primitive slots (`llm_ops`, `stt_ops`, `tts_ops`, `vad_ops`, `embedding_ops`, `vlm_ops`, `diffusion_ops`; X-macro `RAC_PRIMITIVE_TABLE` in `include/rac/plugin/rac_engine_vtable.h` is the source of truth). NULL slot = not supported. Wire value 6 (`rerank_ops`) is retired — do not revive it.

Platform adapter IoC: `rac_platform_adapter_t` (`include/rac/core/rac_platform_adapter.h`) is the only door for platform services. Mandatory slots (validated by `rac_init()`): `file_exists/read/write/delete`, `secure_get/set/delete`, `log`, `now_ms`. Optional slots are null-checked at each call site with documented fallbacks. C++ never calls platform APIs directly.

Key subsystems:
- **Lifecycle** (`src/core/capabilities/lifecycle_manager.cpp`) — per-handle facade over the canonical global `g_loaded` store (`src/core/model_lifecycle.cpp`); owner-scoped ops; refcount pinning (`active_refs` + `g_lifecycle_cv`) blocks unload during inference.
- **Model registry & paths** — all models at `{base_dir}/RunAnywhere/Models/{framework}/{modelId}/`; `refresh()` = remote catalog + local rescan + orphan pruning.
- **Download orchestrator** (`include/rac/infrastructure/download/`) — stages DOWNLOADING 0-80% → EXTRACTING 80-95% → VALIDATING 95-99%; HTTP delegated to the platform adapter.
- **Errors** — the single canonical path is proto: `rac_result_to_proto_error()` → `runanywhere.v1.SDKError` bytes. `rac_structured_error.h` holds only the `RAC_CATEGORY_*` taxonomy. New codes: `rac_error.h` + case in `rac_error_message()` + SDK converters.
- **Events** — dual system: legacy struct pub/sub (`rac_event_publish/track`, lock-copy-dispatch) still used by lifecycle + engines; canonical proto events (`rac::events::emit_*`) carry a destination bitmask (PUBLIC | TELEMETRY | LOG).
- **RAG** (`src/features/rag/`) — embed → USearch HNSW dense + BM25 sparse → RRF fusion (k=60) → context assembly → LLM. Non-negotiables: keep USearch; rerank is LLM-pointwise (never a vtable slot); all persistence via the platform adapter file I/O; content-addressed dedup keyed by SHA-256 (`src/foundation/rac_sha256` is the only SHA-256 impl); persisted indexes fingerprint-guarded; `idl/rag.proto` changes additive-only.

Threading patterns: Meyers singletons for globals; lock-copy-dispatch in event publisher; atomic cancel flags; lock-free `in_flight` counter in the voice-agent VAD hot path.

Symbol visibility: Apple uses `exports/RACommons.exports` (`-exported_symbols_list`); Android currently `-fvisibility=default` (TODO: `RAC_API` annotations); shared builds hide by default + `RAC_API` on public functions.

Versions: `VERSION` (SDK version, canonical) and `VERSIONS` (dependency pins; shell via `scripts/lib/load-versions.sh`, CMake via `include(LoadVersions)`).

## Build Info

All native builds run from this directory (presets in `CMakePresets.json`; output `build/<preset>/`). Scripts live at repo root `scripts/`; `./run` at repo root is the dev entry point.

```bash
cd sdk/runanywhere-commons
cmake --preset macos-debug && cmake --build build/macos-debug     # or linux-debug/-release
cmake --preset linux-asan && cmake --build build/linux-asan       # ASan (RAC_SANITIZER=asan)
ctest --preset macos-debug                                        # or: ctest --test-dir build/<preset>

# Tests need -DRAC_BUILD_TESTS=ON; backend tests also need -DRAC_BUILD_BACKENDS=ON -DRAC_BACKEND_<NAME>=ON
./build/macos-debug/tests/test_core                               # custom minimalist runner (RAG uses GoogleTest)

# Cross-platform builds (repo root)
./scripts/build/deps/download-onnx.sh ios|macos                   # prebuilt deps
./scripts/build/deps/download-sherpa-onnx.sh ios|android|macos|linux
./scripts/build/ios-xcframework.sh [--skip-download|--backend llamacpp|--clean --package]
./scripts/build/android.sh [backend] [abi] [--check]              # --check = 16KB page alignment
./scripts/build/wasm.sh
./scripts/build/linux.sh
./run sdk commons build-android|build-ios|build-wasm|build-linux  # same, via dev entry point

# Lint (repo root)
./scripts/validation/lint-cpp.sh [--fix|--tidy]                   # or: ./run sdk commons lint
```

Key CMake options: `RAC_BUILD_TESTS`, `RAC_BUILD_BACKENDS` + `RAC_BACKEND_*`, `RAC_BUILD_SHARED`, `RAC_BUILD_JNI`, `RAC_BUILD_PLATFORM` (Apple services), `RAC_BUILD_SERVER`, `RAC_BUILD_CLI` (rcli), `RAC_DESKTOP_ADAPTER` (desktop adapter + curl), `RAC_ENABLE_SOLUTIONS`, `RAC_STATIC_PLUGINS` (forced ON iOS/WASM), `RAC_REGENERATE_PROTO`, `RAC_SANITIZER=asan|tsan|ubsan`.

Adding a capability: new `RAC_PRIMITIVE_*` in `rac_primitive.h`, new `*_ops` vtable slot, headers in `include/rac/features/<cap>/`, impl in `src/features/<cap>/`, symbols in `exports/RACommons.exports`.

## Work Ground

- 2026-07-05: The Swift SDK's `Sources/RunAnywhere/CRACommons/include/` headers are hand-maintained flattened copies of the commons public headers — there is no sync script; keep them in sync manually when changing public headers.
- 2026-07-05: `linux-asan` preset now genuinely applies ASan (`RAC_SANITIZER=asan`, wired in `CMakeLists.txt`).
- 2026-07-05: The scoring `EngineRouter` was removed; selection is plain priority via `rac_plugin_find`. `src/router/` now holds only `hybrid/` and `rac_router_capabilities.cpp`.
