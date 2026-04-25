# Runtime VTable Design — L1 Runtime Plugin Layer

> Task **T4.1**: promote compute runtimes (CPU, Metal, CoreML, ANE, CUDA,
> Vulkan, QNN, NNAPI, …) into a first-class plugin layer with their own ABI
> and registry, distinct from engine plugins (llama.cpp, ONNX Runtime,
> whispercpp, MetalRT, …).

## 1. Motivation

The v2 architecture document (`runanywhere_v2_architecture.md`) describes six
layers:

```
┌──────────────────────────────────────────┐
│ L5 Frontend SDKs (Swift / Kotlin / … )   │
│ L4 Services (LLM, STT, TTS, VAD, …)      │
│ L3 Primitive dispatch (router)           │
│ L2 Engines (llama.cpp, ONNX, WhisperKit) │
│ L1 Runtimes (CPU, Metal, CoreML, CUDA)   │ ← this document
│ L0 Platform (OS, drivers)                │
└──────────────────────────────────────────┘
```

Before T4.1, compute runtimes were implicit: each engine plugin hard-linked
its preferred runtime (ONNX Runtime opened its own CUDA EP, WhisperKit
CoreML dlopen'd `CoreML.framework`, llama.cpp dispatched Metal shaders
internally). This forced three problems:

1. **Duplicate ORT sessions** when both an LLM engine and a VAD engine ran
   against ONNX Runtime — each owned its own `Ort::Env`.
2. **No cross-engine runtime sharing**. A future `diffusion-coreml` engine
   couldn't reuse the CoreML model-load path that `whisperkit_coreml`
   already wrote.
3. **Router blindness**. The `EngineRouter` scored plugins by priority plus
   a static `metadata.runtimes[]` list, but had no way to know whether a
   runtime was *actually* loadable at runtime. A plugin could declare
   `RAC_RUNTIME_CUDA` on a Mac and still win scoring.

## 2. Goals & non-goals

**Goals (MVP through Phase 6):**

- A C ABI (`rac_runtime_vtable_t`) that wraps a compute runtime's lifecycle,
  session management, and buffer allocation.
- A process-global registry (`rac_runtime_register` / `rac_runtime_list` /
  `rac_runtime_get_by_id` / `rac_runtime_unregister`) with the same ABI
  guarantees as the engine registry.
- A built-in **CPU runtime** registered at startup, so every host has at
  least one runtime available and the registry is never empty.
- Engine-router awareness: the router rejects engine plugins that declare
  executable runtimes when none of those runtimes is currently registered,
  then scores surviving candidates with explicit primitive, model-format,
  runtime-compatibility, and hardware-profile weights.
- Adapter runtime extraction for ONNX Runtime, CoreML, and Metal so engines
  call thin runtime helpers for shared session/model/device lifecycles instead
  of directly owning every L1 object.

**Non-goals (follow-up work):**

- Full zero-copy tensor exchange between runtime plugins and engines. Phase 6
  introduces executable adapter runtimes, but primitive-specific tensor
  marshaling remains in engines until the vtable grows typed tensor ownership.
- GPU/ANE buffer sharing between runtimes (zero-copy handoff of tensor
  memory).
- Runtime hot-plug / refcount-driven unload. The CPU runtime lives for the
  process lifetime; loader-provided runtimes are unloaded via
  `rac_runtime_unregister`, which trusts the caller.

## 3. ABI surface

### 3.1 Metadata

```c
typedef struct rac_runtime_metadata {
    uint32_t         abi_version;    /* == RAC_RUNTIME_ABI_VERSION */
    rac_runtime_id_t id;             /* CPU / METAL / COREML / … */
    const char*      name;           /* stable short name */
    const char*      display_name;   /* human-readable */
    const char*      version;        /* underlying lib version */
    int32_t          priority;       /* higher wins on dedup */
    uint64_t         capability_flags;
    const uint32_t*  supported_formats;   /* ModelFormat enum values */
    size_t           supported_formats_count;
    const rac_device_class_t* supported_devices;
    size_t           supported_devices_count;
} rac_runtime_metadata_t;
```

### 3.2 Vtable op slots

```c
typedef struct rac_runtime_vtable {
    rac_runtime_metadata_t metadata;

    rac_result_t (*init)(void);
    void         (*destroy)(void);

    rac_result_t (*create_session)(const rac_runtime_session_desc_t*,
                                   rac_runtime_session_t** out);
    rac_result_t (*run_session)(rac_runtime_session_t*,
                                const rac_runtime_io_t* inputs,  size_t n_in,
                                      rac_runtime_io_t* outputs, size_t n_out);
    void         (*destroy_session)(rac_runtime_session_t*);

    rac_result_t (*alloc_buffer)(size_t bytes, rac_runtime_buffer_t** out);
    void         (*free_buffer)(rac_runtime_buffer_t*);

    rac_result_t (*device_info)(rac_runtime_device_info_t* out);
    rac_result_t (*capabilities)(rac_runtime_capabilities_t* out);
} rac_runtime_vtable_t;
```

