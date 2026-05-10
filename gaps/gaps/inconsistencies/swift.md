# Swift / iOS SDK — Current Inconsistencies

Updated: 2026-05-09
Branch: `feat/v2-architecture` @ `b336248b3`

## Current modality state (physical iPhone 17 Pro Max)

| Modality | Status |
|---|---|
| LLM Chat | ✅ PASS |
| VLM (LFM2-VL 450M) | ✅ PASS |
| STT (Sherpa Whisper Tiny, single-shot) | ✅ PASS |
| TTS (Platform + Sherpa Piper) | ✅ PASS |
| Tool Calling | ✅ PASS |
| RAG ingest + query | ✅ PASS |
| Document storage + retrieval | ✅ PASS |
| Archive extraction → canonical path | ✅ PASS |
| Model persistence across relaunch | ✅ PASS |
| Settings / Hardware / Permissions | ✅ PASS |
| VAD | ❌ BROKEN — `SWIFT-VAD-001` |
| Voice Agent (end-to-end pipeline) | ❌ BROKEN — `SWIFT-VOICE-AGENT-001` |
| Solutions | 🟡 UNTESTED — `SWIFT-SOLUTIONS-UNTESTED` |

## Deferred backend Swift bindings (do not file bugs)

Intentionally present but out of scope. Exclude/stub OK:

- `Sources/WhisperKitRuntime/`, `Sources/MetalRTRuntime/`
- `Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+Diffusion.swift` + `Public/Extensions/Diffusion/` + `Features/Diffusion/`
- `CRACommons/include/rac_stt_whisperkit_coreml.h`
- `Package.swift`: `MetalRTBackend`, `MetalRTRuntime`, `RABackendMetalRTBinary`, `WhisperKitRuntime`, `RunAnywhereMetalRT`, `RunAnywhereWhisperKit`
- `examples/ios/RunAnywhereAI/.../Features/Diffusion/`

No Genie or WhisperCPP Swift bindings exist.

---

# Part 1 — Runtime correctness issues

## SWIFT-VAD-001: Voice Activity Detection is broken (HIGH)

- **Symptom**: VAD does not fire speech-start / speech-end events. Silero VAD registered but never commits.
- **Evidence**: `logs3.txt:2350` shows `Model states synced - VAD: false` immediately after `Initializing voice agent...`.
- **Root cause**: `CppBridge+VAD.swift` still manages lifecycle through direct handle-based calls (`rac_vad_component_initialize`, `rac_vad_component_start/stop/reset/load_model`). STT and TTS migrated to lifecycle-proto in Phase 6h; VAD did not.
- **Fix path (confirmed by Foundation audit)**: Commons already exposes the required handle-less surface in `sdk/runanywhere-commons/include/rac/features/vad/rac_vad_service.h:244-279`:
  - `rac_vad_process_lifecycle_proto`
  - `rac_vad_configure_lifecycle_proto`
  - `rac_vad_start_lifecycle_proto`
  - `rac_vad_stop_lifecycle_proto`
  - `rac_vad_reset_lifecycle_proto`
  Add a `VADLifecycleProtoABI` private enum in `CppBridge+ModalityProtoABI.swift` parallel to `STTGeneratedProtoABI`/`TTSGeneratedProtoABI`, load the five symbols via `dlsym`, and have `CppBridge+VAD.swift` delegate `initialize/start/stop/reset` through it. Add a `loadModel(from: RAModelLoadResult)` adapter mirroring the STT/TTS pattern.
- **Scope**: M.

## SWIFT-VOICE-AGENT-001: End-to-end Voice Agent pipeline is broken (HIGH)

