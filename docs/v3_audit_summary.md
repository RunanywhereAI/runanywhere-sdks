# v3.0.0 Post-Release Audit Summary

_Date: 2026-04-19. Audit performed by 3 parallel read-only agents + manual
reconciliation. This document is the single source of truth for "what shipped
in v3.0.0" and "what's left" — supersedes the drift-bearing sections of
`v2_current_state.md` L80+ that predate the v3 cut-over._

## TL;DR

- **v3.0.0 ABI + registry cutover: COMPLETE.** Zero first-party `rac_service_*`
  function calls remain in the tree. `service_registry.cpp` physically
  deleted. `RAC_PLUGIN_API_VERSION = 3u`. Semver 3.0.0 on all 7 SDK packages.
  `test_proto_event_dispatch` 11/11 OK on macOS.
- **2 real bugs were surfaced by the audit and fixed in this pass**: Swift
  CRACommons `rac_plugin_entry.h` was still on `2u`; 6 Swift primitive mirror
  headers missed the `.create` field sync; `Package.swift sdkVersion` still
  `0.19.13`.
- **1 open build issue**: Swift SPM ships committed `*.grpc.swift` sources
  that import `GRPCCore` / `GRPCProtobuf` but `Package.swift` does not
  declare `grpc-swift` as a dependency. External SPM consumers cannot
  resolve the package.
- **Largest remaining scope**: v3.1 follow-up PR — migrate 4 sample-app
  voice views to `VoiceAgentStreamAdapter` + proto events, then delete the
  deprecated SDK shims (`VoiceSessionEvent`, `VoiceSessionHandle`,
  `startVoiceSession`, etc.).

## 1. What definitively shipped in v3.0.0

### C ABI / plugin registry

| Item | Commit | Status |
|------|--------|--------|
| `create(model_id, config_json, out_impl)` op on 7 per-primitive ops structs (LLM, STT, TTS, VAD, VLM, embeddings, diffusion) | `c721a9c6` (B0) | OK |
| `initialize(impl, model_path)` on VAD for symmetry | `c721a9c6` (B0) | OK |
| llamacpp LLM `create` wired + legacy factory deleted | `40d032d4` (B1) | OK |
| llamacpp VLM `create` + mmproj_path JSON parsing | `e1824aa2` (B2) | OK |
| onnx STT+TTS+VAD `create` + VAD `initialize` | `67b7539e` (B3) | OK |
| whispercpp STT `create` | `f75c2c85` (B4) | OK |
| whisperkit_coreml STT `create` (Swift-callback delegation) | `c5ceb7b8` (B5) | OK |
| metalrt LLM+STT+TTS+VLM `create` (4 adapters, stub-build gated) | `ce70e208` (B6) | OK |
| onnx_embeddings + new `rac_plugin_entry_platform.cpp` (Apple LLM/TTS/Diffusion) | `890d759e` (B7) | OK |
| 7 commons consumers rerouted through `rac_plugin_route + vt->ops->create` | `f46c4485` (B8) | OK |
| 6 JNI sites migrated to `rac_plugin_list` | `e33c6fa1` (B9) | OK |
| Swift `CppBridge+Services` migrated to plugin registry + 5 CRACommons bridging headers added | `fd8c9e7c` (B10) | OK |
| `service_registry.cpp` physically deleted (311 LOC) + `rac_core.h` legacy block (163 LOC) + Swift CRACommons mirror + Dart ffi_types + 12 export entries | `7dc2cbdc` (C1) | OK |
| `RAC_PLUGIN_API_VERSION` 2u → 3u + semver 3.0.0 × 7 packages | `b55d41ff` (C3) | OK |

### Verification

```
$ cmake --preset macos-release
-- Configuring done

$ cmake --build build/macos-release --target rac_commons \
                                             rac_backend_onnx \
                                             rac_backend_whisperkit_coreml \
                                             runanywhere_llamacpp
[16/16] Linking CXX shared library librunanywhere_llamacpp.dylib

$ ./build/macos-release/sdk/runanywhere-commons/tests/test_proto_event_dispatch
0 test(s) failed          ← 11/11

$ rg 'rac_service_(create|register_provider|unregister_provider|list_providers|request_t|provider_t|can_handle_fn|create_fn)' \
     sdk/runanywhere-commons/src sdk/runanywhere-commons/include \
     sdk/runanywhere-swift/Sources sdk/runanywhere-kotlin/src \
     sdk/runanywhere-flutter/packages sdk/runanywhere-react-native/packages \
     sdk/runanywhere-web/packages engines/
# ZERO CODE hits. All residual matches are historical comments.
```

## 2. Audit-surfaced bugs — fixed in this pass

