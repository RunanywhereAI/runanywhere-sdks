# State & Roadmap

_Single canonical "where we are now + what's next" for the
`feat/v2-architecture` branch. **No releases have been cut yet** —
all package versions match `main`'s baseline. This doc tracks the
branch's architectural state, not shipped versions._

> **For a 3-min status overview**, read
> [`TEAM_STATUS.md`](TEAM_STATUS.md) instead. This doc has the
> architectural detail.

Updated: 2026-04-22.

> Looking for the per-GAP scoreboard? See [`GAP_STATUS.md`](GAP_STATUS.md).
>
> Looking for the chronological evidence trail? See [`HISTORY.md`](HISTORY.md)
> + [`archive/`](archive/).
>
> Looking for the actively-tracked spec set? See [`../v2_gap_specs/`](../v2_gap_specs/).

## TL;DR

- **Branch**: `feat/v2-architecture`. **114 commits** ahead of `main`.
  **Not merged. Not released.**
- **All package versions equal main's baseline**: `0.19.13` (commons /
  Swift / Flutter / Web / RN), `0.19.6` (Swift VERSION file),
  `0.1.5-SNAPSHOT` (Kotlin Gradle fallback). The earlier
  v3.0.0 / v3.1.x / v4.0.0 markers in commit history were premature
  version-bump experiments and have been reverted to the baseline.
- **Architectural state on this branch**:
  - C ABI: `RAC_PLUGIN_API_VERSION = 3u` (was unset on main; first
    introduced on this branch).
  - `service_registry.cpp` deleted; `rac_service_*` C ABI replaced
    with `rac_plugin_route` + plugin registry. Zero ACTIVE call
    sites in the tree (comment-only mentions remain in migration docs).
  - Proto IDL (`idl/*.proto`) drives 5 languages via codegen.
  - All 5 SDKs are thin adapters over the proto event stream.
  - Sample apps (iOS / Android / Flutter / RN) migrated off
    deprecated `VoiceSessionEvent` → `VoiceAgentStreamAdapter`.
- **Tests on macos-release preset**: `test_proto_event_dispatch` 11/11,
  `test_graph_primitives` 13/13, `perf_producer` 144 ns/event,
  `cancel_producer` clean.
- **Release decision**: deferred. See [release sequencing](#suggested-release-sequencing)
  below for the recommended path when the team is ready.

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

1. **Swift xcframework publication** — DONE-IN-CODE in v3.1.1:
   release script at [`scripts/release-swift-binaries.sh`](../scripts/release-swift-binaries.sh)
   wraps `build-core-xcframework.sh` + `sync-checksums.sh` + emits a
   `gh release create` recipe. Operator-only step (requires Xcode 15+,
   manual `third_party/onnxruntime-ios/onnxruntime.xcframework`
   prereq, and GitHub Releases publish credentials). Until an
   operator runs it for v3.1.1+, external SPM consumers must set
   `useLocalNatives = true` in `Package.swift`.
2. **4 engine CMakeLists migrations** to `rac_add_engine_plugin()` —
   DONE in v3.1.2. All 4 engines (onnx, whispercpp, whisperkit_coreml,
   metalrt) now use the unified pattern; macro extended with
   TARGET_NAME / CXX_STANDARD / SHARED_ONLY / COMPILE_OPTIONS /
   LINK_OPTIONS to support backward-compat target names.
3. **`engine_plugin_authoring.md` refresh** — DONE in v3.1.1.
4. **`sdks/{flutter,kotlin,react-native}-sdk.md`** — DONE in v3.1.1.
   Voice API sections rewritten for `VoiceAgentStreamAdapter` +
   proto event payload switch.

### Architectural (v4.x / breaking) — SHIPPED

5. **Flutter `runanywhere.dart` god-class split** — DONE in v4.0.0.
   New API shape: `RunAnywhereSDK.instance.{llm,stt,tts,vlm,voice,
   models,downloads}.method()`. Static `RunAnywhere.X` API kept as
   `@Deprecated` shim during v4.0.x window; deletion in v4.1.
   See [`docs/migrations/v3_to_v4_flutter.md`](migrations/v3_to_v4_flutter.md)
   for the full v3 → v4 method mapping.

6. **Kotlin LOC trim — GAP 08 #3 (download orchestration)** —
   AUDITED in v3.1.3. Architectural blocker: requires choosing a
   commons HTTP client (libcurl / cpr / platform-native shims). The
   1,485 LOC of CppBridgeDownload is the Android HTTP executor that
   the C++ download manager calls back into — not orchestration
   duplication. v3.1.3 shipped a small DRY refactor (-27 LOC). Full
   cleanup deferred until commons HTTP client decision; see
   [docs/v3_2_kotlin_download_blocker.md](v3_2_kotlin_download_blocker.md).

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

| Layer | Branch value | Bumps when |
|---|---|---|
| `RAC_PLUGIN_API_VERSION` | `3u` (branch); not present on main | Breaking C ABI changes (struct field add/remove, function signature change). |
| `rac_voice_event_abi.h` `RAC_ABI_VERSION` | `2u` (branch) | Voice-agent proto-event ABI changes specifically. |
| All SDK package semvers | `0.19.13` (matches main; pending release decision) | TBD — see [release sequencing](#suggested-release-sequencing). |
| Kotlin Gradle fallback | `0.1.5-SNAPSHOT` (matches main) | TBD. |
| IDL `runanywhere.v1.*` | `v1` | New proto versions only on wire-incompatible changes. |

## Suggested release sequencing

When the team decides to ship, this is one viable path. Other valid
sequencings exist; the key constraint is that the C ABI + voice-session
deletions are breaking and need a major-version-style bump.

1. **Merge `feat/v2-architecture` → `main`** (squash or merge commit;
   the branch is internally consistent and partial-merge would lose
   IDL/plugin coherence).
2. **Pick a target version**:
   - `v0.20.0` — additive minor (0.x semver allows breaking changes
     in minor releases).
   - `v1.0.0` — clean break + signal "stable architecture".
   - `v2.0.0` — matches the "v2 architecture" branch name.
3. **Bump versions** across the 7 packages + `Package.swift sdkVersion`
   + `runanywhere-kotlin/build.gradle.kts` fallback.
4. **Publish artifacts**: run [`scripts/release-swift-binaries.sh`](../scripts/release-swift-binaries.sh)
   on macOS with credentials → upload to GitHub release →
   `pub publish` / `npm publish` / `gradle publish`.
5. **Migration guide**: `docs/migrations/<from>_to_<to>.md` covering
   `VoiceSessionEvent` → `VoiceAgentStreamAdapter` and `rac_service_*`
   → plugin registry for engine plugin authors.

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
│   ├── flutter-sdk.md            ← API ref (refreshed for branch voice API)
│   ├── kotlin-sdk.md             ← API ref (refreshed for branch voice API)
│   └── react-native-sdk.md       ← API ref (refreshed for branch voice API)
│
└── archive/                      ← historical evidence (cite-only)
    ├── gap-reports/              ← 11 per-GAP final gate reports
    ├── v2-closeout/              ← v2 close-out per-phase records
    └── v3-evidence/              ← v3.0/v3.1 sprint deliverables
```

The `v2_gap_specs/` folder at the repo root is the **active spec set**
(11 GAPs to close). Active engineering work referencing those specs
is reflected in [`GAP_STATUS.md`](GAP_STATUS.md).