- **Symptom**: Voice Agent initializes but no full VAD → STT → LLM → TTS round-trip. Only LLM commits.
- **Evidence**: `logs3.txt:2349-2385` — init immediately followed by `VAD:false, STT:false, LLM:true, TTS:false`, then cleanup without voice events.
- **Root cause (likely)**: Voice Assistant Setup screen's commit closures for VAD/STT/TTS don't call `modelManager.setVoiceVAD / setVoiceSTT / setVoiceTTS` — a separate path from the standalone STT/TTS screens that were fixed in Phase 6h. `handleComponentLifecycleEvent` may not fire for Voice-Setup loads.
- **Fix hypothesis**:
  1. Audit `VoiceAgentViewModel.setVADModel / setSTTModel / setTTSModel` — confirm they call `RunAnywhere.loadModel(...)` with the correct `RAModelCategory`.
  2. Audit `VoiceAssistantView.swift` picker "Use" closures — confirm they `await viewModel.setXXXModel(model)`.
  3. Confirm commons emits `componentLifecycle.loaded` events for VAD component on load.
  4. Verify `CppBridge.VoiceAgent.shared.getHandle()` gathers all 4 component handles.
- **Blocked by**: `SWIFT-VAD-001` (VAD must commit before the voice agent can assemble 4 handles).
- **Scope**: M–L.

## SWIFT-SOLUTIONS-UNTESTED: Solutions feature has not been tested (UNKNOWN)

- **Status**: The Solutions YAML runner path (`RunAnywhere.solutions.run(yaml:)`, tab `Solutions` in the iOS example) has not been exercised on physical device.
- **Action**: Include a Solutions smoke test in the next validation pass after VAD + Voice Agent are unblocked.
- **No failure observed yet** — known-untested, not known-broken.

## SWIFT-VLM-STREAM-REVERT: Revert VLM `processImageStream` workaround (LOW)

- **Current state**: `Public/Extensions/VLM/RunAnywhere+VisionLanguage.swift:42-83` routes `processImageStream` through non-streaming `process()` and synthesizes a single TOKEN_GENERATED + COMPLETED pair.
- **Why it's obsolete**: Phase 6j (`26ce54160`) fixed the handle-type-mismatch root cause. Real streaming should work now. The C++ `rac_vlm_process_stream_proto` (`include/rac/features/vlm/rac_vlm_service.h:230`) is never exercised by this workaround.
- **Fix**: Revert the workaround; verify per-token streaming works on device.
- **Scope**: S.

---

# Part 2 — Swift/C++ duplication gaps (2026-05-09 audit)

Cross-module audit across 8 Swift module subtrees found systematic duplication of logic that belongs in the C++ commons layer, plus generated-proto types being hand-re-wrapped. Each gap below is independently actionable. Deletion plan is conservative — every item has been traced to confirm zero live callers.

## SWIFT-DUP-CANHANDLE: `canHandle*` methods are dead code across runtime modules (MEDIUM)

Three places re-implement C++ plugin-router format matching in Swift. The C++ `rac_plugin_route()` in `sdk/runanywhere-commons/src/router/` is the only routing authority; these Swift methods are never called by the dispatch path.

- `Sources/LlamaCPPRuntime/LlamaCPP.swift:155-159` — `canHandle(modelId:)` matches `.gguf`. Misses `.ggml`/`.bin` that C++ accepts.
- `Sources/ONNXRuntime/ONNX.swift:169-190` — `canHandleSTT/TTS/VAD` substring matches `whisper`, `zipformer`, `paraformer`, `piper`, `vits`. Duplicates routing hints in C++ vtable.
- `Sources/RunAnywhere/Features/LLM/System/SystemFoundationModelsModule.swift:89-104` and `Features/TTS/System/SystemTTSModule.swift:49-60` — `canHandle(modelId:/voiceId:)` duplicates the `can_handle` closures already registered in `CppBridge+Platform.swift:122-143` and `:243-255`.

**Fix**: Delete all 5 `canHandle*` implementations.
**Scope**: XS.

## SWIFT-DUP-MODULE-METADATA: `RunAnywhereModule` protocol metadata is never read polymorphically (MEDIUM)

The `RunAnywhereModule` protocol in `Core/Module/RunAnywhereModule.swift` requires `moduleId`, `moduleName`, `capabilities`, `defaultPriority`, `inferenceFramework`. A grep of the Swift SDK confirms these properties are never iterated over the protocol existentially — the protocol is never used as a type constraint. All consumers read the same values from the C-returned `rac_module_info_t` inside `CppBridge+Services.swift:82-143`.

The metadata is already canonical in C++: `rac_plugin_entry_llamacpp.cpp`, `rac_plugin_entry_sherpa.cpp`, `rac_plugin_entry_platform.cpp` all populate `rac_engine_vtable_t.metadata`. Having a second declaration on the Swift enum side creates drift risk.

