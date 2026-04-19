# Phase 1 — Plugin-based backends

> Goal: every backend in `src/backends/` exposes a `ra_plugin_entry`
> vtable. `PluginRegistry` + `EngineRouter` replace `rac_service_registry`.
> Old `rac_service_*` is gone by the end of this phase.

---

## Prerequisites

- Phase 0 landed and green.
- `rac_abi`, `rac_graph`, `rac_registry`, `rac_router` libraries exist and
  are built by the current CMake.
- `ra_engine_vtable_t` in `include/rac/abi/ra_plugin.h` is stable.

---

## What this phase delivers

1. **Each backend has a `<name>_plugin.cpp`** that:
   - Declares its vtable via `RA_PLUGIN_ENTRY_DECL(<name>)`.
   - Implements every function pointer the backend's primitives serve.
   - Calls `RA_STATIC_PLUGIN_REGISTER(<name>)` to self-register on
     iOS/WASM.
   - Reuses the existing integration code in the backend — no
     reimplementation of llama.cpp, whisper.cpp, sherpa-onnx, MetalRT,
     or WhisperKit.
2. **`PluginRegistry::global()` holds every backend** after
   `rac_sdk_init()`.
3. **`EngineRouter` is the single entry point** for getting a session
   of any primitive. No caller reaches for `rac_service_create` anymore.
4. **Wake word works for the first time.** The sherpa-onnx plugin wires
   the real KeywordSpotter; the always-returns-false stub at
   `wakeword_service.cpp:210,233,477-498` is deleted.
5. **`rac_service_*`, `rac_module_register`, and `rac_service_register_provider`
   are deleted.** Their 356 LOC in `src/core/rac_core.cpp` plus the
   matching header block goes away.
6. **OpenAI HTTP server internals routed through PluginRegistry.**

**No L3 primitive API changes yet.** The services
(`rac_llm_service.cpp` etc.) still expose callback APIs externally — they
just obtain their backend session via `PluginRegistry` instead of
`rac_service_create`. Callback→stream migration happens in Phase 2.

---

## Exact file-level deliverables

### New plugin entry points (5 files)

```text
sdk/runanywhere-commons/src/backends/llamacpp/llamacpp_plugin.cpp
sdk/runanywhere-commons/src/backends/whispercpp/whispercpp_plugin.cpp
sdk/runanywhere-commons/src/backends/onnx/sherpa_plugin.cpp
sdk/runanywhere-commons/src/backends/metalrt/metalrt_plugin.cpp
sdk/runanywhere-commons/src/backends/whisperkit_coreml/whisperkit_plugin.cpp
```

Each file follows the same shape:

```cpp
#include "rac/abi/ra_plugin.h"
// … existing backend's public header, e.g. llamacpp_backend.h …

namespace {
    // Free functions mapping ra_engine_vtable_t entries to the
    // existing backend integration. No new behaviour — just forwarding.
    ra_status_t llm_create(const ra_model_spec_t*, const ra_session_config_t*,
                           ra_llm_session_t**) { /* forwards to llamacpp_backend */ }
    // …etc for every primitive this backend serves…

    const ra_primitive_t kPrimitives[]    = { RA_PRIMITIVE_GENERATE_TEXT, RA_PRIMITIVE_EMBED, RA_PRIMITIVE_VLM };
    const ra_model_format_t kFormats[]    = { RA_FORMAT_GGUF };
    const ra_runtime_id_t kRuntimes[]     = { RA_RUNTIME_SELF_CONTAINED };
}

RA_PLUGIN_ENTRY_DECL(llamacpp) {
    if (!out_vtable) return RA_ERR_INVALID_ARGUMENT;
    *out_vtable = {};
    out_vtable->metadata.name             = "llamacpp";
    out_vtable->metadata.version          = "0.1.0";
    out_vtable->metadata.abi_version      = RA_PLUGIN_API_VERSION;
    out_vtable->metadata.primitives       = kPrimitives;
    out_vtable->metadata.primitives_count = std::size(kPrimitives);
    // …formats, runtimes, function pointers…
    return RA_OK;
}

RA_STATIC_PLUGIN_REGISTER(llamacpp)
```

