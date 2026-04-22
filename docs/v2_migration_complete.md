# v2 Architecture Migration — Status & Post-Mortem

_Living document. **Post-v2-closeout + 3-agent audit + Phase A-D fix pass + drift cleanup: READY TO SHIP
as v2** (with follow-up PRs scheduled for v3 cut-over + the 3 remaining v2.1 items)._

**What's true after the post-audit Phase A-D pass + drift cleanup:**

- The close-out's LOC claims (−6,247 from Wave D targets) are **verified correct on disk**. Post-audit Phase C added another **−730 LOC** from pruning 72 truly-orphan native declarations; **combined Wave D + Phase C delete: −6,977 LOC** (36% over the 5,100 ± 500 spec target).
- All 8 bugs the close-out reports finding are **verified fixed**.
- The 3 close-out test suites are **verified building + passing**:
  - `test_proto_event_dispatch`: **11/11 OK** (was 9/9; Phase A added 2 union-arm tests for PROCESSED + WAKEWORD_DETECTED).
  - `test_llm_thinking`: 10/10 OK.
  - `parity_test_cpp_check`: 8/8 OK.
- **6 of the close-out's spec-criteria status flips were too generous**; the post-audit Phase A-D pass closed 3:
  - GAP 09 Phase 2 test coverage: **PARTIAL → OK** (Phase A).
  - GAP 08 #3 orphan natives: **PARTIAL → OK** (Phase C; 99 of 99 truly orphan declarations cleared).
  - P3.5 sample-app risk: **PRODUCTION RISK → MITIGATED** (Phase B; 11 sample-app call sites annotated).
- **3 demotions are still PARTIAL** — these need real refactor work (not annotations) and are queued for v2.1:
  - GAP 09 #6 — `VoiceSessionEvent` still hand-written in 5 SDKs (~1-2 weeks).
  - GAP 09 #7 — Cancellation parity by-design, not 5-SDK behaviorally tested (~1 week).
  - GAP 09 #8 — Per-SDK p50 latency not benched (~3 days).

**Net assessment:** the v2 program ships. The post-audit corrections + Phase A-D pass + drift cleanup leave 3 honest open items, all v2.1-tier. The v3 cut-over (GAP 11 `git rm service_registry.cpp` + 88-call-site repoint + `RAC_PLUGIN_API_VERSION` 2u → 3u) is a separate ~2-week PR.

## TL;DR

- **33 phases** across **6 waves** committed to `feat/v2-architecture`.
- **9 architectural gaps** (`v2_gap_specs/GAP_0[1-9].md` + the
  reverse-engineered "GAP 11") have final-gate reports under
  `docs/gap0*_final_gate_report.md`.
- **Wave E (GAP 05 DAG runtime)** explicitly deferred per spec.
- **Waves A, B, C are substantively shipped** — IDL + codegen, plugin
  ABI + dynamic loading + router, root CMake + presets + engines/
  reorg, and the streaming adapter contract across all 5 SDKs.
- **Wave D (GAP 08 frontend deletion sweep) and Wave F (GAP 11 legacy
  removal) shipped *deprecation pressure*, not the *physical deletes*
  the gate-report tables initially claimed.** The orchestration bodies
  marked `@Deprecated` in Wave D still execute; `service_registry.cpp`
  is still on disk; `RAC_PLUGIN_API_VERSION` is still `2u`.
- This is the same shape as Square Wire 3.x→4.x and gRPC
  `Server`→`aio.server` migrations: emit deprecation, give consumers a
  release window, then delete in v3.

## Audit reality check (post Phase A-D + drift cleanup)

