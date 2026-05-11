# Swift / iOS SDK — Current Inconsistencies

Updated: 2026-05-10
Branch: `feat/v2-architecture`

## E2E Validation Findings (run 20260510-160835)

### Test summary

- **Date**: 2026-05-10
- **Simulator**: iPhone 17 Pro, iOS 26.1, UDID `67528025-0DD2-4B5B-AB6D-585C5FB2EB8E`
- **App**: `com.runanywhere.RunAnywhere` @ commit `992e9f0c7` (post-Phase 5)
- **Test workflow**: `test_workflows/instructions/swift/README.md`
- **Run folder**: `test_workflows/logs/20260510-160835-swift-e2e/02_ios_swift/`

### Modality results

| Modality | Status | Notes |
| --- | --- | --- |
| LLM chat (Qwen 2.5 0.5B) | PASS | streamed 103 tok/s |
| LLM chat (Qwen3 0.6B) | FAIL | SWIFT-IOS-005: main-thread hang |
| VLM (LFM2-VL) | PASS | photo library fixture |
| TTS (platform / AVSpeech) | PASS | iOS system synthesizer |
| Embeddings (MiniLM L6 v2) | PASS | loaded |
| VAD (Silero, ONNX) | FAIL | SWIFT-IOS-001 route fix landed in `507fd3bfd` — route error gone; new loader-level failure tracked as SWIFT-IOS-012 |
| STT (Sherpa Whisper Tiny) | BLOCKED | model downloaded + loaded; no mic input on sim; no file fallback in UI |
| Voice agent | BLOCKED (DEGRADED) | components ready, VAD falls back to energy; mic-blocked anyway |
| RAG (Document Q&A) | BLOCKED | requires PDF/JSON file; no bundled fixture |
| Tool calling | PASS (newly unblocked) | "Add Demo Tools" in Settings → registers via `RunAnywhere.registerTool(...)` |
| Hardware / Settings / Storage / Lifecycle / Telemetry | PASS | deep coverage |
| Structured output, Diffusion, LoRA | N/A | not exposed in iOS example |

### Failure inventory

#### SWIFT-IOS-001 (HIGH) — VAD route mismatch (cross-platform C++ root cause) — **CLOSED** in `507fd3bfd`

- **Symptom**: `RunAnywhere.loadModel(silero-vad)` returns `success=false` with `errorMessage = "no backend route supports requested model for framework onnx"`. Voice agent falls back to energy VAD; speech-start / speech-end events never fire.
- **Root cause**: `framework_to_plugin_name()` returns `"onnx"` for ONNX VAD, but the only engine that actually owns `vad_ops` is named `"sherpa"`. The lifecycle path pins the route by name with `no_fallback=true`, so the router hard-rejects the Sherpa engine on pin-name mismatch.
- **Fix**: ~6-line change in `sdk/runanywhere-commons/src/core/model_lifecycle.cpp:287-312` to special-case speech primitives (`DETECT_VOICE`, `TRANSCRIBE`, `SYNTHESIZE`) when framework is `INFERENCE_FRAMEWORK_ONNX` to return `"sherpa"`. Mirrors the existing `LLAMA_CPP + VLM → "llamacpp_vlm"` special-case in the same function.
- **Cross-platform**: Swift + Kotlin + Flutter + RN all affected (shared C++ lifecycle path).
- **Full RCA**: `gaps/gaps/inconsistencies/SWIFT-IOS-001-vad-route.md`.
- **Status**: **CLOSED** in `507fd3bfd`. Wave 1 verification on iPhone 17 Pro simulator confirms the specific `"no backend route supports requested model for framework onnx"` error is gone. A different downstream failure (`"Failed to load the model"`) now surfaces at the Sherpa plugin's `vad_ops.load_model` — tracked as **SWIFT-IOS-012**.

#### SWIFT-IOS-005 (HIGH) — Qwen3 0.6B Q4_K_M LLM inference hangs main thread on simulator

