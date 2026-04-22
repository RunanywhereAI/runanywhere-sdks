# v2 — Remaining Work to Ship

> **STATUS UPDATE (post-v2-closeout + 3-agent re-audit + Phase A-D fix pass)**:
> P0, P1, and P2 are **structurally DONE** as of the v2 close-out (17 commits
> between `e81fae3f` and `c3e474c4` on `feat/v2-architecture`). LOC deltas and
> tests verified by re-audit. The audit demoted 6 of the close-out's
> spec-criteria flips; **3 of those 6 were FIXED in the post-audit Phase A-C
> pass** (4 commits between `6db999aa` and the gate-doc commit):
>
> - **GAP 09 Phase 2 test coverage**: 9/9 → 11/11 (added PROCESSED + WAKEWORD union arm tests). FIXED.
> - **GAP 08 #3 orphan natives**: 95 declared → 23 (with callers) + 72 pruned (-730 LOC). FIXED.
> - **P3.5 sample-app risk**: 11 lines × 4 platforms annotated with per-call-site `@Suppress` / migration notes. MITIGATED.
>
> See the [Post-audit Phase A-D deliveries section in
> v2_closeout_results.md](v2_closeout_results.md#post-audit-phase-a-d-deliveries)
> for the per-phase table.
>
> **What remains in priority order:**
> - **P3** (v3 cut-over — `git rm service_registry.cpp`, bump `RAC_PLUGIN_API_VERSION`)
> - **P4** (spec-drift cleanups, NDK pin hoist, etc.)
> - **P5** (Wave E — still optional/deferred)
>
> Plus the v2.1-tier follow-ups (the 3 post-audit demotions that need real
> code, not annotations — separated from the auth/sample-app work which is
> orthogonal):
>
> | # | Item | Closes | Effort |
> |---|------|--------|--------|
> | v2.1-1 | Wire `VoiceSessionEvent` to use the codegen'd proto type in 5 SDKs (Kotlin `VoiceAgentTypes.kt`, Swift `VoiceAgentTypes.swift`, Dart `voice_session.dart`, RN `VoiceAgentTypes.ts` + `VoiceSessionHandle.ts`) | GAP 09 #6 | ~1-2 wk |
> | v2.1-2 | 5-SDK behavioral cancellation parity test harness (asserts cancellation propagates identically: Swift `AsyncStream.onTermination`, Kotlin `awaitClose`, Dart `StreamController.onCancel`, TS `AsyncIterator.return()`) | GAP 09 #7 | ~1 wk |
> | v2.1-3 | Per-SDK p50 latency benchmark for VoiceEvent streaming (30-second harness × 5 SDKs) | GAP 09 #8 | ~3 days |
> | v2.1-4 | Implement 16 `rac_auth_*` JNI thunks in `sdk/runanywhere-commons/src/jni/`; `git rm CppBridgeAuth.kt` (currently 182 LOC of HTTP/JSON state) | GAP 08 #2 | ~2 days |
> | v2.1-5 | Sample-app E2E smoke automation (Detox for RN, Maestro for Flutter, XCUITest for iOS, Espresso for Android) | GAP 08 #9 | ~1 wk |
> | ~~v2.1-6~~ | ~~`wc -l` measurement of per-SDK total LOC vs spec targets~~ **DONE in v2.1 quick-wins PR Item 1**: Kotlin 48,020 (60% over → PARTIAL), Swift 24,820 (at target → OK), Dart 33,634 (12% over → OK). See `v2_current_state.md` "Per-SDK LOC measurement". | GAP 08 #6/#7/#8 | DONE |
> | v2.1-7 | Real-device behavioral parity verification (60-sec auth refresh, voice barge-in latency, download resume after disconnect) per `v2_closeout_device_verification.md` | GAP 08 #10 | ~1 wk QA |

_Synthesis of the post-Wave-F audit (3 independent code-reality + spec-vs-gate + build-state passes)._

This was the prioritized list at the end of Wave F. Sections P0-P2 below are now **historical** — they're crossed through to keep the spec-traceability while documenting that they actually shipped. Read this together with [`wave_roadmap.md`](wave_roadmap.md) (state map) and [`v2_migration_complete.md`](v2_migration_complete.md) (post-mortem). Each item below cites the spec criterion and the file(s) that needed to change.

## Priority 0 — Build sanity

These block every other check. Address first.

| # | Item | Why | Effort | Files |
|---|------|-----|--------|-------|
| P0-1 | Get a green `cmake --preset macos-release` on a real machine (no network sandbox). FetchContent for `nlohmann_json` blocked the audit; CI hasn't run the new presets either. | Without this we can't measure spec criterion GAP 07 #5 (build < 10 min) or know that the `engines/` reorg + commons forwarding is wired correctly. | ½ day | `runanywhere-sdks-main/CMakeLists.txt`, `CMakePresets.json`, all `engines/*/CMakeLists.txt` |
| P0-2 | Run `pr-build.yml` end-to-end at least once. The slim 150-line workflow has not exercised the macos-debug, linux-debug, ios-device, android-arm64 jobs against the new presets in CI yet. | Confirms criteria GAP 07 #4, #5, #6, #9. | ½ day (CI rerun) | `.github/workflows/pr-build.yml` |
| P0-3 | Strip the stale comment in root `CMakeLists.txt` saying "backends still live under `commons/src/backends/` until GAP 06 lands" — they already moved. | Doc drift; trivial. | 5 min | `runanywhere-sdks-main/CMakeLists.txt` (around L114-115) |

## Priority 1 — Streaming end-to-end (close the GAP 09 gate)

GAP 09 ships the *contract*; consumers don't use it yet because GAP 08 still holds the orchestration. Closing the streaming loop unblocks Wave D.

| # | Item | Why | Effort | Files |
|---|------|-----|--------|-------|
| P1-1 | Implement `rac::voice_agent::dispatch_proto_event()` body in `rac_voice_event_abi.cpp` — currently a TODO stub. Wire it into the agent's event loop so the proto callback actually fires. | Without this the 5 adapters compile but emit zero events. | 2 days | `sdk/runanywhere-commons/src/features/voice_agent/rac_voice_event_abi.cpp`, `voice_agent.cpp` |
| P1-2 | Generate `*.grpc.swift` (Swift), `*.pbgrpc.dart` (Dart), Python `*_pb2_grpc.py` by running the per-language scripts in CI. Spec criteria GAP 09 #1, #3 currently MISSING. | The codegen infra is ready (`generate_swift.sh`, `generate_dart.sh`); just hasn't been run + checked in. | 1 day | Run `idl/codegen/generate_all.sh`, commit the generated files; verify `idl-drift-check.yml` is happy |
| P1-3 | Land the parity-test fixture: 10-second `parity_input.wav` + `golden_events.txt`. Remove `XCTSkipIf(true)` from all 4 `parity_test.*` files. | Spec criterion GAP 09 #7 (cancellation), #8 (no loss/reorder, p50 ≤ 1ms). | 3 days | `tests/streaming/fixtures/`, `tests/streaming/parity_test.{swift,kt,dart,ts}` |
| P1-4 | Add the C++ producer side `tests/streaming/parity_test.cpp` — the README references it but the file isn't on disk. | Golden producer asserted in spec gate. | 1 day | `tests/streaming/parity_test.cpp` (new) |
| P1-5 | Wire all `parity_test.*` into the per-SDK test runners (XCTest, JUnit, `flutter test`, Jest). Today they exist as orphan files not registered with any test harness. | Otherwise the gate is unverifiable. | 1 day | per-SDK test config |

## Priority 2 — Wave D physical deletes (the bulk of the missing v2 work)

The deprecation markers are in place; now do the actual deletions one platform at a time, after sample-app verification per the GAP 08 schedule.

Each row is one PR. Estimates from the original plan budget.

| # | Platform | Files (delete or shrink) | Replacement | Effort | Spec gate |
|---|----------|---------------------------|-------------|--------|-----------|
| P2-1 | **Kotlin voice** | Delete `streamVoiceSession` + `processVoice` orchestration in `RunAnywhere+VoiceAgent.jvmAndroid.kt` (~270 LOC). **The `streamVoiceSession` function lacks even the marker today — add `@Deprecated` first, then delete.** | `VoiceAgentStreamAdapter(handle).stream()` | 2 wk | GAP 08 #1, #6 |
| P2-2 | **Kotlin auth** | `git rm CppBridgeAuth.kt` (~568 LOC). Spec #2: literally "auth client gone". | `rac_auth_*` C ABI via JNI bridge | 1 wk | GAP 08 #2 |
| ~~P2-3~~ | ~~**Kotlin orphans**~~ **SUPERSEDED by post-audit Phase C (commit `dd9155e5`)**: 72 truly-orphan declarations pruned across 12 of 13 surviving CppBridge*.kt files (−730 LOC). 23 declarations remain, all with at least one in-file caller (verified by 2-layer scan). GAP 08 #3 → OK. | — | DONE | GAP 08 #3 |
| P2-4 | **Swift TextGen** | Delete `ThinkingContentParser` block in `RunAnywhere+TextGeneration.swift`. | `rac_llm_split_thinking_tokens()` C ABI (needs to be added to commons) | 1 wk + 3 days for C ABI | GAP 08 #6, #7 |
| P2-5 | **Swift VoiceSession** | Delete orchestration in `RunAnywhere+VoiceSession.swift` (currently 396 LOC). | `VoiceAgentStreamAdapter` (Swift) | 1 wk | GAP 08 #6, #7 |
| P2-6 | **Swift Download** | Delete retry/progress in `AlamofireDownloadService.swift`. | `rac_download_*` C ABI + `DownloadServiceStreamAdapter` (mechanical follow-up to VoiceAgent adapter) | 1 wk | GAP 08 #6, #7 |
| P2-7 | **Dart sweep** | Shrink `runanywhere.dart` from 2,688 → ≤500 lines (spec criterion #4). Delete `voice_session_handle.dart` orchestration. Move `_mapDownloadStage`, `_inferFormat`, `_saveToCppRegistry` to C ABI. | `voice_agent_stream_adapter.dart` + C helpers | 2 wk | GAP 08 #4, #8 |
| P2-8 | **RN sweep** | Shrink `VoiceSessionHandle.ts` from 636 → ≤250 lines (spec criterion #5). | `Adapters/VoiceAgentStreamAdapter.ts` | 1 wk | GAP 08 #5 |
| P2-9 | **Web sweep** | Delete `tokenQueue: string[]` + `resolveNext` in `RunAnywhere+TextGeneration.ts`. Delete legacy `NativeEventEmitter` block in `EventBus.ts`. | `LLMTokenStream` (build per Phase 14 template) | 1 wk | GAP 08 #6 |
| P2-10 | **Behavioral parity** | Test 60-sec auth refresh window, download resume after disconnect, voice barge-in latency. Sample app smoke runs on iOS, Android, Flutter, RN, Web. | — | 1 wk | GAP 08 #10 |

**Net delete after P2 complete:** ~3,040 LOC tracked (per `gap08_final_gate_report.md`). Spec target was 5,100±500.

## Priority 3 — GAP 11 physical removal (v3 cut-over)

After Wave D + soak, do the layout-incompatible struct removal. This is the v2 → v3 boundary.

| # | Item | Effort |
|---|------|--------|
| P3-1 | Repoint the 30 files / 88 references in `gap11_audit_repoint.md`. Per-call-site `rac_service_create` → `rac_plugin_route`, `rac_service_register_provider` → `rac_plugin_registry_register`. Verify per platform. | 2 wk |
| P3-2 | `git rm sdk/runanywhere-commons/src/infrastructure/registry/service_registry.cpp` + headers. Delete `rac_capability_t` and `rac_service_provider_t`. | 1 day after P3-1 |
| P3-3 | Bump `RAC_PLUGIN_API_VERSION` from `2u` to `3u` in `rac_plugin_entry.h`. | 5 min |
| P3-4 | Bump library version to v3.0.0 (semver major). Update `VERSION` file. | 5 min |

## Priority 4 — Spec drift fixes (cleanup)

Items where the spec was specific and we drifted. Either backfill or document the deviation.

| # | Item | Recommendation |
|---|------|----------------|
| ~~P4-1~~ | ~~GAP 03: spec called for `docs/plugins/PLUGIN_AUTHORING.md`; we shipped `docs/plugin_loader_authoring.md`.~~ **DONE in v2.1 quick-wins Item 2**: `git mv` to spec path; 4 backlinks updated. |
| P4-2 | GAP 04: spec listed `fluid_audio`, `foundation_models`, `system_tts` as router targets. Branch ships `llamacpp`, `onnx`, `whispercpp`, `whisperkit_coreml`, `metalrt` + 3 stubs. | Accept the deviation; update spec to match the actual engine roster. |
| P4-3 | GAP 06: 5 migrated engines kept their original CMakeLists. Spec criterion #2 wants every engine to use `rac_add_engine_plugin()` one-liner. | Rewrite per engine in a follow-up cleanup PR; not blocking. |
| ~~P4-4~~ | ~~GAP 07: a second `CMakePresets.json` remains under commons.~~ **DONE in v2.1 quick-wins Item 2**: deleted; root `CMakePresets.json` is canonical. |
| ~~P4-5~~ | ~~GAP 09: spec demanded `idl/codegen/check-drift.sh` extension; we use `.github/workflows/idl-drift-check.yml`.~~ **DONE in post-audit drift cleanup**: documented as accepted deviation in `gap09_final_gate_report.md` criterion #10 (SPEC-DRIFT). |
| ~~P4-6~~ | ~~GAP 11: no `v2_gap_specs/GAP_11_LEGACY_CLEANUP.md` exists in the repo. The gate report cites it.~~ **DONE in v2.1 quick-wins Item 2**: spec written retroactively at `v2_gap_specs/GAP_11_LEGACY_CLEANUP.md` reverse-engineered from the gate report. |
| P4-7 | GAP 01 #11: spec wanted a "test PR proves single-commit propagation" of a new `ModelFormat` field. Never executed. | One short PR adding a no-op enum value end-to-end would close it. |
| ~~P4-8~~ | ~~NDK pin (GAP 07 criterion #11) lives in 3 places (root preset env var + Kotlin `gradle.properties` + Flutter Android Gradle). Spec wants single source of truth.~~ **PARTIAL DONE in v2.1 quick-wins Item 2**: hoisted to root `gradle.properties` (`racNdkVersion=27.0.12077973`); 5 sites read from it (3 in Kotlin SDK build.gradle.kts, 1 in root, 1 in Android sample). Flutter packages still pin 25.2.9519653 (intentional Flutter-plugin compat); convergence to single version is a v3 task. Documented as `racFlutterNdkVersion` separately. |

## Priority 5 — Optional (Wave E / GAP 05)

Defer until a second pipeline (multi-modal RAG, agent loop) commits to using the DAG primitives. Today's `voice_agent.cpp` works without them. **No action recommended now.**

---

## How to use this document

- **For the next coding session:** start at P0, work through P1, then take P2 platform-by-platform (each is a self-contained PR).
- **For PR review:** P2 items map 1:1 to the GAP 08 final-gate "Files marked for deletion" table — same files, same LOC targets, with the addition of the `streamVoiceSession` Kotlin function which today lacks even the deprecation marker.
- **For release planning:** v2 PR #494 = current branch (Waves A through F deprecation). v3 = P3 + finalized v2. Wave E remains optional.

## Audit methodology

Three parallel agents on `feat/v2-architecture` HEAD:
1. **Code reality**: reading the actual files vs gate-report claims, table-by-table per gap.
2. **Spec vs gate**: cross-referencing each `v2_gap_specs/GAP_0[1-9].md` Success Criterion against its `docs/gap0*_final_gate_report.md` row.
3. **Build sanity**: `cmake --preset` smoke + per-file LOC + parity-test wiring + concrete remaining-work synthesis.

All three found the same story: build infra and contracts shipped real; deletes are deferred. This doc is the merged action list.

---

## Risk register (post-v2-closeout, surfaces from 3-agent re-audit)

What could go wrong in the next 30 days if v2 ships as-is. Each row is "what breaks → which file/line → mitigation".

| Risk | Trigger | Affected | Mitigation |
|------|---------|----------|------------|
| ~~**Sample apps fail to build** if any deprecated API is escalated to error~~ | ~~Bumping `DeprecationLevel.WARNING` → `ERROR` (Kotlin) or `@available(*, deprecated, .obsoleted)` (Swift)~~ | ~~`examples/android/.../VoiceAssistantViewModel.kt` (lines 23-24, 319, 795, 1029); `examples/ios/.../VoiceAgentViewModel.swift` (169, 398); `examples/flutter/.../voice_assistant_view.dart` (29, 159-160); `examples/react-native/.../VoiceAssistantScreen.tsx` (41, 71, 237)~~ | **MITIGATED in post-audit Phase B (commit `916cde4d`):** all 11 sites annotated with per-call `@Suppress` / `// ignore` / `eslint-disable` + migration-target comments. v3 escalation no longer blocks. |
| **Sample-app regression invisible to CI** | Any close-out change introduces a runtime bug only visible at app level | `pr-build.yml` builds the SDKs but NOT `examples/*/RunAnywhereAI/` apps | Add per-platform sample-app build job (Detox/Maestro/XCUITest); track as v2.1 task. |
| ~~**`UnsatisfiedLinkError` at runtime** if anyone calls a Kotlin orphan native~~ | ~~Production code path that touches one of the ~95 unbound `external fun native*` declarations across 13 surviving CppBridge*.kt files~~ | ~~`gap08_kotlin_orphan_natives.md` audit; 13 files~~ | **CLOSED in post-audit Phase C (commit `dd9155e5`):** the 72 truly-orphan declarations (verified via 2-layer caller scan: in-file AND `Class.fn` SDK-wide) deleted. The surviving 23 declarations all have at least one in-file caller (verified post-prune); their JNI symbols ship in `librunanywhere_jni.so` (verified by deduction — non-orphan + compiles + ships). |
| **Auth divergence** if backend changes refresh policy | Kotlin `CppBridgeAuth.kt` still maintains its own state references (181 LOC) instead of delegating to `rac_auth_*` C ABI | `sdk/runanywhere-kotlin/.../CppBridgeAuth.kt` | Implement 16 `rac_auth_*` JNI thunks in `sdk/runanywhere-commons/src/jni/`; `git rm` the file. ~2 days. |
| **`VoiceSessionEvent` schema drift** | Hand-written `VoiceSessionEvent` (in `VoiceAgentTypes.swift` + corresponding files in 4 other SDKs) silently diverges from the codegen'd `VoiceEvent` proto | Spec GAP 09 #6 "zero hand-written `VoiceSessionEvent`" still unmet | Have voice session API consume the codegen'd proto type directly; mechanical follow-up. |
| **v3 cut-over needs 88-call-site repoint** | `RAC_PLUGIN_API_VERSION` 2u → 3u + `git rm service_registry.cpp` would require 88 references (per `gap11_audit_repoint.md`) to be repointed first | engines/*, JNI, Swift/Flutter ffi declarations | Track as P3 prerequisite work; cannot bump until done. |
| **Kotlin/Swift/Dart total-LOC spec criteria unmeasured** | GAP 08 #6, #7, #8 (Kotlin ~30k, Swift ~24k, Dart ~30k) — never re-measured post-close-out | Spec compliance unprovable | `wc -l` over each SDK and document; ~30 minutes. |
| **`p50 ≤ 1ms` claim unproven** for streaming on all 5 SDKs | GAP 09 #8 spec line not benched | None — wire-format parity is verified; per-SDK perf is the open question | Add a 30-second perf bench per SDK; track as v2.1. |
| **CI environment drift** breaks `pr-build.yml` | Homebrew flake, NDK r27c download URL change, Flutter 3.38.x removal from `subosito/flutter-action`, grpc-swift v2 brew formula change | All 11 jobs in `.github/workflows/pr-build.yml` | Pin Homebrew commits; vendor NDK; track Flutter pin upgrades. |
| ~~**Test coverage gap on 2 voice union arms**~~ | ~~`RAC_VOICE_AGENT_EVENT_PROCESSED` and `RAC_VOICE_AGENT_EVENT_WAKEWORD_DETECTED` are dispatched in code but not asserted in `test_proto_event_dispatch.cpp`~~ | ~~`sdk/runanywhere-commons/tests/test_proto_event_dispatch.cpp`~~ | **CLOSED in post-audit Phase A (commit `6db999aa`):** added `test_processed_arm` and `test_wakeword_arm`. Suite is now 11/11 OK locally (`./build/macos-release/sdk/runanywhere-commons/tests/test_proto_event_dispatch`). |

---

## What's NOT a risk (audit confirmation)

The audit also explicitly cleared these worries:

- **`runanywhere.dart` 2,688 LOC**: confirmed as a real multi-day refactor, not a hidden quick win. Honest deferral.
- **`AlamofireDownloadService.swift` 474 LOC**: confirmed already a thin shim; the spec's "180 LOC of duplication" was wrong.
- **`EventBus.ts` 206 LOC**: confirmed has no legacy `NativeEventEmitter` block to delete (Web SDK never had one — RN-only API).
- **Auth refresh window bug fix**: `REFRESH_WINDOW_MS = 60L * 1000L` confirmed in `CppBridgeAuth.kt` line 65 with the `rac_auth_needs_refresh()` reference.
- **gRPC stub generation**: 9 stubs (3 services × 3 langs) confirmed on disk. The original "12+" claim was loose phrasing; actual is 9.
