# AGENTS.md — `runtimes/`

This file provides guidance to AI coding assistants (Claude Code, Cursor, etc.) when working with the **runtime plugins** under `runtimes/`. It is the **single authoritative place** the runtime architecture is documented. For the surrounding system see the root [`AGENTS.md`](../AGENTS.md), the C++ core [`sdk/runanywhere-commons/AGENTS.md`](../sdk/runanywhere-commons/AGENTS.md), and the sibling engine guide [`engines/AGENTS.md`](../engines/AGENTS.md).

---

## What a runtime is

A **runtime is a compute substrate / device** — the hardware (or vendor library treated as a device) that math actually runs on: **CPU**, **Apple Metal** (GPU), **Apple Core ML** (ANE/GPU/CPU chosen by Core ML), **ONNX Runtime as a library**, and future targets (CUDA, Vulkan, QNN, NNAPI, WebGPU). A runtime is **named by the device/framework** (`"cpu"`, `"metal"`, `"coreml"`, `"onnxrt"`), keyed by `rac_runtime_id_t` (`sdk/runanywhere-commons/include/rac/plugin/rac_primitive.h:83`).

**A runtime is NOT an engine.** Engines (llamacpp, sherpa, onnx, coreml, qhexrt, cloud) serve **modalities** — they publish primitive ops (`llm_ops`, `stt_ops`, …) and are *clients* of one or more runtimes. Runtimes provide **compute**; they describe a device and, in exactly one case, host a session. The two registries are separate: engines register a `rac_engine_vtable_t` via `rac_plugin_register`; runtimes register a `rac_runtime_vtable_t` via `rac_runtime_register` (`sdk/runanywhere-commons/include/rac/plugin/rac_runtime_registry.h`).

Promoting runtimes to first-class plugins lets multiple engines share one ORT `Ort::Env`, reuse one Core ML `MLModel` loader, and (eventually) allocate device buffers through one allocator per device instead of one per engine — see the header rationale in `sdk/runanywhere-commons/include/rac/plugin/rac_runtime_vtable.h:1-27`.

---

## The two roles of a runtime

A runtime fills two distinct roles. This is the key clarifying contract, documented verbatim on `rac_runtime_vtable` at `rac_runtime_vtable.h:401-424`:

### 1. Capability role — MANDATORY

Identity + `init` + `destroy` + `device_info` + `capabilities`. **Every runtime MUST implement these** so callers and diagnostics can determine what device is present and what it can do. A *capability-only* runtime stops here and leaves the session-execution slots `NULL`.