- **Symptom**: Model load banner ("'Qwen3 0.6B Q4_K_M' is loaded") appears, but submitting a prompt produces no tokens after 4+ minutes. Mobile MCP WDA becomes unresponsive (`context deadline exceeded`).
- **Diagnostic**: `xcrun simctl spawn booted log show --predicate 'process == "RunAnywhereAI"'` shows repeated `XCTAS Error … Code=6 "Unable to perform work on main run loop, process main thread busy for 30.0s"` cycles every 30s.
- **Recovery**: requires app force-quit (`xcrun simctl terminate` + relaunch).
- **Asymmetry**: Other LLMs (Qwen 2.5 0.5B Q6_K) work fine at 103 tok/s — regression unique to Qwen3 family.
- **Hypothesis**: Likely backend/format issue (Qwen3 Q4_K_M generation extremely slow OR inference loop synchronous on main thread).
- **Next**: Reproduce on physical device (not simulator) and gate the model with a streaming-progress indicator + cancel/timeout affordance.
- **Evidence**: `screenshots/103_llm_switched_qwen3.png` (model loaded), `screenshots/108_after_long_wait.png` (no response after 4 min).

#### SWIFT-IOS-006 (MEDIUM) — Storage view shows phantom Zero-KB models + `MODEL_FORMAT_UNKNOWN` tags — **CLOSED** in `1b3b74791`

- **Symptom**: Storage tab lists 9 Downloaded Models totalling 1.88 GB, but only 6 actually consume disk. The other 3 (`coreml-diffusion`, `foundation-models-default`, `system-tts`) report "Zero KB". All 9 also display `MODEL_FORMAT_UNKNOWN` tag.
- **Root cause**: Registry-only entries (registered modules with no on-disk weights) leak into the disk view; the storage UI is not reading the model's proto-defined format from registry.
- **Fix**: distinguish "registered but not downloaded" from "downloaded" in the Storage view; consult the format enum via proto-generated type rather than printing `MODEL_FORMAT_UNKNOWN`.
- **Evidence**: `screenshots/120_storage_view.png`, `screenshots/121_storage_scroll1.png`, `screenshots/124_after_delete.png`.
- **Status**: **CLOSED** in `1b3b74791`. Storage view filters size > 0 entries; `MODEL_FORMAT_UNKNOWN` badge suppressed.

#### SWIFT-IOS-007 (MEDIUM / UX) — Tap target overlap: "Add Demo Tools" overlaps Voice tab nav bar — **CLOSED** in `1b3b74791`

- **Symptom**: Settings → Tool Calling → "Add Demo Tools" button at y=788–840 overlaps the bottom tab bar at y=795–849. Centre-of-button taps register the Voice tab instead of the action.
- **Reproduction**: 3× — Settings → scroll to Tool Calling → tap centre of "Add Demo Tools" → land on Voice Assistant Setup screen instead of seeing Registered Tools count change.
- **Fix**: add safe-area-insets bottom padding so the button is fully above the tab bar.
- **Evidence**: `screenshots/142_tool_section_view.png` (button position), `screenshots/145_voice_setup_no_file_input.png` (accidental nav).
- **Status**: **CLOSED** in `1b3b74791`. Button no longer overlaps the tab bar.

#### SWIFT-IOS-008 (MEDIUM) — `CRACommons.h` umbrella header missing `rac_runtime_registry.h` include — **CLOSED** in `507fd3bfd`

- **Symptom**: `Sources/RunAnywhere/CRACommons/include/CRACommons.h` does not include `rac_runtime_registry.h`. Works today via textual headers but breaks strict explicit-module mode (Swift 6 / `-strict-concurrency=complete` future tightening).
- **Fix**: 1-line addition to the umbrella header.
- **Scope**: XS.
- **Status**: **CLOSED** in `507fd3bfd`. Umbrella now includes `rac_runtime_registry.h` + `rac_runtime_vtable.h`.

#### SWIFT-IOS-009 (LOW) — SwiftPM `unhandled files` warnings — **CLOSED** in `0eeccda3e`

- **Symptom**: SwiftPM emits "unhandled files" warnings during build:
  - `Sources/LlamaCPPRuntime/README.md` and `Sources/ONNXRuntime/README.md` not classified as resources.
  - Vendored DeviceKit `.gyb` / `Info.plist` files in dependency path.