### New primitive directories (for backends that serve >1 primitive)

`onnx/sherpa_plugin.cpp` populates 4 primitive function-pointer groups:
`transcribe`, `synthesize`, `detect_voice`, `wake_word`. `embed` stays
its own `onnx_embeddings_plugin.cpp` for symmetry with llamacpp+embed.

### Wake word — real inference wired

Remove the stub section of `src/features/wakeword/wakeword_service.cpp`
(lines 210, 233, 477-498 per cleanup audit). Replace with a thin dispatcher
that calls into the sherpa plugin's `ww_feed_audio` function pointer:

```cpp
// New shape
ra_status_t wakeword_feed_audio(ra_ww_session_t* session,
                                 const float* pcm, int32_t n,
                                 int32_t sr, uint8_t* detected_out) {
    // Look up sherpa plugin via PluginRegistry, call ww_feed_audio
}
```

### MetalRT — chip gate in vtable

`metalrt_plugin.cpp` sets `capability_check` to a function that:
1. Calls `HardwareProfile::detect()`.
2. Returns `hw.has_metal && hw.apple_chip_generation >= 3`.
3. PluginRegistry drops the plugin if `capability_check()` returns false.

This means on M1/M2 Macs and Intel the MetalRT plugin is simply absent
from the registry; EngineRouter picks llamacpp (self-contained GGML
kernels) instead.

### Existing register files deleted

```text
DELETE sdk/runanywhere-commons/src/backends/llamacpp/rac_backend_llamacpp_register.cpp
DELETE sdk/runanywhere-commons/src/backends/llamacpp/rac_backend_llamacpp_vlm_register.cpp
DELETE sdk/runanywhere-commons/src/backends/whispercpp/rac_backend_whispercpp_register.cpp
DELETE sdk/runanywhere-commons/src/backends/onnx/rac_backend_onnx_register.cpp
DELETE sdk/runanywhere-commons/src/backends/metalrt/rac_backend_metalrt_register.cpp
DELETE sdk/runanywhere-commons/src/backends/whisperkit_coreml/rac_backend_whisperkit_coreml_register.cpp
DELETE sdk/runanywhere-commons/src/features/platform/rac_backend_platform_register.cpp   (folded into plugin files where relevant)
```

### Core registry deleted

```text
DELETE (or stubbed for this phase then removed in Phase 8):
- include/rac/core/rac_core.h  — the rac_module_register, rac_service_* section
- src/core/rac_core.cpp        — implementation of the above
```

If any transitional call site still needs `rac_service_registry` during
this phase's in-PR refactor, we keep it as a thin inline shim that calls
`PluginRegistry::global().find_by_name(...)` and remove it at phase end.
**No shim survives the phase.**

### Service-layer integration

Each L3 service (`rac_llm_service.cpp`, `rac_stt_service.cpp`,
`rac_tts_service.cpp`, `rac_vad_service.cpp`, `rac_embeddings_service.cpp`,
`rac_vlm_service.cpp`, `rac_wakeword_service.cpp`,
`rac_diffusion_service.cpp`) receives a small patch:

```cpp
// Before
auto* backend = rac_service_create(RAC_SERVICE_LLM, model_spec);

// After
auto plugin = PluginRegistry::global().find(RA_PRIMITIVE_GENERATE_TEXT, fmt);
if (!plugin) return RA_ERR_BACKEND_UNAVAILABLE;
ra_llm_session_t* session = nullptr;
plugin->vtable.llm_create(&spec, &cfg, &session);
```

The public callback-based API shape of each service stays the same in
this phase.

### OpenAI HTTP server

`src/server/openai_handler.cpp` migrates from `rac_service_create` to
`PluginRegistry::global().find()`. API surface of the HTTP server is
unchanged.

### Tests (new)

```text
tests/integration/plugin_registry_integration_test.cpp
  — loads every backend plugin via PluginRegistry, asserts metadata
    matches expectations, asserts EngineRouter picks the right one
    under different hardware profiles (mock).

tests/integration/wakeword_real_inference_test.cpp
  — with a sample KWS model + WAV, asserts detected=true on positive
    and detected=false on silence. Proves the stub theater is dead.
```

### CMake wiring

