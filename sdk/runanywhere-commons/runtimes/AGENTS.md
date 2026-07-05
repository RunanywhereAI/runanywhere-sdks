# runtimes/ (device-runtime adapters)

## Info

Global rules: see repo-root AGENTS.md. This file is the single home of the runtime architecture. Siblings: `../AGENTS.md` (commons core), `../engines/AGENTS.md` (engines; its 3-pattern engine↔runtime taxonomy must stay in sync with this file).

A **runtime is a compute substrate/device** — CPU, Apple Metal, Apple Core ML, ONNX Runtime as a library — named by the device/framework (`"cpu"`, `"metal"`, `"coreml"`, `"onnxrt"`), keyed by `rac_runtime_id_t` (`include/rac/plugin/rac_primitive.h`). A runtime is NOT an engine: engines serve modalities and are clients of runtimes. Separate registries: engines register `rac_engine_vtable_t` via `rac_plugin_register`; runtimes register `rac_runtime_vtable_t` via `rac_runtime_register` (`include/rac/plugin/rac_runtime_registry.h`).

Two roles (contract documented on `rac_runtime_vtable` in `include/rac/plugin/rac_runtime_vtable.h`):
1. **Capability role — MANDATORY**: `metadata` + `init`/`destroy` (must be non-NULL; `init()` non-zero silently rejects, e.g. Metal on Linux) + `device_info` + `capabilities`.
2. **Session-execution role — OPTIONAL**: `create_session`/`run_session`/`destroy_session` + buffer ops, all-or-nothing, and the runtime MUST set `RAC_RUNTIME_CAP_SESSION_EXECUTION` in `capabilities()` (capability-only runtimes MUST NOT). Today only **cpu** provides this role.

ABI: runtime ABI is independent of the engine `RAC_PLUGIN_API_VERSION`. Current = `RAC_RUNTIME_ABI_VERSION_V2` (2u); the registry accepts v2 only (`RAC_ERROR_ABI_VERSION_MISMATCH` otherwise). The v2 extension (`rac_runtime_vtable_v2_t` on `reserved_slot_0`) carries `run_session_v2` + device-aware buffer ops; probe via `rac_runtime_vtable_get_v2()`. Vtable storage must live in `.rodata` — the registry stores pointers, never copies.

Registration validation order: NULL checks → abi match → v2 extension → `init()` == 0 → dedup by `metadata.id` (replace iff priority >= incumbent, else `RAC_ERROR_PLUGIN_DUPLICATE` and the loser's `destroy()` is called). Most runtimes self-register via `RAC_STATIC_RUNTIME_REGISTER(<name>)` (pre-`main()` ctor + `rac_runtime_static_marker_<name>` keep-alive symbol). **CPU is the special case**: bootstrapped explicitly by the registry TU (`src/plugin/rac_runtime_registry.cpp`) so the registry is never empty on any build config; a failed CPU `init()` is logged and skipped.

| Runtime | Session role? | Real consumer | What it actually is | Status |
|---|---|---|---|---|
| cpu (priority 0) | **Yes — the only one** | llamacpp (LLM/VLM) | Provider registry dispatch, not a compute kernel | Live, core |
| onnxrt (80) | No | onnx engine only | C++ `Session` class — the only place raw ORT headers appear; C vtable half is a presence gate + EP config surface | Live (library) |
| coreml (90) | No | coreml engine (diffusion) | Capability runtime + `MLModel` loader helpers (`rac_coreml_load_model_in_dir`, …) | Live (loaders) |
| metal (100) | No | metalrt engine (OFF by default) | Pure presence gate (`rac_metal_runtime_require_available`); real Metal compute is inside ggml | Reserved |

Priorities are used only for same-`id` dedup, not engine selection. **sherpa does NOT use `onnxrt`** — it declares `RAC_RUNTIME_CPU`, links sherpa-onnx + raw onnxruntime statically, and never references `runtime::onnxrt`.

CPU provider pattern (`include/rac/plugin/rac_cpu_runtime_provider.h`): an engine fills `rac_cpu_runtime_provider_t` (name, primitive, formats, create/run/destroy_session, optional `run_session_v2`) and calls `rac_cpu_runtime_register_provider()` at registration (unregister on teardown; struct copied by value but strings/arrays must outlive it). `cpu_create_session` matches provider by primitive+format and wraps the provider session (magic-tagged); `cpu_capabilities` is dynamic — rebuilt from currently registered providers. Even the one session-hosting runtime is a dispatch layer; compute stays in the engine's bundled library (llamacpp registers `k_llamacpp_cpu_provider`).

`metal`'s NULL session slots are deliberate, not TODO — a future first-class Metal runtime would fill them and set `RAC_RUNTIME_CAP_SESSION_EXECUTION`.

Adding a runtime (rare — prefer engine patterns 1/2): decide role (default capability-only); create `runtimes/<name>/` with a `.rodata` vtable (`abi_version = RAC_RUNTIME_ABI_VERSION`, v2 extension NULL-filled if capability-only); `RAC_RUNTIME_ENTRY_DEF(<name>)` + `RAC_STATIC_RUNTIME_REGISTER(<name>)` + an optional `rac_<name>_runtime_require_available()` anchor; `add_subdirectory` in `runtimes/CMakeLists.txt` behind a `RAC_RUNTIME_<NAME>` option (Apple-only guarded); new `rac_runtime_id_t` in `rac_primitive.h`; consumer engine adds the id to its manifest `runtimes[]`.

Conventions: `rac_` prefix / `_t` types / `RAC_ERROR_*`; C++20 internals, pure C boundary; ObjC++ runtimes (`.mm`) must catch every `NSException` at the C boundary (uncaught ObjC exceptions crossing `extern "C"` abort the process).

## Build Info

Runtimes build only as part of the commons CMake tree — no standalone build. From `sdk/runanywhere-commons/` (presets there; output `build/<preset>/`):

```bash
cd sdk/runanywhere-commons
cmake --preset macos-debug && cmake --build build/macos-debug
ctest --preset macos-debug          # test_runtime_loader exercises the static-register path
```

`cpu` is an OBJECT lib folded into `rac_commons` (always on). `coreml`/`metal` are Apple-only. `onnxrt` links real onnxruntime — fetch prebuilt deps first via `./scripts/build/deps/download-onnx.sh <platform>` (repo root). Lint: `./scripts/validation/lint-cpp.sh [--fix]`.

## Work Ground

- 2026-07-05: The old "router hard-rejects declared-but-unregistered runtimes" contract is stale — `src/router/rac_engine_router.cpp` no longer exists and `RAC_ERROR_RUNTIME_UNAVAILABLE` is not produced. Manifest `runtimes[]` declarations are advisory metadata only.
