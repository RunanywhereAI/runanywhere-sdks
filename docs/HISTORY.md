# Engineering History

_Chronological narrative of the v2 → v3.0 → v3.1 architectural
sprints. Brief — high-signal bullets per phase. Full per-phase
evidence (commit lists, LOC diffs, audit tables) lives at
[`archive/`](archive/). Updated: 2026-04-22._

## Timeline at a glance

| Date | Release | Theme |
|---|---|---|
| 2026-04 (early) | v2 close-out | Wire-format parity + delete duplicated frontend orchestration |
| 2026-04-19 | v3.0.0 | C ABI cut-over: delete `rac_service_*`; `RAC_PLUGIN_API_VERSION 2u → 3u` |
| 2026-04-22 | v3.1.0 | Sample app migrations + delete deprecated shims + DAG primitives + perf/cancel parity harnesses |
| 2026-04-22 | v3.1.1 | Doc refreshes (3 SDK API refs + engine authoring guide) + Swift release-tooling script |
| 2026-04-22 | v3.1.2 | 4 engine CMakeLists migrated to `rac_add_engine_plugin()` (onnx, whispercpp, whisperkit_coreml, metalrt); macro extended with TARGET_NAME / CXX_STANDARD / SHARED_ONLY / COMPILE_OPTIONS / LINK_OPTIONS |

---

## v2 close-out (early April 2026)

Closed the original 11-GAP sprint with a multi-wave delete pass that
removed ~6,977 LOC of duplicated orchestration across 5 SDKs.

**Headline deliverables:**
- 5 SDK frontend adapters wrap `rac_voice_agent_set_proto_callback`
  as language-idiomatic streams (Swift `AsyncStream`, Kotlin `Flow`,
  Dart `Stream`, RN/Web `AsyncIterable`).
- Wire-format parity test harness (`tests/streaming/parity_test.cpp`)
  + per-SDK byte-for-byte verification against `golden_events.txt`.
- 4 `*_service.proto` IDL files + Swift `*.grpc.swift`, Dart
  `*.pbgrpc.dart`, Python `*_pb2_grpc.py` codegen committed to tree.
- `rac_llm_thinking` C API for `<think>` block extraction
  (`test_llm_thinking`: 10/10).
- `dispatch_proto_event` wired to `runanywhere::v1::VoiceEvent`
  serialization (`test_proto_event_dispatch`: 11/11 after Phase A).
- Hand-written orchestrators deleted: Kotlin `RunAnywhere+VoiceAgent`
  body (~467 LOC), Swift `VoiceSessionHandle.start()` body, Dart
  `VoiceSessionHandle` actor, RN orchestration.

**Known issues at v2 ship** (later resolved):
- Swift CRACommons mirror header drift (fixed in v3.0.0 audit).
- `Package.swift sdkVersion` lagging (fixed in v3.0.0 audit).
- `service_registry.cpp` still present as marker-only
  (deleted in v3.0.0).

**Evidence:** [`archive/v2-closeout/`](archive/v2-closeout/) —
phase-by-phase records (baseline, build log, Phase 5 C ABIs,
device verification plan, results).

---

## v3.0.0 ABI cut-over (2026-04-19)

Physical deletion of the legacy `rac_service_*` registry. Marked
the architectural transition: there is no longer a "legacy" path.

**Headline deliverables:**
- `rac_service_*` (4 functions + the `service_registry.cpp` impl)
  PHYSICALLY DELETED. Zero first-party callers.
- `RAC_PLUGIN_API_VERSION 2u → 3u` (breaking ABI bump).
- Every `rac_*_service_ops_t` struct gained a `create` op pointer
  for direct backend instance allocation through the plugin
  registry.
- 7 commons consumers + 4 JNI bridges + 1 Swift CppBridge migrated
  off `rac_service_create` to `rac_plugin_route` + `vt->ops->create`.
- Apple platform services (Foundation Models, System TTS, CoreML
  Diffusion) packaged as a unified plugin entry
  (`rac_plugin_entry_platform.cpp`).
- 7 SDK packages bumped to semver `3.0.0`.

**Audit (post-ship)** surfaced 14 small bugs / drift items, all
fixed in a single commit (`b99c82b3`):
- 2 real ABI bugs (Swift CRACommons header staleness).
- 12 doc drift items (mostly version markers + ABI-version
  comments).

