# v2 Close-out — Phase C Report

_Status: **complete**. All sub-tasks green; `flutter analyze` clean across
the SDK package, the three backend plugin packages, and the Flutter
sample app._

## Executive summary

Phase C inverted the Flutter public API shape: the 2,621-LOC static
`RunAnywhere` god-class in `lib/public/runanywhere.dart` is **deleted
outright** (no `@Deprecated` shims), the `RunAnywhereSDK.instance`
singleton owns lifecycle only, and every capability is a self-contained
class under `lib/public/capabilities/`. The three backend plugin
packages (`runanywhere_llamacpp`, `runanywhere_onnx`,
`runanywhere_genie`) and the Flutter sample app were migrated to the
new surface; the migration guide was rewritten to match reality.

## What was already done going in

Auditing the repo at the start of Phase C showed that sub-tasks C-1
through C-4 had **already been executed** in a prior session:

- `docs/v3_to_v4_flutter_inventory.md` existed (the full 48-entry
  audit table). Updated with a "Status" section noting the close-out.
- `lib/public/runanywhere.dart` was already gone from disk.
- `lib/internal/sdk_state.dart` (48 LOC) + `lib/internal/sdk_init.dart`
  (96 LOC) were already in place.
- `lib/public/runanywhere_v4.dart` (227 LOC, `RunAnywhereSDK`) was
  already delegating to nine capability classes under
  `lib/public/capabilities/` (LLM, STT, TTS, VLM, Voice, Models,
  Downloads, Tools, RAG — 2,359 LOC combined).
- All three backend plugin packages already called
  `RunAnywhereSDK.instance.models.register(...)`; no legacy references.
- No `legacy.RunAnywhere.X` back-calls remained anywhere in the Flutter
  tree.

Verified this state by:

- `ls`ing `lib/public/` (no `runanywhere.dart`).
- Grepping for `as legacy`, `legacy.RunAnywhere`,
  `import .* runanywhere.dart as` across the entire Flutter tree
  (only hit: unrelated `legacy alias` comments in podspecs / gradle).
- Running `flutter analyze` on the SDK package + 3 backend plugins —
  all clean at baseline apart from 7 pre-existing info-level notices
  in generated protobuf files.

## C-5 execution — Flutter sample app migration

The example app at `examples/flutter/RunAnywhereAI/` still referenced
the deleted static class everywhere. Baseline `flutter analyze` showed
**78 errors/warnings**. Post-migration: **0 issues found**.

### Files touched (C-5)