- `Sources/RunAnywhere/Core/Module/RunAnywhereModule.swift:40-55` — delete the entire file.
- `Sources/LlamaCPPRuntime/LlamaCPP.swift:66-73` — remove conformance + metadata properties. Keep only `register()`, `registerVLM()`, `unregister()`.
- `Sources/ONNXRuntime/ONNX.swift:55-62` — same.
- `Sources/RunAnywhere/Features/LLM/System/SystemFoundationModelsModule.swift:58-64` — same.
- `Sources/RunAnywhere/Features/TTS/System/SystemTTSModule.swift:40-45` — same.

**Scope**: S.

## SWIFT-DUP-RUNTIME-HEADERS: LlamaCPPRuntime and ONNXRuntime duplicate CRACommons headers (HIGH + latent bug)

Both runtime modules ship local `include/` directories that copy types already exposed through CRACommons. One copy has already drifted.

**LlamaCPPRuntime (`Sources/LlamaCPPRuntime/include/`)** — 4 duplicates of CRACommons headers:
- `rac_error.h`, `rac_types.h`, `rac_llm.h`, `rac_llm_types.h` — byte-for-byte identical to `Sources/RunAnywhere/CRACommons/include/rac_*.h` equivalents.

**ONNXRuntime (`Sources/ONNXRuntime/include/`)** — 12 duplicates:
- `rac_error.h`, `rac_types.h`
- `rac_stt.h`, `rac_tts.h`, `rac_vad.h`
- `rac_stt_types.h`, `rac_tts_types.h`, `rac_vad_types.h`
- `rac_stt_onnx.h`, `rac_tts_onnx.h`, `rac_vad_onnx.h`
- (functions in all three `rac_*_onnx.h` are never called from Swift)

**LATENT BUG — enum divergence**: `Sources/ONNXRuntime/include/rac_stt_types.h:44` defines `RAC_AUDIO_FORMAT_FLAC = 4`. Canonical `sdk/runanywhere-commons/include/rac/features/stt/rac_stt_types.h:76` defines `RAC_AUDIO_FORMAT_AAC = 4, RAC_AUDIO_FORMAT_FLAC = 5`. Any Swift code importing `ONNXBackend` and passing these constants to C++ will silently send the wrong audio-format integer.

**Fix**:
1. Delete all 16 duplicate headers above.
2. Add `#include "rac_llm_llamacpp.h"` to `Sources/RunAnywhere/CRACommons/include/CRACommons.h` (mirrors the existing `rac_vlm_llamacpp.h` include at line 84) so `rac_backend_llamacpp_register` becomes reachable from CRACommons. Then delete the `LlamaCPPBackend` Clang module entirely (module.modulemap, umbrella, shim.c).
3. Similarly collapse ONNXBackend — only `rac_plugin_entry_sherpa.h` (forward-decl of the plugin entry) and the ONNXRuntime Swift source need stay.
4. Migrate the `module.modulemap` `link framework "Metal"` / `"MetalKit"` / `"MetalPerformanceShaders"` directives into `Package.swift` linker settings on the `RunAnywhere` target.

**Scope**: M. Blocks cleanup of runtime modules entirely.

## SWIFT-DUP-CRACOMMONS-PHANTOM: 5 CRACommons headers declare non-existent C++ symbols (HIGH)

The following headers under `Sources/RunAnywhere/CRACommons/include/` declare `RAC_API` functions that have NO implementation in `sdk/runanywhere-commons/` and NO entry in `sdk/runanywhere-commons/exports/RACommons.exports`:

- `rac_llm_events.h` — `rac_llm_event_*` publishing functions
- `rac_stt_events.h` — `rac_stt_event_*` publishing functions
- `rac_tts_events.h` — `rac_tts_event_*` publishing functions
- `rac_vad_events.h` — `rac_vad_event_*` publishing functions
- `rac_rag_pipeline.h` — the entire `rac_rag_pipeline_create/add_document/query` family; superseded by `rac_rag_session_create_proto` etc. in `rac_modality_proto_abi.h`.