| # | Bug | Fix |
|---|-----|-----|
| 1 | Swift `CRACommons/include/rac_plugin_entry.h` still had `#define RAC_PLUGIN_API_VERSION 2u` — C3 only bumped commons, not the Swift mirror. Swift code compiling against the mirror would have seen a stale value. | Bumped mirror to `3u`. |
| 2 | Swift `CRACommons/include/rac_llm_service.h` (and the 5 other primitive mirror headers) missed the `.create` field — ABI mismatch between commons source of truth and Swift consumption. | Re-synced 6 primitive headers from commons to CRACommons with include-path flattening. All 6 now carry `.create`. |
| 3 | `Package.swift` `sdkVersion = "0.19.13"` — not bumped to 3.0.0. Remote XCFramework URLs would point at the wrong GitHub release. | Bumped to `"3.0.0"` with a comment noting release automation is the canonical source. |
| 4 | Kotlin `VoiceAgentTypes.kt` KDoc said the `from(event)` mapper was a "SCAFFOLD returning null" but Phase A shipped the full implementation. | Corrected KDoc to match reality + added v3.1 deletion note. |
| 5 | Dart `voice_session.dart` dartdoc said `fromProto` was a "SCAFFOLD" but Phase A6 shipped the full body. | Corrected dartdoc + added v3.1 deletion note. |
| 6 | `rac_route.h` + Swift mirror comment still said legacy `rac_service_create()` is "parallel" — both can be active. Not true post-C1. | Rewrote to say this is the SOLE routing API post-v3. |
| 7 | `rac_plugin_registry.cpp` file-header comment still said it "coexists with `service_registry.cpp`". Not true post-C1. | Rewrote. |
| 8 | `rac_plugin_entry_llamacpp.cpp` file-header still said `rac_backend_llamacpp_register` uses `rac_service_register_provider`. Not true post-B1. | Rewrote. |
| 9 | `rac_embeddings_service.h` file-header still said "Backends … register via `rac_service_register_provider()`". Not true post-B7. | Rewrote. |
| 10 | `v2_current_state.md` L58 architecture summary still said `RAC_PLUGIN_API_VERSION = 2u`. | Corrected to `3u`. |
| 11 | `v2_current_state.md` L80+ "What's TRULY remaining" still listed Tier 3 v3 cut-over as future work. | Replaced with post-v3 tier list (v3.1 / remaining spec criteria / deferred). |
| 12 | `v2_current_state.md` L157+ described Phase B / C as future work. | Rewrote as shipped-log. |
| 13 | `gap11_final_gate_report.md` criterion #2 still pointed at `service_registry.cpp` for the `rac_legacy_warn_once` helper — file deleted in C1. | Marked criteria #1 and #2 SUPERSEDED; rewrote "Why deprecation, not delete" as "History (v2 → v3 progression)"; deleted "What's deferred to v3" block. |
| 14 | `v3_phaseC2_scope.md` classified Web `VoiceAgentEventData` and `postTelemetryEvent` as "not deprecated" — source actually has `@deprecated` on both. | Corrected. |

## 3. Open build issues (surfaced by audit, NOT fixed)

| # | Issue | Severity | Triage |
|---|-------|----------|--------|
| 1 | **Swift SPM**: `Package.swift` target `RunAnywhere` ships committed `Generated/*.grpc.swift` that imports `GRPCCore` / `GRPCProtobuf`, but the target's dependency list declares only `SwiftProtobuf` + Alamofire etc. SPM resolution for external consumers fails with "no such module 'GRPCCore'". | High | Either wire grpc-swift into the SPM dep list, or `.exclude` the `*.grpc.swift` files from the target. v3.1 scope. |
| 2 | `engines/metalrt/CMakeLists.txt` references `${CMAKE_SOURCE_DIR}/include` which does not exist (top-level `/include` is not in the repo). | Medium | Pre-existing; metalrt is OFF by default so this only surfaces when the engine is enabled. Fix concurrently with MetalRT engine availability. |
| 3 | JNI `AttachCurrentThread` calls have inconsistent casting — some sites use `(void**)&env`, others `reinterpret_cast<void**>(&env)`, others `&env` relying on ABI compatibility. Works on Android NDK; warns on macOS Temurin. | Low | Cosmetic consistency issue. Batch-fix in an unrelated JNI cleanup PR. |
| 4 | `idl/CMakeLists.txt` `rac_idl` target fails to link locally with missing `google/protobuf/runtime_version.h` — generated code uses a newer protobuf version than the system libprotobuf. | Low | Pre-existing toolchain skew; does not break the consumer targets (commons + engines). CI-only pin refresh. |

## 4. Spec-criterion status post-v3.0.0

Data source: Agent 3's GAP spec audit.