- **Fix**: Add `exclude:` entries in `Package.swift` for the affected targets. Cosmetic — no functional impact.
- **Scope**: XS.
- **Status**: **CLOSED** in `0eeccda3e`. Warnings 2 → 0 in our targets; DeviceKit warning remains in external dep (cannot be silenced).

#### SWIFT-IOS-010 (LOW) — Example app Swift 6 warnings (5 sites) — **CLOSED** in `0eeccda3e` (5 of 6)

- `examples/ios/RunAnywhereAI/.../VLMViewModel.swift:39` — `nonisolated(unsafe)` has no effect.
- `examples/ios/RunAnywhereAI/.../STTViewModel.swift:312` — `await` with no async operation.
- `examples/ios/RunAnywhereAI/.../STTViewModel.swift:314` — `await` with no async operation.
- `examples/ios/RunAnywhereAI/.../FlowSessionManager.swift:408` — `await` with no async operation.
- `examples/ios/RunAnywhereAI/.../FlowSessionManager.swift:416` — `await` with no async operation.
- `examples/ios/RunAnywhereAI/.../ConversationStore.swift:378` — unused result.
- **Fix**: Drop redundant `await` / `nonisolated(unsafe)` annotations; use `_ =` for intentionally unused results.
- **Status**: **CLOSED** in `0eeccda3e` — 5 of 6 sites fixed (redundant `await` x4, unused result x1). `VLMViewModel.swift:39 nonisolated(unsafe)` KEPT — load-bearing for `@Observable` + nonisolated deinit.

#### SWIFT-IOS-011 (LOW) — `CSendability.swift` retroactive `@unchecked Sendable` conformances are now redundant — **CLOSED** in `507fd3bfd`

- **File**: `Sources/RunAnywhere/Foundation/Concurrency/CSendability.swift:37-39`.
- **Symptom**: Swift 6 ships built-in unavailable `Sendable` conformances for the affected C-bridged opaque pointer types. Our retroactive `extension ... : @unchecked Sendable {}` declarations trigger "retroactive conformance" warnings.
- **Fix**: Delete the retroactive conformances; rely on the standard-library / Swift 6 defaults.
- **Status**: **CLOSED** in `507fd3bfd`. Retroactive `@unchecked Sendable` declarations on `OpaquePointer`, `UnsafeMutableRawPointer`, `UnsafeRawPointer` deleted.

#### SWIFT-IOS-012 (HIGH) — Silero VAD loader-level failure after the SWIFT-IOS-001 route fix (NEW)

- **Symptom**: After Wave 1's SWIFT-IOS-001 route fix, the auto-load now reaches the Sherpa plugin but Silero VAD `vad_ops.load_model` returns `"Failed to load the model"` on iPhone 17 Pro simulator. Voice agent silently falls back to energy VAD.
- **Diagnostic**: Auto-load fails in ~30 ms — too fast to be a real ONNX model load. Likely path resolution or plugin registration order issue, not actual model file I/O.
- **Evidence**: `test_workflows/logs/20260510-160835-swift-e2e/02_ios_swift/logs/wave1_vad_verification_retry.log` line 60.
- **Cross-platform**: Likely affects Kotlin / Flutter / RN as well (shared Sherpa-ONNX backend path), though not yet re-verified post-Wave-1 on those SDKs.
- **Severity**: HIGH — blocks neural VAD in voice agent; blocks SWIFT-VOICE-AGENT-001 from full unblock.
- **Action**: Investigate Sherpa plugin's `vad_ops.load_model` — path resolution, plugin registration ordering, and whether the Silero VAD model URL/path passed to the plugin matches what the loader expects.

### Confirmed-not-issues (positive findings)

- All 4 Phase 0-3 deleted files (`CommonsErrorMapping`, `DeviceIdentity`, `ComponentProtocols`, `SystemTTSModule`) — zero runtime references in the captured logs; build correctly removes stale `.o` files.
- No `dyld` / `dlsym` failures.
- No Swift fatal errors / preconditions / forced unwraps observed.
- No proto decode/encode warnings.
- SDK init: 70 ms cold.
- No memory warnings during 30-minute test session.
- No crash reports.

