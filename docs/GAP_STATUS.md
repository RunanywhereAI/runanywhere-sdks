# GAP Status — Rolling Scoreboard

_Single source of truth for the 11 GAP specs. Each GAP's full per-
criterion final-gate report lives at
[`archive/gap-reports/`](archive/gap-reports/) for citation. This
file is the rolling status — update when a GAP's status changes.
Updated: 2026-04-22 (post v3.1.0)._

## Status legend

- **CLOSED** — every spec criterion ships and is verified.
- **CLOSED (PARTIAL)** — core criteria ship; specific items
  intentionally deferred per spec (linked).
- **PARTIAL** — substantial work shipped; named criteria still open.
- **DEFERRED** — entire GAP intentionally postponed per spec text.

## Scoreboard

| GAP | Spec | Status | Closed in | Residual / open |
|---|---|---|---|---|
| 01 | [IDL + codegen](../v2_gap_specs/GAP_01_IDL_AND_CODEGEN.md) | **CLOSED** | v2 | None — drift CI active. |
| 02 | [Unified engine plugin ABI](../v2_gap_specs/GAP_02_UNIFIED_ENGINE_PLUGIN_ABI.md) | **CLOSED** | v3.0.0 | None. Single-path; legacy registry deleted. |
| 03 | [Dynamic plugin loading](../v2_gap_specs/GAP_03_DYNAMIC_PLUGIN_LOADING.md) | **CLOSED (PARTIAL)** | v2 | Real-model GGUF E2E + valgrind under CI is QA effort. |
| 04 | [Engine router + HW profile](../v2_gap_specs/GAP_04_ENGINE_ROUTER_AND_HARDWARE_PROFILE.md) | **CLOSED (PARTIAL)** | v2 | iOS17 / ANE device E2E is QA effort. |
| 05 | [DAG runtime](../v2_gap_specs/GAP_05_DAG_RUNTIME.md) | **CLOSED (PARTIAL)** | v3.1 | Skeleton (CancelToken / RingBuffer / StreamEdge) shipped. `GraphScheduler` / `PipelineNode` / `MemoryPool` deferred per spec L63-64 until a 2nd pipeline needs them. |
| 06 | [Engines top-level reorg](../v2_gap_specs/GAP_06_ENGINES_TOPLEVEL_REORG.md) | **CLOSED** | v2 + v3.1.2 | All 9 engines now use the unified pattern: 4 stubs + llamacpp + onnx + whispercpp + whisperkit_coreml via `rac_add_engine_plugin()`; metalrt records the same engine-metadata via direct GLOBAL properties (its OBJECT-library structure can't fit STATIC/SHARED branching). Macro extended in v3.1.2 with TARGET_NAME / CXX_STANDARD / SHARED_ONLY / COMPILE_OPTIONS / LINK_OPTIONS to support backward-compat target names. |
| 07 | [Single root CMake](../v2_gap_specs/GAP_07_SINGLE_ROOT_CMAKE.md) | **CLOSED** | v3.1 | NDK pin hoisted to root `gradle.properties`. |
| 08 | [Frontend duplication delete](../v2_gap_specs/GAP_08_FRONTEND_LOGIC_DUPLICATION.md) | **CLOSED (PARTIAL)** | v2 + v3.1 | Kotlin orchestration (#1) deleted; Dart god-class (#4) blocked on Dart language constraint (v4.x); sample-app E2E (#9) + device parity (#10) are QA effort; download orchestration (#3) deferred pending commons refactor. |
| 09 | [Streaming consistency](../v2_gap_specs/GAP_09_STREAMING_CONSISTENCY.md) | **CLOSED** | v3.1 | All 9 criteria OK — including #6 (zero hand-written `VoiceSessionEvent`), #7 (cancel parity harness), #8 (per-SDK p50 < 1ms with real proto decode). |
| 11 | [Legacy cleanup](../v2_gap_specs/GAP_11_REMOVE_LEGACY.md) | **CLOSED** | v3.0.0 | All voice-session shims also deleted in v3.1 P4. Zero `rac_service_*` references in code. |

## Spec coverage gaps

- **GAP 10 spec is not in repo** (per `wave_roadmap.md` historical
  note — "specs not in repo": GAP_00, GAP_10).
- **GAP 00 spec is not in repo** — early-stage architectural intent.

If you encounter a feature ticket that doesn't map to GAPs 01-11,
treat it as a v3.x backlog item and write a short scoping doc.

## Per-GAP closure summary (1-line each)

### GAP 01 — IDL + codegen
6 proto files + 5-language codegen (Swift/Kotlin/Dart/TS/Python/C++)
+ `ci-drift-check.yml` workflow. v3.1 added `MetricsEvent.created_at_ns`.

### GAP 02 — Unified engine plugin ABI
`rac_engine_vtable_t` with explicit primitive slots; central registry
+ static + dynamic registration paths; `RAC_PLUGIN_API_VERSION = 3u`.

### GAP 03 — Dynamic plugin loading
`dlopen` path with ABI version check; `RAC_STATIC_PLUGIN_REGISTER`
companion for static builds; loader tests.

### GAP 04 — Engine router + HW profile
`EngineRouter` with deterministic scoring; `HardwareProfile`
introspection (CPU / GPU / NPU / NEON detection); `rac_plugin_route`
C ABI.

### GAP 05 — DAG runtime
v3.1: header-only `CancelToken` (lock-free is_cancelled, atomic
cascade), `RingBuffer<T>` (cache-aligned SPSC), `StreamEdge<T>`
(3 overflow policies + cancel + close). 13-test suite.

### GAP 06 — Engines top-level reorg
`engines/<name>/CMakeLists.txt` per engine + `cmake/plugins.cmake`
exposes `rac_add_engine_plugin()` macro + `rac_force_load()`
companion. 8/9 engines on macro (v3.1.2); metalrt is OBJECT-library
(structurally different) but emits the same metadata via GLOBAL
properties.

### GAP 07 — Single root CMake
Root `CMakeLists.txt` orchestrates entire repo; `CMakePresets.json`
exposes `macos-debug/release/linux-debug/release/etc`. Slim
`pr-build.yml` runs presets; `gradle.properties` hosts NDK pins.

### GAP 08 — Frontend duplication delete
Kotlin: voice-agent orchestration (Dup #1) deleted in v3.1 P4 (467
LOC). Auth client (Dup #2) minimized in v2.1-2. Dart god-class (Dup
#4) deferred (Dart lang). Download orchestration (Dup #3) deferred.

### GAP 09 — Streaming consistency
6 IDL service protos + 5-SDK adapters wrapping
`rac_voice_agent_set_proto_callback` as AsyncStream / Flow /
Stream / AsyncIterable. v3.1: cancel parity harness + per-SDK p50
benchmark runners.

### GAP 11 — Legacy cleanup
v3.0.0: `service_registry.cpp` + `rac_service_*` C ABI deleted;
`RAC_PLUGIN_API_VERSION 2u → 3u`. v3.1: deprecated SDK voice-session
shims (`VoiceSessionEvent`, `VoiceSessionHandle`, `startVoiceSession`,
etc.) deleted across all 5 SDKs.

## How to update this scoreboard

When a GAP criterion ships:

1. Update the `Status` cell in the table above.
2. Update the per-GAP 1-line summary if behavior changes.
3. Append a short bullet to [`HISTORY.md`](HISTORY.md) under the
   current sprint section.
4. If the GAP closes a spec criterion that's been DEFERRED, also
   update the spec file under `../v2_gap_specs/`.
5. Do NOT rewrite individual archive gate reports — they're
   point-in-time evidence.

## When a NEW GAP is needed

Specs live at `../v2_gap_specs/GAP_NN_NAME.md`. Numbering is
sequential; reuse existing slots if the work fits an open GAP.
Genuinely new architectural work that doesn't fit gets a new number
and a row added here.
