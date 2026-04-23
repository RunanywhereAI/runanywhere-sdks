# Team Status — `feat/v2-architecture` Branch

_The one document to read before a status update. ~3-min read.
Last refreshed: 2026-04-22._

## In one paragraph

The `feat/v2-architecture` branch is **114 commits ahead of `main`**
and contains a full-stack re-platform of the RunAnywhere SDK per the
11-GAP spec set under [`v2_gap_specs/`](../v2_gap_specs/). It
introduces a new top-level repo layout (`engines/`, `idl/`, `tests/`,
root `cmake/` + `CMakeLists.txt`), a unified C plugin ABI
(`RAC_PLUGIN_API_VERSION = 3u`), proto-driven IDL/codegen as the
cross-language contract, and thin SDK adapters in all 5 languages
(Swift / Kotlin / Flutter / RN / Web). **9 of 10 in-repo GAPs are
closed** (GAP 10 spec was never written; GAP 05 ships only the
primitives, scheduler deferred per spec). **No version bumps have
been applied** — every package is at main's baseline (`0.19.13` /
Kotlin `0.1.5-SNAPSHOT`); the release decision is yours when the
branch is ready to merge.

## Branch state

- **Branch**: `feat/v2-architecture`
- **Commits ahead of `main`**: 114
- **Net diff vs `main`**: ~93k insertions / ~18k deletions / 543 files
- **Released?** No — feature branch only. All package versions equal
  main's baseline (see [Versions](#versions)).
- **Tests**: `test_proto_event_dispatch` 11/11, `test_graph_primitives`
  13/13, `perf_producer` 144 ns/event, `cancel_producer` clean.

## What changed architecturally

### New top-level dirs (didn't exist on main)

```
runanywhere-sdks-main/
├── cmake/              ← shared CMake helpers (plugins.cmake macro etc.)
├── engines/            ← per-engine plugins moved out of sdk/runanywhere-commons/src/backends/
├── idl/                ← *.proto + codegen scripts (single source of truth)
├── tests/              ← cross-SDK harnesses (parity, perf_bench, cancel_parity)
├── sdk/                ← (existed) per-language SDKs
├── examples/           ← (existed) sample apps for each platform
├── scripts/            ← (existed) build + release scripts
└── docs/               ← (existed) consolidated to 3 canonical docs + archive
```

### New unified C plugin layer

- `sdk/runanywhere-commons/include/rac/plugin/rac_plugin_entry.h` —
  `RAC_PLUGIN_API_VERSION = 3u`. (Did not exist on main.)
- `cmake/plugins.cmake` — `rac_add_engine_plugin()` macro used by 8/9
  engines (metalrt is OBJECT-library variant).
- `sdk/runanywhere-commons/src/infrastructure/registry/service_registry.cpp`
  — DELETED on this branch (was 272 LOC on main). All `rac_service_*`
  C ABI calls replaced with `rac_plugin_route` + plugin registry.

### Proto IDL drives every SDK

- `idl/voice_events.proto`, `voice_agent_service.proto`,
  `llm_service.proto`, `download_service.proto`, etc.
- Codegen scripts under `idl/codegen/generate_{cpp,swift,kotlin,dart,ts,python}.sh`
  emit per-language types into `sdk/<lang>/.../generated/`.
- `.github/workflows/ci-drift-check.yml` enforces no hand-edited
  generated code.

### Voice agent: hand-written → proto stream

Across all 5 SDKs, the deprecated `VoiceSessionEvent` /
`VoiceSessionHandle` / `startVoiceSession` API was DELETED. The
canonical voice path is now `VoiceAgentStreamAdapter(handle).stream()`
returning the proto-generated `VoiceEvent` type. Each SDK has a
~100-130 LOC adapter wrapping `rac_voice_agent_set_proto_callback`
into the language-idiomatic stream type:

| SDK | Stream type |
|---|---|
| Swift | `AsyncStream<RAVoiceEvent>` |
| Kotlin | `Flow<VoiceEvent>` |
| Dart | `Stream<VoiceEvent>` |
| RN / Web | `AsyncIterable<VoiceEvent>` |

## Per-GAP status

