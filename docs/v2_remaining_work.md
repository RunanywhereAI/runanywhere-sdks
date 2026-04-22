# v2 — Remaining Work to Ship

> **STATUS UPDATE (post-v2-closeout)**: P0, P1, and P2 are **DONE** as of the
> v2 close-out (Phases 0 through 16 on `feat/v2-architecture`). See
> [`docs/v2_closeout_results.md`](v2_closeout_results.md) for the LOC delta
> tables and per-criterion status flips. **What remains: P3 (v3 cut-over),
> P4 (spec-drift cleanups), P5 (Wave E — still optional/deferred).**

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
| P2-3 | **Kotlin orphans** | Run the symbol-diff procedure from `gap08_kotlin_orphan_natives.md`; delete the unbound `external fun native*` declarations across the 14 `CppBridge*.kt` files. 88 candidates today. | None — pure delete | 1 wk | GAP 08 #3 |
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
| P4-1 | GAP 03: spec called for `docs/plugins/PLUGIN_AUTHORING.md`; we shipped `docs/plugin_loader_authoring.md`. | Rename or symlink — trivial. |
| P4-2 | GAP 04: spec listed `fluid_audio`, `foundation_models`, `system_tts` as router targets. Branch ships `llamacpp`, `onnx`, `whispercpp`, `whisperkit_coreml`, `metalrt` + 3 stubs. | Accept the deviation; update spec to match the actual engine roster. |
| P4-3 | GAP 06: 5 migrated engines kept their original CMakeLists. Spec criterion #2 wants every engine to use `rac_add_engine_plugin()` one-liner. | Rewrite per engine in a follow-up cleanup PR; not blocking. |
| P4-4 | GAP 07: a second `CMakePresets.json` remains under commons. | `git rm` after engine reorg cleanup. |
| P4-5 | GAP 09: spec demanded `idl/codegen/check-drift.sh` extension; we use `.github/workflows/idl-drift-check.yml`. | Document the substitution in the gate report. |
| P4-6 | GAP 11: no `v2_gap_specs/GAP_11_LEGACY_CLEANUP.md` exists in the repo. The gate report cites it. | Either write the spec retroactively or remove the citation. |
| P4-7 | GAP 01 #11: spec wanted a "test PR proves single-commit propagation" of a new `ModelFormat` field. Never executed. | One short PR adding a no-op enum value end-to-end would close it. |
| P4-8 | NDK pin (GAP 07 criterion #11) lives in 3 places (root preset env var + Kotlin `gradle.properties` + Flutter Android Gradle). Spec wants single source of truth. | Hoist to a top-level `gradle.properties` shared variable. |

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
