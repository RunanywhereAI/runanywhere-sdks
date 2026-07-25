# AGENTS.md — `engines/`

This file is the authoritative architecture + contributor guide for the
`engines/` tree. The engine taxonomy lives **here and only here** — do not
re-document it inside engine headers or scatter it across the per-engine
CMakeLists. Cross-references: the repo-root `AGENTS.md` (monorepo overview),
`sdk/runanywhere-commons/AGENTS.md` (the C++ core that owns the plugin registry +
router), and the sibling `runtimes/` tree (the L1 device-runtime adapters this
doc repeatedly contrasts engines against).

> Conventions, per the repo's nested-AGENTS.md style: structured types over
> strings, simplicity over cleverness, cite real symbols. Everything below was
> verified against the current code; where reality differs from folklore, the
> code wins and the discrepancy is noted.

---

## What an engine is

An **engine is an op-table adapter for modalities.** Concretely, an engine:

1. Fills exactly **one** `rac_engine_vtable_t`
   (`sdk/runanywhere-commons/include/rac/plugin/rac_engine_vtable.h`) — a struct
   of per-modality op-table slots:
   `llm_ops` / `stt_ops` / `tts_ops` / `vad_ops` / `embedding_ops` / `vlm_ops` /
   `diffusion_ops` / `diarization_ops` / `segmentation_ops` / `rerank_ops` (10 live
   primitive slots; `rerank_ops` was revived as a first-class primitive in ABI v8 — see below). A **NULL slot means "I do
   not serve that primitive."** Serving more than one modality just means filling
   more than one slot (llama.cpp fills `llm_ops` + `vlm_ops`; sherpa fills
   `stt_ops` + `tts_ops` + `vad_ops`).
2. Attaches a declarative `rac_engine_manifest_t`
   (`rac_engine_manifest.h`) — name, served `primitives[]`, `runtimes[]`,
   `formats[]`, `availability`, `priority`, package ownership.
3. Registers via `rac_plugin_register(vtable)` (directly, or through the
   `rac_engine_entry_with_manifest()` helper which attaches the manifest then
   registers).

Dispatch happens through the plugin registry: callers in commons go through
`rac_plugin_find(primitive)` (or `rac_plugin_find_for_engine(primitive,
engine_name)` to pin a specific engine), declared in
`sdk/runanywhere-commons/include/rac/plugin/rac_plugin_entry.h`. Selection is
plain priority order — the highest-`priority` registered engine that serves the
requested primitive wins (no scoring). The caller then invokes
`vtable->{primitive}_ops->create(...)` and the rest of the op-table.

### An engine is named by its IDENTITY, never by a modality

The engine's `name` is the **library/framework it wraps, or our own codebase
unit** — never the modality it happens to serve today. This keeps the name
stable as modalities are added, and prevents two engines from colliding on a
generic name like `stt`.

- **`cloud`** serves STT today but is named for its *transport* (generic HTTP),
  not for STT. The concrete provider (Sarvam, future HTTP providers) is chosen
  per-`create()` from `config_json["provider"]`, not baked into the name.
  (`engines/cloud/rac_plugin_entry_cloud.cpp`,
  `engines/cloud/rac_stt_cloud.cpp:5-17`.)
- **`coreml`** serves DIFFUSION today (our Stable-Diffusion pipeline on Apple
  CoreML) but is named for the *framework* it runs on, not for diffusion. It was
  renamed from `diffusion-coreml` precisely to be modality-agnostic.
  (`engines/coreml/rac_plugin_entry_coreml.cpp:5-12`.)

Both carry an explicit "to add a modality, fill another op-table slot" comment in
their vtable — they are deliberately built to grow.

**Deleted engines:** `whisperkit_coreml` and `whispercpp` were removed. STT is
now **sherpa** (on-device, offline) plus **cloud** (online HTTP). No whisper
engine exists in this tree.

---

## Current engine roster