- `init()` returns 0 to accept; non-zero **silently rejects** the runtime (e.g. Metal on Linux, Core ML on an OS too old to run a graph). `init`/`destroy` MUST be non-NULL (pass a no-op `destroy` if there's nothing to tear down).
- `device_info()` fills `rac_runtime_device_info_t` (device class, stable `device_id`, display name, memory bytes).
- `capabilities()` fills `rac_runtime_capabilities_t` (a `RAC_RUNTIME_CAP_*` bitmask + supported formats + supported primitives).

### 2. Session-execution role — OPTIONAL

`create_session` / `run_session` / `destroy_session`, plus the buffer ops (`alloc_buffer` / `free_buffer` and the ABI-v2 buffer extension). A runtime that **actually runs inference** fills these slots **and** advertises `RAC_RUNTIME_CAP_SESSION_EXECUTION` in `capabilities()`. Session execution is **all-or-nothing**: a runtime that provides `create_session` MUST also provide `run_session` and `destroy_session`.

> **Today only the built-in CPU runtime provides this role.** Core ML / ONNX Runtime are **capability-only** and leave the session slots NULL.

### The `RAC_RUNTIME_CAP_SESSION_EXECUTION` contract

Quoting the flag definition at `rac_runtime_vtable.h:132-140`:

```c
/** The runtime provides the OPTIONAL session-execution role: it implements
 *  `create_session` / `run_session` / `destroy_session` (+ buffer ops) and can
 *  actually run inference, not merely describe hardware. Runtimes that fill
 *  those vtable slots MUST set this bit in `capabilities()`; capability-only
 *  runtimes (which leave the session slots NULL) MUST NOT. Callers use this
 *  flag to tell "can this runtime host a session?" apart from "this
 *  runtime exists and reports device_info/capabilities". See the two-role note
 *  on `rac_runtime_vtable` below. */
#define RAC_RUNTIME_CAP_SESSION_EXECUTION (1ull << 10)
```

Callers can thus distinguish **"this runtime is registered (device present)"** from **"this runtime can host a session."** A capability-only runtime that left the bit set, or a session runtime that cleared it, would misreport its execution surface.

---

## The runtime contract (`rac_runtime_vtable_t`)

The ABI boundary is `sdk/runanywhere-commons/include/rac/plugin/rac_runtime_vtable.h`. A runtime populates a `rac_runtime_vtable_t` whose storage lives in `.rodata` (the registry does **not** copy it — the plugin keeps the pointer alive until unregister).

### Vtable layout (`rac_runtime_vtable.h:425-478`)

| Slot | Role | NULL-able? |
|------|------|-----------|
| `metadata` (`rac_runtime_metadata_t`) | capability | identity — `abi_version`, `id`, `name`, `display_name`, `version`, `priority`, `supported_formats[]`, `supported_devices[]` |
| `init` / `destroy` | capability | **MUST be non-NULL** |
| `device_info` | capability | MAY be NULL → caller treats as "CPU-generic" |
| `capabilities` | capability | MAY be NULL → `metadata.supported_formats` is authoritative |
| `create_session` / `run_session` / `destroy_session` | session-exec | NULL on capability-only runtimes |
| `alloc_buffer` / `free_buffer` | session-exec | NULL → caller uses host `malloc` |
| `reserved_slot_0` … `reserved_slot_5` | — | `reserved_slot_0` carries the ABI-v2 extension |

### ABI versioning (`rac_runtime_vtable.h:45-75`)

- Runtime ABI is **independent** of `RAC_PLUGIN_API_VERSION` (engines). The only supported value is `RAC_RUNTIME_ABI_VERSION` (`2u`).
- The registry accepts **ABI v2 only**. A v1-only vtable (missing the `reserved_slot_0` v2 extension) is **hard-rejected** with `RAC_ERROR_ABI_VERSION_MISMATCH`. `metadata.abi_version` must equal `RAC_RUNTIME_ABI_VERSION` exactly.
- The v2 extension `rac_runtime_vtable_v2_t` (`rac_runtime_vtable.h:291-318`) hangs off `reserved_slot_0` and carries `run_session_v2` + device-aware buffer ops (`alloc_buffer`/`buffer_info`/`map_buffer`/`unmap_buffer`/`copy_buffer`) + `release_tensor`. Probe it via the inline `rac_runtime_vtable_get_v2()`. Capability-only runtimes may ship a v2 table with every op slot NULL; **onnxrt leaves `reserved_slot_0` itself NULL** since it offers no session role.

### The registry (`rac_runtime_registry.h`)

`rac_runtime_register()` validation order (`rac_runtime_registry.h:31-48`): NULL checks → `abi_version` match → v2 extension required → `init()` returns 0 → dedup by `metadata.id` (a new vtable replaces an existing one **iff** priority `>=` incumbent, else `RAC_ERROR_PLUGIN_DUPLICATE` and the incoming `destroy()` is called to unwind its `init()`). Lookups: `rac_runtime_get_by_id`, `rac_runtime_is_registered` / `rac_runtime_is_available`, `rac_runtime_list`, `rac_runtime_count`.

### Registration: `RAC_STATIC_RUNTIME_REGISTER` + the CPU bootstrap special-case

Most runtimes self-register with `RAC_STATIC_RUNTIME_REGISTER(<name>)` (`rac_runtime_registry.h:147-157`) — a file-scope constructor that calls `rac_runtime_register(rac_runtime_entry_<name>())` before `main`, plus a `rac_runtime_static_marker_<name>` symbol so a `-force_load` / `--whole-archive` reference can keep the TU alive against dead-symbol stripping. `onnxrt` and `coreml` use this path.

**The CPU runtime is the special case.** It does **not** use `RAC_STATIC_RUNTIME_REGISTER`. Instead `rac_commons`' registry TU explicitly bootstraps it (`sdk/runanywhere-commons/src/plugin/rac_runtime_registry.cpp:135-189`, calling `rac_runtime_entry_cpu()` directly). Rationale (`cpu/rac_runtime_cpu.cpp:634-645`, `cpu/CMakeLists.txt:1-11`): this guarantees the registry is non-empty out-of-the-box on **every** build configuration — iOS static xcframework, Android `.so`, plain unit test — with no per-host `-force_load` dance. A failed CPU `init()` is logged and skipped so it can never abort SDK bootstrap. The `RAC_STATIC_RUNTIME_REGISTER` path is still exercised separately by `tests/test_runtime_loader.cpp`.

---

## The current runtime roster

| Runtime | Dir | Session role? | `CAP_SESSION_EXECUTION` | Real consumer(s) | How it's used | Status |
|---------|-----|--------------|------------------------|------------------|---------------|--------|
| **cpu** | `runtimes/cpu/` | **Yes (the only one)** | **Set** | `llamacpp` (LLM/VLM); any engine registering a CPU provider | Provider registry: engines register a `rac_cpu_runtime_provider_t`; `cpu_create_session`/`cpu_run_session` delegate to it. Folded into `rac_commons` (OBJECT lib). | **Live, core** |
| **onnxrt** | `runtimes/onnxrt/` | No (slots NULL) | **Not set** | `onnx` engine **only** | Engines call the C++ `runanywhere::runtime::onnxrt::Session` class (`Session::create`/`run`) directly; the vtable half publishes runtime capability and availability. Links real `onnxruntime`. | **Live (library), one consumer** |
| **coreml** | `runtimes/coreml/` | No (slots NULL) | **Not set** | `coreml` engine (diffusion) | Engine calls Core ML **loader helpers** (`rac_coreml_load_model_in_dir`, `rac_coreml_default_model_configuration`, `rac_coreml_find_resource_dir`) + the `rac_coreml_runtime_require_available` anchor. Apple-only. | **Live (loader helpers)** |

Priorities (`metadata.priority`): coreml `90`, onnxrt `80`, cpu `0`. (Used only for same-`id` dedup, not engine selection.)

### The honest "who uses each" reality

The vtable/registrar machinery is uniform across all three runtimes, but **how much of each runtime is actually load-bearing differs sharply.** Don't assume "registered runtime ⇒ executes inference."

- **cpu** — the **only** runtime that hosts a session. It is a **dispatch/session-ownership indirection**, not a compute kernel: `cpu_create_session` looks up a registered `rac_cpu_runtime_provider_t` and forwards to it; the actual math is the engine's bundled library (for `llamacpp`, that's llama.cpp/ggml). Real consumer today: **llamacpp**, which registers `k_llamacpp_cpu_provider` and routes its LLM path through the CPU session (`engines/llamacpp/rac_backend_llamacpp_register.cpp:116`, `:402`). The provider registry deliberately keeps `rac_commons` from linking against any engine.