| GAP | Spec | Status | Evidence |
|---|---|---|---|
| 01 | IDL + codegen | **DONE** | 6 protos + 5-language codegen + drift CI |
| 02 | Unified engine plugin ABI | **DONE** | `rac_engine_vtable_t` + central registry; `rac_service_*` deleted |
| 03 | Dynamic plugin loading | **DONE (test depth deferred to QA)** | dlopen path + static registration + ABI version check |
| 04 | Engine router + HW profile | **DONE (iOS17/ANE device E2E deferred to QA)** | `EngineRouter` + `rac_plugin_route` C ABI |
| 05 | DAG runtime | **DONE (skeleton)** | `CancelToken`/`RingBuffer`/`StreamEdge` + 13 tests; `GraphScheduler`/`PipelineNode`/`MemoryPool` deferred per spec L63-64 (build when 2nd pipeline appears) |
| 06 | Engines top-level reorg | **DONE** | All 9 engines use `rac_add_engine_plugin()` (metalrt = OBJECT variant) |
| 07 | Single root CMake | **DONE** | Root `CMakeLists.txt` + `CMakePresets.json` + slim `pr-build.yml` + NDK pin in root `gradle.properties` |
| 08 | Frontend duplication delete | **MOSTLY DONE** | Kotlin orchestration (#1) deleted; Flutter god-class (#4) split into instance-method API; sample E2E (#9) + device parity (#10) = QA effort; Kotlin download (#3) blocked on commons HTTP-client vendor decision |
| 09 | Streaming consistency | **DONE** | All 9 criteria including cancel parity harness + per-SDK p50 < 1ms benchmark |
| 10 | _(no spec in repo)_ | N/A | GAP_10 spec was never written |
| 11 | Legacy cleanup | **DONE** | `service_registry.cpp` + `rac_service_*` deleted; voice-session shims deleted across all 5 SDKs |

**Gate reports** for each GAP live at [`docs/archive/gap-reports/`](archive/gap-reports/).

## What's left (per category)

### Engineering (small, ready to schedule)

1. **Swift xcframework publication** — script ready at
   [`scripts/release-swift-binaries.sh`](../scripts/release-swift-binaries.sh).
   Operator step requiring Xcode 15+ + GitHub release credentials +
   manual `third_party/onnxruntime-ios/onnxruntime.xcframework`
   prereq. Until run, external SPM consumers must use
   `useLocalNatives = true` in `Package.swift`.
2. **Pre-existing latent bugs surfaced during work** (not regressions
   — were already broken on main, just exposed):
   - `engines/whispercpp/rac_stt_whispercpp.cpp` includes a
     `rac_stt_whispercpp.h` that doesn't exist in source (only in
     v0.19.13 era xcframework). Building `rac_backend_whispercpp`
     fails when the engine is opted in. Bug-compat: macos-release
     preset doesn't enable it by default.
   - `engines/onnx/CMakeLists.txt` `RAG_DIR` resolves to a
     non-existent path, silently skipping
     `onnx_embedding_provider.cpp` from the build.
   - `engines/onnx/rac_backend_onnx_register.cpp` defines `g_onnx_*_ops`
     inside an anonymous namespace (works for STATIC archives /
     deferred resolution; would fail for SHARED). Same in llamacpp.

### Architectural (multi-month, vendor decisions needed)

3. **Kotlin GAP 08 #3** — moving HTTP transport from Kotlin into
   commons. Requires choosing a commons HTTP client (libcurl / cpr /
   platform-native shims). See
   [`docs/v3_2_kotlin_download_blocker.md`](v3_2_kotlin_download_blocker.md).
4. **Flutter API shape** — branch contains an INSTANCE-METHOD
   refactor (RunAnywhereSDK.instance.{capability}.method) wired as
   `@Deprecated` shim alongside the original static API. Whether to
   ship this as a v0.20+ minor (additive) or v1.0+ major (breaking
   delete of static class) is a release-strategy decision. See
   [`docs/migrations/v3_to_v4_flutter.md`](migrations/v3_to_v4_flutter.md).

### QA (out of engineering scope)

5. GAP 03 — real-model GGUF E2E + valgrind in CI
6. GAP 04 — iOS17 / ANE device E2E
7. GAP 08 #9 — sample app E2E (Detox / Maestro / XCUITest / Espresso)
8. GAP 08 #10 — real-device parity verification

### Indefinite (per spec)

