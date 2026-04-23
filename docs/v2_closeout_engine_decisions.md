# Phase F — Engine / Wakeword Implement-or-Delete Decisions

Scope: the three stub engines registered under `engines/` (sherpa, genie,
diffusion-coreml) and the high-level wakeword service at
`sdk/runanywhere-commons/src/features/wakeword/wakeword_service.cpp`.

All four satisfy the Phase F rule "stub engines with NULL ops +
`capability_check` returning unsupported are dead code — delete unless
there's a real user benefit to implementing them". The audit below
grounds each decision in actual file contents and repo-wide reference
searches.

## Summary

| Artifact                                    | Current state                                               | Real users found                                                                                             | Decision | Rationale                                                                                                                 | LOC delta |
| ------------------------------------------- | ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ | -------- | ------------------------------------------------------------------------------------------------------------------------- | --------- |
| `engines/sherpa/`                           | Plugin entry with NULL ops; `capability_check` unsupported  | none outside the dir itself (option `RAC_BACKEND_SHERPA` defaults OFF; no consumer flips it)                 | DELETE   | Sherpa-ONNX already ships inside `engines/onnx/` via `RAC_USE_SHERPA_ONNX`. The standalone dir is vestigial scaffold.     | –81       |
| `engines/genie/`                            | Plugin entry with NULL ops (`RAC_ERROR_CAPABILITY_UNSUPPORTED` on both Android and desktop) | none (option `RAC_BACKEND_GENIE` defaults OFF; Flutter `runanywhere_genie` package is an unrelated Dart-side wrapper) | DELETE   | Real QNN SDK integration is ~6–10 weeks of work; nothing depends on the scaffold. Re-add with real impl when work lands.  | –74       |
| `engines/diffusion-coreml/`                 | Plugin entry with NULL ops; `capability_check` unsupported  | none (option `RAC_BACKEND_DIFFUSION_COREML` defaults OFF; real diffusion code lives in commons)              | DELETE   | Apple CoreML diffusion already ships in `sdk/runanywhere-commons/src/features/diffusion/`. The standalone dir is vestigial. | –83       |
| `sdk/runanywhere-commons/src/features/wakeword/wakeword_service.cpp` (+ `rac_wakeword_service.h`, `rac_wakeword.h`) | 672-line high-level wakeword service with 7 TODO stubs (destroy backend, load via backend, run VAD, run ONNX, reset state, model info arrays x2) | none — all real consumers (`Playground/openclaw-hybrid-assistant`, `Playground/linux-voice-assistant`, `sdk/runanywhere-commons/tests/test_wakeword.cpp`) bypass the service and call `rac_wakeword_onnx_*` directly | DELETE the service / umbrella headers. KEEP `rac_wakeword_types.h` (error codes + types are used by the real ONNX backend in `engines/onnx/wakeword_onnx.cpp` and by `rac_voice_agent.h`). | –952 (cpp + svc header + umbrella header) |

Net result: 3 engines removed, 1 feature scaffold removed; keeping only
code with a real consumer.

## Per-artifact audit

### 1. `engines/sherpa/` — DELETE

`engines/sherpa/rac_plugin_entry_sherpa.cpp` declares an engine named
`"sherpa"` whose `stt_ops` slot is `nullptr` and whose
`capability_check()` unconditionally returns
`RAC_ERROR_CAPABILITY_UNSUPPORTED`. The CMakeLists gates the whole thing
behind `RAC_BACKEND_SHERPA`, which defaults `OFF` and is not enabled
anywhere in the tree.

Reference search (`rac_plugin_entry_sherpa|engines/sherpa|RAC_BACKEND_SHERPA`)
returns only the dir's own files. The substantive Sherpa-ONNX wiring
lives inside `engines/onnx/` (toggled by `RAC_USE_SHERPA_ONNX`), which is
where every real caller hits.

Impact of deletion: zero on existing callers. Removing the
`add_subdirectory(sherpa)` iteration also simplifies the
`engines/CMakeLists.txt` foreach block.

### 2. `engines/genie/` — DELETE

`engines/genie/rac_plugin_entry_genie.cpp` declares a Qualcomm Genie LLM
plugin whose `llm_ops` slot is `nullptr` and whose `capability_check()`
returns `RAC_ERROR_CAPABILITY_UNSUPPORTED` on every build (including
`__ANDROID__`, where the only action is a TODO comment about dlopen'ing
`libQnnHtp.so`). Option `RAC_BACKEND_GENIE` defaults `OFF` and no caller
flips it.

The Flutter package `sdk/runanywhere-flutter/packages/runanywhere_genie/`
looks related by name only — it calls its own Dart FFI entry
`rac_backend_genie_register()` expecting `librac_backend_genie_jni.so`, a
symbol that does not exist anywhere in this repo. That Flutter package is
an unrelated wrapper with its own lifecycle and does not depend on the
C++ `engines/genie/` scaffold.

Real QNN SDK integration is a multi-week effort (SDK drop, context
binary authoring, Hexagon compilation, runtime download flow). Keeping
the scaffold offers no user value and actively misleads the router into
scoring a no-op candidate. Delete and re-introduce with real ops when
that work is funded.

### 3. `engines/diffusion-coreml/` — DELETE