### Cross-references

- Run folder: `test_workflows/logs/20260510-160835-swift-e2e/02_ios_swift/`
- Detailed RCA: `gaps/gaps/inconsistencies/SWIFT-IOS-001-vad-route.md`
- Canonical Swift status doc (simplification report + residual open items): `gaps/gaps/simplification/SWIFT_REMAINING.md`

---

## Current modality state (physical iPhone 17 Pro Max)

| Modality | Status |
|---|---|
| LLM Chat | PASS |
| VLM (LFM2-VL 450M) | PASS |
| STT (Sherpa Whisper Tiny, single-shot) | PASS |
| TTS (Platform + Sherpa Piper) | PASS |
| Tool Calling | PASS |
| RAG ingest + query | PASS |
| Document storage + retrieval | PASS |
| Archive extraction → canonical path | PASS |
| Model persistence across relaunch | PASS |
| Settings / Hardware / Permissions | PASS |
| VAD | BROKEN — route fix landed in `507fd3bfd`; remaining blocker is loader-level `SWIFT-IOS-012` |
| Voice Agent (end-to-end pipeline) | BROKEN — `SWIFT-VOICE-AGENT-001` (PARTIALLY UNBLOCKED; remaining blocker is SWIFT-IOS-012) |
| Solutions | UNTESTED — `SWIFT-SOLUTIONS-UNTESTED` |

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

## SWIFT-VAD-001: Voice Activity Detection is broken (HIGH) — C++ ROUTER ROOT CAUSE — **ROUTE FIX LANDED**; loader-level failure remains (see SWIFT-IOS-012)

> **Attribution corrected 2026-05-10**: This was previously attributed to a Swift bridge gap (`VADLifecycleProtoABI` missing). Deep RCA during the 20260510-160835 E2E run identified the actual root cause as a C++ router misroute. See `gaps/gaps/inconsistencies/SWIFT-IOS-001-vad-route.md` for the full evidence chain.

- **Symptom**: `RunAnywhere.loadModel(silero-vad)` returns `success=false` with `errorMessage = "no backend route supports requested model for framework onnx"`. VAD does not fire speech-start / speech-end events; voice agent falls back to energy-based VAD silently. `Model states synced - VAD: false` immediately after `Initializing voice agent...`.
- **Evidence (this run)**: `examples/ios/RunAnywhereAI/.../VoiceAgentViewModel.swift:471-483` auto-load returns success=false; warning surfaces only as a `logger.warning` line at `:481`.
- **Root cause (C++, not Swift)**: `sdk/runanywhere-commons/src/core/model_lifecycle.cpp:287-312` — `framework_to_plugin_name(INFERENCE_FRAMEWORK_ONNX, DETECT_VOICE)` returns the string `"onnx"`. The lifecycle path then sets `hints.preferred_engine_name = "onnx"` and `hints.no_fallback = true` (`model_lifecycle.cpp:1407-1411`). The router (`sdk/runanywhere-commons/src/router/rac_engine_router.cpp:167-180`) does case-sensitive equality against `vt.metadata.name`. The `"onnx"` engine has `vad_ops = nullptr` (it serves embeddings only — see `engines/onnx/rac_plugin_entry_onnx.cpp:46-78`). The engine that owns `vad_ops` is named `"sherpa"` (`engines/sherpa/rac_plugin_entry_sherpa.cpp:65,138`), but the pin name mismatch causes hard-rejection. Result: no candidate plugin survives; router returns `RAC_ERROR_NOT_FOUND`.
- **Why STT/TTS work**: They are registered with `framework: .sherpa` in `examples/ios/RunAnywhereAI/.../App/RunAnywhereAIApp.swift:378-410`, which resolves to plugin name `"sherpa"` and matches. Only the VAD model is registered with `framework: .onnx` (line 412-420), making it the lone failing modality. Same asymmetry exists in Kotlin Android (`ModelBootstrap.kt:383-393`).
- **Fix (Option A, recommended)**: ~6-line change in `framework_to_plugin_name` in `sdk/runanywhere-commons/src/core/model_lifecycle.cpp:287-312` — special-case speech primitives (`DETECT_VOICE`, `TRANSCRIBE`, `SYNTHESIZE`) when framework is `INFERENCE_FRAMEWORK_ONNX` to return `"sherpa"`. Mirrors the existing `LLAMA_CPP + VLM → "llamacpp_vlm"` special-case in the same function. No example-app churn. No proto changes.
- **Fix (Option B, cleaner)**: Update every model registration that says `framework: .onnx` for speech models to say `framework: .sherpa` (iOS, Kotlin, Flutter, RN). Honest about which engine runs the model; more cross-SDK alignment work.
- **Cross-platform implication**: One C++ change fixes Swift, Kotlin, Flutter, and RN simultaneously — they all share the C++ lifecycle path.
- **Scope**: XS (Option A, single C++ file).
- **Status (2026-05-10, post-Wave 1)**: **ROUTE FIX LANDED in `507fd3bfd`** (Option A applied). The original `"no backend route supports requested model for framework onnx"` error is gone (verified on iPhone 17 Pro simulator). However, a different loader-level failure now surfaces at the Sherpa plugin's `vad_ops.load_model` (`"Failed to load the model"`, ~30 ms) — tracked as **SWIFT-IOS-012**.