They currently link under the static xcframework (static archives ignore exports lists) but will break any dynamic-library build.

**Fix**: Delete all 5 headers + their `#include` lines in `CRACommons.h`.
**Scope**: XS.

## SWIFT-DUP-CRACOMMONS-THINKING-DRIFT: `rac_llm_thinking.h` regressed the SWF-THINKING-MIGRATE cleanup (MEDIUM)

`Sources/RunAnywhere/CRACommons/include/rac_llm_thinking.h:52-88` still declares three functions with `RAC_API`:
- `rac_llm_extract_thinking`
- `rac_llm_strip_thinking`
- `rac_llm_split_thinking_tokens`

Canonical commons `sdk/runanywhere-commons/include/rac/features/llm/rac_llm_thinking.h:64-108` has stripped `RAC_API`, marked all three `@internal`, and none appear in `RACommons.exports`. The Swift extension `CppBridge+LLMThinking.swift` calls these — meaning Swift code is now calling symbols the commons public ABI does not export.

**Fix**: Either (a) restore `RAC_API` + exports entries in commons if Swift actually needs these (audit `CppBridge+LLMThinking.swift` call sites), or (b) delete the Swift wrappers and migrate thinking extraction to the proto-field-based API on `RALLMGenerationResult`.
**Scope**: S.

## SWIFT-DUP-CRACOMMONS-STRUCTURED-OUTPUT-MISSING: `rac_llm_structured_output.h` missing 5 proto-byte overloads (MEDIUM)

`Sources/RunAnywhere/CRACommons/include/rac_llm_structured_output.h` contains only legacy struct-based APIs. The canonical commons header adds:
- `rac_structured_output_parse_proto`
- `rac_structured_output_generate_proto`
- `rac_structured_output_generate_stream_proto`
- `rac_structured_output_prepare_prompt_proto`
- `rac_structured_output_validate_proto`
- type `rac_structured_output_parse_result_t`

All five `_proto` variants ARE in `RACommons.exports`. Swift cannot see them because the CRACommons mirror is stale.

**Fix**: Update the CRACommons header to match the canonical commons copy.
**Scope**: XS.

## SWIFT-DUP-RACTYPES-CPPBRIDGE-DEAD: Post-Phase-6h the C-struct bridge code is orphaned (HIGH)

Phase 6h migrated STT/TTS/VLM/LLM to the proto-byte ABI (`rac_*_lifecycle_proto` / `rac_*_component_*_proto`). The C-struct marshaling layer in `Sources/RunAnywhere/Foundation/Bridge/Extensions/` is now unreachable:

- `RALLMTypes+CppBridge.swift:57-73` — `RALLMGenerationOptions.withCOptions<T>` builds `rac_llm_options_t`; no caller.
- `RALLMTypes+CppBridge.swift:116-129` — `RALLMGenerationResult.init(from cResult: rac_llm_result_t, ...)`; no caller.
- `RALLMTypes+CppBridge.swift:130-145` — `RALLMGenerationResult.init(from cStreamResult: rac_llm_stream_result_t, ...)`; no caller.
- `RASTTTypes+CppBridge.swift:78-92` — `RASTTOptions.withCOptions<T>`; no caller.
- `RASTTTypes+CppBridge.swift:101-147` — `RASTTOutput.init(from cOutput: rac_stt_output_t)`; no caller.
- `RATTSTypes+CppBridge.swift:56-77` — `RATTSOptions.withCOptions<T>`; no caller.
- `RATTSTypes+CppBridge.swift:86-120` — `RATTSOutput.init(from cOutput: rac_tts_output_t)`; no caller.
- `RAVADTypes+CppBridge.swift:20-29` — `RAVADStatistics.init(from cStats: rac_energy_vad_stats_t)`; no caller (stats now come via `statisticsProto()`).

**Fix**: Delete the 8 listed initializers + methods. Keep the remaining convenience extensions (`.defaults()`, `.validate()`, computed aliases) in the same files — those have public-API callers.
**Scope**: S.

## SWIFT-DUP-LIFECYCLE-STATE: `SystemFoundationModelsService` re-implements LifecycleManager (MEDIUM)