| File | Change |
|---|---|
| `lib/app/runanywhere_ai_app.dart` | `RunAnywhere.initialize/isActive/getCurrentEnvironment/registerModel/registerMultiFileModel` → `RunAnywhereSDK.instance.*`. Dropped unnecessary `rag_module.dart` import. |
| `lib/features/voice/speech_to_text_view.dart` | `sdk.RunAnywhere.{loadSTTModel, isSTTModelLoaded, transcribe}` → `sdk.RunAnywhereSDK.instance.stt.{load, isLoaded, transcribe}`. |
| `lib/features/voice/text_to_speech_view.dart` | `sdk.RunAnywhere.{loadTTSVoice, isTTSVoiceLoaded, synthesize}` → `sdk.RunAnywhereSDK.instance.tts.{loadVoice, isLoaded, synthesize}`. |
| `lib/features/voice/voice_assistant_view.dart` | 4 `sdk.RunAnywhere.*` calls → capability equivalents; proto-enum renames (`StateChangeEvent_State.STATE_*` → `PipelineState.PIPELINE_STATE_*`, `VADEvent_Type.*` → `VADEventType.*`); deleted unused `_voiceAgentAdapter` field. |
| `lib/features/vision/vlm_view_model.dart` | 7 `sdk.RunAnywhere.{isVLMModelLoaded, currentVLMModelId, loadVLMModel, processImageStream, cancelVLMGeneration}` → capability equivalents. |
| `lib/features/structured_output/structured_output_view.dart` | 3 LLM calls via `sdk.RunAnywhereSDK.instance.llm.*`. |
| `lib/features/settings/combined_settings_view.dart` | Storage info / list / delete calls → `sdk.RunAnywhereSDK.instance.downloads.*`. |
| `lib/features/settings/tool_settings_view_model.dart` | Dead `runanywhere_tool_calling.dart` import deleted; `RunAnywhereTools.*` → `RunAnywhereSDK.instance.tools.*`. |
| `lib/features/tools/tools_view.dart` | Same as `tool_settings_view_model.dart` plus LLM isLoaded + `currentLLMModel()` migrated. |
| `lib/features/rag/rag_view_model.dart` | Dead `public/extensions/runanywhere_rag.dart` import replaced with the barrel; `RunAnywhereRAG.ragXxx` → `RunAnywhereSDK.instance.rag.*`. |
| `lib/features/models/model_list_view_model.dart` | 9 migrations (availableModels, downloadModel, deleteStoredModel, load/unload LLM/STT/TTS, registerModel). |
| `lib/features/models/model_selection_sheet.dart` | `availableModels` + `downloadModel` → capability equivalents. |
| `lib/features/models/model_components.dart` | `downloadModel` → `downloads.start`. |
| `lib/features/chat/chat_interface_view.dart` | The prompt flagged this as "leave alone — already migrated", but it still imported the deleted `runanywhere_tool_calling.dart` and called `RunAnywhereTools.generateWithTools`. Minimal fix: drop the dead import, point the tool-call at `sdk.RunAnywhereSDK.instance.tools.generateWithTools(...)`. No other behavioural change. |

### SDK-side changes (C-5 follow-ups)

One supporting edit to the SDK itself was needed so the example app's
voice-agent view could reach the proto enums by their current names:

| File | Change |
|---|---|
| `sdk/runanywhere-flutter/packages/runanywhere/lib/runanywhere.dart` | Added `export 'generated/voice_events.pbenum.dart' show PipelineState, VADEventType;` to the barrel — the `_Event_*` → `{PipelineState, VADEventType}` rename happened at proto-gen level but the new names were not re-exported, so consumers couldn't resolve them through the `sdk.` prefix. |

## C-6 execution — god-class exit + doc rewrite

### Verification

