# engines/ (backend engine plugins)

## Info

Global rules: see repo-root AGENTS.md. This file is the single home of the engine taxonomy — do not re-document it in headers or per-engine CMakeLists. Siblings: `../AGENTS.md` (commons core) and `../runtimes/AGENTS.md` (device-runtime adapters).

An **engine is an op-table adapter for modalities**: it fills exactly one `rac_engine_vtable_t` (`include/rac/plugin/rac_engine_vtable.h`; 7 primitive slots, NULL = not served), attaches a declarative `rac_engine_manifest_t` (name, `primitives[]`, `runtimes[]`, `formats[]`, availability, priority), and registers via `rac_plugin_register()`. Dispatch is `rac_plugin_find(primitive)` (or `rac_plugin_find_for_engine()` for a name pin) — plain priority order, highest wins, no scoring. `rerank_ops` (wire value 6) was removed in ABI v4; re-introducing it requires a `RAC_PLUGIN_API_VERSION` bump.

**Engines are named by IDENTITY (the library/framework wrapped), never by modality.** `cloud` is named for its transport (provider chosen per-`create()` from `config_json["provider"]`); `coreml` for its framework (renamed from `diffusion-coreml`). Adding a modality = fill another slot, no rename, no ABI bump. Deleted: `whisperkit_coreml`, `whispercpp` — STT is sherpa (on-device) + cloud (HTTP).

| Engine | Slots filled | Wraps | Runtime pattern | Default | Priority |
|---|---|---|---|---|---|
| llamacpp | llm + vlm | llama.cpp/ggml (FetchContent), mtmd | 1 (bundled; registers a CPU provider) | ON | 100 |
| sherpa | stt + tts + vad | Sherpa-ONNX C API (bundles its own ORT) | 3 (bundled-lib) | ON | 90 |
| onnx | embedding | ONNX Runtime via `runtimes/onnxrt` `Session` | 2 (runtime as library) | ON | 50 |
| cloud | stt | none — HTTP (Sarvam today) | 3 (no runtime, `runtimes=NULL`) | ON | 50 |
| coreml | diffusion | our SD pipeline on Apple CoreML `MLModel` | 3 (our code on a runtime) | ON (Apple) | 100 |
| genie | none (stub shell) | Qualcomm Genie NPU (not in-tree) | — | OFF | — |
| metalrt | none by default; llm+stt+tts+vlm when private binary linked | closed-source `libmetalrt_engine.a` | 1 | OFF (reserved) | 120 |

Valid-engine contract: (1) manifest with snake_case identity name matching `RAC_PLUGIN_ENTRY_DEF(<name>)`; (2) vtable in `.rodata`, served slots non-NULL, everything else explicit NULL; (3) uniform model lifecycle on every op-table: `create(model_id, config_json, **impl) → initialize(impl, model_path, …) → use → cleanup (unload, keep shell) → destroy`; `config_json` is advisory — unknown keys must be ignored; (4) `capability_check` via `rac_engine_unavailable_capability(platform_supported, backend_present)` (3-way: `RAC_ERROR_CAPABILITY_UNSUPPORTED` / `RAC_ERROR_BACKEND_UNAVAILABLE` / `RAC_SUCCESS`; NULL = always accept); (5) registration carriers (below).

4-file skeleton (sherpa and cloud are the cleanest references): `rac_plugin_entry_<name>.cpp` (manifest + vtable + entry def), `rac_backend_<name>_register.cpp` (idempotent register/unregister; skippable if no extra bring-up), `rac_static_register_<name>.cpp` (pre-`main()` shim, `RAC_STATIC_REGISTER_BACKEND` or `RAC_STATIC_PLUGIN_REGISTER`, gated on static mode), plus the impl files. `RAC_DEFINE_CREATE_ADAPTER(primitive, name)` generates the boilerplate `create` forward.

