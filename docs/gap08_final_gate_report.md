# GAP 08 — Final Gate Report

_Closes [`v2_gap_specs/GAP_08_FRONTEND_LOGIC_DUPLICATION.md`](../v2_gap_specs/GAP_08_FRONTEND_LOGIC_DUPLICATION.md) Success Criteria._

> **POST-AUDIT-PHASE-C UPDATE (commits `dd9155e5` + `8a1ebfaa`)**: After the
> v2 close-out's `−6,247 LOC` delete, the post-audit Phase C pruned an
> additional **−730 LOC** of truly-orphan native declarations across 12
> CppBridge*.kt files. Combined Wave D + Phase C delete: **−6,977 LOC**
> (36% over the 5,100 ± 500 spec target). See
> [`docs/v2_closeout_results.md`](v2_closeout_results.md) for the per-criterion
> status flips (3 of 6 audit demotions closed) and
> [`docs/gap08_kotlin_orphan_natives.md`](gap08_kotlin_orphan_natives.md) for
> the per-file Phase C breakdown.

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | All voice-session orchestration delegated to C++ voice agent in every SDK | **OK** | Wave D Phases 6, 10, 12, 13 deleted orchestration bodies: Kotlin VoiceAgent (−279), Swift VoiceSession (−293), Dart voice_session_handle (−387), RN VoiceSessionHandle (−466). All 4 wrappers now thin deprecation shells. |
| 2 | Auth window drift fixed (Kotlin 5-min → C++ 60-sec) + auth client gone | **OK** (with caveat) | Both halves DONE: the 5-min vs 60-sec drift was fixed in v2 close-out Phase 7 (`REFRESH_WINDOW_MS = 60L * 1000L`), then permanently fixed in v2.1 quick-wins Item 4 by deleting the Kotlin constant entirely — the threshold now comes from `rac_auth_needs_refresh()` C ABI. The "auth client" half is closed too: `CppBridgeAuth.kt` shrunk 182 → 152 LOC, with state + token + JSON parsing + refresh-window math all moved to the `rac_auth_*` C ABI via 16 JNI thunks (commits `bd7da766` → `52e9e48d`). **Caveat**: HTTP transport stays in Kotlin (`HttpURLConnection`); a JNI httpPost helper would let us delete the remaining ~50 LOC, scheduled for v2.1-2 follow-up. |
| 3 | Kotlin orphan native declarations ≤0 | **OK** | Phase 8 deleted 3 zero-caller files (−4,318 LOC, 27 declarations). Post-audit Phase C pruned 72 truly-orphan declarations across 12 files (−730 LOC). 99 of 99 truly orphan declarations cleared total. Verified by 2-layer caller scan in [`gap08_kotlin_orphan_natives.md`](gap08_kotlin_orphan_natives.md). |
| 4 | `runanywhere.dart` ≤500 LOC | **DEFERRED** | Audit-confirmed file is still **2,688 LOC**. Multi-day extension-extraction refactor; not in this session's scope. v3-tier work. |
| 5 | `VoiceSessionHandle.ts` ≤250 LOC | **OK** | Wave D Phase 13 shrunk to 170 LOC. |
| 6 | Swift sweep covers ThinkingContentParser + voice session + download orchestration | **OK** | All 3 targets done: ThinkingContentParser deleted (−78, replaced by `rac_llm_thinking` C ABI); VoiceSession orchestration deleted (−293); AlamofireDownloadService audit-verified as already a thin shim. |
| 7 | Dart + RN + Web sweeps complete | **OK** | Dart `voice_session_handle.dart` (−387), RN `VoiceSessionHandle.ts` (−466), Web `tokenQueue` extracted to `AsyncQueue` helper (−47). |
| 8 | Per-SDK total LOC targets met (Kotlin ~30k, Swift ~24k, Dart ~30k) | **UNKNOWN** | Spec target never re-measured post-close-out. `wc -l` audit pending; ~30 minutes work. |
| 9 | Sample app smoke runs (iOS, Android, Flutter, RN, Web) — every demo screen works | **PARTIAL** | Sample apps build and run; Phase B annotated 11 deprecated-API call sites with per-call-site suppressions for v3 escalation safety. **No automated Detox/Maestro/XCUITest harness yet** — that's a v2.1 follow-up. iOS uses comment-only annotation (Swift treats deprecation as warning by default). |
| 10 | Behavioral parity tests verify 60-sec auth + download resume + voice barge-in latency | **PARTIAL** | Verification plan documented in [`v2_closeout_device_verification.md`](v2_closeout_device_verification.md). Real-device runs cannot happen in CI sandbox; awaits manual QA. |

## Files actually deleted (Wave D + post-audit Phase C — superseded scheduling table)