`Sources/RunAnywhere/Features/LLM/System/SystemFoundationModelsService.swift`:
- Lines 22-23, 36-37, 55-82, 128, 172, 180 — `_isReady` / `_currentModel` guards mirror the `IDLE → LOADING → LOADED` state machine in `sdk/runanywhere-commons/src/core/capabilities/lifecycle_manager.cpp`.
- Line 41 — `contextLength: Int? { 4096 }` hard-codes a value already set in `rac_backend_platform_register.cpp:119` via `out_info->context_length = 4096`.

**Fix**: Remove `_isReady`/`_currentModel` state; rely on C++ lifecycle via `rac_model_lifecycle_current_model_proto`. Delete `contextLength` override.
**Scope**: S.

## SWIFT-DUP-FACTORY-BYPASS: `createService()` module factories bypass the C++ plugin system (MEDIUM)

- `SystemFoundationModelsModule.swift:106-114` — `createService()` public factory.
- `SystemTTSModule.swift:64-68` — `createService()` public factory.

Both return a service instance directly, skipping `rac_plugin_route` and the whole component lifecycle. This is a second back door around the architecture. The comment at `SystemFoundationModelsModule.swift:106` explicitly advertises the bypass: "Use this for direct access without going through the service registry."

**Fix**: Delete both factory methods. All access must go through `CppBridge.LLM`/`CppBridge.TTS` which route via the plugin registry.
**Scope**: XS.

## SWIFT-DUP-COMPONENT-PROTOCOLS: `ComponentProtocols.swift` is over-specified (LOW)

`Sources/RunAnywhere/Foundation/Core/ComponentProtocols.swift`:
- Line 17 — `ComponentConfiguration.validate()` is a protocol requirement with zero call sites and zero real implementations.
- Lines 14-18 — `modelId` and `preferredFramework` are fine (consumed by concrete request types).
- Lines 51-66 — `RASDKComponent.analyticsKey` hand-codes strings (`"llm"`, `"stt"`, ...) that C++ `rac_analytics_events.h` already owns for event categorization. If these diverge, analytics buckets will mismatch across logs.

**Fix**: Delete `validate()` requirement and `analyticsKey` extension. Keep `displayName` (UI-facing, no C++ equivalent).
**Scope**: XS.

## SWIFT-DUP-ERROR-CABI: Proto factory reconstructs `cAbiCode` (LOW)

`Sources/RunAnywhere/Foundation/Errors/RASDKError+Helpers.swift:34-36`:
```swift
let raw = code.rawValue
if raw > 0 && raw <= 899 { p.cAbiCode = -Int32(raw) }
```
This re-derives the proto-enum → C-integer mapping that `CommonsErrorMapping` already performs canonically. Two places deriving the same relationship will drift.

`CommonsErrorMapping.swift:48-91` — `categoryFor(_:)` 44-case switch from `RAErrorCode` to `RAErrorCategory`. C++ already has `rac_error_category_t` and `rac_error_category_name()`; the mapping should be queried from C rather than hand-maintained in Swift.

**Fix**: Delete the `cAbiCode` lines from `RASDKError.make()`. Replace `CommonsErrorMapping.categoryFor` with a call to `rac_error_get_category_proto` (or add that symbol if missing) so there's one authority.
**Scope**: S.

## SWIFT-DUP-MODELTYPES-COMPUTED: `RAModelCategory` Swift computed properties duplicate C functions (LOW)

`Sources/RunAnywhere/Public/Extensions/Models/ModelTypes.swift:176-195` — comments on `RAModelCategory.requiresContextLength` and `.supportsThinking` explicitly say "Matches `rac_model_category_requires_context_length()` on the C side." The C functions are the source of truth; the Swift duplicates will drift.

`ModelTypes.swift:308-345` — `RAInferenceFramework.toCFramework()` / `fromCFramework(_:)` are large hand-maintained switches. Same drift risk.

**Fix**: Call the C functions directly. For `toCFramework`/`fromCFramework`, add a proto → rac_inference_framework_t helper in commons (e.g. `rac_inference_framework_from_proto(int32_t)`) and delete the Swift switches.
**Scope**: S.

## SWIFT-DUP-STORAGE-ALIASES: Storage field aliases shadow canonical proto names (LOW)

