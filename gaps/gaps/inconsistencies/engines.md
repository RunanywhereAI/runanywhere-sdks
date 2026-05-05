# Engines (Backend Plugins) — Current Inconsistencies

Updated: 2026-05-05 (post-audit prune)
Branch: feat/v2-architecture @ 6217d9e67

## Scope

Active engines only: **`engines/llamacpp/`**, **`engines/sherpa/`**, **`engines/onnx/`**.

Every other engine plugin is parked behind Iteration I — see the *Deferred to Iteration I* section at the bottom. Iteration-I gaps are not audited, not verified, and not actionable out of this document.

## Current state summary

All three active backends publish a `rac_engine_vtable_t` via `RAC_PLUGIN_ENTRY_DEF(<name>)` and declare `rac_engine_manifest_t` metadata. Post ENG-SHERPA-03 / ENG-LLAMA-03, registration is standardized across the active tree: every backend ships both (a) an explicit `rac_backend_<name>_register()` entry used by dynamic hosts (Android / Linux / macOS dev; onnx / sherpa / llamacpp) and (b) a `rac_static_register_<name>.cpp` shim expanding `RAC_STATIC_PLUGIN_REGISTER(<name>)` used by static hosts (iOS / WASM, `RAC_STATIC_PLUGINS=ON`). The sherpa ELF `__attribute__((constructor))` auto-register block has been deleted. The ONNX JNI bridge dlsyms `rac_backend_sherpa_register` opportunistically so Android / JVM hosts that dlopen `librac_backend_sherpa.so` still register Sherpa without requiring a dedicated sherpa JNI bridge.

Backend health: llamacpp (healthy, 5 gaps already resolved — 01/02/05/06/07), sherpa (healthy — wakeword file no longer present, former DUP-02 concern closed), onnx (healthy modulo the two remaining CMake / registration smells).

## Per-backend gaps

### engines/llamacpp

#### ENG-LLAMA-03: llamacpp is the only backend with a dedicated static-register TU
`engines/llamacpp/rac_static_register_llamacpp.cpp:28` is the only `RAC_STATIC_PLUGIN_REGISTER(<name>)` call in the active tree. Sherpa and onnx have no equivalent. On iOS / WASM (`RAC_STATIC_PLUGINS=ON` per CLAUDE.md architectural note) all backends MUST go through this macro, otherwise the registry is empty for them. Either add `rac_static_register_<name>.cpp` shims to sherpa and onnx, or retire the shim and rely on a force-referenced symbol scheme.

### engines/sherpa

(no open gaps — ENG-SHERPA-03 resolved in Wave 2a: ELF ctor removed from `rac_plugin_entry_sherpa.cpp`; explicit `rac_backend_sherpa_register()` added in `rac_backend_sherpa_register.cpp`; public header `rac_plugin_entry_sherpa.h` added; `rac_static_register_sherpa.cpp` shim added to match llamacpp; ONNX JNI bridge opportunistically dlsyms `rac_backend_sherpa_register` at `nativeRegister` time; parallel `rac_static_register_onnx.cpp` shim added so all three active backends use the same explicit-register + static-shim pattern.)

### engines/onnx

(no open gaps — ENG-ONNX-05 resolved in Wave 2a: audited commons — no consumer calls `rac_storage_strategy_register`/`rac_download_strategy_register` outside this TU, wrappers `rac_model_strategy_*` all fall through to the default `rac_model_paths_resolve_artifact` path; deleted the three registrations + 7 strategy callbacks + unused `rac_model_strategy.h`/`rac_model_types.h` includes. Framework gating for ONNX already lives in `g_onnx_engine_vtable.metadata` per the plugin-entry TU comment. Whole strategy registry infrastructure in commons is now dead machinery — tracked as CPP-STRATEGY-CLEANUP in cpp-layer.md.)

## Cross-backend duplication

(DUP-03 resolved in Wave 2a: `RAC_DEFINE_CREATE_ADAPTER(primitive, name)` landed in `sdk/runanywhere-commons/include/rac/plugin/rac_plugin_entry.h`. Sherpa STT / TTS / VAD `*_create_impl` scaffolds collapsed to a single macro invocation each — net -32 LOC in `engines/sherpa/rac_backend_sherpa_register.cpp`. Llamacpp LLM `create_impl` intentionally NOT migrated: its 45-line body wraps `LlamaCppRuntimeImpl` around the CPU-runtime session path and cannot be expressed as a 7-line forward. Onnx embeddings `create_impl` also NOT migrated: wraps the create in try/catch + std::make_unique + is_ready()-after-init check. Both remain hand-written by design. Follow-up opportunity — DUP-03B — if and when whispercpp / whisperkit_coreml come off Iteration-I hold, their minimal STT `create_impl` scaffolds are direct candidates for the same macro.)

(DUP-05 resolved in Wave 2a: shared template `rac::plugin::StreamAdapter<CallbackT>` landed at `sdk/runanywhere-commons/include/rac/plugin/rac_stream_adapter.h`. Both llamacpp TUs now `using StreamAdapter = rac::plugin::StreamAdapter<rac_llm_stream_callback_fn>;` / `using VLMStreamAdapter = rac::plugin::StreamAdapter<rac_vlm_stream_callback_fn>;`. Duplicate struct definitions deleted from `engines/llamacpp/rac_backend_llamacpp_register.cpp` and `engines/llamacpp/rac_backend_llamacpp_vlm_register.cpp`. Both TUs recompile clean under `cmake --build build/macos-debug --target rac_backend_llamacpp`; the pre-existing ggml-metal link errors are unrelated. The per-primitive C trampoline (`stream_adapter_callback` / `vlm_stream_adapter_callback`) was intentionally NOT collapsed since each still needs to discard its own `is_final` arg and cast to its specialization — the win is the removed struct body, not the 6-line trampoline.)