All op pointers except `init`/`destroy` MAY be NULL when the runtime only
advertises metadata (e.g. a lightweight `cpu` runtime that engines use for
fallback identification but that doesn't own session lifecycles). Callers
probe with `rac_runtime_has_op(vt, &rac_runtime_vtable::run_session)` before
dispatch.

### 3.3 Session + buffer handles

`rac_runtime_session_t` and `rac_runtime_buffer_t` are opaque structs
forward-declared in the header; the runtime owns the concrete type. This
mirrors how Ort's `OrtSession*` and CoreML's `MLModel*` are opaque to
callers.

The session descriptor carries a `primitive`, a `model_format`, a path or
byte-blob, and a JSON-encoded options string — keeping the signature stable
across runtimes that need radically different configuration.

### 3.4 ABI version policy

`RAC_RUNTIME_ABI_VERSION` (starts at `1u`) lives next to
`RAC_PLUGIN_API_VERSION`. The versions are independent: promoting a
reserved engine-vtable slot does not invalidate runtime plugins, and
vice-versa. `rac_runtime_register` rejects any vtable whose
`metadata.abi_version` ≠ host's, with
`RAC_ERROR_ABI_VERSION_MISMATCH`.

## 4. Registry semantics

The registry is an in-process map keyed by `rac_runtime_id_t`. At most one
active entry per id. Registering a second vtable for the same id:

- Replaces the existing entry when `new.priority >= existing.priority`.
- Returns `RAC_ERROR_PLUGIN_DUPLICATE` otherwise.

`rac_runtime_list(out, max, *n)` snapshots the registered runtime vtable
pointers; the vtables themselves live in the plugin's `.rodata` (no
heap-ownership transfer).

Thread-safety: the registry uses a single `std::mutex`; ops on registered
runtimes are the runtime's own concern.

## 5. Relationship to engine plugins