| Engine | Modalities (filled slots) | Wraps (3rd-party / our code) | Engine↔runtime pattern | Default | Notes |
|---|---|---|---|---|---|
| **llamacpp** | LLM (`llm_ops`) + VLM (`vlm_ops`) | llama.cpp / ggml (FetchContent), mtmd for VLM | **1** — bundles its own runtime | **ON** | priority 100. Declares `RAC_RUNTIME_CPU` always + Metal/CUDA/Vulkan gated on `GGML_USE_*`. Registers a CPU *provider* into `runtimes/cpu` (see Pattern 1). |
| **sherpa** | STT + TTS + VAD (`stt_ops`/`tts_ops`/`vad_ops`) | Sherpa-ONNX C API (prebuilt, bundles its own ORT) | **3** (bundled-lib sub-case) | **ON** | priority 90. Declares `RAC_RUNTIME_CPU`. Offline recognizer; VAD is Silero-style. Routable only when `SHERPA_ONNX_AVAILABLE` + `RAC_SHERPA_SPEECH_OPS_AVAILABLE`. |
| **onnx** | SEGMENT (`segmentation_ops`) + optional EMBED (`embedding_ops`) | ONNX Runtime via `runtimes/onnxrt` `Session` | **2** — uses a separate runtime as a library | **ON** | priority 50. Declares `RAC_RUNTIME_ONNXRT`. Segmentation is always advertised; embeddings remain gated on `RAC_BACKEND_RAG`. STT/TTS/VAD are sherpa's, not onnx's. |
| **cloud** | STT (`stt_ops`) | none — HTTP to a provider (Sarvam today) | **3** (no runtime — HTTP) | **ON** | priority 50, modality-agnostic name. `runtimes=NULL` → always eligible, never runtime-rejected. Provider via `config_json["provider"]`. Multi-modality-ready. |
| **coreml** | DIFFUSION (`diffusion_ops`) | **our** Stable-Diffusion pipeline on Apple CoreML `MLModel` | **3** — our inference code on a device-runtime | **ON (Apple)** | priority 100, Apple-only (`AVAILABILITY_PRIVATE`), modality-agnostic name. Self-registers via `RAC_STATIC_PLUGIN_REGISTER(coreml)`. The engine `coreml` uses the runtime `coreml` (same framework name, separate registry/dir). CMake pins `RAC_COREML_GENERATE_AVAILABLE=1`, so it is routable by default on Apple. Multi-modality-ready. |
| **mlx** | LLM (`llm_ops`) + STT (`stt_ops`) + TTS (`tts_ops`) + EMBED (`embedding_ops`) + VLM (`vlm_ops`) | **our** Swift `mlx-swift-lm` callback bridge (Apple MLX) | **1** — bundles its own runtime (mlx-swift) | **ON (Apple)** | priority 110. PUBLIC availability but Apple-gated: `mlx_capability_check` silent-rejects non-Apple, and `RAC_BACKEND_MLX` is forced OFF off-Apple. Declares `RAC_RUNTIME_CPU` + `RAC_RUNTIME_METAL` (hints); formats SAFETENSORS + FOLDER. `SHARED_ONLY`. Multi-modality (5 filled slots). |
| **qhexrt** | LLM, VLM, STT, TTS (`llm_ops`/`vlm_ops`/`stt_ops`/`tts_ops`) when linked | private RunAnywhere QHexRT prebuilt archive | **1** — QNN-context bundles on Snapdragon HNPU | **OFF** | priority 150 when routable. Public builds compile a not-routable shell when the private archive is absent; authorized Android builds link the prebuilt under `QHEXRT_ROOT`. |

`RAC_PRIMITIVE_RERANK` was **revived as a first-class cross-encoder reranking
primitive in ABI v8** at **wire value 11**, with its `rerank_ops` slot promoted
from `reserved_slot_2` on `rac_engine_vtable_t` (same binary offset, so the
struct layout stayed stable). It is present in `RAC_PRIMITIVE_TABLE` and routable.
The *original* rerank slot (wire value 6, retired in ABI v4) stays permanently
retired — the revived primitive is a new wire value, not a reuse of 6, and the
registry still rejects manifests that declare wire value 6.

---

## The valid-engine contract (checklist)

An engine is valid iff it provides all five of the following. The all-NULL
tripwire in the vtable initializer is what keeps the ABI from drifting silently.

1. **A `rac_engine_manifest_t`** (`rac_engine_manifest.h`):
   - `name` — snake_case **identity** (library/engine), matching the
     `RAC_PLUGIN_ENTRY_DEF(<name>)` symbol and the dlopen loader's
     filename-derived entry-name heuristic (`librunanywhere_<name>.*`).
   - `primitives[]` — the served primitives (must agree with the non-NULL vtable
     slots; the registry validates this via `rac_engine_manifest_validate_vtable`).
   - `runtimes[]` — declared **iff execution depends on that device** (the rule
     below).
   - `formats[]` — accepted `RAC_MODEL_FORMAT_ID_*` model-file formats (NULL when
     there is no local model file, e.g. cloud).
   - `availability` (PUBLIC / PRIVATE), `priority`, package owner/name.