Top-level `CMakeLists.txt` adds, after each backend's `add_library`:

```cmake
# Phase 1: every backend becomes a plugin-exposed target.
target_sources(rac_backend_llamacpp PRIVATE src/backends/llamacpp/llamacpp_plugin.cpp)
target_link_libraries(rac_backend_llamacpp PRIVATE rac_abi rac_registry)
# …repeat for whispercpp, onnx, metalrt, whisperkit_coreml…
```

`cmake/PluginSystem.cmake::rac_add_backend_plugin` eventually replaces
the per-backend `add_library` calls in Phase 7. Phase 1 leaves the
existing CMake structure intact — the existing backend libraries just
gain plugin-entry sources.

---

## Implementation order

1. **Write a reference implementation for one backend.** Start with
   llama.cpp — least dependency surface. Follow the structure from Phase 0
   step 15. Verify all 3 primitives (generate_text, embed, VLM) reachable
   through `PluginRegistry::find()`.

2. **Write its integration test.** Load a small GGUF, generate 5 tokens
   via `plugin->vtable.llm_generate`. Confirm fires token callback.

3. **Repeat for the other 4 backends** in this order (sorted by
   dependency simplicity):
   - whispercpp (1 primitive — `transcribe`)
   - whisperkit_coreml (1 primitive — `transcribe`; platform-gated to
     iOS/macOS)
   - metalrt (LLM + STT + TTS + VLM; chip-gated)
   - onnx/sherpa (4 primitives: transcribe, synthesize, detect_voice,
     wake_word)

4. **Fix wake word.** Before merging the sherpa plugin, delete the stub
   section of `wakeword_service.cpp` and wire the real dispatcher to
   the sherpa plugin's `ww_feed_audio`.

5. **Migrate each L3 service call site** from `rac_service_create` to
   `PluginRegistry::find`. Do it one service per commit for reviewability.

6. **Migrate OpenAI HTTP server** in the same commit as the service
   migration for LLM + embeddings.

7. **Delete `rac_service_registry`, `rac_module_register`,
   `rac_service_create`, `rac_service_register_provider`** and all their
   header declarations. Run the build — any stragglers become compile
   errors, fix them.

8. **Delete the 6 `rac_backend_*_register.cpp` files** since their
   register-to-registry logic is now in the plugin entry + auto-register.

9. **Add `RAC_BUILD_TESTS=ON` integration tests** and run them through
   ctest.

10. **Run full CI matrix** (macOS, Linux, Android, iOS). Every platform
    should still build and test green.

---

## API changes

### Removed (no replacement, no shim)

| Symbol | Replacement |
| --- | --- |
| `rac_module_register` | `RA_STATIC_PLUGIN_REGISTER(name)` macro |
| `rac_service_registry` | `ra::core::PluginRegistry::global()` |
| `rac_service_create(service_type, model_spec)` | `PluginRegistry::find(primitive, format)` + `vtable.<primitive>_create(...)` |
| `rac_service_register_provider(...)` | None — register files are deleted entirely |
| Enum `rac_service_type_t` | `ra_primitive_t` (already defined in Phase 0) |

### New public entry points

| Symbol | Location | Purpose |
| --- | --- | --- |
| `ra::core::PluginRegistry::global()` | `include/rac/registry/plugin_registry.h` | Sole registry |
| `ra::core::EngineRouter` | `include/rac/router/engine_router.h` | Smart backend selection |
| `ra::core::HardwareProfile::detect()` | `include/rac/router/hardware_profile.h` | Hardware capability snapshot |

No proto3 changes yet. That's Phase 5.

---

## Acceptance criteria

- [ ] Every backend is discoverable via `PluginRegistry::global().enumerate()`
      after `rac_sdk_init()`.
- [ ] `PluginRegistry::find(RA_PRIMITIVE_GENERATE_TEXT, RA_FORMAT_GGUF)`
      returns the llama.cpp plugin on a machine where it's registered.
- [ ] `PluginRegistry::find(RA_PRIMITIVE_WAKE_WORD, RA_FORMAT_ONNX)`
      returns the sherpa plugin. Integration test confirms real
      detection on a sample audio file.