- **onnxrt** — **used by exactly one engine: `onnx`.** Its value is the C++ `Session` class (`runtimes/onnxrt/rac_runtime_onnxrt.cpp:335-631`), the **only** place raw ONNX Runtime headers (`<onnxruntime_c_api.h>`) are included across commons/engines. The `onnx` engine reaches ORT through `Session::create`/`Session::run` in `engines/onnx/onnx_embedding_provider.cpp:789,823` (`EMBED` primitive), and **hard-requires** the runtime — `engines/onnx/CMakeLists.txt:154-155` is a `FATAL_ERROR` if `rac_runtime_onnxrt` is absent. The C **vtable/registrar half is capability-only** (session slots NULL); it publishes ONNX Runtime availability and is retained by `rac_onnxrt_runtime_require_available` (`rac_runtime_onnxrt.cpp:799-811`). It also exposes the execution-provider config surface (`rac_onnxrt_runtime_enable_execution_provider` — CoreML EP wired on Apple, others stubbed).

  > **`sherpa` does NOT use this runtime.** This is the most common misconception. The `sherpa` engine declares **`RAC_RUNTIME_CPU`** in `k_sherpa_runtimes[]` (`engines/sherpa/rac_plugin_entry_sherpa.cpp:47-48`), links the **sherpa-onnx** library + **raw `onnxruntime`** as static archives (`engines/sherpa/CMakeLists.txt:370-373`), and calls the sherpa-onnx C API directly. Its sources contain **zero** references to `runtime::onnxrt` / `rac_runtime_onnxrt`. So `onnxrt` = a thin ORT wrapper used by **one** engine (`onnx`); sherpa reaches ONNX Runtime transitively through sherpa-onnx, never through `runtimes/onnxrt`.