## SWIFT-VOICE-AGENT-001: End-to-end Voice Agent pipeline is broken (HIGH) — **PARTIALLY UNBLOCKED**

- **Symptom**: Voice Agent initializes but no full VAD → STT → LLM → TTS round-trip. Only LLM commits.
- **Evidence**: `logs3.txt:2349-2385` — init immediately followed by `VAD:false, STT:false, LLM:true, TTS:false`, then cleanup without voice events.
- **Root cause (likely)**: Voice Assistant Setup screen's commit closures for VAD/STT/TTS don't call `modelManager.setVoiceVAD / setVoiceSTT / setVoiceTTS` — a separate path from the standalone STT/TTS screens that were fixed in Phase 6h. `handleComponentLifecycleEvent` may not fire for Voice-Setup loads.
- **Fix hypothesis**:
  1. Audit `VoiceAgentViewModel.setVADModel / setSTTModel / setTTSModel` — confirm they call `RunAnywhere.loadModel(...)` with the correct `RAModelCategory`.
  2. Audit `VoiceAssistantView.swift` picker "Use" closures — confirm they `await viewModel.setXXXModel(model)`.
  3. Confirm commons emits `componentLifecycle.loaded` events for VAD component on load.
  4. Verify `CppBridge.VoiceAgent.shared.getHandle()` gathers all 4 component handles.