Three independent audits have happened: (1) the original Wave-F audit,
(2) the post-close-out 3-agent re-review that surfaced the 6 demotions,
and (3) a fresh 3-agent audit after the Phase A-D pass that confirmed
the demotion fixes and surfaced the doc-drift items now corrected. The
findings live in [`wave_roadmap.md` "Audit snapshot"](wave_roadmap.md#audit-snapshot--what-is-on-the-branch-right-now)
and the prioritized list in
[`v2_remaining_work.md`](v2_remaining_work.md).

| What is real on disk today | What's still deferred |
|----------------------------|----------------------|
| Root `CMakeLists.txt` + `CMakePresets.json` + `cmake/{platform,sanitizers,plugins,protobuf}.cmake` | Verifying `cmake --preset macos-release` configures + builds + tests **in CI** (works locally; CI run not yet kicked off) |
| `engines/` with 5 migrated backends (history preserved) + 3 stub engines | The 5 migrated engines using `rac_add_engine_plugin()` one-liners (still use original CMakeLists) |
| `idl/voice_agent_service.proto` + `llm_service.proto` + `download_service.proto` | — |
| **9 generated gRPC stubs** (3 services × Swift/Dart/Python) — committed, CI drift-checked | — |
| `rac_voice_event_abi.h/.cpp` C++ proto-byte ABI; `RAC_ABI_VERSION=2u` | — |
| **`dispatch_proto_event()` body is fully implemented** — translates all 7 union arms to `runanywhere::v1::VoiceEvent`; **11/11 tests OK** post Phase A | — |
| 5 `VoiceAgentStreamAdapter` files (Swift / Kotlin / Dart / RN / Web) | Consumer code migration to consume codegen'd `VoiceEvent` proto (GAP 09 #6, v2.1) |
| **4 `parity_test.*` files wired (XCSkipIf removed)** + C++ golden producer + `golden_events.txt` fixture | Per-SDK test runner integration (XCTest/JUnit/`flutter test`/Jest) — local-only today |
| `@Deprecated` + `[[deprecated]]` + `@available(*, deprecated)` markers on Wave-D target files | — |
| **−6,977 LOC actually deleted** from Wave D + Phase C targets (Kotlin orphan files Phase 8: −4,318; per-SDK orchestration shrinks Phase 6/9/10/12/13/14: −1,929; Phase C orphan declarations: −730) | `runanywhere.dart` 2,688 (spec ≤500) — DEFERRED, multi-day refactor |
| `[[deprecated]]` + `rac_legacy_warn_once` on `rac_service_*` (GAP 11) | `git rm service_registry.cpp` + 88-call-site repoint + `RAC_PLUGIN_API_VERSION` 2u → 3u — **v3 cut-over PR** |
| Sample-app per-call-site deprecation suppressions (Phase B) | Detox/Maestro/XCUITest sample-app smoke automation (v2.1) |

**Aggregate diff vs branch start (`8d1f851b`):** post Phase A-D, the net branch delta is approximately **−1,371 LOC** (−744 at close-out + the Phase B/C/D deltas).

**What this means for the program:**

- **PR #494 in its current form is a v2 ship**, not a v2-foundation PR. The contracts (plugin ABI, router, IDL, streaming adapters), the deletes (−6,977 LOC), the proto-event dispatch implementation, and 11/11 union-arm test coverage are all real on disk.
- **A v2 release tag** (semver minor) is appropriate as soon as the 3 remaining v2.1 items below either land or are explicitly punted to a follow-up minor:
  - GAP 09 #6 — `VoiceSessionEvent` codegen migration in 5 SDKs.
  - GAP 09 #7 — Cancellation parity 5-SDK behavioral test harness.
  - GAP 09 #8 — Per-SDK p50 latency benchmark.
- **A v3 release tag** (semver major) is the right boundary for the GAP 11 cut-over (`git rm service_registry.cpp` + `RAC_PLUGIN_API_VERSION` 3u).

## Architecture as built

```
runanywhere-sdks-main/
├── CMakeLists.txt                  ← root project (GAP 07 P1)
├── CMakePresets.json               ← 9 preset families (GAP 07 P2)
├── cmake/
│   ├── platform.cmake              ← rac_detect_platform()      (GAP 07 P3)
│   ├── sanitizers.cmake            ← rac_apply_sanitizer()      (GAP 07 P3)
│   ├── plugins.cmake               ← rac_add_engine_plugin()    (GAP 07 P4)
│   │                                  + rac_force_load()
│   └── protobuf.cmake              ← rac_protobuf_generate()    (GAP 07 P5)
├── scripts/
│   ├── setup-toolchain.sh          ← protoc + plugins (incl. GAP 09 grpc)
│   ├── build-core-android.sh       ← preset → jniLibs/          (GAP 07 P6)
│   ├── build-core-xcframework.sh   ← preset → Binaries/         (GAP 07 P6)
│   └── build-core-wasm.sh          ← preset → dist/wasm/        (GAP 07 P6)
├── idl/                            ← Protobuf IDL — single source of truth
│   ├── README.md
│   ├── model_types.proto           ← consolidated enums         (GAP 01)
│   ├── voice_events.proto          ← VoiceAgent event union     (GAP 01)
│   ├── pipeline.proto              ← DAG spec (Wave E target)   (GAP 01)
│   ├── solutions.proto             ← VoiceAgent / RAG configs   (GAP 01)
│   ├── voice_agent_service.proto   ← gRPC stream                (GAP 09 P12)
│   ├── llm_service.proto           ← LLMToken stream            (GAP 09 P12)
│   ├── download_service.proto      ← DownloadProgress stream    (GAP 09 P12)
│   ├── CMakeLists.txt              ← rac_idl static lib
│   └── codegen/
│       ├── generate_all.sh         ← orchestrator
│       ├── generate_swift.sh       ← swift-protobuf + grpc-swift (GAP 13)
│       ├── generate_kotlin.sh      ← Wire (KMP-safe)             (GAP 01)
│       ├── generate_dart.sh        ← protoc_plugin + grpc out    (GAP 09 P13)
│       ├── generate_python.sh      ← protoc + grpc_tools         (GAP 09 P13)
│       ├── generate_ts.sh          ← ts-proto                    (GAP 01)
│       ├── generate_cpp.sh         ← protoc                      (GAP 01)
│       ├── generate_rn_streams.sh  ← Nunjucks → AsyncIterable    (GAP 09 P14)
│       ├── generate_web_streams.sh ← Nunjucks → AsyncIterable    (GAP 09 P14)
│       └── templates/
│           └── ts_async_iterable.njk                             (GAP 09 P14)
├── engines/                        ← top-level engine plugins   (GAP 06)
│   ├── CMakeLists.txt              ← orchestrator
│   ├── llamacpp/                   ← (was sdk/.../src/backends/) (GAP 06 P8)
│   ├── llamacpp/jni/
│   ├── onnx/
│   ├── whispercpp/
│   ├── whisperkit_coreml/
│   ├── metalrt/
│   ├── sherpa/                     ← NEW stub                    (GAP 06 P10)
│   ├── genie/                      ← NEW stub for QNN routing    (GAP 06 P10)
│   └── diffusion-coreml/           ← NEW stub                    (GAP 06 P10)
├── tools/
│   └── plugin-loader-smoke/        ← CLI dlopen smoke test       (GAP 06 P11)
├── tests/
│   └── streaming/
│       ├── README.md                                             (GAP 09 P20)
│       └── parity_test.{swift,kt,dart,ts}                        (GAP 09 P20)
├── sdk/
│   ├── runanywhere-commons/        ← C++ core (was monolithic project)
│   │   ├── CMakeLists.txt          ← redirected to engines/* paths
│   │   ├── include/rac/
│   │   │   ├── plugin/             ← unified plugin ABI          (GAP 02 + GAP 03 + GAP 04)
│   │   │   │   ├── rac_primitive.h           ← + runtime_id_t   (GAP 04)
│   │   │   │   ├── rac_engine_vtable.h       ← + runtimes/formats (GAP 04)
│   │   │   │   ├── rac_plugin_entry.h        ← API_VERSION 2u   (GAP 04)
│   │   │   │   └── rac_plugin_loader.h       ← dlopen ABI       (GAP 03)
│   │   │   ├── router/             ← Engine router               (GAP 04)
│   │   │   │   ├── rac_routing_hints.h
│   │   │   │   ├── rac_hardware_profile.h
│   │   │   │   ├── rac_engine_router.h
│   │   │   │   └── rac_route.h     ← C ABI shim
│   │   │   ├── core/rac_core.h     ← rac_service_* [[deprecated]] (GAP 11 P29)
│   │   │   └── features/voice_agent/
│   │   │       └── rac_voice_event_abi.h   ← proto-byte callback (GAP 09 P15)
│   │   └── src/
│   │       ├── plugin/             ← registry + loader impl      (GAP 02-03)
│   │       ├── router/             ← scoring + hardware detect   (GAP 04)
│   │       ├── features/voice_agent/
│   │       │   └── rac_voice_event_abi.cpp                       (GAP 09 P15)
│   │       └── infrastructure/registry/
│   │           └── service_registry.cpp ← legacy + warn_once    (GAP 11 P29)
│   ├── runanywhere-swift/
│   │   └── Sources/.../Adapters/
│   │       └── VoiceAgentStreamAdapter.swift                     (GAP 09 P16)
│   ├── runanywhere-kotlin/
│   │   └── src/.../adapters/
│   │       └── VoiceAgentStreamAdapter.kt                        (GAP 09 P17)
│   ├── runanywhere-flutter/
│   │   └── packages/runanywhere/lib/adapters/
│   │       └── voice_agent_stream_adapter.dart                   (GAP 09 P18)
│   ├── runanywhere-react-native/
│   │   └── packages/core/src/Adapters/
│   │       └── VoiceAgentStreamAdapter.ts                        (GAP 09 P19)
│   └── runanywhere-web/
│       └── packages/core/src/Adapters/
│           └── VoiceAgentStreamAdapter.ts                        (GAP 09 P19)
└── .github/workflows/
    ├── pr-build.yml                ← 601 → 150 lines (GAP 07 P7)
    └── idl-drift-check.yml         ← unchanged from GAP 01
```

## Wave / GAP scoreboard

| Wave | GAP | Spec target | Phases | LOC delta | Final-gate report |
|------|-----|-------------|--------|-----------|-------------------|
| Pre-A | 01 | IDL + codegen | 6 | +~3,500 | `gap01_final_gate_report.md` |
| Pre-A | 02 | Unified plugin ABI | 4 | +~1,200 | `gap02_final_gate_report.md` |
| A | 03 | Dynamic plugin loading | 7 | +~800 | `gap03_final_gate_report.md` |
| A | 04 | Engine router + HW profile | 5 | +~600 | `gap04_final_gate_report.md` |
| B | 07 | Single root CMake | 7 | +~750, −5,485 | `gap07_final_gate_report.md` |
| B | 06 | engines/ top-level reorg | 4 | (mv only) +~250 | `gap06_final_gate_report.md` |
| C | 09 | Streaming consistency | 9 | +~1,400 | `gap09_final_gate_report.md` |
| D | 08 | Frontend duplication | 8 | markers only (~3,040 LOC scheduled for v3) | `gap08_final_gate_report.md` |
| F | 11 | Legacy cleanup | 3 | +~150 (deprecation infra) | `gap11_final_gate_report.md` |
| E | 05 | DAG runtime primitives | — | DEFERRED | `wave_roadmap.md` §"Wave E" |

**Net LOC delta in this PR:** roughly +8,650 / −5,485 (mostly the 11
legacy `build-*.sh` scripts deleted in GAP 07 Phase 7). The ~3,040 LOC
of orchestration deletes from Wave D + the 30-file `rac_service_*`
repoint from Wave F land in v3.

## What v2 unlocks

1. **One source of truth for cross-language types.** Any change to
   `model_types.proto` or `voice_events.proto` is automatically
   reflected in Swift / Kotlin / Dart / TS / Python via the
   ci-drift-check workflow. Type-drift bugs (e.g. the documented
   Kotlin 5-min vs Swift 60-sec auth refresh) are caught at code-review
   time.

2. **One way to register an engine plugin.** Anywhere the spec says
   "an engine plugin," it means: drop a `rac_plugin_entry_<name>`
   function returning a `const rac_engine_vtable_t*` somewhere on the
   plugin search path, and the registry picks it up. Static (linked
   into rac_commons via `RAC_STATIC_PLUGIN_REGISTER` + the
   `rac_force_load` cmake helper) on iOS/WASM, dlopen-loaded on
   Android/Linux/macOS/Windows.

3. **One way to route to an engine.** `rac_plugin_route(&request,
   &result)` ranks every registered plugin by primitive match,
   `HardwareProfile` capability, format support, priority, and
   per-call hints. Replaces N hand-written router-per-domain
   call sites.

4. **One streaming contract.** `idl/voice_agent_service.proto` +
   `idl/llm_service.proto` + `idl/download_service.proto` are the
   shared service definitions. Each language gets one ~150-LOC
   adapter that wraps the C proto-byte callback as the language's
   idiomatic stream type. Replaces 5 hand-written orchestrators.

5. **One way to build for any platform.** `cmake --preset <name>` +
   `cmake --build --preset <name>` works for macOS, Linux (Debug /
   Release / ASan), Android (arm64 / armv7 / x86_64), iOS (device /
   simulator), and WASM. The wrapper scripts package artifacts for
   each frontend SDK; CI uses the same commands a developer types
   locally.

## What's deferred to v3

1. Physical `git rm` of `service_registry.cpp` + the
   `rac_capability_t` / `rac_service_provider_t` types it defines.
2. `RAC_PLUGIN_API_VERSION` bump 2u → 3u (struct-layout-incompatible).
3. Physical delete of the Wave D orchestration bodies marked
   `@Deprecated` / DEPRECATED in this PR (~3,040 LOC).
4. Per-call-site repoint of the 30 files that still call `rac_service_*`
   (per `docs/gap11_audit_repoint.md`).
5. Wave E (GAP 05 DAG runtime primitives) — gated on a second
   pipeline committing to use them.

## Files merged into PR #494 (this branch)

- 9 final-gate reports under `docs/gap0[1-9]_final_gate_report.md` +
  `docs/gap11_final_gate_report.md`.
- `docs/v2_migration_complete.md` (this file).
- `docs/wave_roadmap.md` (running map of remaining waves).
- `docs/voice_event_proto_handoff.md` (GAP 01 → GAP 09 contract).
- `docs/engine_plugin_authoring.md` + `docs/plugins/PLUGIN_AUTHORING.md`.
- `docs/gap08_kotlin_orphan_natives.md` + `docs/gap11_audit_repoint.md`.

Reviewers should start with `docs/wave_roadmap.md` for the high-level
shape, then drill into individual gate reports for evidence.
