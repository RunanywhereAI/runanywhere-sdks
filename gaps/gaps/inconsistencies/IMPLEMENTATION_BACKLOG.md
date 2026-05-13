# Implementation Backlog — Current Open Items

> Updated: 2026-05-13
> State: current execution backlog only. Historical Wave/R2 rows that are closed or intentionally deferred are removed from active tracking.

## Deferred backends policy

- Genie, MetalRT, WhisperKit, WhisperKit CoreML, WhisperCPP, Diffusion (CoreML), and whisperkit_coreml are all deferred.
- They can be excluded from builds, deleted, or left as compile-time stubs.
- Goal is only that the 5 SDKs + 5 example apps compile.
- No bug rows should be filed only because these deferred backends are unimplemented, broken, or missing.
- If a bug row only makes sense because one of these backends is "needed," delete it from the active backlog.

## Open BUG rows

### HIGH — cross-platform root cause

#### BUG-KOT-E2E-R2-001 — Kotlin example crashes on Genie module reference
- Lane: 01_android_kotlin — blocks example app launch.
- Evidence: `test_workflows/logs/20260505-232326-seven-lane-validation/01_android_kotlin/agent_report.md`
- Fix: exclude/remove/stub Genie module from Kotlin example app. Genie is deferred; the example must compile and launch without it.

#### BUG-RN-E2E-R2-001 — rac_model_paths_get_model_folder fails on every download
- Lane: 03_react_native_android — blocks LLM/STT/TTS/VAD/Voice/VLM/RAG/ToolCalling/StructuredOutput downloads.
- Evidence: `test_workflows/logs/20260505-232326-seven-lane-validation/03_react_native_android/agent_report.md`
- Root cause: Nitro platform adapter is not wiring `base_dir` into commons or proto framework is UNKNOWN.

#### BUG-FLT-COMMONS-EVENT-001 — Flutter-safe commons event publish
- Lane: 05_flutter_android + 06_flutter_ios — blocks safe worker-isolate model lifecycle calls.
- Evidence: Flutter lifecycle loads can publish commons events from worker execution paths while Dart callbacks are isolate-bound.
- Status: Flutter-side listener registration landed with `NativeCallable.listener`; keep open as validation-gated until real model-load event traffic proves clean.
- Fallback fix if validation fails: add a commons event queue drained on the originating Dart isolate boundary.
- Close criteria: Flutter Android and iOS can download, load, and run real inference with event publication enabled and no Dart VM cross-isolate callback abort.

#### BUG-WEB-E2E-R2-001 — WASM missing _rac_model_paths_set_base_dir export
- Lane: 07_web — every download fails; size-independent.
- Evidence: `test_workflows/logs/20260505-232326-seven-lane-validation/07_web/agent_report.md`
- Fix: re-add to `EXPORTED_FUNCTIONS` in `sdk/runanywhere-web/wasm/scripts/build.sh`; rebuild.

### HIGH — lane-specific

#### BUG-WEB-E2E-R2-003 — ONNX+RAG backends disabled on Web
- Fix: enable `RAC_WASM_ONNX=ON` + `RAC_BACKEND_RAG=ON` in WASM CMake preset; ship artifacts.

#### BUG-BUILD-EXCLUSION-001 — SDKs + example apps must compile with deferred backends excluded/stubbed
- Scope: all 5 SDKs + all 5 example apps.
- Policy: deferred backends must not block compilation.
- Current known failure: Kotlin example Genie AAR reference.
- Next action: audit each SDK + example for hard references to deferred backends and replace with stubs or remove.

#### BUG-FLT-SWIFT-PARITY-001 — Flutter exact Swift parity cleanup
- Scope: Flutter SDK public API, bridge slices, and Flutter docs.
- Status: implementation pass landed: static `RunAnywhere`, generated-proto LLM request helpers, structured-output helpers, typed `ToolValue` C++ JSON helpers, RAG helpers, artifact accessors, deletion of stale wrappers, and Flutter doc cleanup.
- Close criteria: Flutter analyze is clean, Swift/Flutter public surface audit has no unplanned drift, and docs list only current open items.

### MEDIUM

#### BUG-SWIFT-E2E-R2-001 — Swift STT "Use" button does not commit
- Inspect `VoiceAgentViewModel.swift` STT commit path.

#### BUG-SWIFT-E2E-R2-002 — Swift VLM picker download tap unresponsive
- Instrument `VLMViewModel` download action.

#### BUG-RN-E2E-R2-002 — RN iOS LLM Get button never transitions + a11y
- Add model name+state to accessibility labels; instrument Nitro download progress callback on iOS sim.

#### BUG-FLT-REGISTRY-001 — Flutter download success does not refresh model registry
- Lane: 05_flutter_android + 06_flutter_ios.
- Status: implementation landed: download completion refreshes the registry, resolves local paths, and emits a generated model download-completed event.
- Close criteria: after a fresh download, the model appears in the registry immediately and can be loaded in the same app session.

### LOW

#### BUG-WEB-E2E-R2-002 — racommons-llamacpp-webgpu.wasm not shipped

#### BUG-WEB-E2E-R2-004 — Web chat hangs on "..." when no model loaded

#### BUG-RN-E2E-R2-003 — RN iOS bundle-ID doc drift in test_workflows

#### BUG-FLT-IOS-KEYCHAIN-001 — residual iOS secure-storage entitlement warning
- Lane: 06_flutter_ios.
- Fix: investigate remaining `-34018` keychain/entitlement warnings if they persist after the Flutter parity pass.
- Close criteria: graceful fallback remains confirmed, and auth/device-registration behavior is not masked by fallback.

## Removed from active tracking

- Flutter Wave/R2 rows that are already closed: HTTP transport FQN, proto flood, closed plugin-routing symptoms, NDK/page-size alignment, stale xcframework symbol rows, and reverted Dart isolate experiments.
- Deferred-backend gaps whose only failure is deferred backend incompleteness.
- Historical wave plans. Git history and validation logs remain the audit trail.

## Convergence criteria

- All current BUG rows drained, with one commit per code fix where practical.
- Seven-lane E2E re-run shows zero FAIL modalities in `failure_summary.tsv`.
- All 5 SDKs + all 5 example apps compile green with deferred backends excluded or stubbed.
- Existing per-layer gap docs reflect only currently open items.
- Flutter-specific success is not reported until both Flutter lanes complete fresh install, continuous logs, model download, model load, real inference, screenshots, and log review.