- **Status (2026-05-10, post-Wave 1)**: **PARTIALLY UNBLOCKED** — `SWIFT-IOS-001` route fix landed in `507fd3bfd`, so the VAD lifecycle no longer hard-rejects on routing. Remaining blocker is **SWIFT-IOS-012** (Sherpa plugin's `vad_ops.load_model` returns failure). Once SWIFT-IOS-012 is investigated and fixed, the secondary audit of `VoiceAgentViewModel.setVADModel/setSTTModel/setTTSModel` (correct `RAModelCategory` usage) should follow.
- **Scope**: M–L.

## SWIFT-SOLUTIONS-UNTESTED: Solutions feature has not been tested (UNKNOWN)

- **Status**: The Solutions YAML runner path (`RunAnywhere.solutions.run(yaml:)`, tab `Solutions` in the iOS example) has not been exercised on physical device.
- **Action**: Include a Solutions smoke test in the next validation pass after VAD + Voice Agent are unblocked.
- **No failure observed yet** — known-untested, not known-broken.

## SWIFT-VLM-STREAM-REVERT: Revert VLM `processImageStream` workaround (LOW) — **CLOSED (NO-OP)**

- **Current state**: `Public/Extensions/VLM/RunAnywhere+VisionLanguage.swift:42-83` routes `processImageStream` through non-streaming `process()` and synthesizes a single TOKEN_GENERATED + COMPLETED pair.
- **Why it's obsolete**: Phase 6j (`26ce54160`) fixed the handle-type-mismatch root cause. Real streaming should work now. The C++ `rac_vlm_process_stream_proto` (`include/rac/features/vlm/rac_vlm_service.h:230`) is never exercised by this workaround.
- **Fix**: Revert the workaround; verify per-token streaming works on device.
- **Scope**: S.
- **Status**: **CLOSED (NO-OP)** during Wave 2 — already cleaned up in a prior phase; Wave 2 audit was stale.

---

# Part 2 — Swift/C++ duplication gaps (2026-05-09 audit)

Cross-module audit across 8 Swift module subtrees found systematic duplication of logic that belongs in the C++ commons layer. **Most items have been resolved through the 5-phase simplification work** — only OPEN entries are listed below. For the full historical catalog see git history of this file or the pre-execution audit docs under `gaps/gaps/simplification/swift-*-duplication.md`.

## RESOLVED (Phase 0–5, deletion-only or moved-to-commons)

The following have been DELETED or migrated and are no longer present in the codebase:

- `SWIFT-DUP-CANHANDLE` — DONE. 5 `canHandle*` methods removed across `LlamaCPPRuntime`, `ONNXRuntime`, `SystemFoundationModelsModule`, `SystemTTSModule`. (`2c4b8b599`)
- `SWIFT-DUP-MODULE-METADATA` — DONE. `RunAnywhereModule.swift` protocol deleted, 4 module conformances removed. (`bf0cd5d7f`)
- `SWIFT-DUP-RUNTIME-HEADERS` — DONE. 16 duplicate C headers removed from `LlamaCPPRuntime` and `ONNXRuntime`. (`30039099b`)
- `SWIFT-DUP-CRACOMMONS-PHANTOM` — DONE. 5 phantom CRACommons headers deleted (`rac_llm_events.h`, `rac_stt_events.h`, `rac_tts_events.h`, `rac_vad_events.h`, `rac_rag_pipeline.h`). (`f83ca88ec`)
- `SWIFT-DUP-RACTYPES-CPPBRIDGE-DEAD` — DONE. 8 orphaned C-struct marshaling initializers/methods deleted in `RALLMTypes+CppBridge.swift`, `RASTTTypes+CppBridge.swift`, `RATTSTypes+CppBridge.swift`, `RAVADTypes+CppBridge.swift`. (`8df0036da`)
- `SWIFT-DUP-LIFECYCLE-STATE` — DONE. `SystemFoundationModelsService.swift` lifecycle state mirror removed. (`96ef9e45f`)
- `SWIFT-DUP-FACTORY-BYPASS` — DONE. `createService()` factories deleted on `SystemFoundationModelsModule` and `SystemTTSModule`. (`bf0cd5d7f`)
- `SWIFT-DUP-COMPONENT-PROTOCOLS` — DONE. `Foundation/Core/ComponentProtocols.swift` deleted; `displayName` moved to `RASDKComponent+DisplayName.swift`.
- `SWIFT-DUP-CRACOMMONS-STRUCTURED-OUTPUT-MISSING` — DONE (different file split). The proto-byte structured-output API is now exposed via `CRACommons/include/rac_llm_schema_to_json.h` rather than retrofitting `rac_llm_structured_output.h`.
- Various LOW items (`SWIFT-DUP-COMPONENT-PROTOCOLS`, partial `SWIFT-DUP-STORAGE-ALIASES`, partial `SWIFT-DUP-HTTP-ADAPTER-MISLOCATED`, partial `SWIFT-DUP-ERROR-CABI`) — see `gaps/gaps/simplification/SWIFT_REMAINING.md` for the residual sliver in each.

## OPEN

### SWIFT-DUP-CRACOMMONS-THINKING-DRIFT: `rac_llm_thinking.h` regressed the SWF-THINKING-MIGRATE cleanup (MEDIUM) — **DEFERRED / ABORTED** (Wave 2)

`Sources/RunAnywhere/CRACommons/include/rac_llm_thinking.h:52-88` still declares three functions with `RAC_API`:
- `rac_llm_extract_thinking`
- `rac_llm_strip_thinking`
- `rac_llm_split_thinking_tokens`

Canonical commons `sdk/runanywhere-commons/include/rac/features/llm/rac_llm_thinking.h:64-108` has stripped `RAC_API`, marked all three `@internal`, and none appear in `RACommons.exports`. The Swift extension `CppBridge+LLMThinking.swift` calls these — meaning Swift code is now calling symbols the commons public ABI does not export.

**Fix**: Either (a) restore `RAC_API` + exports entries in commons if Swift actually needs these (audit `CppBridge+LLMThinking.swift` call sites), or (b) delete the Swift wrappers and migrate thinking extraction to the proto-field-based API on `RALLMGenerationResult`.
**Scope**: S.
**Status**: **DEFERRED / ABORTED in Wave 2**. Commit `57dbcdfbd` deliberately marked the 3 thinking helpers `@internal`. The correct fix is Swift-side migration to the proto-field-based API on `RALLMGenerationResult` (tracked as **SWF-THINKING-MIGRATE**) — not restoration of `RAC_API` + exports. The Swift mirror header is slightly stale (still says `RAC_API`) but functionally everything links and works today. Deferred to a future Swift migration task.

### SWIFT-DUP-HTTP-ADAPTER-MISLOCATED: `HTTPClientAdapter` is in the wrong directory (MEDIUM) — **CLOSED** in `0eeccda3e`

`Sources/RunAnywhere/Adapters/HTTPClientAdapter.swift` is named like an IoC platform adapter but is mislocated. Phase 3 already absorbed most of the business logic (Supabase upsert injection, auth retry loop, `parseHTTPError` status-code→`SDKException` classification — now in C++ via `rac_api_error_from_response`, `rac_http_request_set_upsert_mode`, `rac_http_default_headers`).

The remaining items:
1. Move `HTTPClientAdapter.swift` from `Adapters/` to `Foundation/Bridge/` or `Data/Network/` (file is still 338 LOC).
2. Review `Data/Network/Protocols/NetworkService.swift` — a second Swift protocol layer over `rac_http_transport_ops_t`. If nothing uses it, delete.

**Scope**: S.
**Status**: **CLOSED** in `0eeccda3e`. `HTTPClientAdapter.swift` moved to `Foundation/Bridge/`. `NetworkService.swift` kept; the protocol still serves as a conformance marker but has no real type-level consumers — deferred for removal in a future cleanup pass.

### SWIFT-DUP-MODELTYPES-COMPUTED: `RAModelCategory` Swift computed properties duplicate C functions (LOW)

`Sources/RunAnywhere/Public/Extensions/Models/ModelTypes.swift:176-195` — comments on `RAModelCategory.requiresContextLength` and `.supportsThinking` explicitly say "Matches `rac_model_category_requires_context_length()` on the C side." The C functions are the source of truth; the Swift duplicates will drift.

`ModelTypes.swift:308-345` — `RAInferenceFramework.toCFramework()` / `fromCFramework(_:)` are large hand-maintained switches. Same drift risk.

**Fix**: Call the C functions directly. For `toCFramework`/`fromCFramework`, add a proto → rac_inference_framework_t helper in commons (e.g. `rac_inference_framework_from_proto(int32_t)`) and delete the Swift switches.
**Scope**: S.

### SWIFT-DUP-STORAGE-ALIASES: Storage field aliases shadow canonical proto names (LOW)

`Sources/RunAnywhere/Public/Extensions/Storage/StorageProto+Helpers.swift`:
- Lines 24-33 — `RADeviceStorageInfo.totalSpace/freeSpace/usedSpace/usedPercent` alias the canonical proto fields `totalBytes/freeBytes/usedBytes`.
- Lines 56-74 — `RAAppStorageInfo.documentsSize/cacheSize/appSupportSize/totalSize` alias existing proto fields.

These aliases create two names for each field, divorcing Swift callers from the wire representation.

**Fix**: Delete the aliases. Callers should use the proto field names directly. Keep the `usedPercent` computation as a utility (it's a derived value, not an alias).
**Scope**: XS.

### SWIFT-DUP-DEAD-LIFECYCLE-HELPERS: Dead component-sync helpers (LOW) — **CLOSED (NO-OP)**

`Sources/RunAnywhere/Public/Extensions/Models/RunAnywhere+ModelLifecycle.swift:96-134` — `synchronizeSTTComponentLoad` and `synchronizeTTSComponentLoad` private functions are never called. The file's own comment at lines 38-43 explicitly says STT+TTS sync was removed in Phase 6h; the helpers weren't cleaned up.

**Fix**: Delete both functions.
**Scope**: XS.
**Status**: **CLOSED (NO-OP)** during Wave 2 — already cleaned up in a prior phase; Wave 2 audit was stale.

### SWIFT-DUP-ERROR-CABI: Proto factory reconstructs `cAbiCode` (LOW)

`Sources/RunAnywhere/Foundation/Errors/RASDKError+Helpers.swift:34-36`:
```swift
let raw = code.rawValue
if raw > 0 && raw <= 899 { p.cAbiCode = -Int32(raw) }
```
This re-derives the proto-enum → C-integer mapping. Phase 3 deleted `CommonsErrorMapping.swift` and now uses `rac_result_to_proto_error` for translation, but `RASDKError+Helpers.swift` still has this dangling lines block.

**Fix**: Delete the 3 lines from `RASDKError.make()`. (Optionally add `rac_error_get_category_proto` as a unified entry point.)
**Scope**: XS.

### SWIFT-DUP-UNUSED-PROTO-TYPES: Generated proto types with zero Swift callers (LOW)

Spot-grep of Generated/ finds proto types with no consumer in the Swift SDK:

- `router.pb.swift` — `RARouterStrategy`, `RARouterConfig`, `RARouterState`. Zero callers.
- `pipeline.pb.swift` — only consumed internally by `solutions.pb.swift`.
- `solutions.pb.swift` — consumed only by `RunAnywhere+Solutions.swift`, which is itself stub-level and doesn't call through to CppBridge.
- `diffusion_options.pb.swift` — consumed by nothing (the Diffusion deferred-backend CppBridge extension was removed).

**Fix**: Exclude these from the Swift SPM target's `sources` until consumers land. They're generated from `idl/` unconditionally but the Swift target doesn't have to compile them.
**Scope**: XS (Package.swift exclude list).

### SWIFT-DUP-TTS-LISTVOICES-HANDLE: `listVoices` still requires the actor handle (LOW)

`CppBridge+ModalityProtoABI.swift:531-553` — `CppBridge.TTS.listVoices()` passes a `rac_handle_t` from `getHandle()` to `rac_tts_component_list_voices_proto`. All other post-Phase-6h TTS ops use the handle-less lifecycle-proto path. This is the one inconsistent call on the TTS actor.

**Fix (requires C++ change)**: Add `rac_tts_list_voices_lifecycle_proto` in commons; switch Swift to the lifecycle variant. Low priority — it works as-is.
**Scope**: S.

### SWIFT-DUP-ISLOADED-INCONSISTENCY: STT/TTS/VLM use divergent "is-loaded" checks (LOW)

- `RunAnywhere+STT.swift:30-34` — queries `RunAnywhere.currentModel(...)` via `RACurrentModelRequest`.
- `RunAnywhere+TTS.swift:34-37` — same pattern.
- `RunAnywhere+TTS.swift:53` — but `synthesizeStream` guards on `CppBridge.TTS.shared.isLoaded` (actor-handle-based check), not `currentModel`.
- VLM mixes both patterns similarly.

The mismatch is because bridge actors hold their own handles while the lifecycle service holds its own. Either source can disagree. The comments in the files explicitly flag this as a known architectural gap.

**Fix (architectural, low priority)**: Consolidate on the lifecycle service as the single source of truth; remove the actor-side `isLoaded` flag entirely.
**Scope**: M.

---

## Summary

For a consolidated cross-reference of completed work, residual open items, and PR-review explainer see [`gaps/gaps/simplification/SWIFT_REMAINING.md`](../simplification/SWIFT_REMAINING.md).

Per repo convention: **DELETE, don't deprecate**. No compat shims, no `@available` gates, no `#if false`. Per `CLAUDE.md`: business logic lives in C++; proto types from `idl/*.proto` are canonical; Swift should be a thin bridge.