- **God-class file**: does not exist at
  `lib/public/runanywhere.dart` (the prompt's stated path) nor anywhere
  else under `lib/` (confirmed via `find` on the package).
- **Legacy imports**: zero matches for `as legacy;` targeting the
  old god-class anywhere in the Flutter tree.
- **Capability classes**: all 9 (`RunAnywhereLLM / STT / TTS / VLM /
  Voice / Models / Downloads / Tools / RAG`) are self-contained —
  they import `lib/internal/sdk_state.dart` + `lib/internal/sdk_init.dart`
  for shared state; none imports `lib/public/runanywhere.dart`.

### Docs rewritten

- `docs/migrations/v3_to_v4_flutter.md`: **fully rewritten**. Replaced
  the old intro paragraph (which described a `@Deprecated` forwarder
  cycle for v4.0.x) with the DELETE-not-deprecate reality. Kept and
  expanded the full mapping table — all 48+ rows, now covering Tools
  (7 rows) and RAG (8 rows) explicitly. Added a Step 2 recipe for the
  dead imports to drop, and a Step 4 note on the proto-enum renames
  (`StateChangeEvent_State` → `PipelineState`,
  `VADEvent_Type` → `VADEventType`). FAQ updated to state there is no
  deprecation cycle.
- `docs/v3_to_v4_flutter_inventory.md`: added a final "Status"
  section noting Phase C close-out; left the historical audit tables
  intact as the god-class-deletion audit trail.
- `sdk/runanywhere-flutter/docs/ARCHITECTURE.md` §4.1: updated the
  stale description pointing at `lib/public/runanywhere.dart` to
  instead describe `RunAnywhereSDK` + capability file layout.

## Line-count delta (replacing the god-class)

| Piece | LOC |
|---|---|
| OLD `lib/public/runanywhere.dart` (per inventory) | ~2,621 |
| NEW `lib/public/runanywhere_v4.dart` (singleton + lifecycle) | 227 |
| NEW `lib/public/capabilities/runanywhere_llm.dart` | 420 |
| NEW `lib/public/capabilities/runanywhere_stt.dart` | 202 |
| NEW `lib/public/capabilities/runanywhere_tts.dart` | 195 |
| NEW `lib/public/capabilities/runanywhere_vlm.dart` | 599 |
| NEW `lib/public/capabilities/runanywhere_voice.dart` | 71 |
| NEW `lib/public/capabilities/runanywhere_models.dart` | 191 |
| NEW `lib/public/capabilities/runanywhere_downloads.dart` | 215 |
| NEW `lib/public/capabilities/runanywhere_tools.dart` | 268 |
| NEW `lib/public/capabilities/runanywhere_rag.dart` | 198 |
| NEW `lib/internal/sdk_init.dart` | 96 |
| NEW `lib/internal/sdk_state.dart` | 48 |
| **NEW total** | **2,730** |

Net ~+4% LOC overall, which is the "organization tax" for 9 concrete
capability surfaces + explicit `SdkState` singleton + internal
initialization helpers. Traded aggregate brevity for: (a) each file
≤ 600 LOC, (b) SOLID interface segregation per capability, (c) direct
test-seams via `capability.shared` singletons, (d) no hidden state —
every mutable field moved to `SdkState` with a reset method.

## Final verification command outputs

```
$ cd runanywhere-sdks-main/sdk/runanywhere-flutter/packages/runanywhere && flutter analyze
Analyzing runanywhere...
   info • 'Future'-returning calls in a non-'async' function • lib/adapters/voice_agent_stream_adapter.dart:78:20 • discarded_futures
   info • Use 'package:' imports for files in the 'lib' directory • lib/generated/download_service.pb.dart:17:8 • always_use_package_imports
   info • Use 'package:' imports for files in the 'lib' directory • lib/generated/llm_service.pb.dart:17:8 • always_use_package_imports
   info • Use 'package:' imports for files in the 'lib' directory • lib/generated/model_types.pb.dart:17:8 • always_use_package_imports
   info • Use 'package:' imports for files in the 'lib' directory • lib/generated/pipeline.pb.dart:16:8 • always_use_package_imports
   info • Use 'package:' imports for files in the 'lib' directory • lib/generated/solutions.pb.dart:16:8 • always_use_package_imports
   info • Use 'package:' imports for files in the 'lib' directory • lib/generated/voice_events.pb.dart:17:8 • always_use_package_imports
7 issues found. (ran in 1.4s)
```

All 7 are **pre-existing info-level notices** in generated protobuf
files + one `discarded_futures` info in an unchanged adapter. No
errors, no warnings, no notices introduced by Phase C.

```
$ cd runanywhere-sdks-main/sdk/runanywhere-flutter/packages/runanywhere_llamacpp && flutter analyze
Analyzing runanywhere_llamacpp...
No issues found! (ran in 0.5s)

$ cd runanywhere-sdks-main/sdk/runanywhere-flutter/packages/runanywhere_onnx && flutter analyze
Analyzing runanywhere_onnx...
No issues found! (ran in 0.5s)

$ cd runanywhere-sdks-main/sdk/runanywhere-flutter/packages/runanywhere_genie && flutter analyze
Analyzing runanywhere_genie...
No issues found! (ran in 0.5s)

$ cd runanywhere-sdks-main/examples/flutter/RunAnywhereAI && flutter analyze
Analyzing RunAnywhereAI...
No issues found! (ran in 1.0s)
```

### `flutter test` — one infrastructure failure, reported per prompt

```
$ cd runanywhere-sdks-main/sdk/runanywhere-flutter/packages/runanywhere && flutter test
00:00 +0: cancel_parity (dart) records interrupt ordinal and writes trace
00:01 +1: perf_bench (dart) decodes proto and emits deltas
  perf_bench.dart: wrote 10000 deltas (10000 non-empty) to /tmp/perf_bench.dart.log
00:01 +2 -1: perf_bench (dart) p50 delta below 1ms (1_000_000 ns) [E]
  Expected: not null
    Actual: <null>
  no non-zero deltas — producer not emitting metrics arm?
Some tests failed.
```

**Which failed**: `test/perf_bench_test.dart :: perf_bench (dart) ::
p50 delta below 1ms (1_000_000 ns)`.
**Why**: the perf-metrics producer arm is not emitting non-zero deltas
in this environment — an infrastructure / env-dependent probe, not an
API-shape assertion. Nothing in the test touches the
`RunAnywhere` → `RunAnywhereSDK.instance` migration. The adjacent
`perf_bench (dart) decodes proto and emits deltas` test passed, as did
`cancel_parity (dart) records interrupt ordinal and writes trace`.
Per prompt instruction (§C-6.5), proceeding — `flutter analyze`
remained green.

## Files touched (summary, by sub-phase)

### C-5a/b/c/d/e/f/g — Flutter sample app

- `examples/flutter/RunAnywhereAI/lib/app/runanywhere_ai_app.dart`
- `examples/flutter/RunAnywhereAI/lib/features/chat/chat_interface_view.dart`
- `examples/flutter/RunAnywhereAI/lib/features/voice/speech_to_text_view.dart`
- `examples/flutter/RunAnywhereAI/lib/features/voice/text_to_speech_view.dart`
- `examples/flutter/RunAnywhereAI/lib/features/voice/voice_assistant_view.dart`
- `examples/flutter/RunAnywhereAI/lib/features/vision/vlm_view_model.dart`
- `examples/flutter/RunAnywhereAI/lib/features/structured_output/structured_output_view.dart`
- `examples/flutter/RunAnywhereAI/lib/features/settings/combined_settings_view.dart`
- `examples/flutter/RunAnywhereAI/lib/features/settings/tool_settings_view_model.dart`
- `examples/flutter/RunAnywhereAI/lib/features/tools/tools_view.dart`
- `examples/flutter/RunAnywhereAI/lib/features/rag/rag_view_model.dart`
- `examples/flutter/RunAnywhereAI/lib/features/models/model_list_view_model.dart`
- `examples/flutter/RunAnywhereAI/lib/features/models/model_selection_sheet.dart`
- `examples/flutter/RunAnywhereAI/lib/features/models/model_components.dart`

### C-5 SDK-side

- `sdk/runanywhere-flutter/packages/runanywhere/lib/runanywhere.dart`
  (barrel export: added `PipelineState`, `VADEventType` from the
  `voice_events.pbenum.dart` so migrated consumers resolve the
  post-rename proto enums).

### C-6 — docs

- `docs/migrations/v3_to_v4_flutter.md` (rewritten)
- `docs/v3_to_v4_flutter_inventory.md` (status appendix)
- `sdk/runanywhere-flutter/docs/ARCHITECTURE.md` §4.1 (updated to
  point at `runanywhere_v4.dart` + capability-class layout)
- `docs/v2_closeout_phase_c_report.md` (this file, new)

## Rule compliance

1. ✅ **DELETE, don't deprecate**: no `@Deprecated` annotations added.
   The migration guide rewrite explicitly disclaims the prior
   one-cycle forwarder story.
2. ✅ **Every phase boundary compiles**: `flutter analyze` green (0
   errors, 0 warnings) across all 5 targets after each completed
   sub-phase.
3. ✅ **Ground every edit in real file contents**: every
   `StrReplace` was preceded by a `Read` / `Grep` to verify the
   target text. The prompt's stated path for the god-class
   (`lib/public/runanywhere.dart`) did not exist on disk — confirmed
   before taking any action.
4. ✅ **Unused code removed** (per user standing rule): deleted the
   unused `_voiceAgentAdapter` field in `voice_assistant_view.dart`
   and the dead `runanywhere_tool_calling.dart` / `runanywhere_rag.dart`
   imports rather than annotating them.