- **coreml** — a capability runtime **plus a bag of MLModel loader helpers** (`runtimes/coreml/rac_runtime_coreml.mm:141-255`). Real consumer: the **`coreml` engine** (our diffusion pipeline, recently renamed from `diffusion-coreml`) via those loaders + `rac_coreml_runtime_require_available`, in `engines/coreml/rac_diffusion_coreml.mm`. **Same-name, different registry:** engine `coreml` (registers `rac_plugin_entry_coreml` / `RAC_STATIC_PLUGIN_REGISTER(coreml)`, `engines/coreml/rac_static_register_coreml.cpp:27`) and runtime `coreml` (registers `rac_runtime_entry_coreml`, `runtimes/coreml/rac_runtime_coreml.mm:262-266`) share the framework name but live in separate dirs/registries with distinct symbols — a clean illustration of **"an engine uses a same-named device runtime."**

---

## The CPU provider pattern

The CPU runtime is the seam through which an engine delegates **session execution** to a shared, engine-agnostic runtime. Contract: `sdk/runanywhere-commons/include/rac/plugin/rac_cpu_runtime_provider.h`.

```
engine plugin                         runtimes/cpu (in rac_commons)
─────────────                         ─────────────────────────────
k_llamacpp_cpu_provider {             provider_registry()  (ProviderRegistry<…>)
  .name = "llamacpp"                    register_provider(provider)  ← copied by value
  .primitive = GENERATE_TEXT            find_by_desc(desc, &provider) ← match primitive+format
  .formats = {GGUF, …}
  .create_session / run_session   ┐   cpu_create_session(desc, &out):
  .destroy_session                │     find_by_desc → provider.create_session → wrap
  .run_session_v2 (optional)      │   cpu_run_session(session, …):
}                                 │     → provider.run_session(provider_session, …)
        │                         │
  rac_cpu_runtime_register_provider(&provider)   (engine register fn)
```