`rac_engine_metadata_t.runtimes[]` already lists the runtimes an engine
*can* serve (e.g. ONNX's vtable declares `{CPU, CUDA, COREML}`). T4.1 adds:

- **Engine router**: an engine is scored higher when at least one of its
  declared runtimes has an entry in the runtime registry AND the hardware
  profile confirms it. This replaces the older "metadata.runtimes declared
  vs hardware detected" check that had no knowledge of whether a runtime
  was actually loaded.
- **Engine metadata**: no ABI change. The existing `runtimes[]` array is
  reinterpreted as *preferred* runtimes; the router's scoring logic now
  also intersects against the runtime registry.

The engine vtable header gains a comment block (no layout change) linking
to this document and explaining the relationship. Bumping
`RAC_PLUGIN_API_VERSION` is NOT required by T4.1.

## 6. Default CPU runtime

A built-in CPU runtime is registered by `rac_commons` at startup (from
`src/plugin/rac_runtime_registry.cpp`, via a function-local Meyers
singleton that triggers `rac_runtime_register` on first access to the
registry). Its vtable:

- Declares `id = RAC_RUNTIME_CPU`, `priority = 0`.
- Implements `init`/`destroy` as no-ops, `device_info` returning a CPU
  descriptor built from `HardwareProfile::cached()`, and
  `capabilities` returning a generic "supports any ModelFormat" set.
- Leaves `create_session` / `run_session` / `destroy_session` NULL: the CPU
  runtime in this MVP is a marker, not a compute engine. Engines that run
  on the CPU (llama.cpp CPU backend, ONNX Runtime CPU EP) continue to own
  their own execution paths, they just now *observe* that
  `RAC_RUNTIME_CPU` is registered.

The CPU runtime uses the same `RAC_STATIC_PLUGIN_REGISTER`-style mechanism
used for engine plugins, so it survives iOS / WASM static-linking.

## 7. Executable runtime extraction status

Phase 6 promotes the registry from descriptor-only to executable adapter
runtimes. The public ABI remains additive: `rac_runtime_vtable_t` keeps the
same op slots, and `RAC_RUNTIME_ONNXRT = 13` promotes the first reserved
runtime id.

### 7.1 Concrete op signatures

The executable contract is the same C ABI declared in
`rac_runtime_vtable.h`:

```c
rac_result_t (*create_session)(const rac_runtime_session_desc_t* desc,
                               rac_runtime_session_t** out);

rac_result_t (*run_session)(rac_runtime_session_t* session,
                            const rac_runtime_io_t* inputs,
                            size_t n_in,
                            rac_runtime_io_t* outputs,
                            size_t n_out);

void (*destroy_session)(rac_runtime_session_t* session);

rac_result_t (*alloc_buffer)(size_t bytes, rac_runtime_buffer_t** out);
void (*free_buffer)(rac_runtime_buffer_t* buffer);

rac_result_t (*device_info)(rac_runtime_device_info_t* out);
rac_result_t (*capabilities)(rac_runtime_capabilities_t* out);
```

`create_session` consumes a stable `rac_runtime_session_desc_t`: primitive,
model format, model path or in-memory blob, and JSON options. `run_session`
consumes named `rac_runtime_io_t` tensors; runtimes own any opaque session or
buffer handles they return. `device_info` and `capabilities` are safe metadata
queries used by the router, diagnostics, and future SDK introspection.

### 7.2 Migration matrix

| Runtime | Current status | Engine contract |
| --- | --- | --- |
| `runtimes/onnxrt` | Executable adapter. Owns shared `OrtEnv`, ORT session creation, generic run, and host buffer allocation. | `engines/onnx` links `rac_runtime_onnxrt`; the RAG embedding provider includes the thin `rac_runtime_onnxrt.h` wrapper, not raw ORT headers. ONNX engine metadata declares `RAC_RUNTIME_ONNXRT` as required. |
| `runtimes/coreml` | Executable metadata/runtime helper. Owns default `MLModelConfiguration`, model loading, and CoreML availability/capability reporting. | `diffusion-coreml` loads all `MLModel` bundles through `rac_coreml_load_model_in_dir`; `whisperkit_coreml` gates capability on `rac_coreml_runtime_require_available`. CoreML prediction-specific code remains in engines. |
| `runtimes/metal` | Executable metadata/runtime helper. Owns default `MTLDevice`, command queue, Metal-backed `alloc_buffer/free_buffer`, and availability checks. | `metalrt` wrappers call `rac_metal_runtime_require_available` before touching the private MetalRT C API. Private engine-specific handles stay in `engines/metalrt`. |
| `runtimes/cpu` | Built-in descriptor/helper runtime. | CPU remains process-default and provides device/capability metadata. It still does not own arbitrary engine sessions. |

### 7.3 Remaining direct ownership

The extraction is intentionally adapter-based:

- Sherpa wake-word still uses ORT C++ APIs directly under `engines/sherpa`
  because it is a separate Sherpa-owned ONNX stack.
- CoreML diffusion still uses `MLFeatureProvider`, `MLMultiArray`, and
  `MLModel` prediction APIs inside the engine because those are
  primitive-specific tensor layouts.
- MetalRT still owns private `metalrt_*` engine handles; `runtimes/metal`
  owns only common device/queue/buffer readiness.

The next migration step is to promote typed tensor descriptors and output
ownership into reserved runtime vtable slots, then move more primitive-specific
`run_session` paths behind the runtime ABI.

## 8. Testing

- **`test_runtime_registry.cpp`** — 8 scenarios: happy-path register /
  find / list / unregister, ABI-version rejection, duplicate-id
  priority-promotion, NULL guards, default CPU-runtime presence,
  `rac_runtime_get_by_id` negative cases.
- **`test_runtime_loader.cpp`** — smoke-test that a runtime vtable built in
  another TU registers cleanly and survives a re-register cycle. Exercises
  the static-registration helper, mirrors `test_static_registration.cpp`
  for engines.

Both tests link only `rac_commons` (no backend dependency) so they run on
every preset including `linux-debug`, `ios-device`, and `wasm`.

## 9. Error codes

The runtime layer reuses the existing plugin error set — no new
`RAC_ERROR_*` constants. Specifically:

- `RAC_ERROR_ABI_VERSION_MISMATCH` — vtable's `abi_version` ≠ host.
- `RAC_ERROR_NULL_POINTER` / `RAC_ERROR_INVALID_PARAMETER` — bad input.
- `RAC_ERROR_NOT_FOUND` — lookup by id when no runtime is registered.
- `RAC_ERROR_PLUGIN_DUPLICATE` — duplicate id with lower priority.
- `RAC_ERROR_CAPABILITY_UNSUPPORTED` — runtime's own `init()` refused.

## 10. Out-of-scope / deferred

- Dynamic loading of runtime plugins via `dlopen` (symbol convention
  `rac_runtime_entry_<name>`) is sketched in the header but not wired into
  `plugin_loader.cpp` yet. Tracked as follow-up.
- Cross-runtime buffer handoff (e.g. Metal→CoreML zero-copy) is a feature
  of `alloc_buffer`/`free_buffer` but has no implementation in the CPU
  runtime, and no tests beyond "pointer round-trip".
- Telemetry hooks per runtime call (latency histograms, VRAM high-water
  mark) — tracked separately under the telemetry roadmap.