2. **A `rac_engine_vtable_t`**: the served-primitive slots non-NULL, **every
   other slot explicit NULL** (10 primitive slots + 7 reserved slots). Lives in
   `.rodata` (no runtime allocation). A future reserved-slot promotion turns the
   aggregate initializer into a compile error — the intended tripwire.
3. **The uniform MODEL LIFECYCLE** on each served op-table (verified in
   `rac_llm_service.h`, `rac_stt_service.h`, `rac_diffusion_service.h`, and the
   VAD/TTS/VLM/embeddings service headers):

   ```
   create(model_id, config_json, **impl)   // allocate backend impl; route already chose this engine
        → initialize(impl, model_path, …)  // load weights into the impl (VLM also takes mmproj_path;
        →   use:                           //   diffusion takes a config; VAD's initialize was added in v3)
              generate / transcribe / synthesize / process / embed / …
        → cleanup(impl)                    // unload the model, KEEP the service/impl shell alive
        → destroy(impl)                    // free the impl
   ```

   `create` originated in v4 (the current `RAC_PLUGIN_API_VERSION` is `8u`) and replaced the
   deleted `rac_service_provider_t` factory; commons' `rac_<primitive>_create()`
   calls it after `rac_plugin_find` picks the engine. `config_json` is
   advisory: engines that don't understand it **must** ignore it and succeed with
   defaults.
4. **`capability_check`** — use the shared 3-way helper
   (`engines/common/rac_engine_unavailable.h`):
   `rac_engine_unavailable_capability(platform_supported, backend_present)`
   returns `RAC_ERROR_CAPABILITY_UNSUPPORTED` (wrong OS — silent reject),
   `RAC_ERROR_BACKEND_UNAVAILABLE` (right OS, impl absent), or `RAC_SUCCESS`. May
   be NULL ⇒ always-accept. A non-zero return rejects the plugin **without**
   logging an error.
5. **Registration** — `RAC_PLUGIN_ENTRY_DEF(<name>)` returning the vtable, plus a
   static/dynamic register carrier (see the skeleton + build sections).

---

## The 4-file skeleton

Every in-tree engine follows the same file layout (sherpa and cloud are the
cleanest references). Names are by convention; CMake lists them explicitly.

| File | Role |
|---|---|
| `rac_plugin_entry_<name>.cpp` | The **manifest + vtable + `RAC_PLUGIN_ENTRY_DEF(<name>)`**. Declares `primitives[]`/`runtimes[]`/`formats[]`, wires the ops-table pointers, owns `capability_check`. The single source of truth the router reads. |
| `rac_backend_<name>_register.cpp` | The idempotent `rac_backend_<name>_register()` / `_unregister()` entry point: `rac_plugin_register(rac_plugin_entry_<name>())` plus any engine-specific bring-up. Called directly by SDK bridges on dynamic-link hosts (Android/desktop). *(Engines with no extra bring-up — e.g. `coreml` — skip this file and let the static shim call the entry directly.)* |
| `rac_static_register_<name>.cpp` | One-line static-init shim, gated on `RAC_PLUGIN_MODE_STATIC`. Schedules a pre-`main()` ctor: `RAC_STATIC_REGISTER_BACKEND(<name>)` (routes through the register fn) or `RAC_STATIC_PLUGIN_REGISTER(<name>)` (calls the entry directly). Used by iOS/WASM static hosts. |
| the impl (`<name>_backend.cpp`, `rac_<primitive>_<name>.cpp`, `.mm`, …) | The actual op-table implementations + native-lib glue. |

The boilerplate `create` adapter (a 7-line forward onto the engine's native
`rac_<primitive>_<name>_create`) can be generated with
`RAC_DEFINE_CREATE_ADAPTER(primitive, name)` — sherpa uses it for STT/TTS/VAD;
engines with richer create flows (llamacpp, onnx, coreml, qhexrt) hand-write it.

### `engines/common/` shared helpers

