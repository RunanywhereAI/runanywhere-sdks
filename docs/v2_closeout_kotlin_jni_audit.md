# Kotlin/JNI TODO audit — Phase E / v2 close-out

Audit of every `// TODO: Call native (un)registration` marker in
`sdk/runanywhere-kotlin/src/jvmAndroidMain/.../foundation/bridge/extensions/CppBridge*.kt`.

## Method

For each marker we verified five things:

1. The companion `private external fun nativeSet/UnsetXxxCallbacks()` declaration in
   the same `CppBridge*` file.
2. Whether the matching `Java_..._nativeSet/UnsetXxxCallbacks` body exists in
   `runanywhere-commons/src/jni/runanywhere_commons_jni.cpp`.
3. Every caller of `bridge.register()` / `bridge.unregister()` / `bridge.shutdown()`
   across the Kotlin SDK, the Android sample, and tests (`rg -n` over the full
   mono-repo).
4. The matching C ABI entry point under
   `runanywhere-commons/include/rac/features/<feature>/` (is there a
   `rac_<feature>_set_callbacks(...)`?).
5. Decision: **KEEP+IMPLEMENT** (real callbacks reach commons from Kotlin) or
   **DELETE-AS-DEAD** (no caller benefits from wiring).

## Result summary

Key empirical findings:

- **No `Java_...nativeSet/UnsetXxxCallbacks` body exists in the JNI cpp file.**
  `rg -n 'nativeSet|nativeUnset'` over
  `runanywhere-commons/src/jni/` returns zero matches. Calling any of the
  `nativeSet/UnsetXxxCallbacks` `external fun` declarations at runtime would
  throw `UnsatisfiedLinkError`.
- **No callers exist for 9 of the 11 bridges.** `rg -n
  'CppBridge(VAD|TTS|STT|LLM|Storage|State|ModelPaths|Download|HTTP)\.register\('`
  returns zero matches. The same for `.unregister()` and `.shutdown()`. The two
  bridges that ARE called from `CppBridge.kt` (`initialize`/`shutdown`) are
  `CppBridgePlatformAdapter` and `CppBridgePlatform`.
- **The commons C ABI does not expose a top-level `rac_<feature>_set_callbacks`
  for LLM / STT / TTS / VAD components.** Streaming callbacks are passed per
  call via `rac_llm_component_generate_stream_with_timing(..., token_cb,
  complete_cb, error_cb, user_data)`, `rac_stt_component_..._stream(..., cb,
  user_data)`, `rac_tts_component_..._stream(..., cb, user_data)`, and
  `rac_vad_component_set_audio_callback(handle, cb, user_data)`. There is no
  global "set callbacks for this feature" sink to wire into.
- **No Kotlin code calls the four orphan JNI "set callback" entry points on
  `RunAnywhereBridge`** (`racLlmSetCallbacks`, `racSttSetCallbacks`,
  `racTtsSetCallbacks`, `racVadSetCallbacks`). They have empty JNI bodies and
  no C side to hook into.

### Per-file decision table