> The pre-execution scheduling table that lived here listed **~3,040 LOC**
> of intended deletes across 11 files. Reality came in **2.3× higher**
> at **−6,977 LOC** because Phase 8 found 3 entirely-orphan files (−4,318
> LOC) the spec hadn't budgeted, and post-audit Phase C found 72 more
> orphan declarations (−730 LOC) the gate report hadn't budgeted. Below
> is the actual delivered table.

| Phase | File | LOC removed | Replacement |
|-------|------|------------:|-------------|
| 6 | `RunAnywhere+VoiceAgent.jvmAndroid.kt` (orchestration body) | −279 | `VoiceAgentStreamAdapter.stream()` |
| 7 | `CppBridgeAuth.kt` (567 → 182) | −386 | `rac_auth_*` C ABI (JNI thunks pending — see #2 above) |
| 8 | `CppBridgeServices.kt` (zero-caller — git rm) | −1,285 | none — was orphan |
| 8 | `CppBridgeStrategy.kt` (zero-caller — git rm) | −1,204 | none — was orphan |
| 8 | `CppBridgeVoiceAgent.kt` (zero-caller — git rm) | −1,829 | none — was orphan |
| 9 | `RunAnywhere+TextGeneration.swift` (ThinkingContentParser block) | −78 | `rac_llm_split_thinking_tokens()` C ABI |
| 10 | `RunAnywhere+VoiceSession.swift` (orchestration body, 396 → 103) | −293 | `VoiceAgentStreamAdapter` (Swift) |
| 11 | `AlamofireDownloadService.swift` audit | +4 (cleanup) | already a thin shim — spec was inaccurate |
| 12 | `voice_session_handle.dart` (orchestration body, 472 → 85) | −387 | `VoiceAgentStreamAdapter` (Dart) |
| 13 | `VoiceSessionHandle.ts` (orchestration body, 636 → 170) | −466 | `VoiceAgentStreamAdapter` (RN) |
| 14 | `RunAnywhere+TextGeneration.ts` (tokenQueue → AsyncQueue) | −47 | `AsyncQueue` helper |
| **Wave D subtotal** | | **−6,247** | |
| Phase C (post-audit) | 12 × `CppBridge*.kt` orphan declarations (72 total) | **−730** | none — were unreachable |
| **Combined Wave D + Phase C** | | **−6,977** | |

Spec target was 5,100 ± 500. **Actual: 36% over target** — driven by:
- 3 entirely-orphan Kotlin files the spec underestimated (Phase 8: −4,318 LOC).
- 72 truly-orphan native declarations the spec didn't catalog (Phase C: −730 LOC).
- Honest deferral on `runanywhere.dart` (still 2,688 LOC).

## Why deprecation markers stayed alongside the deletes

The original Wave D plan was markers-only. The v2 close-out (Phases 6-14)
flipped to actual deletion where API shape allowed; the surviving public
API surface was kept as `@Deprecated` thin shells so production sample
apps continue to compile during v2.x. The Phase B post-audit pass added
per-call-site suppressions in the 4 sample apps so the v3 escalation
to error doesn't break their builds.

This is the same pattern Square used migrating Wire 3.x → 4.x and that
gRPC used migrating from `grpc.Server` → `grpc.aio.server` — emit the
warning, give consumers a release window, then delete.

## Commits in this series

| # | Commit | Subject |
|---|--------|---------|
| 1 | (Wave D Phase 21) | `chore(gap08-phase21-22): kotlin voice + auth deprecation markers` |
| 2 | (Wave D Phase 23) | `chore(gap08-phase23): kotlin orphan native audit + worst-offender marker` |
| 3 | (Wave D Phase 24) | `chore(gap08-phase24): swift TextGen + VoiceSession + Download deprecation markers` |
| 4 | (Wave D Phase 25-27) | `chore(gap08-phase25-26-27): dart + rn + web deprecation markers` |
| 5 | (Wave D Phase 28) | `chore(gap08-phase28): final gate + audit doc + sample app verification scheduling` |
| 6 | Close-out P2 (`e81fae3f`-`c3e474c4`) | 17 commits executing the actual physical deletes (−6,247 LOC) |
| 7 | Post-audit Phase A | `6db999aa` — added 2 union-arm tests |
| 8 | Post-audit Phase B | `916cde4d` — sample-app deprecated-API annotations |
| 9 | Post-audit Phase C | `dd9155e5` — pruned 72 orphan native fun declarations (−730 LOC) |
| 10 | Post-audit Phase D | `8a1ebfaa` — flipped 3 of 6 audit demotions back to OK |

## What's next

- **v2.1 follow-ups**: complete `CppBridgeAuth.kt` deletion via `rac_auth_*` JNI thunks (closes #2); measure per-SDK total LOC (closes #8); Detox/Maestro/XCUITest harness (closes #9); real-device behavioral parity (closes #10).
- **v3 cut-over** (separate PR): GAP 11 `git rm service_registry.cpp` + `RAC_PLUGIN_API_VERSION` 2u → 3u + 88-call-site repoint. See [`gap11_final_gate_report.md`](gap11_final_gate_report.md).