Header-only, internal to `engines/` (not part of the stable `rac_*` C ABI).
Include via the `engines/` dir on the include path (e.g.
`#include "common/rac_engine_unavailable.h"`).

| Header | Provides |
|---|---|
| `rac_engine_unavailable.h` | `rac_engine_unavailable_capability(...)` (the 3-way decision) + `RAC_ENGINE_UNAVAILABLE_PLUGIN(name, display, cap_fn)` — emits the full not-routable shell: empty manifest + all-NULL `.rodata` vtable + `RAC_PLUGIN_ENTRY_DEF`. Internal building blocks `RAC_ENGINE_UNAVAILABLE_MANIFEST_DEF` / `_VTABLE_DEF` are exposed for engines wanting the shared manifest but a bespoke vtable. Used by qhexrt when the private archive is absent. |
| `rac_engine_jni_bridge.h` | `RAC_DEFINE_ENGINE_JNI_BRIDGE(...)` and `RAC_DEFINE_ENGINE_JNI_BRIDGE_NO_ONLOAD(...)` — the standard `nativeRegister/Unregister/IsRegistered/GetVersion` Android JNI quartet. The full variant also emits `JNI_OnLoad` (for a standalone per-engine `.so`: onnx, llamacpp); the `_NO_ONLOAD` variant omits it (for a TU folded into a host lib that already owns `JNI_OnLoad`: cloud's `rac_cloud_jni.cpp` → `librunanywhere_jni.so`). Plus `RAC_JNI_FN`, `RAC_DEFINE_ENGINE_JNI_LOG_TAG`, `LOGi/LOGe/LOGw`. **JVM symbol parity is load-bearing** — the class-path token must match the Kotlin `*Bridge` byte-for-byte. |
| `rac_engine_sibling_loader.h` | `rac_engine_register_sibling(solib_name, register_symbol)` — cross-registers a sibling engine that lives in a separate `.so`, working around Android's per-class-loader linker namespaces (dlopen-then-dlsym, falling back to `RTLD_DEFAULT`). |
| `rac_engine_stt_types.h` | Shared internal STT request/result structs (`STTRequest`, `STTResult`, `WordTiming`, `AudioSegment`, `STTModelType`) — one definition to avoid an ODR landmine across STT engines. Sherpa is the sole consumer today. |
| `rac_engine_device_type.h` | Shared `runanywhere::DeviceType` enum (CPU/GPU/NEURAL_ENGINE/METAL/CUDA/WEBGPU) returned by an engine's `get_device_type()`. |

---

## The engine↔runtime relationship

This is the single most-misunderstood part of the architecture, so it gets its
own section. (See `runtimes/` for the L1 device-runtime adapters.)

### The 3 legitimate patterns

1. **Engine bundles its own runtime.** The engine compiles the compute backend
   straight in and never calls into `runtimes/` for compute.
   - *Example:* **`llamacpp`** — ggml with Metal/CUDA/Vulkan compiled in. It
     declares `RAC_RUNTIME_CPU` + (conditionally) Metal/CUDA/Vulkan in its
     manifest **purely as routing/hardware HINTS**, gated on the `GGML_USE_*`
     macros the build actually defined
     (`engines/llamacpp/rac_plugin_entry_llamacpp.cpp:83-94`).
   - *Nuance:* llamacpp **does** register a CPU **provider** into `runtimes/cpu`
     for session-dispatch (`retain_llamacpp_cpu_runtime()` →
     `rac_llamacpp_cpu_runtime_register()`), refcounted and released in
     `on_unload`. That is a provider registration, not a compute call into the
     runtime's vtable.

2. **Engine uses a separate runtime as a library.** The engine has a real C++
   dependency on a `runtimes/` adapter and calls its API for compute.
   - *Example:* **`onnx`** → `runtimes/onnxrt`'s C++ `Session` class.
     `onnx_embedding_provider.cpp` and `onnx_segmentation_provider.cpp` call
     `runanywhere::runtime::onnxrt::Session::create(...)` / `->run(...)`
     for EMBED and SEGMENT, and the CMake links
     `rac_runtime_onnxrt` ("this engine uses only its thin session wrapper",
     `engines/onnx/CMakeLists.txt:145-146`). The ONNX Runtime `Env`/session are
     owned by the L1 onnxrt runtime, not the engine.

3. **Engine IS our own inference code on a device-runtime.** The engine is our
   pipeline; a device runtime executes the sub-models.
   - *Example:* **`coreml`** — our Stable-Diffusion pipeline; CoreML's `MLModel`
     runs each sub-model via the `rac_coreml_*` loader helpers. The **engine
     `coreml` uses the runtime `coreml`** — same framework name, **separate
     registries / directories / symbols** (`engines/coreml` vs `runtimes/coreml`)
     — the cleanest illustration of this pattern. It links `rac_runtime_coreml`.
   - *Sub-case (bundled-lib):* **`sherpa`** bundles its own ORT inside
     sherpa-onnx and calls the prebuilt library directly; it declares
     `RAC_RUNTIME_CPU`.
   - *Sub-case (no runtime):* **`cloud`** has no compute substrate at all — it is
     HTTP. It declares `runtimes = NULL`.

### THE RULE

> **Declare a runtime in the manifest `runtimes[]` if-and-only-if your execution
> depends on that device being present.**

The declaration is **advisory metadata**, *not* a claim that you call the
runtime's vtable — and since the scoring `EngineRouter` was removed it is **not**
used for selection today:

- Selection is plain priority order via `rac_plugin_find` (highest
  `metadata.priority` wins), or an explicit name pin via
  `rac_plugin_find_for_engine`. There is no runtime/format scoring, no
  `preferred_runtime` matching, and no pinned-engine bonus.
- Declared L1 runtimes are validated for consistency at registration (the
  manifest must match `metadata.runtimes`), but the registry does **not**
  hard-reject an engine whose declared runtimes are unregistered.
  `RAC_ERROR_RUNTIME_UNAVAILABLE` is reserved and currently not produced.
- `cloud` declaring zero runtimes is therefore informational only.

Corollary: llamacpp still declares CUDA only when built with `GGML_USE_CUDA`, so
its advertised runtimes honestly reflect the linked ggml. Selection no longer
consults them, but keeping the metadata truthful avoids misleading tooling and
telemetry.

---

## How to ADD A NEW ENGINE

Mirror **sherpa** (multi-modality, separate `.so`) or **cloud** (single
modality, no runtime). Concretely:

1. **Create `engines/<name>/`** with the 4-file skeleton above.
2. **Write the manifest** in `rac_plugin_entry_<name>.cpp`:
   - `name` = snake_case identity (NOT a modality).
   - `primitives[]` = what you serve; fill the matching vtable slots; leave all
     others explicit NULL.
   - `runtimes[]` per **THE RULE** — only devices your compute requires (NULL for
     cloud/HTTP engines).
   - `formats[]` = `RAC_MODEL_FORMAT_ID_*` you accept (NULL if no local model).
   - `priority`, `availability`, package owner/name.
3. **Implement the op-table(s)** honoring the **MODEL LIFECYCLE**
   (`create → initialize → use → cleanup → destroy`). Use
   `RAC_DEFINE_CREATE_ADAPTER` for simple create flows.
4. **`capability_check`** via `rac_engine_unavailable_capability(...)` when the
   engine is platform- or binary-gated.
5. **Registration carriers:** `RAC_PLUGIN_ENTRY_DEF(<name>)`; a
   `rac_backend_<name>_register()` if you have extra bring-up; a
   `rac_static_register_<name>.cpp` shim
   (`RAC_STATIC_REGISTER_BACKEND` / `RAC_STATIC_PLUGIN_REGISTER`).
6. **CMake:** `rac_add_engine_plugin(<name> SOURCES … LINK_LIBRARIES …
   AVAILABILITY … PACKAGE_OWNER … PACKAGE_NAME …)` in
   `engines/<name>/CMakeLists.txt`, fronted by an
   `option(RAC_BACKEND_<NAME> "…" <default>)` + `if(NOT RAC_BACKEND_<NAME>)
   return() endif()` self-gate. Add `add_subdirectory(<name>)` to
   `engines/CMakeLists.txt`. Engine `primitives/runtimes/formats` are declared
   **only** in the C manifest, never in CMake — so the build graph cannot drift
   from what the router routes.
7. **Android:** add a JNI bridge with `RAC_DEFINE_ENGINE_JNI_BRIDGE[_NO_ONLOAD]`
   if the SDK loads the engine via `System.loadLibrary` + `nativeRegister`.
8. **iOS/WASM static hosts:** ensure the host force-loads the plugin
   (`rac_force_load(<app> PLUGINS <name>)`) so the static-init Registrar survives
   the linker.

Do **not** invent a new modality just to ship an engine — fill an existing slot.
Adding a brand-new *primitive* is a commons ABI change (see
`sdk/runanywhere-commons/AGENTS.md` → "Adding a new capability interface"), not an
engine change.

---

## How to ADD A MODALITY to an existing engine

Multi-modality is the whole point of an identity-named engine. `cloud` and
`coreml` are explicitly built for this and carry the recipe inline:

1. Implement the new modality's op-table (e.g. a cloud TTS `g_cloud_tts_ops`,
   backed by a per-modality provider adapter under `providers/`).