(DUP-06 resolved in Wave 2a: lifted `rac_event_track("*.backend.created", ...)` into the commons service layer. LLM emit fires from `sdk/runanywhere-commons/src/features/llm/rac_llm_service.cpp` at the end of `rac_llm_create` after a successful `vt->llm_ops->create`; STT from `rac_stt_service.cpp` in `rac_stt_create`; TTS from `rac_tts_service.cpp` in `rac_tts_create`; VAD from `src/features/vad/vad_component.cpp` in `rac_vad_component_load_model` after a successful `vad_ops->create` + start. All four commons emits read the backend name from `vt->metadata.name` so the payload is correct regardless of which plugin the router picks — future backends inherit the emit for free. Deleted the per-backend firings in `engines/llamacpp/rac_llm_llamacpp.cpp` (was line 114), `engines/sherpa/rac_stt_sherpa.cpp` (was line 97), `engines/sherpa/rac_tts_sherpa.cpp` (was line 74), `engines/sherpa/rac_vad_sherpa.cpp` (was line 78). `rac_commons` + `rac_backend_sherpa` targets recompile clean under `cmake --build build/macos-debug`. Note: deferred `engines/whispercpp/rac_stt_whispercpp.cpp:90` still fires its own `stt.backend.created` — will double-fire if whispercpp comes off Iteration-I hold without cleanup; accepted since whispercpp is not currently built by any active host.)

## Items to DELETE

(none currently tracked)

## Cross-SDK alignment expectations (active backends)

- **Swift**: RABackendLLAMACPP, RABackendONNX, RABackendSherpa are separate xcframeworks. iOS (`RAC_STATIC_PLUGINS=ON`) now has a dedicated static-register shim for each backend (`rac_static_register_{llamacpp,sherpa,onnx}.cpp`). Hosts must still `-force_load` every backend archive so the shim TU survives linker DCE — builds are silently broken if the flag is missing.

- **Kotlin / Android**: JNI bridges live in `engines/{llamacpp,onnx}/jni/`. Each calls `rac_backend_<name>_register()` explicitly. The onnx JNI bridge additionally dlsyms `rac_backend_sherpa_register` opportunistically from `nativeRegister`, so Android hosts that load `librac_backend_sherpa.so` still wire up sherpa through the standardized explicit-register path.

- **Flutter / React Native**: Mirror Kotlin on Android and Swift on iOS. Every backend now exposes an explicit `rac_backend_<name>_register` symbol (including sherpa, post ENG-SHERPA-03). The Flutter `-all_load` + LTO strip workaround in `scripts/build-core-xcframework.sh` remains in place to keep the static-shim TUs alive; no other per-platform special casing is needed.

- **Web / WASM**: WASM is static-plugins-only. All three active backends now ship a static-register shim (`rac_static_register_{llamacpp,sherpa,onnx}.cpp`); the WASM export-list entry for `_rac_backend_sherpa_register` at `sdk/runanywhere-web/wasm/CMakeLists.txt:936` is no longer a dead reference. onnx and sherpa are still force-OFF on WASM (`engines/onnx/CMakeLists.txt:56-58`, `engines/sherpa/CMakeLists.txt:95-98`) pending the vendored static-archive TODO (CPP-13 / WEB-01). WASM remains LLM-only until those TODOs land.

- **Manifest `package_name` consistency**: `runanywhere_llamacpp`, `runanywhere_sherpa`, `rac_backend_onnx`. The onnx value is the outlier (uses the CMake target name). Standardize to `runanywhere_onnx`.

- **Priority declarations**: llamacpp=100, sherpa=90, onnx=50. CLAUDE.md lists llamacpp=100, sherpa=90 but omits onnx=50. Add the onnx entry.

## Deferred to Iteration I

All gaps under the following backends are parked. Do not audit, fix, or reference them in the active tracker.

- `engines/metalrt/` — ENG-METALRT-01, ENG-METALRT-02, ENG-METALRT-03, ENG-METALRT-04, ENG-METALRT-05 *(Iteration I — deferred)*
- `engines/genie/` — ENG-GENIE-01, ENG-GENIE-02, ENG-GENIE-03, ENG-GENIE-04 *(Iteration I — deferred)*
- `engines/whispercpp/` — ENG-WHISPER-* *(Iteration I — deferred)*
- `engines/diffusion-coreml/` — ENG-DIFFUSION-01, ENG-DIFFUSION-02, ENG-DIFFUSION-03, ENG-DIFFUSION-04 *(Iteration I — deferred)*
- `engines/whisperkit_coreml/` — ENG-WKC-01, ENG-WKC-02, ENG-WKC-03 *(Iteration I — deferred)*

Cross-backend items that originally pulled in deferred backends (DUP-03 whispercpp / metalrt slices, DUP-05 metalrt slices, DUP-06 metalrt / diffusion-coreml / whisperkit_coreml slices) are stripped to their active-backend portions above. DUP-01 (pcm16→f32) was resolved in Wave 2a: sherpa now routes through the shared commons helper `rac::audio::rac_audio_pcm16_to_float32` in `sdk/runanywhere-commons/include/rac/audio/rac_audio_convert.h`. DUP-07 (Android 16 KiB page-alignment link block) was resolved in Wave 2a: extracted to `rac_apply_android_page_alignment()` in `cmake/plugins.cmake`; whispercpp / genie still carry the raw block because they remain deferred.

Previously-tracked llamacpp wins — ENG-LLAMA-01, ENG-LLAMA-02, ENG-LLAMA-04 (DeviceType dedup — shared header at `engines/common/rac_engine_device_type.h`), ENG-LLAMA-05, ENG-LLAMA-06, ENG-LLAMA-07 — were closed and are not re-listed here.
