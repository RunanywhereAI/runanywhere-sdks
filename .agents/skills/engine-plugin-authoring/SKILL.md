---
name: engine-plugin-authoring
description: Step-by-step recipe for adding a new engine plugin under runanywhere-sdks/engines/, or adding a modality (e.g. TTS) to an existing engine (llamacpp, sherpa, onnx, cloud, mlx, neurt, qhexrt). Use when the task is "add engine X", "wire up backend Y", or "make engine Z also serve <modality>".
---

# Engine plugin authoring (`engines/`)

Two related runbooks: adding a brand-new engine plugin, and adding a modality to one
that already exists. Read `engines/AGENTS.md` first for the concepts these steps
assume (op-table vtable, manifest, the valid-engine checklist, the 4-file skeleton,
the engine↔runtime rule). This skill is the "how", that file is the "what/why".

**Invariant that applies to both procedures:** never invent a new modality just to
ship an engine — fill an existing `rac_engine_vtable_t` slot. Adding a brand-new
*primitive* (a new `RAC_PRIMITIVE_*` + vtable slot) is a commons ABI change, covered
by `core/AGENTS.md` → "Adding a new capability interface", not an engine change.

---

## Procedure A — add a new engine

Mirror **sherpa** (multi-modality, standalone `.so`) or **cloud** (single modality,
no runtime) as your template; both are the cleanest references for the 4-file
skeleton described in `engines/AGENTS.md`.

1. **Create `engines/<name>/`** with the 4-file skeleton: `rac_plugin_entry_<name>.cpp`,
   `rac_backend_<name>_register.cpp` (skip it if there's no extra bring-up, like
   `neurt`), `rac_static_register_<name>.cpp`, plus your impl files.
2. **Write the manifest** in `rac_plugin_entry_<name>.cpp`:
   - `name` = snake_case identity (the library/framework you wrap, or your own
     codebase unit — NEVER a modality name; see the naming rule in
     `engines/AGENTS.md`).
   - `primitives[]` = what you serve; fill the matching vtable slots; leave every
     other slot explicit NULL (the all-NULL tripwire depends on this).
   - `runtimes[]` — only devices your compute actually depends on (NULL for
     cloud/HTTP engines) — see THE RULE in `engines/AGENTS.md`.
   - `formats[]` = the `RAC_MODEL_FORMAT_ID_*` values you accept (NULL if there's
     no local model file).
   - `priority`, `availability` (PUBLIC/PRIVATE), `package_owner`/`package_name`.
3. **Implement the op-table(s)** honoring the MODEL LIFECYCLE:
   `create → initialize → use → cleanup → destroy` (see `engines/AGENTS.md` for the
   exact signatures). Use `RAC_DEFINE_CREATE_ADAPTER(primitive, name)`
   (`core/include/rac/plugin/rac_plugin_entry.h`) when `create` is a plain forward
   onto `rac_<primitive>_<name>_create` — sherpa uses it for STT/TTS/VAD. Engines
   with richer create flows (llamacpp, onnx, neurt, qhexrt) hand-write it.
4. **`capability_check`** when the engine is platform- or binary-gated: use the
   shared 3-way helper `rac_engine_unavailable_capability(platform_supported,
   backend_present)` from `engines/common/rac_engine_unavailable.h`. When the
   backend can be entirely absent at build time (a private prebuilt archive, a
   sibling private repo), emit the stub with `RAC_ENGINE_UNAVAILABLE_PLUGIN(name,
   display, cap_fn)` from the same header — see qhexrt and neurt for the two-mode
   (ROUTABLE vs STUB) pattern this produces.
5. **Registration carriers:** `RAC_PLUGIN_ENTRY_DEF(<name>)` returning the vtable; a
   `rac_backend_<name>_register()`/`_unregister()` pair if you have extra bring-up
   (called directly by SDK bridges on dynamic-link hosts); a
   `rac_static_register_<name>.cpp` shim using `RAC_STATIC_REGISTER_BACKEND(<name>)`
   (routes through the register fn) or `RAC_STATIC_PLUGIN_REGISTER(<name>)` (calls
   the entry directly) for iOS/WASM static hosts.
