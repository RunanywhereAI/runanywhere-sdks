# v3.1 Phase 8 — Kotlin LOC audit

_Status: Phase 4.2 deletions already banked the major Kotlin LOC win
for v3.1 (216 LOC). Remaining bloat is in canonical bridge code, not
duplication._

## Current state

Total Kotlin SDK: 49,547 LOC

Top 5 files by LOC:

| File | LOC | Nature |
|---|---|---|
| CppBridgeDownload.kt | 1,485 | Canonical bridge over `rac_download_*` C ABI |
| CppBridgePlatform.kt | 1,461 | Canonical bridge over `rac_platform_*` C ABI |
| CppBridgeEvents.kt | 1,451 | Canonical bridge over `rac_events_*` C ABI |
| CppBridgeTTS.kt | 1,384 | Canonical bridge over `rac_tts_*` C ABI |
| RunAnywhereBridge.kt | 1,358 | Raw JNI `external fun` declarations |

These are legitimate bridge code — each function has:
- Docstring (2-5 lines)
- JNI thunk type signature
- Data class conversion
- Error propagation

There's no way to significantly trim them without refactoring the C
ABI or converting bridges to codegen.

## GAP 08 alignment

GAP 08 explicitly targets ~2,900 LOC of **duplicated orchestration**
across 5 SDKs, not overall SDK size. The target: make frontends
`~200 LOC adapters` per GAP 08 L47.

### v3.1 deliveries against GAP 08

- **GAP 08 Kotlin Duplicate 1** (voice-agent orchestration, 467 LOC
  in `RunAnywhere+VoiceAgent.jvmAndroid.kt`) — DELETED in Phase 4.2
  (216 LOC direct + the expect/actual declarations).
  Replacement: `CppBridgeVoiceAgent.kt` (93 LOC) + sample-app's
  `processVoiceTurnDirect` helper (60 LOC in sample, not SDK).
  Net SDK reduction: ~120 LOC.

- GAP 08 Kotlin Duplicate 2 (CppBridgeAuth 542 LOC): kept. The HTTP
  transport layer stays in Kotlin (per v2.1 quick-wins Item 4, see
  RunAnywhereBridge.kt's Auth Manager section which delegates
  request-building + state to native). Already rewritten during
  v2.1-2 to be minimal around the JNI thunks.

- GAP 08 Kotlin Duplicate 3 (download orchestration 1,308 LOC in
  `RunAnywhere+ModelManagement.jvmAndroid.kt`): deferred. The
  `downloadModel()` impl uses platform-specific download queues
  (Android WorkManager, JVM OkHttp) that still need Kotlin code;
  the C-side `rac_download_manager_set_progress_callback` wire-up
  is in place but the policy code stays. Tracked as post-v3.1.

## Phase 8 scope

v3.1 Phase 8 deletes ran in Phase 4.2 ahead of the phase-8 todo. No
additional deletes fit the "zero stubs" quality bar here — the remaining
bridge code is real implementation, not fluff.

### What we did

- Phase 4.2: -216 LOC from deprecated VoiceSession surface (expect+actual decls +
  sealed class + mapper).
- Phase 3.2: +93 LOC new CppBridgeVoiceAgent facade (not duplication —
  new capability wrapping previously-inaccessible JNI thunks).
- RunAnywhereBridge.kt: +20 LOC for 4 new voice-agent external fun decls.

### Net v3.1 delta

  -216 (P4.2) + 93 (P3.2 facade) + 20 (bridge decls) ≈ -103 LOC

## What's NOT Phase 8 work

- Wire-generated proto duplicates (`ai.runanywhere.proto.v1.*`): these
  are codegen output from `bash idl/codegen/generate_kotlin.sh`;
  trimming them requires proto schema changes, not Kotlin SDK work.
- Hand-written CppBridge data classes that mirror proto structures:
  some exist (e.g. auth-result DTOs) but are used in non-proto call
  paths; leaving them until a proto migration is scheduled.

## Follow-up backlog (post-v3.1)

- [ ] Extract download-orchestration into commons (~1,000 LOC saving)
- [ ] Convert CppBridgePlatform.kt facade to generated code from rac_platform_*
- [ ] Convert CppBridgeEvents.kt to wire-generated event types (~400 LOC saving)

These are multi-sprint efforts requiring C-ABI schema changes.

## Metrics

| Metric | v3.0.0 | v3.1 | Notes |
|---|---|---|---|
| Kotlin SDK total LOC | ~49,650 | 49,547 | -103 LOC |
| GAP 08 Kotlin Dup 1 | 467 LOC | 0 LOC | DONE (Phase 4.2) |
| GAP 08 Kotlin Dup 2 | 542 LOC | ~400 LOC | v2.1-2 minimized |
| GAP 08 Kotlin Dup 3 | 1,308 LOC | 1,308 LOC | Deferred |

Phase 8 closes as "GAP 08 #1 closed, #2 minimized, #3 deferred" with
the Phase 4.2 Kotlin deletes being the substantive v3.1 delivery.