- [ ] On an M3+ Mac, `PluginRegistry::find(RA_PRIMITIVE_GENERATE_TEXT,
      RA_FORMAT_GGUF)` returns **MetalRT** (higher router score) if the
      MetalRT SDK is available at build time.
- [ ] `grep -rn "rac_service_create\|rac_service_registry\|rac_module_register"
      sdk/runanywhere-commons/ | grep -v .md` returns empty.
- [ ] All 6 `rac_backend_*_register.cpp` files are deleted.
- [ ] `src/core/rac_core.cpp` has lost its registry section (~350 LOC
      shorter).
- [ ] `wakeword_service.cpp` no longer has the stub lines
      210/233/477-498.
- [ ] `cmake --build` + `ctest` green on macOS, Linux, Android, iOS.
- [ ] ASan + UBSan clean; no new TSan warnings.

---

## Validation checkpoint — **MAJOR**

Phase 1 is the first phase where runtime behaviour changes. See
`testing_strategy.md` for the standard gates. Phase-specific
checkpoint work:

- **Full feature preservation matrix run.** Every row of the L3 +
  L5 matrix runs via the new plugin path. Each of LLM / STT / TTS /
  VAD / VLM / wake-word / embed / voice-agent / RAG / OpenAI server
  endpoints must produce the same outputs (byte-identical for
  deterministic ops, ≤1-word Levenshtein for STT) as pre-Phase-1 on
  the same fixture. Record the expected outputs once before the
  phase starts; diff against them after.
- **Engine parity diff.** For LLM specifically, run the same prompt
  + seed + model through (a) the pre-Phase-1 build on a commit
  pinned to `main`, and (b) the post-Phase-1 build. The token
  streams must match. This is the regression shield for the
  registry refactor.
- **Wake word real-path test.** `wakeword_service.cpp` stub is
  gone; the real sherpa KWS is active. Use the Picovoice-style
  hotword + negative fixtures to confirm detect=true / detect=false
  on the two samples.
- **MetalRT chip gate.** On an M2 Mac the router selects MetalRT
  for LLM; on an Intel Mac (CI runner) the router selects
  llama.cpp. Verified by an integration test that inspects the
  router's chosen plugin name.
- **OpenAI server smoke.** Run the server; curl each of the three
  core endpoints (`/chat/completions`, `/embeddings`,
  `/audio/transcriptions`); verify 200 OK with the same response
  schema as pre-Phase-1.
- **Grep gate for deleted symbols.** `rac_service_create`,
  `rac_service_registry`, `rac_module_register`,
  `rac_service_register_provider`, `rac_backend_*_register` all
  return zero matches under `grep -rn sdk/runanywhere-commons/src/`.

**Sign-off before moving to Phase 2**: a team member other than the
author walks the feature preservation matrix and confirms every row
still works. No exceptions — Phase 2 starts from a known-good base.

---

## What this phase does NOT do

- L3 primitives still use callback APIs externally.
- Voice agent still uses the batch loop.
- RAG retrieval unchanged.
- No proto3 on the C ABI yet.
- Plugin binaries are still linked statically into `librac_commons.a` —
  Phase 7 adds dynamic loading.

---

## Known risks

| Risk | Probability | Mitigation |
| --- | --- | --- |
| Missing plugin on a platform breaks a downstream service call | Medium | Service returns `RA_ERR_BACKEND_UNAVAILABLE` cleanly; integration test covers each combination |
| `RA_STATIC_PLUGIN_REGISTER` + `__attribute__((constructor))` doesn't fire under some compiler (e.g. emscripten) | Low | Tested on clang 15 / gcc 12 / emscripten 3.1.50 in prior reference commit; fallback = manual call site in `rac_sdk_init` |
| Removing `rac_service_create` breaks an existing JNI call path | Low | Grep the JNI tree once; any survivors get the same migration treatment inside this phase |
| WhisperKit plugin only links on macOS/iOS — Linux build tries to compile it | Medium | `if(APPLE)` guard around `add_library` and `target_sources` for the whisperkit plugin |
| Chip-gate check for MetalRT runs before `rac_sdk_init` completes | Low | `capability_check` only called at plugin-load time — sufficiently early |
