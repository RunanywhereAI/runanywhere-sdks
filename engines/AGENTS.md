# AGENTS.md — `engines/`

This file is the authoritative architecture guide for the `engines/` tree — the
engine taxonomy lives **here and only here**; do not re-document it inside engine
headers or per-engine CMakeLists. See also the repo-root [`AGENTS.md`](../AGENTS.md)
(monorepo overview), [`core/AGENTS.md`](../core/AGENTS.md) (the plugin registry +
router this file's engines register into), and the sibling
[`runtimes/AGENTS.md`](../runtimes/AGENTS.md) (the L1 device-runtime adapters
engines are contrasted against below — its 3-pattern taxonomy is kept in sync with
this file's). For the step-by-step recipe to add a new engine or a modality to an
existing one, use the `engine-plugin-authoring` skill.

Everything below was verified against the current code as of this writing. This
file has drifted from the code before (stale primitive lists, a stale reserved-slot
count) — when reality and this doc disagree, the code wins; fix the doc.

---

## What an engine is

An **engine is an op-table adapter for modalities.** It fills exactly **one**
`rac_engine_vtable_t` (`core/include/rac/plugin/rac_engine_vtable.h`) — 10 live
primitive slots (`llm_ops`/`stt_ops`/`tts_ops`/`vad_ops`/`embedding_ops`/
`vlm_ops`/`diffusion_ops`/`diarization_ops`/`segmentation_ops`/`rerank_ops`);
**NULL means "I do not serve that primitive."** Serving more than one modality
just means filling more than one slot — today `llamacpp` fills four
(`llm`/`embedding`/`vlm`/`rerank`), `sherpa` fills three (`stt`/`tts`/`vad`). It
also attaches a declarative `rac_engine_manifest_t` (name, `primitives[]`,
`runtimes[]`, `formats[]`, `availability`, `priority`, package ownership) and
registers via `rac_plugin_register(vtable)`.

Dispatch goes through the plugin registry: callers in commons call
`rac_plugin_find(primitive)` (or `rac_plugin_find_for_engine(primitive,
engine_name)` to pin a specific engine). Selection is **plain priority order** —
the highest-`priority` engine serving the primitive wins, no scoring. The caller
then invokes `vtable->{primitive}_ops->create(...)`.

### An engine is named by its IDENTITY, never by a modality

The `name` is the **library/framework it wraps, or our own codebase unit** —
never the modality it happens to serve today, so the name stays stable as
modalities are added and two engines can't collide on a generic name like `stt`.

- **`cloud`** serves STT today but is named for its *transport* (generic HTTP);
  the concrete provider (Sarvam, future providers) is chosen per-`create()` from
  `config_json["provider"]`, not baked into the name.
- **`neurt`** serves LLM, STT, and DIFFUSION but is named for the *runtime that
  implements it* (NeuRT, the Apple half of the sibling `neurun` repo) — it was
  `diffusion-coreml`, then `coreml`, then `neurt`, each rename moving further
  from a modality and closer to a stable identity.

Both carry a "to add a modality, fill another op-table slot" comment next to
their vtable — deliberately built to grow.

**Deleted engines:** `whisperkit_coreml` and `whispercpp` were removed. STT is
now **sherpa** (on-device) plus **cloud** (HTTP). No whisper engine exists in
this tree — don't resurrect one from old docs/memory.

---

## Current engine roster

| Engine | Modalities (filled slots) | Wraps | Pattern¹ | Default | Notes |
|---|---|---|---|---|---|
| **llamacpp** | LLM + EMBED + VLM + RERANK | llama.cpp/ggml (FetchContent); mtmd for VLM | 1 | ON | priority 100. Declares `RAC_RUNTIME_CPU` always + Metal/CUDA/Vulkan gated on `GGML_USE_*`. Also registers a CPU **provider** into `runtimes/cpu` for session dispatch. |
| **sherpa** | STT + TTS + VAD | Sherpa-ONNX C API (prebuilt, bundles its own ORT) | 3 (bundled-lib) | ON | priority 90. Declares `RAC_RUNTIME_CPU`. Offline recognizer; VAD is Silero-style. Routable only when `SHERPA_ONNX_AVAILABLE` + `RAC_SHERPA_SPEECH_OPS_AVAILABLE`. |
| **onnx** | SEGMENT + DIARIZE (always) + EMBED (when `RAC_BACKEND_RAG`) | ONNX Runtime via `runtimes/onnxrt`'s `Session` class | 2 | ON | priority 50. Declares `RAC_RUNTIME_ONNXRT`. STT/TTS/VAD are sherpa's, not onnx's. |
| **cloud** | STT | none — HTTP to a provider (Sarvam today) | 3 (no runtime) | ON | priority 50, modality-agnostic name. `runtimes = NULL` → never runtime-rejected. Provider chosen via `config_json["provider"]`. Multi-modality-ready. |
| **neurt** | LLM + STT + DIFFUSION | **NeuRT** (sibling `neurun` repo): prebuilt Core ML LLM + ASR graphs on the Apple Neural Engine, plus our Stable-Diffusion pipeline on `MLModel` | 3 | ON (Apple) | priority 100, Apple-only, identity-named. Kept **below** mlx's 110 on purpose: ANE models arrive by `rac_plugin_find_for_engine` name pin, not priority. ROUTABLE from **prebuilt archives** published by `neurun` and pinned in `core/VERSIONS` (`scripts/build/download-neurt.sh`); a `NEURT_ROOT` checkout is a local-development fallback and prebuilt deliberately wins over it. See the shell pattern below. |
| **mlx** | LLM + STT + TTS + EMBED + VLM | our Swift `mlx-swift-lm` callback bridge (Apple MLX) | 1 | ON (Apple) | priority 110. PUBLIC availability but Apple-gated: `mlx_capability_check` silent-rejects non-Apple. Declares `RAC_RUNTIME_CPU` + `RAC_RUNTIME_METAL` as hints. `SHARED_ONLY`. |
| **qhexrt** | LLM, VLM, STT, TTS, EMBED, DIFFUSION (six) when linked | private RunAnywhere QHexRT prebuilt archive | 1 (QNN-context bundles) | OFF | priority 150 when routable. Diffusion here is inpainting-only (LaMa) with host preprocessing around one QNN graph. Authorized Android arm64-v8a / Windows ARM64 builds link the archive under `QHEXRT_ROOT`. |

¹ Pattern number = the engine↔runtime pattern below.

`RAC_PRIMITIVE_RERANK` was **revived as a first-class cross-encoder reranking
primitive in ABI v8** at **wire value 11**, its `rerank_ops` slot promoted from
`reserved_slot_2` (same binary offset, so the struct layout stayed stable). The
*original* rerank slot (wire value 6, retired in ABI v4) stays permanently
retired — the registry still rejects a manifest that declares wire value 6.

### Private/optional engines: the ROUTABLE-vs-STUB shell

`qhexrt` and `neurt` both compile the **same public entry symbol** two ways,
selected by a build-time availability macro (the private prebuilt archives are
present — for `neurt`, downloaded to `core/third_party/neurt/<slice>/`; or, for
local development only, `NEURT_ROOT` points at a neurun checkout):
**ROUTABLE** (manifest + vtable filled for real) or **STUB**
(the public default when the private archive/checkout is absent) — the shared
all-NULL not-routable shell from `RAC_ENGINE_UNAVAILABLE_PLUGIN` (see below),
whose `capability_check` returns `RAC_ERROR_BACKEND_UNAVAILABLE` so registration
is *refused* rather than accepted-and-useless. This is what lets public CI build
Android/Windows-ARM64 and Apple targets at all, since the QHexRT archive and the
neurun checkout are both private repos/artifacts. Packaging still double-guards
neurt: `build-core-xcframework.sh` refuses to ship a stub unless
`RAC_ALLOW_NEURT_STUB=1`.

---

## The valid-engine contract (checklist)

An engine is valid iff it provides all five. The all-NULL tripwire in the vtable
initializer is what keeps the ABI from drifting silently.

1. **A `rac_engine_manifest_t`**: `name` (snake_case identity matching
   `RAC_PLUGIN_ENTRY_DEF(<name>)` and the dlopen loader's filename heuristic,
   `librunanywhere_<name>.*`); `primitives[]` (must agree with the non-NULL
   vtable slots, validated by `rac_engine_manifest_validate_vtable`);
   `runtimes[]` (declared **iff** execution depends on that device — THE RULE
   below); `formats[]` (`RAC_MODEL_FORMAT_ID_*`, NULL when there's no local
   model file, e.g. cloud); `availability` (PUBLIC/PRIVATE), `priority`,
   package owner/name.
2. **A `rac_engine_vtable_t`**: served-primitive slots non-NULL, **every other
   slot explicit NULL** (10 primitive slots + the optional
   `get_stream_token_counts` callback + **7 reserved slots**). Lives in
   `.rodata`; a future reserved-slot promotion turns the aggregate initializer
   into a compile error — the intended tripwire.
3. **The uniform MODEL LIFECYCLE** on each served op-table:

   ```
   create(model_id, config_json, **impl)   // allocate impl; route already chose this engine
        → initialize(impl, model_path, …)  // load weights (VLM also takes mmproj_path;
        →   use:                           //   diffusion takes a config; VAD's initialize added in v3)
              generate / transcribe / synthesize / process / embed / …
        → cleanup(impl)                    // unload, KEEP the service/impl shell alive
        → destroy(impl)                    // free the impl
   ```

   `config_json` is advisory: an engine that doesn't understand a key **must**
   ignore it and succeed with defaults.
4. **`capability_check`** — the shared 3-way helper
   `rac_engine_unavailable_capability(platform_supported, backend_present)`
   (`engines/common/rac_engine_unavailable.h`) returns
   `RAC_ERROR_CAPABILITY_UNSUPPORTED` (wrong OS, silent reject),
   `RAC_ERROR_BACKEND_UNAVAILABLE` (right OS, impl absent), or `RAC_SUCCESS`.
   NULL ⇒ always-accept. A non-zero return rejects the plugin without logging.
5. **Registration** — `RAC_PLUGIN_ENTRY_DEF(<name>)` plus a static/dynamic
   register carrier (Build & registration below).

`RAC_PLUGIN_API_VERSION` is currently `9u`; a mismatch rejects the plugin outright.

---

## The 4-file skeleton

Every in-tree engine follows the same file layout (sherpa and cloud are the
cleanest references). Names are by convention; CMake lists them explicitly.

| File | Role |
|---|---|
| `rac_plugin_entry_<name>.cpp` | The **manifest + vtable + `RAC_PLUGIN_ENTRY_DEF(<name>)`**. The single source of truth the router reads. |
| `rac_backend_<name>_register.cpp` | Idempotent `rac_backend_<name>_register()`/`_unregister()`: `rac_plugin_register(rac_plugin_entry_<name>())` plus any engine-specific bring-up. Called by SDK bridges on dynamic-link hosts. *(Engines with no extra bring-up — e.g. `neurt` — skip this file; the static shim calls the entry directly.)* |
| `rac_static_register_<name>.cpp` | One-line static-init shim, gated on `RAC_PLUGIN_MODE_STATIC`: `RAC_STATIC_REGISTER_BACKEND(<name>)` or `RAC_STATIC_PLUGIN_REGISTER(<name>)`. Used by iOS/WASM static hosts. |
| the impl (`<name>_backend.cpp`, `rac_<primitive>_<name>.cpp`, `.mm`, …) | The actual op-table implementations + native-lib glue. |

The boilerplate `create` adapter (a forward onto `rac_<primitive>_<name>_create`)
can be generated with `RAC_DEFINE_CREATE_ADAPTER(primitive, name)`
(`core/include/rac/plugin/rac_plugin_entry.h`) — sherpa uses it for STT/TTS/VAD;
engines with richer create flows (llamacpp, onnx, neurt, qhexrt) hand-write it.

### `engines/common/` shared helpers

Header-only, internal to `engines/` (not part of the stable `rac_*` C ABI).
Include via the `engines/` dir on the include path, e.g.
`#include "common/rac_engine_unavailable.h"`.

| Header | Provides |
|---|---|
| `rac_engine_unavailable.h` | `rac_engine_unavailable_capability(...)` + `RAC_ENGINE_UNAVAILABLE_PLUGIN(name, display, cap_fn)` — emits the full not-routable shell (empty manifest + all-NULL `.rodata` vtable + entry). Used by qhexrt/neurt in STUB mode. |
| `rac_engine_jni_bridge.h` | `RAC_DEFINE_ENGINE_JNI_BRIDGE(...)` / `_NO_ONLOAD(...)` — the standard `nativeRegister/Unregister/IsRegistered/GetVersion` Android JNI quartet. Full variant also emits `JNI_OnLoad` (standalone `.so`: onnx, llamacpp); `_NO_ONLOAD` omits it (folded into a host lib that already owns it, e.g. cloud → `librunanywhere_jni.so`). **JVM symbol parity is load-bearing** — the class-path token must match the Kotlin `*Bridge` byte-for-byte. |
| `rac_engine_sibling_loader.h` | `rac_engine_register_sibling(solib_name, register_symbol)` — cross-registers a sibling engine living in a separate `.so`, working around Android's per-class-loader linker namespaces. |
| `rac_engine_stt_types.h` | Shared internal STT request/result structs (one definition to avoid an ODR landmine across STT engines; sherpa is the sole consumer today). |
| `rac_engine_device_type.h` | Shared `runanywhere::DeviceType` enum returned by an engine's `get_device_type()`. |

---

## The engine↔runtime relationship

This is the single most-misunderstood part of the architecture (see
`runtimes/AGENTS.md` for the L1 runtime side of this same contract — its
3-pattern taxonomy must stay in sync with this section).

- **Pattern 1 — bundles its own runtime.** `llamacpp` compiles ggml straight in
  and never calls `runtimes/` for compute; it declares `RAC_RUNTIME_CPU` always
  plus Metal/CUDA/Vulkan **only when the linked ggml was actually built with
  that backend** (`GGML_USE_*` gating) — a routing **hint**, not a dependency
  claim. It separately registers a CPU *provider* into `runtimes/cpu` for
  session dispatch (see that file's "CPU provider pattern") — that's a provider
  registration, not a compute call into the runtime's vtable.
- **Pattern 2 — uses a separate runtime as a library.** `onnx` declares
  `RAC_RUNTIME_ONNXRT` and calls `runtimes/onnxrt`'s C++ `Session::create()`/
  `->run()` for EMBED and SEGMENT; the ORT `Env`/session are owned by the L1
  runtime, not the engine.
- **Pattern 3 — IS our own inference code on a device-runtime.** `neurt` is our
  LLM/STT/diffusion pipeline; Core ML's `MLModel` runs each sub-model via
  `rac_coreml_*` loader helpers from `runtimes/coreml` — separate
  registries/dirs/symbols (the cleanest illustration; until the `neurt` rename
  the engine and runtime shared the name `coreml`, which is what made this
  pattern easy to misread). *Sub-case (bundled-lib):* `sherpa` bundles its own
  ORT inside sherpa-onnx and declares `RAC_RUNTIME_CPU`. *Sub-case (no
  runtime):* `cloud` is pure HTTP and declares `runtimes = NULL`.

### THE RULE

> Declare a runtime in the manifest `runtimes[]` **iff-and-only-if** your
> execution depends on that device being present.

This is **advisory metadata**, not a claim you call the runtime's vtable, and
since the scoring `EngineRouter` was removed it is **not** used for selection
today — selection is plain priority order via `rac_plugin_find`, or an explicit
name pin via `rac_plugin_find_for_engine`. The registry validates declared
runtimes for consistency at registration but does **not** hard-reject an engine
whose declared runtimes are unregistered (`RAC_ERROR_RUNTIME_UNAVAILABLE` is
reserved, currently unproduced). Keep the metadata truthful anyway: llamacpp
declares CUDA only when `GGML_USE_CUDA` was actually defined, so tooling reading
`runtimes[]` isn't misled even though routing ignores it.

---

## Adding an engine or a modality

Use the **`engine-plugin-authoring`** skill for the step-by-step recipe (new
engine: mirror `sherpa`/`cloud`; new modality on an existing engine: mirror
`cloud`/`neurt`, which both carry a "to add a modality, fill this slot" comment
next to their vtable).

The one invariant to hold onto regardless: **never invent a new modality just to
ship an engine** — fill an existing `rac_engine_vtable_t` slot instead. Adding a
brand-new *primitive* is a commons ABI change (`core/AGENTS.md` → "Adding a new
capability interface"), not an engine change.

---

## Build & registration

Two link/registration modes, chosen by `RAC_STATIC_PLUGINS`:

- **Static fold-into-`rac_commons`** (`RAC_STATIC_PLUGINS=ON`, forced on
  iOS/WASM): the engine's SOURCES become private sources of `rac_commons`; the
  static-init Registrar (`RAC_STATIC_PLUGIN_REGISTER`/
  `RAC_STATIC_REGISTER_BACKEND`) registers it before `main()`. **No `dlopen`.**
  The host must keep the TU alive with `rac_force_load(<target> PLUGINS
  <name>)` — the per-platform linker incantation
  (`-Wl,-force_load` / `--whole-archive` / `/INCLUDE:`) lives in
  `cmake/plugins.cmake`, and is a two-layer defense (with the `[[gnu::used]]`
  marker symbol) against Apple's linker stripping the unreferenced Registrar TU
  — if a statically-linked engine mysteriously never registers, check this first.
- **SHARED `.so` dlopen** (default on Android/Linux/macOS/Windows): the engine
  builds as `librunanywhere_<name>.so` (or a `TARGET_NAME` override, e.g.
  `rac_backend_onnx`) with hidden visibility except the entry symbol. The host
  loads it via `rac_registry_load_plugin()`, which `dlsym`s
  `rac_plugin_entry_<name>` from the filename. On Android the SDK instead calls
  `rac_backend_<name>_register()` through the JNI bridge after
  `System.loadLibrary`.

`rac_add_engine_plugin(...)` (`cmake/plugins.cmake`) hides the static-vs-shared
branching — see its header comment for the full parameter list. `SHARED_ONLY`
means "never fold into `rac_commons`" (JNI bridges, test-link surfaces); it does
**not** force SHARED linkage, which is driven solely by `RAC_BUILD_SHARED` (iOS
still produces static archives for xcframework packaging even on a
`SHARED_ONLY` engine).