9. GAP 05 — `GraphScheduler` / `PipelineNode` / `MemoryPool`. Spec
   marks as "build when 2nd pipeline needs them" (L63-64). Skeleton
   primitives are shipped + tested, ready for first consumer.

## Versions

**All packages at main's baseline** — no release has happened.

| Package | Version |
|---|---|
| `sdk/runanywhere-commons/VERSION` | `0.19.13` |
| `sdk/runanywhere-swift/VERSION` | `0.19.6` |
| `Package.swift sdkVersion` | `"0.19.13"` |
| `sdk/runanywhere-flutter/packages/{runanywhere,_genie,_llamacpp,_onnx}/pubspec.yaml` | `0.19.13` |
| `sdk/runanywhere-{web,react-native}/{,packages/*}/package.json` | `0.19.13` |
| `sdk/runanywhere-kotlin/build.gradle.kts` fallback | `0.1.5-SNAPSHOT` |

**No version bump until the team decides on a release strategy.** The
branch contains all the architectural work; tagging + publishing is
a separate operator step.

## Suggested release sequencing (when you decide to ship)

This is one viable path; alternatives are equally valid:

1. **Merge `feat/v2-architecture` → `main`** as a single squash or
   merge commit. The branch is internally consistent; partial-merge
   would lose the IDL/plugin coherence.
2. **Bump versions according to the change shape:**
   - C ABI is breaking (`rac_service_*` deleted, `RAC_PLUGIN_API_VERSION`
     2u→3u) → suggests **major version bump** for at least
     runanywhere-commons + every package that links it.
   - Voice-session shims deleted → breaking SDK API → **major bump**
     for all 5 SDKs.
   - Realistic candidates: `v1.0.0` (clean break from pre-v1 era),
     `v2.0.0` (matches the "v2 architecture" branch name), or just
     `v0.20.0` (treat as additive minor since 0.x semver allows
     breaking changes in minor releases).
3. **Publish artifacts**: run
   [`scripts/release-swift-binaries.sh`](../scripts/release-swift-binaries.sh)
   on a macOS box with credentials; `gh release create` for
   xcframework zips; `pub publish` / `npm publish` /
   `gradle publish` for the language packages.
4. **Migration guide for consumers**: a `docs/migrations/<from>_to_<to>.md`
   covering at minimum (a) deletion of `VoiceSessionEvent` / 
   `startVoiceSession` and the `VoiceAgentStreamAdapter` replacement,
   (b) deletion of `rac_service_*` for engine plugin authors.

## Doc map

If you want to dig deeper than this status doc:

| Topic | Read |
|---|---|
| Architecture overview + layout diagram | [`STATE_AND_ROADMAP.md`](STATE_AND_ROADMAP.md) |
| Per-GAP scoreboard with per-criterion detail | [`GAP_STATUS.md`](GAP_STATUS.md) |
| Chronological narrative (114-commit phasing) | [`HISTORY.md`](HISTORY.md) |
| Spec set being closed | [`../v2_gap_specs/`](../v2_gap_specs/) (10 files: GAP_01 … GAP_09, GAP_11) |
| Per-GAP closure evidence (commit SHAs, LOC tables) | [`archive/gap-reports/`](archive/gap-reports/) |
| Engine plugin authoring guide | [`engine_plugin_authoring.md`](engine_plugin_authoring.md) |
| DAG primitives user guide (GAP 05 skeleton) | [`graph_primitives.md`](graph_primitives.md) |
| Voice migration (v0.x → branch) | [`migrations/VoiceSessionEvent.md`](migrations/VoiceSessionEvent.md) |
| Flutter API-shape design doc | [`migrations/v3_to_v4_flutter.md`](migrations/v3_to_v4_flutter.md) |
| Kotlin download architectural blocker | [`v3_2_kotlin_download_blocker.md`](v3_2_kotlin_download_blocker.md) |
| Swift release script + operator runbook | [`../scripts/release-swift-binaries.sh`](../scripts/release-swift-binaries.sh) |

## Bottom line for the standup

> "The v2-architecture branch closes 9 of 10 GAPs from the original
> spec set. Build green; tests green; no version bumps yet. Two
> architectural items remain (Kotlin download HTTP-in-commons,
> Flutter API-shape decision) plus QA test automation work. Release
> sequencing is a separate decision when we're ready to merge to
> main."
