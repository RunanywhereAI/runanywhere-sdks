# v2 Architecture — Current State Snapshot

> **Purpose**: Single-source-of-truth for "where is v2 right now and what
> remains?" after the v2 close-out + 3-agent re-audit + post-audit Phase
> A-D fix pass + post-Phase-A-D drift cleanup. If you read only one doc
> in `docs/`, read this one. Everything else is the receipts.
>
> **Last updated**: After commits `6db999aa` (Phase A) → `916cde4d`
> (Phase B) → `dd9155e5` (Phase C) → `8a1ebfaa` (Phase D) → drift cleanup
> commits on `feat/v2-architecture`.

## TL;DR — One paragraph

The v2 rearchitecture is **ship-ready as v2**. Of 9 architectural gaps
specified, 8 have shipped (GAP 05 is intentionally deferred). Of 6
post-audit demotions surfaced by the 3-agent re-review, **3 are now
fixed** (Phase A: union-arm test coverage; Phase B: sample-app
deprecation safety; Phase C: 99/99 truly orphan Kotlin natives cleared).
**3 remain PARTIAL** as honest v2.1 follow-ups (`VoiceSessionEvent`
codegen migration, cancellation parity behavioral test, p50 latency
benchmark).

**v3 cut-over SHIPPED (2026-04-19) — see `docs/v3_phaseB_complete.md`
and GAP 11 final gate report (#5 + #6 flipped to OK).** The following
are no longer deferred:

- `git rm sdk/runanywhere-commons/src/infrastructure/registry/service_registry.cpp` ✅
- `RAC_PLUGIN_API_VERSION` `2u` → `3u` in `rac/plugin/rac_plugin_entry.h` ✅
- Package-manifest bumps to 3.0.0 across 7 packages ✅
- 5 engines migrated from `rac_service_register_provider` to
  `rac_plugin_register` via `rac_engine_vtable_t` ✅
- 7 commons consumers rerouted from `rac_service_create` to
  `rac_plugin_route + vt->ops->create` ✅
- JNI + Swift bridges migrated to `rac_plugin_list` ✅

The only remaining v3 work is deprecated-SDK-surface cleanup
(`VoiceSessionEvent`, `VoiceSessionHandle`, `startVoiceSession`, etc.),
deferred to a focused v3.1 follow-up PR — see
`docs/v3_phaseC2_scope.md` for the disposition table.

## Numbers that matter

| Metric | Value | Notes |
|--------|-------|-------|
| LOC deleted from Wave D + Phase C targets | **−6,977** | Spec target was 5,100 ± 500 → **36% over target** |
| Net branch delta vs `8d1f851b` | ~−1,371 | Includes new infrastructure (+5,606) |
| Truly-orphan Kotlin native declarations cleared | **99 of 99** | Phase 8: 27 + Phase C: 72 |
| `test_proto_event_dispatch` | **11/11 OK** | All 7 union arms covered (was 9/9 / 5 of 7 pre-Phase-A) |
| `test_llm_thinking` | 10/10 OK | |
| `parity_test_cpp_check` | 8/8 events match golden | Wire-format parity across 6 implementations |
| Sample-app deprecated-API call sites annotated | **11 sites × 4 platforms** | Per-call-site suppressions; v3 escalation safe |
| GAP 08 spec criteria | 8 OK · 2 PARTIAL · 1 DEFERRED · 2 PARTIAL | #2 auth flipped to OK (v2.1 Item 4); #4 dart (DEFERRED), #6 kotlin LOC over (PARTIAL), #9 sample-smoke (PARTIAL), #10 device (PARTIAL) |
| GAP 09 spec criteria | 7 OK · 2 PARTIAL · 1 SPEC-DRIFT (intentional) | #6 closed in v2.1-1 (Swift full + 3 scaffolds + Web trivially-satisfied); #7 cancellation parity, #8 p50 still PARTIAL |

## Architecture as built (1-line per layer)

- **C ABI** (`rac_*` opaque handles, struct-based) — legacy `rac_service_*` DELETED in v3.0.0 (Phase C1). Sole registry surface is `rac_plugin_*`.
- **Plugin ABI** (`rac_engine_vtable_t` + central registry + dynamic `dlopen`) — **`RAC_PLUGIN_API_VERSION = 3u`** (v3.0.0).
- **Engines** under `engines/` (6 migrated: llamacpp, llamacpp_vlm, onnx, whispercpp, whisperkit_coreml, metalrt + 3 stubs) — register via `RAC_STATIC_PLUGIN_REGISTER` / `rac_plugin_register` only.
- **IDL** (`idl/*_service.proto`) — single source of truth; codegen → 9 gRPC stubs in 3 langs + Nunjucks-templated TS AsyncIterable wrappers.
- **Streaming adapters** (5 langs) — wrap C proto-event callbacks as `AsyncStream` / `Flow` / `Stream` / `AsyncIterable`.
- **CMake** — single root + 9 preset families; 6 native + 5 frontend CI jobs in `pr-build.yml` (151 lines, was 601).
- **Hardware Profile + Engine Router** — scores plugins by primitive × format × HW × hints; commons consumers (`rac_llm_create` etc.) go through `rac_plugin_route + vt->ops->create`.

## What shipped per gap

| Gap | What shipped | Status |
|-----|--------------|--------|
| GAP 01 — IDL & codegen | 7 protos + 5-language codegen + drift-check CI | OK |
| GAP 02 — Unified engine plugin ABI | `rac_engine_vtable_t` + registry + version check; `RAC_PLUGIN_API_VERSION` bumped `2u→3u` in v3.0.0 | OK |
| GAP 03 — Dynamic plugin loading | `dlopen` + `RAC_STATIC_PLUGIN_REGISTER` + plugin-loader-smoke test | OK (spec-drift on doc filename — minor) |
| GAP 04 — Engine router + HW profile | `rac::router::HardwareProfile` + scoring + 6 engines populate metadata; `rac_plugin_route` is now the SOLE routing API | OK (engine roster differs from spec — accepted deviation) |
| GAP 05 — DAG runtime | — | **DEFERRED** per spec gate |
| GAP 06 — Engines top-level reorg | 6 backends `git mv`'d; 3 stubs added | OK partial (5 migrated still use original CMakeLists; one-liner only on stubs) |
| GAP 07 — Single root CMake | Root + presets + 4 helper modules + slim CI | OK (v2.1 quick-wins removed commons/CMakePresets.json — single preset file now canonical) |
| GAP 08 — Frontend duplication delete | −6,977 LOC across 11 files in 5 SDKs + 16 JNI thunks for auth (v2.1 Item 4) | 8 OK · 2 PARTIAL · 1 DEFERRED · 1 PARTIAL |
| GAP 09 — Streaming consistency | 3 service .protos + 9 gRPC stubs + 5 adapters + golden producer + VoiceSessionEvent derived-view migration (v2.1-1 + v3 Phase A) | 7 OK · 2 PARTIAL · 1 intentional spec-drift |
| GAP 11 — Legacy cleanup | v3.0.0 C1: `service_registry.cpp` physically deleted; v3.0.0 C3: API version bumped to `3u`, semver 3.0.0 on 7 packages | **OK** (v3.0.0) |

## What's TRULY remaining (post v3.0.0)

**Tier 1 — v3.1 follow-up PR** (committed-to scope, 1 PR):

| # | Item | Closes | Effort |
|---|------|--------|--------|
| v3.1-1 | Migrate 4 sample-app voice-assistant views to `VoiceAgentStreamAdapter` + proto events (iOS, Android, Flutter, RN) | C2 prerequisite | 3-5 days |
| v3.1-2 | Delete `VoiceSessionEvent` + `VoiceSessionHandle` + `startVoiceSession` / `streamVoiceSession` / `processVoice` + `startStreamingTranscription` across Swift / Kotlin / Dart / RN | C2 backlog | 1 day (after v3.1-1) |
| v3.1-3 | Audit & delete remaining RN deprecations (`getTTSVoices`, `getLogLevel`, `SDKErrorCode`) | C2 backlog | 0.5 day |

See `docs/v3_phaseC2_scope.md` for full disposition table.

**Tier 2 — Remaining spec-criterion closures** (mechanical, 1 PR each):

| # | Item | Closes | Effort |
|---|------|--------|--------|
| T2-1 | 5-SDK behavioral cancellation parity test harness | GAP 09 #7 | 1 wk |
| T2-2 | Per-SDK p50 latency benchmark (30-sec harness × 5 SDKs) | GAP 09 #8 | 3 days |
| T2-3 | Sample-app E2E smoke automation (Detox/Maestro/XCUITest/Espresso) | GAP 08 #9 | 1 wk |
| T2-4 | Real-device behavioral parity verification | GAP 08 #10 | 1 wk QA |
| T2-5 | NDK pin single source of truth — hoist to root `gradle.properties` | GAP 07 #11 | 1 day |
| T2-6 | Swift `Package.swift` gRPC-Swift dep wiring (OR remove committed `.grpc.swift` files) — `GRPCCore` imports currently don't resolve via SPM | Swift build hygiene | 0.5 day |

**Tier 3 — Large refactors**:

- `runanywhere.dart` 2,688 → ≤500 LOC — GAP 08 #4 DEFERRED, multi-day refactor; not release-blocking.
- Kotlin LOC trim — GAP 08 PARTIAL (60% over target); multi-day refactor.

**Tier 4 — Optional / deferred indefinitely**:

- GAP 05 — DAG runtime; defer until a second pipeline (multi-modal RAG, agent loop) commits to using the primitives.

## Risk register (still-open items)

| Risk | Mitigation status |
|------|-------------------|
| Sample-app regression invisible to CI | OPEN — needs T2-3 |
| ~~Auth divergence if backend changes refresh policy~~ | **CLOSED** by v2.1 quick-wins Item 4 |
| ~~`VoiceSessionEvent` schema drift~~ | **CLOSED** by v2.1-1 + v3 Phase A (all 4 SDKs have real mapper bodies now — Swift/Kotlin/Dart/RN; Web trivially satisfied) |
| ~~v3 cut-over needs 88-call-site repoint~~ | **CLOSED** by v3.0.0 Phase B (consumer reroute) + Phase C1 (registry deletion) |
| ~~Per-SDK total-LOC criteria unmeasured~~ | **CLOSED** by v2.1 quick-wins Item 1 |
| `p50 ≤ 1ms` claim unproven | PARTIAL — harness shipped; per-SDK runner integration is the T2-2 follow-up. C++ producer measures 362 ns/event locally. |
| CI environment drift | OPEN — pin Homebrew/NDK/Flutter versions |
| ~~Sample apps fail to build on v3 escalation~~ | **MITIGATED** — deprecated shims retained in v3.0.0; deletion in v3.1 with sample-app migration |
| ~~Kotlin orphan native UnsatisfiedLinkError~~ | **CLOSED** by Phase C (99/99 cleared) |
| ~~Test coverage gap on 2 voice union arms~~ | **CLOSED** by Phase A (11/11 OK) |
| Swift SPM `GRPCCore` import fails | OPEN — `Package.swift` ships committed `.grpc.swift` sources but doesn't declare grpc-swift as a dep; SPM resolution fails for external consumers. T2-6 closes. |

## v3-readiness PR — Phase A complete (cross-SDK consumption)

The v3-readiness plan has 3 phases; Phase A closed the audit-flagged
"broken replacement path" blockers + achieved cross-SDK parity for
the LLM thinking C ABI. 11 commits `c95608e6` → `8038c141`.

### Audit demotion closures (all 4 broken replacement paths FIXED)

| # | Symbol | Before Phase A | After Phase A |
|---|--------|----------------|---------------|
| 1 | Kotlin `VoiceAgentStreamAdapter.nativeRegisterCallback` | declared, no JNI → `UnsatisfiedLinkError` at runtime | **FIXED** (commit `c95608e6` — JNI trampoline wraps `rac_voice_agent_set_proto_callback`) |
| 2 | Dart `../core/native/rac_native.dart` | imported but file missing | **FIXED** (commit `65e7fee8` — created with typed `RacBindings` facade) |
| 3 | RN `../generated/NitroVoiceAgentSpec` + `voice_agent_service` | imports unresolvable → doesn't compile | **FIXED** (commits for A3 — Nitro spec + HybridVoiceAgent.{cpp,hpp} + 3 generated TS files) |
| 4 | Web `_rac_voice_agent_set_proto_callback` | calls the symbol but WASM export list didn't include it | **FIXED** (commit for A4 — added to RAC_EXPORTED_FUNCTIONS + RACommons.exports + created EmscriptenModule.ts runtime) |

### Per-SDK × new-API matrix — AFTER Phase A

| API | Swift | Kotlin | Dart | RN | Web |
|-----|:-----:|:------:|:----:|:---:|:---:|
| `rac_voice_agent_set_proto_callback` | ✓ | ✓ (A1) | ✓ (A2) | ✓ (A3) | ✓ (A4) |
| `VoiceSessionEvent.from/fromProto` mappers (no more null stubs) | ✓ | ✓ (A5) | ✓ (A6) | ✓ (A7) | ✓ (shared with RN) |
| `rac_llm_extract_thinking` | ✓ | ✓ (A8) | ✓ (A9) | ✓ (A10) | ✓ (A11) |
| `rac_llm_strip_thinking` | ✓ | ✓ (A8) | ✓ (A9) | ✓ (A10) | ✓ (A11) |
| `rac_llm_split_thinking_tokens` | ✓ | ✓ (A8) | ✓ (A9) | ✓ (A10) | ✓ (A11) |

All 5 SDKs now consume the new v2 commons C ABIs symmetrically. The
remaining audit items (rac_plugin_route / rac_registry_load_plugin
not exposed through SDK FFI) are scoped separately to v3.x since app
code generally doesn't need them — backend packages register at init.

### Phase A, B, C — ALL SHIPPED in v3.0.0

Phase B (12 commits `c721a9c6` → `fd8c9e7c`) — migrated C++ first-party
code off `rac_service_*`:
  - B0: ABI extension (added `create` op to 7 per-primitive ops structs)
  - B1-B7: 6 engines + 2 commons registers migrated to the unified
    plugin registry
  - B8: 7 commons consumers rerouted through `rac_plugin_route +
    vt->ops->create`
  - B9-B10: 6 JNI sites + Swift CppBridge+Services migrated to
    `rac_plugin_list`
  - B11: grep audit confirms zero `rac_service_*` CODE references in
    first-party trees (only historical comments remain)

Phase C1 (`7dc2cbdc`) — physically deleted `service_registry.cpp` (311
LOC) + `rac_core.h` legacy block (163 LOC) + Swift CRACommons mirror
(118 LOC) + Dart ffi_types typedefs + 12 export entries across 3
lists. Net `-604` LOC.

Phase C2 (`eee8fe79`) — deleted `buildRegistrationJSON` helper; scope-
narrowed the broader deprecated-SDK-surface cleanup (VoiceSessionEvent,
VoiceSessionHandle, startVoiceSession, etc.) to a v3.1 follow-up PR
because the 4 sample apps still consume those types. See
`docs/v3_phaseC2_scope.md`.

Phase C3 (`b55d41ff`) — `RAC_PLUGIN_API_VERSION` bumped `2u → 3u`;
semver 3.0.0 shipped across all 7 SDK package manifests. GAP 11 final-
gate criteria #5 and #6 flipped to **OK**.

Verification:
  - `cmake --preset macos-release` + `rac_commons` + 3 engine targets
    build cleanly under the v3 ABI.
  - `test_proto_event_dispatch` 11/11 OK.
  - Grep audit: zero first-party `rac_service_*` function calls
    (only historical comments in 6 files).

## v2.1 quick-wins PR — what landed (post drift cleanup)

After the post-audit Phase A-D + drift cleanup, a v2.1 quick-wins PR
landed 4 items closing additional spec criteria and v2.1 follow-ups:

| Item | Commits | Closes | LOC delta |
|------|---------|--------|----------:|
| Item 1: Per-SDK LOC measurement | `0156ec77` | GAP 08 #6/#7/#8 (v2.1-6) | +33 doc |
| Item 2: 6 P4 spec-drift fixes (CMakeLists comment, plugin doc rename, second `CMakePresets.json` deletion, IDL drift-check substitution, retroactive `GAP_11` spec, NDK pin hoist) | `3f7eadb0` | P0-3, P4-1, P4-4, P4-5, P4-6, P4-8 | −54 net |
| Item 3: p50 latency bench harness (`tests/streaming/perf_bench/`) | `016ead14` | GAP 09 #8 measurement infra (v2.1-3 partial) | +600 |
| Item 4: 16 `rac_auth_*` JNI thunks + `CppBridgeAuth.kt` shrink | `bd7da766` `13e79d3c` `52e9e48d` `ba145f25` | GAP 08 #2 (v2.1-4) | +207 native, −30 Kotlin |
| **v2.1-1**: `VoiceSessionEvent` → codegen'd proto across 5 SDKs (Swift full + 3 scaffolds + Web audit) | `540deec2` `52ae409d` `47c3f36d` `6b4e3cb3` `64661d07` | GAP 09 #6 (v2.1-1) | +80 Swift mapper, +131 migration doc, ~+180 LOC of scaffolds across Kotlin/Dart/RN/Web |

After v2.1 quick-wins + v2.1-1:
- **8 of 9** P4 spec-drift items closed (P4-3, P4-7 explicitly scoped out — engine CMake one-liner rewrites and end-to-end ModelFormat propagation test, both warrant their own PRs).
- **GAP 08 #2 OK**, **#6 OK**, **#7 OK**, **#8 OK** (was UNKNOWN/PARTIAL).
- **GAP 09 #6 OK** (was PARTIAL — flipped in v2.1-1).
- **GAP 09 #8 measurement infra DONE**; per-SDK runner integration is the v2.1-2 follow-up.
- **4 of 7 v2.1 follow-ups DONE** (v2.1-1 with per-SDK-runtime-completion caveat, v2.1-3 partial, v2.1-4, v2.1-6); 3 still open (v2.1-2, v2.1-5, v2.1-7).
- **GAP 09 at 7/10 OK · 2 PARTIAL · 1 intentional SPEC-DRIFT** (best state achievable without per-SDK runtime rewiring).

## Per-SDK LOC measurement (post Phase A-D + drift cleanup)

Closes the GAP 08 #6/#7/#8 measurement gap that the post-audit flagged
as UNKNOWN. Methodology: `find ... -name "*.{kt,swift,dart,ts}" |
xargs wc -l`, excluding generated files (`*.pb.swift`, `*.grpc.swift`,
`*.pb.dart`, `*.pbgrpc.dart`, `*.pbenum.dart`, `*.pbjson.dart`,
`*.pb.ts`), tests, and build artifacts (`build/`, `.gradle/`,
`.dart_tool/`, `node_modules/`, `dist/`).

| SDK | Source LOC | Generated LOC | Test LOC | Total | Spec target | Status |
|-----|-----------:|--------------:|---------:|------:|------------:|--------|
| Kotlin           | **48,020** |     0 |    56 |  48,076 | ~30,000 | **PARTIAL** — 60% over target |
| Swift            | **24,820** | 5,353 |   161 |  30,334 | ~24,000 | **OK** — 3% over (at target) |
| Flutter (Dart)   | **33,634** | 5,580 |     0 |  39,214 | ~30,000 | **OK** — 12% over (within tolerance) |
| React Native     | **25,284** |     0 |     0 |  25,284 | (no spec target) | n/a |
| Web              | **21,553** |     0 |    67 |  21,620 | (no spec target) | n/a |

**Headline finding**: Kotlin is the outlier at 48,020 LOC (60% over the
~30k spec target). Root cause: the surviving 21 `CppBridge*.kt` files
account for ~17,000 LOC alone — the spec underestimated the per-feature
JNI bridge layer required for KMP. A v3 cleanup PR could shrink this by
auto-generating the boilerplate `external fun` + `racXxx` thunk pattern
from the C ABI headers (similar to how `swift-protobuf` generates
typesafe wrappers); estimated ~10k LOC reduction, deferred to v3.

**Status flips**:
- GAP 08 #6 (Kotlin ~30k): **UNKNOWN → PARTIAL** (over target; rationale documented).
- GAP 08 #7 (Swift ~24k): **UNKNOWN → OK** (24,820 vs 24,000 target = 3% over, at noise floor).
- GAP 08 #8 (Dart ~30k): **UNKNOWN → OK** (33,634 vs 30,000 target = 12% over, within typical spec tolerance).

## Doc map (read in order)

1. **THIS DOC** — current state snapshot.
2. [`wave_roadmap.md`](wave_roadmap.md) — wave-by-wave delivery vs original plan.
3. [`v2_remaining_work.md`](v2_remaining_work.md) — actionable prioritized list with file paths and effort.
4. [`v2_closeout_results.md`](v2_closeout_results.md) — close-out + post-audit Phase A-D deliveries (the receipts).
5. [`v2_migration_complete.md`](v2_migration_complete.md) — narrative post-mortem.
6. Per-gap reports: [`gap01`](gap01_final_gate_report.md), [`gap02`](gap02_final_gate_report.md), [`gap03`](gap03_final_gate_report.md), [`gap04`](gap04_final_gate_report.md), [`gap06`](gap06_final_gate_report.md), [`gap07`](gap07_final_gate_report.md), [`gap08`](gap08_final_gate_report.md), [`gap09`](gap09_final_gate_report.md), [`gap11`](gap11_final_gate_report.md).
7. Audit support: [`gap08_kotlin_orphan_natives.md`](gap08_kotlin_orphan_natives.md), [`gap11_audit_repoint.md`](gap11_audit_repoint.md), [`v2_closeout_device_verification.md`](v2_closeout_device_verification.md).

## Decision

**Ship as v2** (PR #494) once one of these happens:
- The 3 remaining audit demotions are explicitly deferred to a v2.1 minor release (recommended; the v2.1 work is 3 weeks total and orthogonal to v2 ship-readiness), OR
- All 3 demotions land on this branch (adds ~3 weeks to v2).

**Defer** the v3 cut-over (Tier 3) to a separate PR after v2 ships and bakes for a release window.