**Evidence:** [`archive/v3-evidence/v3_phaseB_complete.md`](archive/v3-evidence/v3_phaseB_complete.md),
[`archive/v3-evidence/v3_phaseB_gate_analysis.md`](archive/v3-evidence/v3_phaseB_gate_analysis.md)
(the "why we needed `create_impl`" decision record),
[`archive/v3-evidence/v3_audit_summary.md`](archive/v3-evidence/v3_audit_summary.md)
(post-release audit).

---

## v3.1.0 Full Architectural Cleanup (2026-04-22)

10-phase sprint closing all 13 remaining-work items from the v3.0.0
audit. Zero stubs; every deliverable is real implementation.

### Phase 1 — Unblockers
- Swift SPM gRPC issue: excluded the 3 `*.grpc.swift` files (they
  required macOS 15 / iOS 18; our floor is macOS 14 / iOS 17 — and
  the streams aren't used at runtime, `VoiceAgentStreamAdapter` is).
- MetalRT `CMakeLists.txt:41` — `${CMAKE_SOURCE_DIR}/include` →
  `sdk/runanywhere-commons/include`.
- 4 JNI `AttachCurrentThread` casts normalized to the canonical
  `reinterpret_cast<void**>(&env)` pattern (fixes macOS Temurin vs
  Android NDK skew).
- 4 Flutter plugin `build.gradle` files: hardcoded `ndkVersion
  "25.2.9519653"` hoisted to read `rootProject.property
  ("racFlutterNdkVersion")` from root `gradle.properties`.
- RN deprecation decisions doc (4 RN deprecated APIs categorized).

### Phase 2 — perf_bench scaffolds → real implementations
- New IDL field: `MetricsEvent.created_at_ns` (field 8;
  wire-compatible).
- C++ `perf_producer` rewrites timestamp injection to use the new
  field directly (was a hacky pack-into-tokens_generated workaround).
- 4 SDK consumer files rewritten with REAL proto decode +
  consumer-side `recvNs - producerNs` delta computation:
  - `perf_bench.swift` + `Tests/PerfBenchTests.swift` (XCTest)
  - `perf_bench.kt` + `jvmTest/.../PerfBenchTest.kt` (JUnit/Gradle)
  - `perf_bench.dart` + `test/perf_bench_test.dart` (flutter_test)
  - `perf_bench.ts` + `.rn.test.ts` (Jest) + `.web.test.ts` (Vitest)
- Each runner asserts p50 < 1ms (GAP 09 #8 spec).

### Phase 3 — Sample app migrations
4 commits, one per sample (iOS / Android / Flutter / RN). Each
swapped `RunAnywhere.startVoiceSession()` + `VoiceSessionEvent`
switch for `VoiceAgentStreamAdapter(handle).stream()` + proto
`event.payload` switch.

**Prerequisite work landed in this phase:**
- Kotlin: 4 new JNI thunks (`racVoiceAgentCreateStandalone` +
  `Initialize` + `IsReady` + `Destroy`) + new
  `CppBridgeVoiceAgent.kt` facade.
- RN: new Nitro `getVoiceAgentHandle(): Promise<number>` method on
  `RunAnywhereCore` + C++ impl reinterpreting the global handle as
  a JS double.

**Behavioral change:** assistant text is now streamed token-by-token
(typewriter UX) where it used to be batched as `.responded(fullText)`.

### Phase 4 — Delete deprecated SDK shims
4 commits, one per SDK family. ~1,800 LOC net deletion.

- **Swift**: `RunAnywhere+VoiceSession.swift` (entire file, 100 LOC),
  `VoiceSessionEvent` enum + `from(_:)` mapper (~90 LOC),
  `startStreamingTranscription` (10 LOC). `LiveTranscriptionSession`
  retained but rewired to `transcribeStream`.
- **Kotlin**: `VoiceSessionEvent` sealed class + Companion.from
  (~155 LOC), 3 expect/actual pairs (`processVoice`,
  `startVoiceSession`, `streamVoiceSession`).
- **Dart**: `voice_session.dart` + `voice_session_handle.dart`
  (entire files, ~500 LOC), `RunAnywhere.startVoiceSession` +
  `_processVoiceAgentAudio` (~90 LOC).
- **RN + Web**: `VoiceSessionHandle.ts` (entire file),
  `RunAnywhere+VoiceSession.ts` (entire file), 6 mapper helpers in
  `VoiceAgentTypes.ts` (~200 LOC), 3 RN misc deprecated APIs
  (`getTTSVoices`, `getLogLevel`, `startStreamingSTT`). Kept
  `SDKErrorCode` (audit fix — the @deprecated marker was misleading).

### Phase 5 — Quality gates
- New `tests/streaming/cancel_parity/` harness:
  - C++ `cancel_producer` emits 1,000 VoiceEvents with
    `InterruptedEvent` (reason=APP_STOP) at index 500.
  - 5 SDK consumer files: `cancel_parity.{swift,kt,dart,ts}`
    decode each frame, record `<ordinal> <kind> <recv_ns>` traces.
  - Python `compare_cancel_traces.py` aggregator verifies
    wire-parity (all SDKs see interrupt at same ordinal) +
    50ms latency budget.
- 5 test runners wired (CancelParityTests.swift, CancelParityTest.kt,
  cancel_parity_test.dart, cancel_parity.{rn,web}.test.ts).

### Phase 6 — CMake normalization (audit)
The `rac_add_engine_plugin()` macro already existed at
`cmake/plugins.cmake:59` (shipped GAP 07 Phase 4). Audit confirmed
4/9 engines use it. 5/9 retained hand-rolled CMake (each has heavy
per-platform / per-tool config: ONNX `find_package`, whisper.cpp
`FetchContent`, WhisperKit `swift build`, MetalRT Objective-C++).
Per-engine migration path documented for post-v3.1 PRs.

### Phase 7 — Flutter god-class split (analyzed + deferred)
Investigation surfaced a Dart language constraint: extension static
methods change call syntax (`X.method()` vs `Type.method()`); `part`
files can't split a class body; recommended path is API migration
to `RunAnywhere.instance.method()` (matches `supabase-dart`,
`firebase_core`). Multi-day breaking change deferred to v4.x.

### Phase 8 — Kotlin LOC trim (audit)
Total Kotlin SDK = 49,547 LOC. Top 5 files (1,358-1,485 LOC each)
are canonical CppBridge facades, not duplication. Substantive
deletes already happened in Phase 4.2 (-216 LOC voice agent
orchestration). GAP 08 #1 closed; #2 minimized in v2.1-2; #3
(download orchestration, ~1,308 LOC) deferred pending commons
refactor.

### Phase 9 — DAG primitives skeleton
Header-only C++20 primitives under
`sdk/runanywhere-commons/include/rac/graph/`:

- **`CancelToken`** — hierarchical, lock-free `is_cancelled()`,
  parent cancels cascade through weak-ptr child list.
- **`RingBuffer<T>`** — wait-free SPSC with cache-line-aligned
  head/tail atomics (~30% throughput win at audio rates).
- **`StreamEdge<T>`** — bounded queue with 3 overflow policies
  (BlockProducer / DropNewest / DropOldest) + close + cancel
  integration.

13-test suite covers concurrent cancel cascade, SPSC ring at 10k
items, all 3 overflow policies + cancel + close paths.
`GraphScheduler` / `PipelineNode` / `MemoryPool` deliberately
deferred per [`v2_gap_specs/GAP_05_DAG_RUNTIME.md`](../v2_gap_specs/GAP_05_DAG_RUNTIME.md)
L63-64 ("build when a 2nd pipeline needs them").

### Phase 10 — Final verification + release
- 7 packages bumped to `3.1.0` (VERSION files, `Package.swift`,
  4 pubspecs, 8 package.jsons, Kotlin `build.gradle.kts` fallback).
- `RAC_PLUGIN_API_VERSION` stays at `3u` (no ABI changes in v3.1).
- Final builds: `test_proto_event_dispatch` 11/11,
  `test_graph_primitives` 13/13, `perf_producer` 144 ns/event,
  `cancel_producer` clean.
- Doc consolidation (this set of docs).

---

## v3.1.2 engine CMakeLists normalization (2026-04-22)

Sprint 2 of the post-v3.1 cleanup roadmap. Migrated 4 hand-rolled
engine CMakeLists to `rac_add_engine_plugin()`. Tagged 2026-04-22.

**Headline deliverables:**
- `cmake/plugins.cmake` macro extended with 5 new options:
  `TARGET_NAME` (override default `runanywhere_<name>`),
  `CXX_STANDARD` (default 17, can be 20),
  `SHARED_ONLY` (skip the static-fold-into-rac_commons path),
  `COMPILE_OPTIONS` (per-target -O3 / visibility flags),
  `LINK_OPTIONS` (per-target linker flags incl. Android 16K alignment).
  These were necessary to migrate engines without renaming their
  existing `rac_backend_X` CMake targets (preserves 52+ existing
  references across tests + sample apps + RN Android linker config).
- Macro hidden-visibility logic fixed: only applied for SHARED+dlopen
  builds; STATIC archives keep default visibility so cross-TU
  symbol resolution works at the final link site.
- 4 engines migrated: onnx (365 LOC kept its custom Sherpa-ONNX
  cross-platform IMPORTED setup), whispercpp (whisper.cpp FetchContent
  retained), whisperkit_coreml (down to 35 LOC), metalrt (kept
  OBJECT-library structure + emits engine metadata via direct
  GLOBAL properties).
- 7 packages bumped to `3.1.2`.

**Pre-existing latent bugs surfaced (NOT fixed in this sprint):**
- `engines/whispercpp/rac_stt_whispercpp.cpp` includes
  `rac_stt_whispercpp.h` which doesn't exist in the source tree
  (only in v0.19.13 era xcframework). Build of `rac_backend_whispercpp`
  fails when the engine is opted in. Tracked as separate fix.
- `engines/onnx/CMakeLists.txt` `RAG_DIR` variable resolves to a
  non-existent path (`features/rag` at repo root), so
  `onnx_embedding_provider.cpp` is silently skipped from the build.
  Bug-compat preserved per Sprint 2 scope; fixing it surfaces a
  separate stale `#include "../../backends/onnx/onnx_backend.h"` in
  the source. Tracked as separate fix.
- `engines/onnx/rac_backend_onnx_register.cpp` defines `g_onnx_*_ops`
  inside an anonymous namespace, which gives them internal linkage —
  but `rac_plugin_entry_onnx.cpp` declares them with `extern "C"`.
  This works for STATIC archives (deferred resolution at final link)
  but would fail for SHARED. Same pattern in llamacpp. Tracked.

---

## v3.1.1 doc + release-tooling patch (2026-04-22)

Sprint 1 of the post-v3.1 cleanup roadmap. No code changes; doc
refreshes + a release-automation script. Tagged 2026-04-22.

**Headline deliverables:**
- 3 SDK API ref docs refreshed for v3.1+ voice surface (deletion of
  `VoiceSessionEvent` reflected in [`docs/sdks/flutter-sdk.md`](sdks/flutter-sdk.md),
  [`docs/sdks/kotlin-sdk.md`](sdks/kotlin-sdk.md),
  [`docs/sdks/react-native-sdk.md`](sdks/react-native-sdk.md));
  version examples bumped from 0.x to 3.1.0.
- `docs/engine_plugin_authoring.md` rewritten for `RAC_PLUGIN_API_VERSION = 3u`
  (legacy `rac_service_*` text removed; `create` op added to all
  primitive-ops examples; cross-link to `cmake/plugins.cmake`).
- New release-automation script:
  [`scripts/release-swift-binaries.sh`](../scripts/release-swift-binaries.sh)
  wraps the existing `build-core-xcframework.sh` + `sync-checksums.sh`
  + emits a `gh release create` recipe. Documents prereqs + operator
  steps for publishing the xcframework binaries.
- 7 packages bumped to `3.1.1`.

---

## Flutter split analysis (v3.1 P7 deep-dive)

For the inevitable v4.x revisit. Four options were explored; none
preserve the current static-method API:

1. **`extension X on T { static method() }`** — call syntax becomes
   `X.method()` (breaks every consumer).
2. **`part`/`part of`** — Dart parser sees one class body per file;
   can't span.
3. **Top-level functions + thin facade** — preserves API, adds ~100
   LOC of forwarding boilerplate per method.
4. **Instance methods + singleton** — `RunAnywhere.instance.method()`.
   Canonical Dart pattern (supabase-dart, firebase_core). Breaking.

**Recommended for v4.x: Option 4.**

---

## Sprint commit indexes

For audit-quality traceability, full commit lists per sprint live at:

- v2 close-out: [`archive/v2-closeout/v2_closeout_results.md`](archive/v2-closeout/v2_closeout_results.md)
- v3.0.0 cut-over: [`archive/v3-evidence/v3_phaseB_complete.md`](archive/v3-evidence/v3_phaseB_complete.md)
- v3.1.0 sprint: see git log filtered by `--grep 'v3.1-'` (17 commits)

```sh
git log --oneline --grep='v3\.1-' --reverse
```

---

## How to add a new sprint to this history

1. Append a new `## v<x>.<y>.<z> <Sprint Name> (<date>)` section
   above the "Sprint commit indexes" footer.
2. List headline deliverables as bullets — keep it short, prefer
   linking to evidence files in `archive/` over copying tables.
3. Update the "Timeline at a glance" table at the top.
4. Move per-phase records to `archive/<release>/` if they exceed
   one or two screen-fulls of detail.