Mechanics:
- An engine fills a `rac_cpu_runtime_provider_t` (name, primitive, formats, `create_session`/`run_session`/`destroy_session`, optional V2-native `run_session_v2`) and calls `rac_cpu_runtime_register_provider()` at registration; `rac_cpu_runtime_unregister_provider(name)` on teardown. Strings/format arrays must outlive the registration (copied by value). See `engines/llamacpp/rac_backend_llamacpp_register.cpp:116,402,406`.
- `cpu_create_session` (`cpu/rac_runtime_cpu.cpp:239`) validates the primitive range, requires a model path **or** blob, then `find_by_desc()` picks the matching provider and forwards. The CPU runtime wraps the provider's session in a magic-tagged `CpuRuntimeSession` (`kCpuSessionMagic`); `cpu_run_session` (`:279`) forwards to `provider.run_session`.
- `cpu_capabilities` (`cpu/rac_runtime_cpu.cpp:181`) is **dynamic**: it rebuilds the supported-primitive list from whichever providers are currently registered (so STT/TTS/VAD/EMBED/RERANK/VLM/DIFFUSION can plug in without a CPU-runtime rebuild). The flags — including `RAC_RUNTIME_CAP_SESSION_EXECUTION` — are unconditional; `RAC_RUNTIME_CAP_OWNED_OUTPUTS` is added only when some provider implements `run_session_v2` (the V1 shim can't transport output ownership).
- `rac_cpu_runtime_get_provider_session` (`:615`) exposes the provider-owned handle used by engine-specific streaming and LoRA operations.

Net: even the one session-hosting runtime is a **dispatch layer** — it owns the session lifecycle and the buffer ops, but the compute is the engine's bundled library.

---

## The engine ↔ runtime relationship

An engine declares which device runtimes it needs in its manifest's `runtimes[]` array (`rac_engine_manifest_t.runtimes` / `runtimes_count`). Three patterns describe how engines relate to runtimes — **kept consistent with [`engines/AGENTS.md`](../engines/AGENTS.md)**:

**Pattern 1 — Engine bundles its own runtime.** The engine ships the compute internally and declares the device(s) it can target as **hints**. `llamacpp` bundles llama.cpp/ggml and declares `RAC_RUNTIME_CPU` always, plus `RAC_RUNTIME_METAL` / `RAC_RUNTIME_CUDA` / `RAC_RUNTIME_VULKAN` **only when the linked ggml was actually compiled with that backend** (`#if defined(GGML_USE_METAL|CUDA|VULKAN)`, `engines/llamacpp/rac_plugin_entry_llamacpp.cpp:83-94,120-121`). For session ownership it registers a **CPU provider** (Pattern above). Declaring a runtime it cannot honor would make capability metadata misleading.

**Pattern 2 — Engine uses a separate runtime as a library.** The engine declares the runtime and calls into the runtime's C++/helper API. `onnx` declares `RAC_RUNTIME_ONNXRT` (`engines/onnx/rac_plugin_entry_onnx.cpp:44,77`) and drives ORT via `runtime::onnxrt::Session`. **This is the runtime as a shared library, not a session host.**

**Pattern 3 — Engine IS our own code on a device-runtime.** The engine is RunAnywhere code that runs on a device runtime via that runtime's loader/helpers. `coreml` declares `RAC_RUNTIME_COREML` (`engines/coreml/rac_plugin_entry_coreml.cpp:128,177`) and calls the Core ML loader helpers. (Contrast `cloud` engines: no runtime / pure HTTP — they declare no device runtime.)

### THE RULE

> An engine declares a runtime in `runtimes[]` **iff** its execution depends on that device.

Runtime declarations are currently advisory metadata. Engine selection is plain priority order through `rac_plugin_find()`, or an explicit identity pin through `rac_plugin_find_for_engine()`; it does not score or reject candidates based on runtime registration. Engines still must keep this metadata truthful for capability reporting and future routing policy.

**The thing to internalize:** declaring a runtime describes the device an engine depends on; it does **not** currently gate selection or mean the runtime executes the session. **Only `cpu` actually executes sessions; `onnxrt`/`coreml` provide a library / loader-helpers.**

---

## How to ADD a runtime (rare)

Adding a runtime is uncommon — most new device support arrives via an engine's bundled backend (Pattern 1) or a library wrapper (Pattern 2). Add a first-class runtime only when a **device/substrate** must be shared across engines or exposed to hardware-aware routing.

1. **Decide the role.** Capability-only (describe a device + maybe expose loader/helpers — like `coreml`/`onnxrt`) vs session-execution (actually host `create_session`/`run_session` — like `cpu`). **Default to capability-only** unless you genuinely host sessions through the C vtable; if you do, fill *all* of `create_session`/`run_session`/`destroy_session` **and** set `RAC_RUNTIME_CAP_SESSION_EXECUTION`.
2. **Create `runtimes/<name>/`** with `CMakeLists.txt` + `rac_runtime_<name>.cpp` (`.mm` for Apple frameworks). Fill a `rac_runtime_vtable_t` in `.rodata`: `metadata` (`abi_version = RAC_RUNTIME_ABI_VERSION`, a `rac_runtime_id_t`, `name`, `priority`, formats, devices), mandatory `init`/`destroy`/`device_info`/`capabilities`, session slots only if applicable, and a v2 extension on `reserved_slot_0` (NULL-filled if capability-only, or omit the slot entirely as `onnxrt` does).
3. **Register.** Define the entry with `RAC_RUNTIME_ENTRY_DEF(<name>)` and add `RAC_STATIC_RUNTIME_REGISTER(<name>);` at namespace scope. (Only the always-on CPU runtime is bootstrapped explicitly by the registry instead.) Add an `rac_<name>_runtime_require_available()` keep-alive anchor if engines need to force-retain the registrar TU under dead-symbol stripping.
4. **Wire the build.** Append `add_subdirectory(<name>)` in `runtimes/CMakeLists.txt` (guard Apple-only runtimes with `if(NOT APPLE) return() endif()`), behind a `RAC_RUNTIME_<NAME>` option.
5. **Connect a consumer.** A new `rac_runtime_id_t` value goes in `rac_primitive.h`. An engine opts in by adding the id to its manifest `runtimes[]` (Pattern 1/2/3). Only declare a runtime the engine truly depends on, and make sure it actually registers on the target host.

---

## Conventions

- C ABI surface prefixed `rac_`, types `_t`, errors `RAC_ERROR_*`, macros `RAC_*`. C++20 internals, pure C at the boundary. Run `./scripts/lint-cpp.sh` (`--fix`) before committing.
- Strings/arrays in a vtable must be lifetime-stable (`.rodata`); the registry stores pointers, never copies.
- An ObjC++ runtime (`.mm`) must **catch every `NSException`** at the C boundary — an uncaught ObjC exception bridging into `extern "C"` aborts the process (see the `@try/@catch` blocks in `coreml`).
- Keep this file in sync with [`engines/AGENTS.md`](../engines/AGENTS.md): the **3-pattern engine↔runtime taxonomy** must match across both documents.
