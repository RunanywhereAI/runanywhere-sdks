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

#### ENG-ONNX-05: `rac_backend_onnx_register` still registers storage + download strategies (v2 model_strategy code)
`engines/onnx/rac_backend_onnx_register.cpp:165-166` keeps `rac_storage_strategy_register(RAC_FRAMEWORK_ONNX, ...)` + `rac_download_strategy_register(RAC_FRAMEWORK_ONNX, ...)`. `RAC_FRAMEWORK_ONNX` is a pre-v3 identifier; the equivalent code in other backends has migrated the framework gating into the plugin-entry manifest (`g_<name>_engine_vtable.metadata`). Audit whether these strategies are still consumed by commons; if not, delete them and the matching `rac_model_strategy_unregister(RAC_FRAMEWORK_ONNX)` at line 195.

## Cross-backend duplication

### DUP-01: Int16→Float32 audio conversion is duplicated across active STT backends
- `engines/sherpa/rac_backend_sherpa_register.cpp:40-50` `convert_int16_to_float32`

Currently only active in sherpa. Consolidate into a shared commons helper `rac_audio_pcm16_to_float32()` so the Iteration-I STT backends (whispercpp, metalrt) can reuse one implementation when they come back online.

### DUP-03: Backend-create scaffolding is structurally identical across active backends
Each backend's `<primitive>_create_impl` function in `rac_backend_<name>_register.cpp` follows the exact same shape:
```c++
if (!out_impl) return RAC_ERROR_NULL_POINTER;
*out_impl = nullptr;
RAC_LOG_INFO(LOG_CAT, "..._create_impl: model=%s", model_id);
rac_handle_t backend_handle = nullptr;
rac_result_t rc = rac_<primitive>_<name>_create(model_id, nullptr, &backend_handle);
if (rc != RAC_SUCCESS) return rc;
*out_impl = backend_handle;
return RAC_SUCCESS;
```
See `engines/sherpa/rac_backend_sherpa_register.cpp:141-153`, `engines/llamacpp/rac_backend_llamacpp_register.cpp:290-336`. Consolidate into a `RAC_DEFINE_CREATE_ADAPTER(primitive, name)` macro in `rac_plugin_entry.h`.

### DUP-05: Stream-callback adapter struct is copy-pasted inside llamacpp
- `engines/llamacpp/rac_backend_llamacpp_register.cpp:160-172` `StreamAdapter`
- `engines/llamacpp/rac_backend_llamacpp_vlm_register.cpp:46-58` `VLMStreamAdapter`

Same `{callback, user_data}` bridge, written twice inside the same engine. Factor into a shared `rac/plugin/rac_stream_adapter.h`.

### DUP-06: `rac_event_track("*.backend.created", ...)` sprinkled inconsistently
- llamacpp: emitted in `rac_llm_llamacpp_create` (`rac_llm_llamacpp.cpp:114`)
- sherpa STT: emitted in `rac_stt_sherpa_create` (`rac_stt_sherpa.cpp:97`)
- sherpa TTS: emitted in `rac_tts_sherpa_create` (`rac_tts_sherpa.cpp:74`)
- sherpa VAD: emitted in `rac_vad_sherpa_create` (`rac_vad_sherpa.cpp:78`)
- onnx: not applicable (no per-handle create flow — embeddings ops are stateless)

Active backends are consistent; lift the call pattern into the commons service layer so future backends inherit it by default (and Iteration-I backends can't silently drop it).

### DUP-07: Android 16K page-alignment link options block is copy-pasted in every CMakeLists
`engines/llamacpp/CMakeLists.txt:281-282, 309-310, 374-375`, `engines/sherpa/CMakeLists.txt:358-361`, `engines/onnx/CMakeLists.txt:209-210, 281-282`. Move into a shared `cmake/plugins.cmake` helper.

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

Cross-backend items that originally pulled in deferred backends (DUP-01 metalrt / whispercpp slices, DUP-03 whispercpp / metalrt slices, DUP-05 metalrt slices, DUP-06 metalrt / diffusion-coreml / whisperkit_coreml slices, DUP-07 whispercpp / genie slices) are stripped to their active-backend portions above.

Previously-tracked llamacpp wins — ENG-LLAMA-01, ENG-LLAMA-02, ENG-LLAMA-04 (DeviceType dedup — shared header at `engines/common/rac_engine_device_type.h`), ENG-LLAMA-05, ENG-LLAMA-06, ENG-LLAMA-07 — were closed and are not re-listed here.