| File                             | Line(s)     | Symbol                                    | `external fun` exists? | JNI body exists?     | Callers of `register()` | Matching C ABI                                               | Decision       | Rationale                                                                                                                            |
| -------------------------------- | ----------- | ----------------------------------------- | ---------------------- | -------------------- | ----------------------- | ------------------------------------------------------------ | -------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `CppBridgeVAD.kt`                | 443, 1156   | `nativeSet/UnsetVADCallbacks`             | Yes (1122 / 1134)      | **No** (no symbol)   | **None**                | None (per-call via `rac_vad_component_set_audio_callback`)   | **DELETE**     | `register()` body is `isRegistered = true; log`. No callers. No C sink.                                                              |
| `CppBridgeTTS.kt`                | 482, 1206   | `nativeSet/UnsetTTSCallbacks`             | Yes (1172 / 1184)      | **No**               | **None**                | None (per-call via `rac_tts_component_synthesize_stream`)    | **DELETE**     | Same shape as VAD. `TTSRouter` uses `CppBridgeTTS.synthesize/...` directly but never `.register()`.                                  |
| `CppBridgeSTT.kt`                | 437, 1094   | `nativeSet/UnsetSTTCallbacks`             | Yes (1060 / 1072)      | **No**               | **None**                | None (per-call via `rac_stt_component_transcribe_stream`)    | **DELETE**     | Same shape.                                                                                                                          |
| `CppBridgeLLM.kt`                | 420, 1186   | `nativeSet/UnsetLLMCallbacks`             | Yes (1152 / 1164)      | **No**               | **None**                | None (per-call via `rac_llm_component_generate_stream_with_timing`) | **DELETE**     | Same shape.                                                                                                                          |
| `CppBridgeStorage.kt`            | 282, 765    | `nativeSet/UnsetStorageCallbacks`         | Yes (738 / 748)        | **No**               | **None**                | None (storage uses platform adapter, already wired)          | **DELETE**     | Storage callbacks are already dispatched via `CppBridgePlatformAdapter`.                                                             |
| `CppBridgeState.kt`              | 260, 597    | `nativeSet/UnsetStateCallbacks`           | Yes (568 / 580)        | **No**               | **None**                | None                                                         | **DELETE**     | State observer stub, never wired.                                                                                                    |
| `CppBridgePlatform.kt`           | 588, 1147   | `nativeSet/UnsetPlatformCallbacks`        | Yes (1108 / 1118)      | **No**               | `CppBridge.kt:456/536`  | `rac_platform_llm_set_callbacks` / `rac_platform_tts_set_callbacks` exist but Kotlin does not aggregate them | **KEEP METHOD, DELETE TODO+DECLS** | `register()` also does `initializeServiceAvailability()` which is real work; keep the function, strip the TODO comment and the unused `external fun`s. |
| `CppBridgeModelPaths.kt`         | 223, 620    | `nativeSet/UnsetModelPathsCallbacks`      | Yes (591 / 603)        | **No**               | **None**                | None                                                         | **DELETE**     | Model-path callbacks go through `CppBridgePlatformAdapter` file ops.                                                                 |
| `CppBridgeDownload.kt`           | 434, 1238   | `nativeSet/UnsetDownloadCallbacks`        | Yes (1205 / 1217)      | **No**               | **None**                | None (downloads use `CppBridgePlatformAdapter.httpDownload`) | **DELETE**     | Entire `register()` / `unregister()` / `shutdown()` chain is dead; executor is never spun up via the declared API.                   |
| `CppBridgeHTTP.kt`               | 219, 642    | `nativeSet/UnsetHttpCallback`             | Yes (591 / 603)        | **No**               | **None**                | None (telemetry HTTP is wired separately via `CppBridgeTelemetry`) | **DELETE**     | Independent `httpCallback` is bundled inside a bridge whose registration never runs.                                                 |
| `CppBridgePlatformAdapter.kt`    | 658 (unreg) | `nativeUnregisterPlatformAdapter`         | Yes (640)              | **No**               | `CppBridge.kt:544`      | Only `rac_set_platform_adapter(ptr)` / pass `nullptr` to unset; no dedicated unset ABI | **KEEP METHOD, DELETE TODO+DECL** | `register()` already wires `RunAnywhereBridge.racSetPlatformAdapter(this)`. `unregister()` clears in-memory state; there's no `rac_unset_platform_adapter`, so the `external fun` is unreachable. |

### RunAnywhereBridge-level JNI TODOs (feed into E-3)

`runanywhere-commons/src/jni/runanywhere_commons_jni.cpp`:

| Line | Symbol                                    | Kotlin caller                        | C ABI match                 | Decision                 |
| ---- | ----------------------------------------- | ------------------------------------ | --------------------------- | ------------------------ |
| 1314 | `Java_..._racLlmSetCallbacks`             | **None** (`external fun racLlmSetCallbacks` declared at `RunAnywhereBridge.kt:191`, unused) | **None** (per-call only) | **DELETE** JNI body + Kotlin decl |
| 1812 | `Java_..._racSttSetCallbacks`             | **None** (`RunAnywhereBridge.kt:256`) | **None**                    | **DELETE**               |
| 1921 | `Java_..._racTtsComponentSynthesizeToFile` | `CppBridgeTTS.kt:918`                | `rac_tts_component_synthesize` + manual `std::ofstream` | **KEEP + IMPLEMENT** |
| 1986 | `Java_..._racTtsSetCallbacks`             | **None** (`RunAnywhereBridge.kt:302`) | **None**                    | **DELETE**               |
| 2129 | `Java_..._racVadSetCallbacks`             | **None** (`RunAnywhereBridge.kt:351`) | **None**                    | **DELETE**               |

## Standing-rule compliance

All deletions satisfy Standing Rule #1 ("DELETE don't deprecate"):
for each bridge whose `register()` is a no-op and has no callers, every dead
symbol is removed (Kotlin method, `external fun` declaration, JNI body).
`CppBridgePlatform` and `CppBridgePlatformAdapter` keep their methods because
those methods do real, non-callback work; only the orphan TODO block and
matching dead `external fun`s are removed.