`engines/diffusion-coreml/rac_plugin_entry_diffusion.cpp` declares a
CoreML diffusion plugin whose `diffusion_ops` slot is `nullptr` and whose
`capability_check()` unconditionally returns
`RAC_ERROR_CAPABILITY_UNSUPPORTED`. Option
`RAC_BACKEND_DIFFUSION_COREML` defaults `OFF`.

The real Apple CoreML diffusion implementation lives in
`sdk/runanywhere-commons/src/features/diffusion/` and is linked straight
into `rac_commons` on Apple platforms. Every caller uses that path. The
separate engine scaffold has never provided a working `diffusion_ops`
table.

Delete now; reintroduce the engine-plugin wrapper only when the
commons-side diffusion code is being actively peeled into a standalone
shared library.

### 4. Wakeword service (`wakeword_service.cpp` + friends) — DELETE stub service, KEEP types

`sdk/runanywhere-commons/src/features/wakeword/wakeword_service.cpp` is
a 672-line wrapper that **says** it calls into the ONNX backend but
actually has 7 TODO placeholders where real inference should happen:

- line ~164: `rac_wakeword_destroy` never destroys a backend handle
  (comment: "Destroy backend handle when implemented")
- line ~207: `rac_wakeword_load_model` marks `is_loaded=true` without
  loading via any backend
- line ~229: `rac_wakeword_load_vad` similarly marks `vad_loaded=true`
  without loading via any backend
- line ~286 + line ~647: model info arrays return `nullptr` with a
  "TODO: Implement proper model info array" comment
- line ~411: `rac_wakeword_reset` skips backend reset with a "TODO:
  Reset backend state" comment
- lines ~463 + ~473: `rac_wakeword_process` never runs ONNX or VAD
  inference — it just extracts frames and returns silence

Repo-wide `rac_wakeword_create|rac_wakeword_initialize|rac_wakeword_load_model|rac_wakeword_process|rac_wakeword_start|rac_wakeword_set_callback`
finds exactly one implementation (the stub itself) and zero consumers.

Real consumers all bypass this service and use the fully-implemented
ONNX backend directly:

- `Playground/openclaw-hybrid-assistant/src/pipeline/voice_pipeline.cpp`
  → `rac_wakeword_onnx_create`, `rac_wakeword_onnx_load_model`,
  `rac_wakeword_onnx_process`, …
- `Playground/linux-voice-assistant/src/pipeline/voice_pipeline.cpp` →
  same pattern
- `sdk/runanywhere-commons/tests/test_wakeword.cpp` → same pattern
- `Playground/openclaw-hybrid-assistant/tests/test_components.cpp` →
  same pattern

Decision:
1. Delete `sdk/runanywhere-commons/src/features/wakeword/wakeword_service.cpp`.
2. Delete `sdk/runanywhere-commons/include/rac/features/wakeword/rac_wakeword_service.h`.
3. Delete `sdk/runanywhere-commons/include/rac/features/wakeword/rac_wakeword.h`
   (umbrella header that only exists to pull in the service header).
4. Keep `sdk/runanywhere-commons/include/rac/features/wakeword/rac_wakeword_types.h` —
   it defines `rac_wakeword_config_t`, `rac_wakeword_event_t`,
   `rac_wakeword_callback_fn`, and the `RAC_ERROR_WAKEWORD_*` error code
   set. The real ONNX backend (`engines/onnx/wakeword_onnx.cpp`) and the
   voice-agent aggregator (`rac_voice_agent.h`) both use these types.
5. Retarget `rac_wakeword_onnx.h` to include `rac_wakeword_types.h`
   directly instead of the deleted umbrella header.
6. Remove the `src/features/wakeword/wakeword_service.cpp` entry from
   `sdk/runanywhere-commons/CMakeLists.txt`.

The feature can be re-added in a future sprint with a real service layer
once a consumer actually wants the high-level façade rather than the raw
ONNX backend. Today nobody wants that façade and the 7 TODO stubs only
mislead readers.

## What gets touched

| File                                                                                           | Change                                   |
| ---------------------------------------------------------------------------------------------- | ---------------------------------------- |
| `engines/sherpa/`                                                                              | directory removed                        |
| `engines/genie/`                                                                               | directory removed                        |
| `engines/diffusion-coreml/`                                                                    | directory removed                        |
| `engines/CMakeLists.txt`                                                                       | stub-engine foreach loop removed         |
| `CMakeLists.txt` (root)                                                                        | engines-header comment updated to reflect 5 migrated backends, no stubs |
| `docs/engine_plugin_authoring.md`                                                              | stub rows dropped from priority ladder   |
| `sdk/runanywhere-commons/src/features/wakeword/wakeword_service.cpp`                           | deleted                                  |
| `sdk/runanywhere-commons/include/rac/features/wakeword/rac_wakeword_service.h`                 | deleted                                  |
| `sdk/runanywhere-commons/include/rac/features/wakeword/rac_wakeword.h`                         | deleted                                  |
| `sdk/runanywhere-commons/include/rac/backends/rac_wakeword_onnx.h`                             | switch include to `rac_wakeword_types.h` |
| `sdk/runanywhere-commons/CMakeLists.txt`                                                       | drop `wakeword_service.cpp` source entry |

No implement-work is triggered by this phase.