| GAP | Title | Status | Remaining work |
|-----|-------|--------|----------------|
| GAP 01 | IDL + codegen | PARTIAL | #4 5-SDK build green across samples is still partial. |
| GAP 02 | Unified engine plugin ABI | **OK** (v3.0.0) | None. Spec's "coexistence with legacy" text is now historically accurate but the codebase is single-path. |
| GAP 03 | Dynamic plugin loading | PARTIAL | Full real-model GGUF E2E + valgrind under CI. |
| GAP 04 | Engine router + HW profile | PARTIAL | iOS17 / ANE device E2E. Spec row 5 ("legacy rac_service_create for unmigrated") is now obsolete. |
| GAP 05 | DAG runtime | DEFERRED | Optional; no active consumers. |
| GAP 06 | Engines top-level reorg | PARTIAL | 5 engines still have non-uniform `CMakeLists.txt`; helper-macro normalization pending. |
| GAP 07 | Single root CMake | OK | NDK pin single-source is the remaining polish. |
| GAP 08 | Frontend duplication delete | PARTIAL (8 OK · 2 PARTIAL · 1 DEFERRED · 1 PARTIAL) | #4 `runanywhere.dart` 2,688 → ≤500 LOC deferred. Sample-app smoke tests (#9) + device parity (#10) outstanding. |
| GAP 09 | Streaming consistency | PARTIAL (7 OK · 2 PARTIAL) | #7 cancellation parity test, #8 per-SDK p50 benchmark runners. |
| GAP 11 | Legacy cleanup | **OK** (v3.0.0) | None — criteria #1 and #2 SUPERSEDED; #5 and #6 flipped to OK with v3 evidence. |

## 5. Remaining work, prioritized

### v3.1 follow-up PR (next)

1. **Migrate 4 sample-app voice views** to `VoiceAgentStreamAdapter` +
   proto events (iOS `VoiceAgentViewModel`, Android
   `VoiceAssistantViewModel`, Flutter `voice_assistant_view`, RN
   `VoiceAssistantScreen`). Each view switches on the deprecated
   `VoiceSessionEvent` type; migration is view-model-level rewrite,
   not one-liner substitution. Estimated 3-5 days.

2. **Delete deprecated SDK shims** across Swift/Kotlin/Dart/RN once
   sample apps migrate:
   - `VoiceSessionEvent` enum/interface + `from()` / `fromProto()` mappers
   - `VoiceSessionHandle` actor/class
   - `startVoiceSession` / `streamVoiceSession` / `processVoice` entry points
   - Swift `startStreamingTranscription` + `LiveTranscriptionSession`
   - RN `voiceSessionEventFromProto` / `voiceSessionEventKindFromProto`
   Estimated 1 day after sample apps migrate.

3. **Swift SPM fix** — either wire grpc-swift into `Package.swift`
   dependencies, or `.exclude(["Generated/*.grpc.swift"])` from the
   target. Estimated 0.5 day.

4. **Audit remaining RN deprecations** — `getTTSVoices`, `getLogLevel`,
   `SDKErrorCode`. Some have real replacements; some are mislabeled.
   Estimated 0.5 day.

### v3.x backlog (no single PR)

5. **GAP 09 #7** — 5-SDK behavioral cancellation parity test harness.
   Estimated 1 week.

6. **GAP 09 #8** — Per-SDK p50 latency benchmark runners. C++ producer
   + Python aggregator already shipped (v2.1 quick-wins Item 3); what's
   missing is the 5-SDK consumer integration. Estimated 3 days.

7. **GAP 08 #9** — Sample-app E2E smoke automation (Detox / Maestro /
   XCUITest / Espresso). Estimated 1 week.

8. **GAP 08 #10** — Real-device behavioral parity verification. QA
   effort; ~1 week manual.

9. **GAP 06 polish** — normalize per-engine `CMakeLists.txt` to use
   `rac_add_engine_plugin` uniformly. Estimated 1-2 engineer-weeks.

10. **GAP 07 #11** — NDK pin single source of truth (root
    `gradle.properties`). Estimated 1 day.

### Deferred indefinitely

11. **GAP 05** — DAG runtime. Optional; revisit when a second pipeline
    (multi-modal RAG, agent loop) commits to using the primitives.

12. **Flutter `runanywhere.dart` 2,688 → ≤500 LOC** — multi-day refactor;
    not release-blocking, spec DEFERRED.

13. **Kotlin per-SDK total LOC trim** — GAP 08 PARTIAL (60% over spec
    target). Multi-day refactor; not release-blocking.

## 6. What this audit did NOT cover

- Linux / Android native builds (macOS-only verification).
- XCFramework output artifacts (script exists; didn't run).
- Per-SDK behavioral tests against live models (sample-app tests opted
  out per user instruction).
- Third-party consumer breakage from `rac_service_*` deletion — any
  external consumer that called the deleted APIs needs to migrate
  via `docs/engine_plugin_authoring.md` §"Migrating off the legacy
  service registry".

## 7. Source materials

- Agent 1 verification report: per-claim table + export-list audit +
  residue grep.
- Agent 2 deprecation inventory: 5-SDK `@deprecated` surface map +
  sample-app coupling per view controller.
- Agent 3 GAP spec cross-check: per-GAP criterion matrix + gate-report
  disagreements.

All 3 audits converge on the same conclusion: the v3 cut-over
mechanically landed; documentation + Swift mirror sync were the gaps
the audit caught and this pass closed.