`Sources/RunAnywhere/Public/Extensions/Storage/StorageProto+Helpers.swift`:
- Lines 24-33 — `RADeviceStorageInfo.totalSpace/freeSpace/usedSpace/usedPercent` alias the canonical proto fields `totalBytes/freeBytes/usedBytes`.
- Lines 56-74 — `RAAppStorageInfo.documentsSize/cacheSize/appSupportSize/totalSize` alias existing proto fields.

These aliases create two names for each field, divorcing Swift callers from the wire representation. App developers get a Swift-flavored API; wire format stays proto-native.

**Fix**: Delete the aliases. Callers should use the proto field names directly. Keep the `usedPercent` computation as a utility (it's a derived value, not an alias).
**Scope**: XS.

## SWIFT-DUP-DEAD-LIFECYCLE-HELPERS: Dead component-sync helpers (LOW)

`Sources/RunAnywhere/Public/Extensions/Models/RunAnywhere+ModelLifecycle.swift:96-134` — `synchronizeSTTComponentLoad` and `synchronizeTTSComponentLoad` private functions are never called. The file's own comment at lines 38-43 explicitly says STT+TTS sync was removed in Phase 6h; the helpers weren't cleaned up.

**Fix**: Delete both functions.
**Scope**: XS.

## SWIFT-DUP-HTTP-ADAPTER-MISLOCATED: `HTTPClientAdapter` has business logic and is in the wrong directory (MEDIUM)

`Sources/RunAnywhere/Adapters/HTTPClientAdapter.swift` is named like an IoC platform adapter but holds feature-layer logic:
- Lines 85-98 — Supabase UPSERT semantics (`on_conflict=device_id` query param, `Prefer: resolution=merge-duplicates` header) hard-coded into the transport.
- Lines 191-209 — auth retry loop (`resolveToken` → `CppBridge.Auth.refreshToken()` → retry).
- Lines 438-469 — `parseHTTPError` status-code→`SDKException` classification.
- Lines 211-230 — non-trivial URL construction.

The `Adapters/` directory should hold IoC shims that populate the `rac_platform_adapter_t` vtable. The three files in there today are actually:
- `LLMStreamAdapter.swift` / `VoiceAgentStreamAdapter.swift` — correct fan-out multiplexers (keep).
- `HTTPClientAdapter.swift` — mislocated feature-layer HTTP service.

**Fix**:
1. Move `HTTPClientAdapter.swift` to `Foundation/Bridge/` or `Data/Network/`.
2. Extract Supabase UPSERT injection into the device-registration call site (`CppBridge+Device.swift`).
3. Extract the auth retry loop into `CppBridge.Auth`.
4. Move `parseHTTPError` into `Foundation/Errors/CommonsErrorMapping.swift`.
5. Move `parseLogMetadata` (`CppBridge+PlatformAdapter.swift:123-163`) and `createSDKErrorFromCppError` (`:456-483`) into `CommonsErrorMapping.swift`.
6. Review `Data/Network/Protocols/NetworkService.swift` — it's a second Swift protocol layer over the C `rac_http_transport_ops_t`. If nothing uses it, delete.

**Scope**: M.

## SWIFT-DUP-UNUSED-PROTO-TYPES: Generated proto types with zero Swift callers (LOW)

Spot-grep of Generated/ finds proto types with no consumer in the Swift SDK. These don't cost much (just compilation), but they indicate either unfinished features or types that should move to a separate module:

- `router.pb.swift` — `RARouterStrategy`, `RARouterConfig`, `RARouterState`. Zero callers.
- `pipeline.pb.swift` — `RADeviceAffinity`, `RAPipelineNodeSpec`, `RAPipelineSpec`, `RAPipelineConfig`. Only consumed internally by `solutions.pb.swift`.
- `solutions.pb.swift` — consumed only by `RunAnywhere+Solutions.swift`, which is itself stub-level and doesn't call through to CppBridge.
- `diffusion_options.pb.swift` — consumed by nothing (the Diffusion deferred-backend CppBridge extension was removed).

**Fix**: Exclude these from the Swift SPM target's `sources` until consumers land. They're generated from `idl/` unconditionally but the Swift target doesn't have to compile them.
**Scope**: XS (Package.swift exclude list).

## SWIFT-DUP-TTS-LISTVOICES-HANDLE: `listVoices` still requires the actor handle (LOW)

`CppBridge+ModalityProtoABI.swift:531-553` — `CppBridge.TTS.listVoices()` passes a `rac_handle_t` from `getHandle()` to `rac_tts_component_list_voices_proto`. All other post-Phase-6h TTS ops use the handle-less lifecycle-proto path. This is the one inconsistent call on the TTS actor.

**Fix (requires C++ change)**: Add `rac_tts_list_voices_lifecycle_proto` in commons; switch Swift to the lifecycle variant. Low priority — it works as-is.
**Scope**: S.

## SWIFT-DUP-ISLOADED-INCONSISTENCY: STT/TTS/VLM use divergent "is-loaded" checks (LOW)

- `RunAnywhere+STT.swift:30-34` — queries `RunAnywhere.currentModel(...)` via `RACurrentModelRequest`.
- `RunAnywhere+TTS.swift:34-37` — same pattern.
- `RunAnywhere+TTS.swift:53` — but `synthesizeStream` guards on `CppBridge.TTS.shared.isLoaded` (actor-handle-based check), not `currentModel`.
- VLM mixes both patterns similarly.

The mismatch is because bridge actors hold their own handles while the lifecycle service holds its own. Either source can disagree. The comments in the files explicitly flag this as a known architectural gap.

**Fix (architectural, low priority)**: Consolidate on the lifecycle service as the single source of truth; remove the actor-side `isLoaded` flag entirely.
**Scope**: M.

---

## Summary of recommended deletions (v1 cleanup)

| Severity | Gap ID | Files/lines | Net LOC removed |
|---|---|---|---|
| HIGH | SWIFT-DUP-RUNTIME-HEADERS | 16 duplicate C headers + 2 entire runtime Clang modules | ~2,500 (after fold) |
| HIGH | SWIFT-DUP-RACTYPES-CPPBRIDGE-DEAD | 8 initializers/methods | ~220 |
| HIGH | SWIFT-DUP-CRACOMMONS-PHANTOM | 5 phantom headers | ~600 |
| MEDIUM | SWIFT-DUP-HTTP-ADAPTER-MISLOCATED | 1 file moved + 4 functions extracted | ~150 relocated, not deleted |
| MEDIUM | SWIFT-DUP-MODULE-METADATA | 1 file + 4 conformance blocks | ~120 |
| MEDIUM | SWIFT-DUP-LIFECYCLE-STATE | state vars + guards + contextLength | ~40 |
| MEDIUM | SWIFT-DUP-CANHANDLE | 5 methods | ~40 |
| MEDIUM | SWIFT-DUP-FACTORY-BYPASS | 2 factories | ~20 |
| LOW | SWIFT-DUP-MODELTYPES-COMPUTED | 2 computed props + 2 switches | ~60 |
| LOW | SWIFT-DUP-STORAGE-ALIASES | 2 alias blocks | ~30 |
| LOW | SWIFT-DUP-DEAD-LIFECYCLE-HELPERS | 2 private functions | ~40 |
| LOW | SWIFT-DUP-COMPONENT-PROTOCOLS | 1 protocol req + 1 extension | ~25 |
| LOW | SWIFT-DUP-ERROR-CABI | 3 lines + switch helper | ~50 |
| LOW | SWIFT-DUP-UNUSED-PROTO-TYPES | 4 .pb.swift files excluded | 0 (exclude, not delete) |

Approximate gross deletion: **~3,900 LOC** (dominated by header duplication).

## Rules followed in the audit

Per repo convention: **DELETE, don't deprecate**. No compat shims, no `@available` gates, no `#if false`. Per `CLAUDE.md`: business logic lives in C++; proto types from `idl/*.proto` are canonical; Swift should be a thin bridge. Every "must stay" justification in the raw audit reports traces to a legitimate Apple-platform-only concern (microphone capture, Keychain, AVAudioSession, UIImage → RGB) or a Swift-native idiom with no C equivalent (AsyncStream, actor isolation, `DispatchGroup`-bridged Foundation Models call).