Shared helpers in `engines/common/` (header-only, internal, not part of the C ABI): `rac_engine_unavailable.h` (capability 3-way + `RAC_ENGINE_UNAVAILABLE_PLUGIN` stub shell — used by genie and metalrt's stub arm), `rac_engine_jni_bridge.h` (`RAC_DEFINE_ENGINE_JNI_BRIDGE[_NO_ONLOAD]` — JVM class-path token must match the Kotlin `*Bridge` byte-for-byte), `rac_engine_sibling_loader.h` (cross-`.so` registration on Android), `rac_engine_stt_types.h`, `rac_engine_device_type.h`.

Engine↔runtime patterns (keep in sync with `../runtimes/AGENTS.md`):
1. **Bundles its own runtime** — llamacpp: ggml compiled in; declares `RAC_RUNTIME_CPU` + Metal/CUDA/Vulkan only when `GGML_USE_*` is set. Registers a CPU *provider* into `runtimes/cpu` for session dispatch.
2. **Uses a runtime as a library** — onnx: links `rac_runtime_onnxrt`, calls its C++ `Session` class.
3. **Our inference code on a device runtime** — coreml (engine `coreml` uses runtime `coreml`: same name, separate registries/dirs/symbols). Sub-cases: sherpa (bundled lib), cloud (no runtime at all).

THE RULE: declare a runtime in `runtimes[]` iff execution depends on that device. Declarations are advisory metadata — since the scoring router was removed they are not used for selection, and the registry does not hard-reject unregistered declared runtimes. Keep them truthful anyway (tooling/telemetry).

Adding an engine: `engines/<name>/` with the skeleton; manifest per the contract; `rac_add_engine_plugin(<name> SOURCES … LINK_LIBRARIES … AVAILABILITY … PACKAGE_OWNER/NAME …)` fronted by `option(RAC_BACKEND_<NAME>)` + self-gate; `add_subdirectory` in `engines/CMakeLists.txt`; JNI bridge for Android; `rac_force_load(<host> PLUGINS <name>)` for iOS/WASM static hosts. Primitives/runtimes/formats are declared only in the C manifest, never in CMake. Do not invent a modality to ship an engine — a new primitive is a commons ABI change (see `../AGENTS.md`).

Stubs: **genie** — `RAC_GENIE_LLM_OPS_AVAILABLE=0` pinned in its CMakeLists; entirely the shared unavailable shell; never routable in-tree. **metalrt** — RESERVED, not a live boundary member; public repo carries only `stubs/`; `rac_backend_metalrt_register()` has zero call sites (only the static shim, built only under `RAC_STATIC_PLUGINS` when the target exists); built as an OBJECT lib folded into `rac_commons` (the one engine not using `rac_add_engine_plugin`). Treat it as a re-drop seam for the closed-source engine.

## Build Info

Engines build as part of the commons CMake tree — presets and outputs live in `sdk/runanywhere-commons/` (`build/<preset>/`). Two modes chosen by `RAC_STATIC_PLUGINS`:

- **Static fold into `rac_commons`** (forced on iOS/WASM): engine sources become private sources of `rac_commons`; the static-init Registrar registers before `main()`; host must `rac_force_load` (`-force_load` / `--whole-archive` / MSVC `/INCLUDE:rac_plugin_static_marker_<name>`).
- **SHARED `.so` dlopen** (default Android/Linux/macOS/Windows): builds `librunanywhere_<name>.so`, entry symbol `rac_plugin_entry_<name>` dlsym'd by `rac_registry_load_plugin()`. On Android the SDK instead calls `rac_backend_<name>_register()` via JNI after `System.loadLibrary`. `SHARED_ONLY` means "never fold into `rac_commons`", not "force SHARED linkage" (that is `RAC_BUILD_SHARED`).

Helpers in `cmake/plugins.cmake`: `rac_add_engine_plugin`, `rac_force_load`, `rac_apply_android_page_alignment` (Android 15+ 16 KiB pages).

```bash
cd sdk/runanywhere-commons
cmake --preset macos-debug -DRAC_BUILD_BACKENDS=ON -DRAC_BACKEND_LLAMACPP=ON
cmake --build build/macos-debug
# From repo root:
./scripts/build/android.sh llamacpp arm64-v8a   # per-backend, per-ABI
./scripts/build/ios-xcframework.sh --backend llamacpp
./scripts/build/deps/download-sherpa-onnx.sh android|ios|macos|linux
./scripts/validation/lint-cpp.sh --fix
```

## Work Ground

- 2026-07-05: The scoring `EngineRouter` (runtime/format scoring, hard-reject on unregistered declared runtimes, `RAC_ERROR_RUNTIME_UNAVAILABLE`) is gone — selection is plain priority. Docs or comments still describing scoring are stale.
- 2026-07-05: metalrt remains a stub with zero register call sites; do not wire it into SDK bridges without the private binary.