2. **Fill the corresponding slot** in the engine's `rac_engine_vtable_t`
   (`tts_ops` / `llm_ops` / `embedding_ops` / …).
3. **Add the primitive** to the manifest's `primitives[]`.
4. Update `formats[]`/`runtimes[]` only if the new modality needs them.

The future-modality contract is written into the code itself:

- `engines/cloud/rac_plugin_entry_cloud.cpp:80-83` —
  *"To add a cloud TTS/LLM/embeddings modality: fill `tts_ops`/`llm_ops`/
  `embedding_ops` here … and add its primitive to k_cloud_manifest.primitives."*
- `engines/coreml/rac_plugin_entry_coreml.cpp:210-213` —
  *"To add a CoreML LLM/VLM/embeddings modality: fill `llm_ops`/`vlm_ops`/
  `embedding_ops` here … and add its primitive to k_coreml_manifest.primitives."*

No new plugin, no rename, no ABI bump — the engine already owns one
`rac_engine_vtable_t` with all the slots.

---

## Private engine shells

`qhexrt` is private and Android/Snapdragon-only. Public builds compile the same
`rac_plugin_entry_qhexrt` symbol as a not-routable shell when the prebuilt
archive is absent; authorized builds set `-DRAC_BACKEND_QHEXRT=ON` and point
`QHEXRT_ROOT` at the private archive to expose LLM, VLM, STT, and TTS over QNN
context bundles. The source for the private runtime never enters this repo.

