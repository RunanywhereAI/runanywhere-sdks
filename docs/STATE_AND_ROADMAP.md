# State & Roadmap

_Single canonical "where we are now + what's next". Reconciles the
v2 close-out, v3.0.0 ABI cut-over, and v3.1.0 architectural cleanup.
Updated: 2026-04-22._

> Looking for the per-GAP scoreboard? See [`GAP_STATUS.md`](GAP_STATUS.md).
>
> Looking for the chronological evidence trail? See [`HISTORY.md`](HISTORY.md)
> + [`archive/`](archive/).
>
> Looking for the actively-tracked spec set? See [`../v2_gap_specs/`](../v2_gap_specs/).

## TL;DR

- **Current shipped version: v3.1.0** across all 7 packages
  (Swift / Kotlin / Flutter `runanywhere` + 3 backend plugins / Web
  core+plugins / RN core+plugins). Tagged 2026-04-22.
- **C ABI version: `RAC_PLUGIN_API_VERSION = 3u`** (bumped in v3.0.0).
  Wire-compatible IDL extension shipped in v3.1: `MetricsEvent.created_at_ns`
  field 8.
- **Architecture state**: monolithic `sdk/legacy/` C++ deleted; modular
  `core/` (`ra_*`/`rac_*` C ABI) is the only path. All 5 SDKs are thin
  adapters over the canonical proto event stream.
- **Sample apps**: iOS / Android / Flutter / RN voice ViewModels all
  migrated to `VoiceAgentStreamAdapter` + proto `VoiceEvent`.
- **Tests**: `test_proto_event_dispatch` 11/11, `test_graph_primitives`
  13/13, `perf_producer` 144 ns/event, `cancel_producer` clean.
- **Zero `rac_service_*` references in code** (only historical comments).

## What you should read

| You are... | Start here |
|---|---|
| Onboarding to the codebase | [`STATE_AND_ROADMAP.md`](STATE_AND_ROADMAP.md) (this file) → [`GAP_STATUS.md`](GAP_STATUS.md) |
| Building / running the SDK | [`building.md`](building.md) (Gradle/Android) + [`../README.md`](../README.md) |
| Authoring an engine plugin | [`engine_plugin_authoring.md`](engine_plugin_authoring.md) + [`plugins/PLUGIN_AUTHORING.md`](plugins/PLUGIN_AUTHORING.md) |
| Implementing a new pipeline | [`graph_primitives.md`](graph_primitives.md) |
| Migrating off `VoiceSessionEvent` | [`migrations/VoiceSessionEvent.md`](migrations/VoiceSessionEvent.md) (v2.x → v3.1) |
| Adding LoRA support | [`impl/lora_adapter_support.md`](impl/lora_adapter_support.md) |
| Auditing what shipped when | [`HISTORY.md`](HISTORY.md) + [`archive/`](archive/) |

## Architecture summary (post-v3.1)

```
┌────────────────────────────────────────────────────────────────┐
│ Sample apps (iOS/Android/Flutter/RN voice ViewModels)          │
│   → consume VoiceAgentStreamAdapter → AsyncStream<VoiceEvent>  │
└─────────────────────────────┬──────────────────────────────────┘
                              │
┌─────────────────────────────▼──────────────────────────────────┐
│ 5 SDK frontends (Swift / Kotlin / Dart / RN / Web)             │
│   ~thin adapter layers + ts-proto/Wire/protoc/swift-protobuf   │
│   public API: RunAnywhere.{loadX, generate, transcribe, ...}   │
└─────────────────────────────┬──────────────────────────────────┘
                              │ FFI / JNI / Nitro / Emscripten
┌─────────────────────────────▼──────────────────────────────────┐
│ runanywhere-commons (C++20)                                    │
│   ra_* + rac_* C ABI · plugin registry · engine router         │
│   voice agent (rac_voice_agent_*) · proto bus · metrics        │
│   DAG primitives (CancelToken/RingBuffer/StreamEdge)           │
│                                                                │
│   RAC_PLUGIN_API_VERSION = 3u                                  │
└─────────────────────────────┬──────────────────────────────────┘
                              │ rac_engine_vtable_t per plugin
┌─────────────────────────────▼──────────────────────────────────┐
│ Engine plugins (each = static OR dlopen-able shared library)   │
│   llamacpp · onnx · whispercpp · whisperkit_coreml · metalrt   │
│   genie (stub) · sherpa (stub) · diffusion-coreml (stub)       │
└────────────────────────────────────────────────────────────────┘
```

The IDL (`idl/*.proto`) is the single source of truth for cross-
language types. Codegen scripts under `idl/codegen/generate_*.sh`
emit Swift / Kotlin / Dart / TS / Python / C++ bindings.