6. **CMake:** call `rac_add_engine_plugin(<name> SOURCES … LINK_LIBRARIES …
   AVAILABILITY … PACKAGE_OWNER … PACKAGE_NAME …)` (`cmake/plugins.cmake`) from
   `engines/<name>/CMakeLists.txt`, fronted by your own
   `option(RAC_BACKEND_<NAME> "…" <default>)` + `if(NOT RAC_BACKEND_<NAME>)
   return() endif()` self-gate (each engine owns its own option — `engines/CMakeLists.txt`
   just unconditionally `add_subdirectory()`s and lets the child decide). Add
   `add_subdirectory(<name>)` there. Declare `primitives`/`runtimes`/`formats` ONLY
   in the C manifest, never in CMake, so the build graph can't drift from what the
   router routes.
7. **Android:** if the SDK loads the engine via `System.loadLibrary` +
   `nativeRegister`, add a JNI bridge with `RAC_DEFINE_ENGINE_JNI_BRIDGE(...)`
   (standalone per-engine `.so` — onnx, llamacpp) or
   `RAC_DEFINE_ENGINE_JNI_BRIDGE_NO_ONLOAD(...)` (folded into a host lib that
   already owns `JNI_OnLoad`, e.g. cloud → `librunanywhere_jni.so`) from
   `engines/common/rac_engine_jni_bridge.h`. The JVM class-path token in the macro
   call must match the Kotlin `*Bridge` class byte-for-byte.
8. **iOS/WASM static hosts:** make sure the host force-loads the plugin —
   `rac_force_load(<app> PLUGINS <name>)` in the host's CMakeLists — so the
   static-init Registrar TU survives linker stripping.
9. **If this engine ships an Electron/npm carrier package**, register it in
   `scripts/validation/gates/check_plugin_natives.py`'s `REQUIRED_OPS` dict (the
   ops-table symbol name(s) your entry TU references only on the routable
   branch) — `package-sdk.sh` calls this automatically, so an unregistered
   engine's stub/shell builds ship undetected. **Check which FILE actually
   compiles `rac_plugin_entry_<name>.cpp`** before assuming the carrier
   (`runanywhere_<name>`) is what to gate: sherpa/onnx/llamacpp compile it into
   the carrier itself (an undefined symbol reference there is the evidence),
   but neurt's `rac_add_engine_plugin()` call puts it on the ENGINE target
   (`rac_backend_neurt`) instead — the carrier there is empty boilerplate with
   zero symbols. Add the engine id to `EVIDENCE_IN_BACKEND_FILE` if it follows
   neurt's shape; discovered by actually building neurt for real and running
   `nm -a` on both files, not by reading the CMakeLists and assuming.

## Procedure B — add a modality to an existing engine

Multi-modality is the whole point of an identity-named engine. `cloud` and `neurt`
are explicitly built for this and carry the recipe inline as a comment next to
their vtable.

1. Implement the new modality's op-table (e.g. a cloud TTS `g_cloud_tts_ops`,
   typically backed by a per-modality provider adapter under `providers/`).
2. **Fill the corresponding slot** in the engine's `rac_engine_vtable_t`
   (`tts_ops` / `llm_ops` / `embedding_ops` / …) — every other slot must stay
   explicit NULL.
3. **Add the primitive** to the manifest's `primitives[]`.
4. Update `formats[]`/`runtimes[]` only if the new modality actually needs them
   (per THE RULE — don't declare a runtime your new op-table doesn't depend on).

No new plugin, no rename, no ABI bump — the engine already owns one
`rac_engine_vtable_t` with all ten primitive slots; you're just filling another one.
Grep the target engine's `rac_plugin_entry_<name>.cpp` for the phrase "To add a"
— cloud and neurt both leave a comment naming exactly which slots are still free
and what to add to `primitives[]`.