---

## Build & registration

Two link/registration modes, chosen by `RAC_STATIC_PLUGINS`:

- **Static fold-into-`rac_commons`** (`RAC_STATIC_PLUGINS=ON` — **forced on iOS /
  WASM**): the engine's SOURCES become private sources of `rac_commons`, and the
  static-init Registrar (`RAC_STATIC_PLUGIN_REGISTER` / `RAC_STATIC_REGISTER_BACKEND`)
  registers it before `main()`. **No `dlopen`.** The host must keep the TU alive
  with `rac_force_load(<target> PLUGINS <name>)`, which emits the per-platform
  linker incantation:
  - macOS/iOS: `-Wl,-force_load,<lib.a>`
  - GNU/Android: `-Wl,--whole-archive <lib.a> -Wl,--no-whole-archive`
  - MSVC: `/INCLUDE:rac_plugin_static_marker_<name>`

  (The `[[gnu::used]]` marker symbol + force-load are the two-layer defense
  against Apple's linker stripping the unreferenced Registrar TU.)
- **SHARED `.so` dlopen** (default on Android / Linux / macOS / Windows): the
  engine builds as `librunanywhere_<name>.so` (or a `TARGET_NAME` override such
  as `rac_backend_onnx`) with hidden visibility except the entry symbol. The host
  loads it at runtime via `rac_registry_load_plugin()`, which `dlsym`s
  `rac_plugin_entry_<name>` (derived from the filename). On Android the SDK
  instead calls `rac_backend_<name>_register()` through the JNI bridge after
  `System.loadLibrary`.

Authoring helpers live in `cmake/plugins.cmake`:
`rac_add_engine_plugin(...)` (hides the static-vs-shared branching),
`rac_force_load(...)` (linker keep-alive), and
`rac_apply_android_page_alignment(...)` (the Android 15+ 16 KiB page-size flags).
`SHARED_ONLY` means "never fold into `rac_commons`" (needed for JNI bridges and
test-link surfaces); it does **not** force SHARED linkage — that is driven solely
by `RAC_BUILD_SHARED`, so iOS produces static archives the xcframework packaging
consumes.