## Active backlog (post-v3.1)

These items have known scope + a documented path; tracked for v3.x or
v4.x. None are release-blocking.

### Engineering (post-v3.1.x patches)

1. **Swift xcframework regeneration** — Required for full
   `swift build` green by external SPM consumers. Release-automation
   step (`scripts/build-core-xcframework.sh`); not a code issue.
2. **5/9 engine CMakeLists migrations** to `rac_add_engine_plugin()`
   — onnx / whispercpp / whisperkit_coreml / metalrt + one more.
   Per-engine PRs with platform CI matrix verification. Plan in
   the consolidated [`HISTORY.md`](HISTORY.md) appendix.
3. **`engine_plugin_authoring.md` refresh** — Update example snippets
   to reflect `RAC_PLUGIN_API_VERSION 3u`, deletion of
   `rac_service_*`, and the `create` op on every primitive ops struct.
4. **`sdks/{flutter,kotlin,react-native}-sdk.md`** — Pre-v2-era
   API references; need a v3.1 refresh pass (versions, voice API,
   proto types).

### Architectural (v4.x / breaking)

5. **Flutter `runanywhere.dart` 2,607 LOC god-class** — Dart language
   constraints prevent a Swift-style extension split without
   breaking the API. Recommendation: migrate to the canonical Dart
   pattern of `RunAnywhere.instance.capability.method()` (matches
   `supabase-dart`, `firebase_core`). Rationale + 4 explored
   options preserved in [`HISTORY.md#flutter-split-analysis`](HISTORY.md#flutter-split-analysis).

6. **Kotlin LOC trim — GAP 08 #3 (download orchestration)** —
   `RunAnywhere+ModelManagement.jvmAndroid.kt` ~1,308 LOC. Needs
   a commons-side orchestrator + thin Flow adapter. Multi-sprint
   effort (~1,000 LOC saving expected).

### QA (out of v3.1 scope per user directive)

7. **GAP 08 #9 sample-app E2E automation** (Detox / Maestro /
   XCUITest / Espresso). Rough estimate: 1 week.
8. **GAP 08 #10 real-device behavioral parity verification** —
   QA effort, ~1 week manual.
9. **GAP 04 iOS17 / ANE E2E device tests** — QA effort.
10. **GAP 03 real-model GGUF E2E + valgrind** under CI.

### Deferred indefinitely (per spec)

11. **GAP 05 `GraphScheduler` + `PipelineNode` + `MemoryPool`** —
    Spec L63-64 marks as "build when a 2nd pipeline needs them".
    Skeleton primitives shipped in v3.1 Phase 9; full DAG runtime
    waits for a real consumer.

## Versioning policy

| Layer | Version | Bumps when |
|---|---|---|
| `RAC_PLUGIN_API_VERSION` | `3u` | Breaking C ABI changes (struct field add/remove, function signature change). |
| `rac_voice_event_abi.h` `RAC_ABI_VERSION` | `2u` | Voice-agent proto-event ABI changes specifically. |
| Package semver (Swift/Flutter/Kotlin/RN/Web) | `3.1.0` | Sprint releases. v4.x for breaking SDK API changes. |
| IDL `runanywhere.v1.*` | `v1` | New proto versions only on wire-incompatible changes. |

## Doc index (post-consolidation)

```
docs/
├── STATE_AND_ROADMAP.md          ← you are here
├── GAP_STATUS.md                 ← rolling 11-GAP status table
├── HISTORY.md                    ← chronological evidence trail
│
├── building.md                   ← Kotlin/Gradle build entry
├── engine_plugin_authoring.md    ← engine plugin reference
├── graph_primitives.md           ← DAG primitives user guide
├── plugins/
│   └── PLUGIN_AUTHORING.md       ← third-party plugin packaging
├── impl/
│   └── lora_adapter_support.md   ← LoRA implementation ref
├── migrations/
│   └── VoiceSessionEvent.md      ← v2.x → v3.1 migration
├── sdks/
│   ├── flutter-sdk.md            ← API ref (needs v3.1 refresh)
│   ├── kotlin-sdk.md             ← API ref (needs v3.1 refresh)
│   └── react-native-sdk.md       ← API ref (needs v3.1 refresh)
│
└── archive/                      ← historical evidence (cite-only)
    ├── gap-reports/              ← 11 per-GAP final gate reports
    ├── v2-closeout/              ← v2 close-out per-phase records
    └── v3-evidence/              ← v3.0/v3.1 sprint deliverables
```

The `v2_gap_specs/` folder at the repo root is the **active spec set**
(11 GAPs to close). Active engineering work referencing those specs
is reflected in [`GAP_STATUS.md`](GAP_STATUS.md).
