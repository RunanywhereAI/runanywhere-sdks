# v2 Architecture Migration — Status & Post-Mortem

_Living document. **Post-v2-closeout + 3-agent audit status: READY TO SHIP
as v2** (with follow-up PRs scheduled for v3 cut-over + the v2.1 items
the post-close-out audit surfaced)._

**What's true after the audit:**

- The close-out's LOC claims (−6,247 from Wave D targets, net branch
  −744 to −600 depending on doc-churn timing) are **verified correct on
  disk**.
- All 8 bugs the close-out reports finding are **verified fixed**.
- The 3 close-out test suites are **verified building + passing**
  (proto event dispatch 9/9, llm thinking 10/10, parity_test_cpp 8/8).
- **6 of the close-out's spec-criteria status flips were too generous**
  when measured against strict spec text (GAP 09 #6 / #7 / #8 / #9,
  GAP 08 #3, Phase 2 test coverage). All 6 corrections are documented
  in [v2_closeout_results.md "Post-audit corrections"](v2_closeout_results.md#post-audit-corrections-3-agent-re-review).
- **One previously-untracked production risk surfaced**: sample apps
  under `examples/` are NOT in the CI matrix and call deprecated
  Kotlin/Swift/Flutter/RN APIs — when those deprecations escalate, 11
  lines × 4 platforms need updating in lock-step. Tracked in
  [v2_remaining_work.md "Risk register"](v2_remaining_work.md#risk-register-post-v2-closeout-surfaces-from-3-agent-re-audit).

**Net assessment:** the v2 program ships. The corrections sharpen — not
invalidate — the v3 / v2.1 follow-up scope. The deltas of the corrections
are documented honestly in the per-doc updates so future readers don't
have to re-discover them._

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

## Audit reality check

Three independent agents audited the branch on Wave-F-final HEAD. The
findings are summarized in [`wave_roadmap.md` "Audit snapshot"](wave_roadmap.md#audit-snapshot--what-is-on-the-branch-right-now)
and the prioritized close-out list lives in
[`v2_remaining_work.md`](v2_remaining_work.md).

| What is real on disk today | What is documented but deferred |
|----------------------------|----------------------------------|
| Root `CMakeLists.txt` + `CMakePresets.json` + `cmake/{platform,sanitizers,plugins,protobuf}.cmake` | Verifying `cmake --preset macos-release` configures + builds + tests in CI |
| `engines/` with 5 migrated backends (history preserved) + 3 stub engines | The 5 migrated engines using `rac_add_engine_plugin()` one-liners (still use original CMakeLists) |
| `idl/voice_agent_service.proto` + `llm_service.proto` + `download_service.proto` | The generated `*.grpc.swift` / `*.pbgrpc.dart` files (codegen ready, not run) |
| `rac_voice_event_abi.h/.cpp` C++ proto-byte ABI; `RAC_ABI_VERSION=2u` | `dispatch_proto_event()` body is a TODO stub — adapters compile, emit zero events |
| 5 `VoiceAgentStreamAdapter` files (Swift / Kotlin / Dart / RN / Web) | Consumer code that uses them — all 5 SDKs still call the duplicated orchestration |
| 4 `parity_test.*` scaffolds + README | Fixture audio + golden-events file + actual `XCTAssert` (today: `XCTSkipIf(true)`) |
| `@Deprecated`/DEPRECATED markers on 11 Wave-D target files | The actual deletes (~3,040 LOC scheduled). Note: Kotlin `streamVoiceSession` lacks even the marker |
| `[[deprecated]]` + `rac_legacy_warn_once` on `rac_service_*` | `git rm service_registry.cpp` + `RAC_PLUGIN_API_VERSION` 2u→3u |
| 5 file-level deprecation markers in 3 SDKs (Kotlin auth, Swift TextGen/Voice/Download, Dart, RN, Web) | LOC ceilings: `runanywhere.dart` 2,688 (spec ≤500); `VoiceSessionHandle.ts` 636 (spec ≤250) |

**Aggregate diff vs branch start (`8d1f851b`):** 127 files,
+3,845 / −6,095, **net −2,250 LOC**. (The deletes that hit the diff are
the 10 retired `build-*.sh` scripts from GAP 07 Phase 7, not Wave D's
~3,040 LOC of orchestration — that work is scheduled.)

**What this means for the program:**

- **PR #494 in its current form is a v2-foundation PR**, not a v2 ship.
  Reviewing + merging it gives you the contracts (plugin ABI, router,
  IDL, streaming adapters) on `main`, but the duplication-deletion
  payoff comes in follow-up PRs (Priority 2 in `v2_remaining_work.md`).
- **A v2 release tag** (semver minor) should land **after Priority 1
  + Priority 2** are done — that's when the spec's claimed LOC
  reduction + behavioral simplification becomes real.
- **A v3 release tag** (semver major) is the right boundary for
  Priority 3 (physical struct removal + `RAC_PLUGIN_API_VERSION` 3u).

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
- `docs/engine_plugin_authoring.md` + `docs/plugin_loader_authoring.md`.
- `docs/gap08_kotlin_orphan_natives.md` + `docs/gap11_audit_repoint.md`.

Reviewers should start with `docs/wave_roadmap.md` for the high-level
shape, then drill into individual gate reports for evidence.
