# Implementation Backlog — Round 2 (Post-2026-05-05 Seven-Lane E2E)

Source of this round: `test_workflows/logs/20260505-232326-seven-lane-validation/failure_summary.tsv`.
Commit at run time: `bb63158d6861c9c298d271f2946ed5193e3da643` on `feat/v2-architecture`.
All previous waves (F-0 through F-7) DONE and removed from this doc.

## Deferred backends policy

- Genie, MetalRT, WhisperKit, WhisperKit CoreML, WhisperCPP, Diffusion (CoreML), whisperkit_coreml are all **deferred**.
- They can be excluded from builds, deleted, or left as compile-time stubs.
- Goal is only that the 5 SDKs + 5 example apps compile.
- NO bug rows will be filed about these backends being unimplemented, broken, or missing.
- If a bug row only makes sense because one of these backends is "needed," it should be deleted.

## Open BUG rows (15)

### HIGH — cross-platform root-cause (4)
#### BUG-KOT-E2E-R2-001 — Kotlin example crashes on Genie module reference
- Lane: 01_android_kotlin — blocks example app launch
- Evidence: `test_workflows/logs/20260505-232326-seven-lane-validation/01_android_kotlin/agent_report.md`
- Fix: exclude/remove/stub Genie module from Kotlin example app. Genie is deferred (see policy above); example must compile and launch without it. Options: drop the Genie dependency from `examples/android/RunAnywhereAI/app/build.gradle.kts`, delete any Genie source references, or replace with a compile-time stub.

#### BUG-RN-E2E-R2-001 — rac_model_paths_get_model_folder fails on every download
- Lane: 03_react_native_android — blocks LLM/STT/TTS/VAD/Voice/VLM/RAG/ToolCalling/StructuredOutput downloads
- Evidence: `test_workflows/logs/20260505-232326-seven-lane-validation/03_react_native_android/agent_report.md`
- Root-cause: RN Nitro platform adapter not wiring `base_dir` into commons OR proto framework UNKNOWN. Possibly same class as BUG-WEB-E2E-R2-001.

#### BUG-FLT-E2E-R2-002 — DownloadProgress proto wire-format drift (Flutter Android)
- Lane: 05_flutter_android — 7783 decode errors during one download; UI stalls at 91%
- Evidence: `test_workflows/logs/20260505-232326-seven-lane-validation/05_flutter_android/logs/android_snapshot_during_download.log`
- Fix: regenerate Dart `DownloadProgress` proto bindings; verify vs C++ rac_download_progress_proto.

#### BUG-FLT-E2E-R2-003 — xcframework missing rac_model_format_from_url_proto + rac_artifact_infer_from_url_proto
- Lane: 06_flutter_ios — every catalog entry warns; downloads blocked
- Evidence: `test_workflows/logs/20260505-232326-seven-lane-validation/06_flutter_ios/logs/ios_live.log`
- Fix: audit `scripts/build-core-xcframework.sh` strip workaround scope.

#### BUG-WEB-E2E-R2-001 — WASM missing _rac_model_paths_set_base_dir export
- Lane: 07_web — every download fails; size-independent
- Evidence: `test_workflows/logs/20260505-232326-seven-lane-validation/07_web/agent_report.md`
- Fix: re-add to `EXPORTED_FUNCTIONS` in `sdk/runanywhere-web/wasm/scripts/build.sh`; rebuild.

### HIGH — lane-specific (3)
#### BUG-FLT-E2E-R2-001 — Flutter Android 16 KB page-size dialog (NDK 25 vs 27)
- Fix: align Flutter NDK pin with Commons NDK 27 in `scripts/build-core-android.sh`.

#### BUG-WEB-E2E-R2-003 — ONNX+RAG backends disabled on Web
- Fix: enable `RAC_WASM_ONNX=ON` + `RAC_BACKEND_RAG=ON` in WASM CMake preset; ship artifacts.

#### BUG-BUILD-EXCLUSION-001 — SDKs + example apps must compile with deferred backends excluded/stubbed
- Scope: all 5 SDKs (Swift, Kotlin, Flutter, React Native, Web) + all 5 example apps
- Policy: Genie, MetalRT, WhisperKit, WhisperKit CoreML, WhisperCPP, Diffusion (CoreML), whisperkit_coreml are deferred and must not block compilation
- Current known failures: Kotlin example (Genie AAR reference — see BUG-KOT-E2E-R2-001)
- Next-action: audit each SDK + example for hard references to deferred backends (imports, Gradle deps, CocoaPods specs, npm deps, CMake targets, xcframework stripping rules) and replace with stubs or remove.

### MEDIUM (3)
#### BUG-SWIFT-E2E-R2-001 — Swift STT "Use" button does not commit
- Inspect `VoiceAgentViewModel.swift` STT commit path.

#### BUG-SWIFT-E2E-R2-002 — Swift VLM picker download tap unresponsive
- Instrument `VLMViewModel` download action.

#### BUG-RN-E2E-R2-002 — RN iOS LLM Get button never transitions + a11y
- Add model name+state to accessibility labels; instrument Nitro download progress callback on iOS sim.

### LOW (4)
#### BUG-WEB-E2E-R2-002 — racommons-llamacpp-webgpu.wasm not shipped
#### BUG-WEB-E2E-R2-004 — Web chat hangs on "..." when no model loaded
#### BUG-RN-E2E-R2-003 — RN iOS bundle-ID doc drift in test_workflows
#### BUG-FLT-E2E-R2-004 — Flutter iOS rac_http_request_send -151 silent auth fail

## Convergence criteria

- All 15 BUG rows drained (one commit each) → re-run seven-lane E2E → zero FAIL modalities in failure_summary.tsv.
- All 5 SDKs + all 5 example apps compile green (with deferred backends excluded/stubbed per policy).
- Existing per-layer gap docs (cpp-layer.md, idl.md, engines.md, runtimes.md, swift.md, kotlin.md, flutter.md, react-native.md, web.md) reflect only currently-open items.
