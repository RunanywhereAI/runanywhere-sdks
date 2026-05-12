# Flutter SDK — Open Inconsistencies & Simplification Candidates

> Updated: 2026-05-11
> Branch: `feat/v2-architecture`
> State: post-Wave-4 + Wave-B. `flutter analyze` clean. Working tree dirty (uncommitted).

## Current state summary

Structurally the Flutter SDK is clean post-Wave-4 + Wave-B: 4 directory renames, 10 file/folder deletions (Wave B added 2 capability aliases), 12 stale `.so.bak` removals, and one stale dependency dropped. Two new bridge slices were added (`dart_bridge_sdk_init.dart` — now wired as canonical, `dart_bridge_structured_output.dart`) and 6 capability/bridge methods landed to match Swift parity. All known T15a, Phase-G, Wave-7B C ABIs are adopted in Dart; init + model-registry discovery are now driven by proto paths. The remaining items below are smaller-scope drift (open by design or example-app only).

Skip scope: `runanywhere_genie` package is deferred; do not file items about it being incomplete.

## A. Open R2 e2e bugs (2 remaining of 4 original)

<table>
<tr><th>ID</th><th>Severity</th><th>Lane</th><th>Summary</th><th>Root cause</th><th>Fix owner</th></tr>
<tr>
  <td><code>FLT-E2E-R2-002</code></td>
  <td>HIGH</td>
  <td>05 Flutter Android</td>
  <td><code>DartBridge</code> emits 7 783 <code>InvalidProtocolBufferException</code> while decoding <code>DownloadProgress</code>; UI stalls at 91 %.</td>
  <td>C++ ring-slot lifetime in <code>download_orchestrator.cpp:475-504</code> — <code>std::string&amp;</code> is overwritten before the Dart callback finishes serializing. NOT a Dart-side bug; wire format is bit-exact.</td>
  <td>C++ commons team (tracked as CPP-E2E-R2-004)</td>
</tr>
<tr>
  <td><code>FLT-E2E-R2-003</code></td>
  <td>HIGH</td>
  <td>06 Flutter iOS</td>
  <td><code>rac_model_format_from_url_proto</code> and <code>rac_artifact_infer_from_url_proto</code> miss <code>dlsym</code> on every catalog entry.</td>
  <td>Shipped xcframeworks timestamped May 4 17:15 predate commit <code>7ac5db254</code> (May 4 23:06) which landed the <code>.cpp</code> implementations. Rebuild via <code>./scripts/build-core-xcframework.sh</code>.</td>
  <td>Build pipeline</td>
</tr>
</table>

## B. Open architectural drift (Flutter vs Swift)

<table>
<tr><th>#</th><th>Item</th><th>File(s)</th><th>Action</th></tr>
<tr>
  <td>1</td>
  <td>AGP 8.1.0 / Kotlin 1.9.10 / compileSdk 34 in all 4 Flutter <code>android/build.gradle</code> files.</td>
  <td>4 <code>android/build.gradle</code> files under <code>packages/runanywhere{,_llamacpp,_onnx,_genie}/</code></td>
  <td>Kotlin SDK uses 8.11.2 / 2.1.21 / 35. Open by design — bump only if the Kotlin SDK pin is chosen as canonical.</td>
</tr>
<tr>
  <td>2</td>
  <td>W2 example-app workaround still live (500 ms post-download wait).</td>
  <td><code>examples/flutter/RunAnywhereAI/lib/app/runanywhere_ai_app.dart:145</code></td>
  <td>Deferred per user — example-app only, not SDK code.</td>
</tr>
</table>

## C. Open documentation drift

<table>
<tr><th>Doc</th><th>Item</th><th>Severity</th></tr>
<tr><td>Project root <code>CLAUDE.md</code></td><td>"Active issues" section still lists 4 SDK-level v2-architecture regressions. Confirm each is still current after this wave's resolutions.</td><td>LOW</td></tr>
<tr><td><code>gaps/gaps/inconsistencies/SWIFT-IOS-001-vad-route.md</code> ~line 166</td><td>Flutter-symlink stale claim was removed locally; sweep other docs to ensure none repeat the symlink narrative.</td><td>LOW</td></tr>
</table>

## D. Simplification candidates (aggressive deletion / fold targets)

These are Flutter-only constructs with no direct Swift counterpart. Decision rule: KEEP if it adds Dart-idiomatic value, DELETE / FOLD if it is pure indirection.

<table>
<tr><th>#</th><th>File / construct</th><th>LOC</th><th>Recommendation</th><th>Risk</th></tr>
<tr><td>1</td><td><code>runanywhere_diffusion.dart</code></td><td align="right">202</td><td>KEEP — Swift has no public diffusion surface yet, but Flutter exposes it; diffusion is a real capability.</td><td>n/a</td></tr>
<tr><td>2</td><td><code>runanywhere_embeddings.dart</code></td><td align="right">144</td><td>KEEP — Swift exposes via <code>NativeProtoABI</code> inline; Flutter's class surface is reasonable.</td><td>n/a</td></tr>
<tr><td>3</td><td><code>dart_bridge_diffusion.dart</code> + <code>dart_bridge_embeddings.dart</code></td><td align="right">87 + 53</td><td>KEEP — paired with the capability classes above.</td><td>n/a</td></tr>
<tr><td>4</td><td><code>dart_bridge_solutions.dart</code></td><td align="right">128</td><td>KEEP — Swift has <code>RunAnywhere+Solutions.swift</code>; Flutter bridge slice is the matching layer.</td><td>n/a</td></tr>
<tr><td>5</td><td><code>dart_bridge_model_format.dart</code></td><td align="right">149</td><td>Consider folding into <code>dart_bridge_model_registry.dart</code> — Swift handles this inline.</td><td>MEDIUM.</td></tr>
<tr><td>6</td><td><code>dart_bridge_proto_utils.dart</code></td><td align="right">119</td><td>KEEP — equivalent of Swift's <code>CppBridge+NativeProtoABI.swift</code>.</td><td>n/a</td></tr>
<tr><td>7</td><td><code>lib/native/native_functions.dart</code> (post-Wave-K cleanup of -109 LOC)</td><td align="right">271</td><td>KEEP — equivalent of Swift's <code>ComponentVTable.swift</code>.</td><td>n/a</td></tr>
</table>

## E. Resolved 2026-05-11 (recent wave closures)

For audit trail. All items below are CLOSED on the working tree (uncommitted).

### Wave B (2026-05-11 follow-up) — closes 8 items vs Swift ARCHITECTURE.md

- **T1** — 4 dead ONNX Result Dart structs (`RacSttOnnxResultStruct`, `RacTtsOnnxResultStruct`, `RacVadOnnxResultStruct`, `RacVadResultStruct`) deleted from `speech_struct_types.dart` (−49 LOC; no C counterpart, zero in-tree usages).
- **T2** — `format` field (`rac_tool_call_format_t`) added to `RacToolCallStruct` (5→6 fields; +5 LOC; matches C `rac_tool_call_t`).
- **T3** — `runanywhere_vision_language.dart` deleted (9-LOC alias shim; barrel exports already include both names).
- **T4** — `runanywhere_vlm_models.dart` deleted (29 LOC); `vlmModels` accessor removed from `RunAnywhereSDK` singleton + barrel.
- **T5** — W1 `adapter.ref.nowMs = nullptr` reclassified as "correct-by-design" — matches Swift's `PlatformAdapter` behavior (Dart `Pointer.fromFunction` thread-safety constraints documented inline). NOT A WORKAROUND.
- **T6** — `DartBridge.initialize()` migrated to proto path (`rac_sdk_init_phase1_proto` + `phase2_proto`); legacy `rac_sdk_init` + `RacSdkConfigStruct` init path deleted from `dart_bridge.dart` (−43 LOC + new proto envelope logging).
- **T7** — `dart_bridge_model_registry.dart` discovery migrated to `rac_model_registry_discover_proto`; legacy struct + 5 callbacks deleted (−185 LOC).
- **T8** — `extractStructuredOutput` moved to `RunAnywhereLLM` instance method (matches Swift §5.4.1.4); `runanywhere_thinking_utils.dart` slimmed 107→74 LOC; kept thinking-token parsers.
- **W6** — iOS `protoAvailable()` forced-false workaround — not found in source code; already resolved in an earlier wave.

### File renames (4)

- `lib/public/runanywhere_v4.dart` → `lib/public/runanywhere.dart`
- `lib/foundation/error_types/` → `lib/foundation/errors/`
- `lib/foundation/configuration/` → `lib/foundation/constants/`
- `lib/generated/stt_options_helpers.dart` → `lib/public/extensions/stt/stt_options_helpers.dart`

### Files deleted (8 files + 1 folder + 12 backups + 1 doc-issue)

- `lib/foundation/dependency_injection/service_container.dart` (97 LOC; inlined into entry)
- `lib/internal/sdk_init.dart` (100 LOC; inlined into platform/bridge)
- `lib/internal/sdk_state.dart` (32 LOC; replaced by C-side global lifecycle)
- `lib/internal/sdk_event_factories.dart` (238 LOC; plus 32 redundant publish call-sites removed across 6 capability files — C++ commons auto-publishes via `event_publisher.cpp` + `rac_rag_proto_abi.cpp`)
- `lib/native/dart_bridge_platform_services.dart` (89 LOC; folded into `dart_bridge_platform.dart`)
- `lib/native/dart_bridge_dev_config.dart` (109 LOC; folded into `dart_bridge_environment.dart`)
- `lib/native/ffi_types.dart` (14-LOC barrel; 32 importers switched to direct paths)
- `lib/data/network/` folder (`network.dart` + `network_configuration.dart`)
- 12 `.so.bak` files across all `jniLibs/{abi}/`
- `thoughts/shared/issues/004_flutter_symlink_risk.md` (state resolved)
- `rxdart` dependency from `pubspec.yaml` (unused)

### Files added (2)

- `lib/native/dart_bridge_sdk_init.dart` (143 LOC; mirrors Swift `CppBridge+SdkInit.swift`)
- `lib/native/dart_bridge_structured_output.dart` (118 LOC; mirrors Swift `CppBridge+StructuredOutput.swift`)

### Bridge slice additions (existing files)

- `dart_bridge_events.dart`: + `clearQueue()`
- `dart_bridge_file_manager.dart`: + `modelFolderHasContents()`
- `dart_bridge_hardware.dart`: + `getAccelerators()`
- `dart_bridge_plugin_loader.dart`: + `listLoaded()`
- `dart_bridge_tool_calling.dart`: + `toolValueToJson` / `toolValueFromJson`
- `rac_native.dart`: + `rac_audio_compute_level_db`, `rac_vlm_cancel_lifecycle_proto`

### Bridge slice cleanup

- `rac_native.dart`: −33 LOC dead VLM struct-path bindings
- `native_functions.dart`: −109 LOC dead lookups (`loadModel`, `loadVoice`, cleanup variants, VAD lifecycle, voice-agent transcribe / synthesize)

### Capability surface alignment (8 renames, 7 additions)

- LLM: `cancel()` → `cancelGeneration()`
- VLM: `cancel()` → `cancelVLMGeneration()`
- Tools: `register` / `unregister` / `registeredTools` / `clear` → `registerTool` / `unregisterTool` / `getRegisteredTools` / `clearTools`
- Models: + `getModel(req)`, `queryModels()`, `downloadedModels()`
- LoRA: + `markImportCompleted()`
- Hardware: + `getAccelerators()`
- PluginLoader: + `listLoaded()`
- Storage: + `getStorageInfo()`, `deleteStorage()`, `clearCache()`, `cleanTempFiles()`

### Phase-2 / Phase-G / T15a / Wave-7 ABI adoptions

- All 5 T15a enum mapper ABIs (`rac_inference_framework_*`, `rac_model_category_*`, `rac_model_format_*`, `rac_model_source_*`, `rac_archive_type_*`) — adopted in `model_types_cpp_bridge.dart`
- Wave 7A archive structure mapper (`rac_archive_structure_*`) — adopted in `dart_bridge_model_paths.dart`
- Wave 7B VLM cancel lifecycle (`rac_vlm_cancel_lifecycle_proto`) — confirmed in `dart_bridge_vlm.dart`
- Phase G audio level dB (`rac_audio_compute_level_db`) — replaces hand-rolled DSP in `audio_capture_manager.dart` (−30 LOC)
- Phase G tool value JSON (`rac_tool_value_{to,from}_json_proto`) — wired in `dart_bridge_tool_calling.dart`
- Phase 2 pt 2: `dart_bridge_sdk_init.dart` created and (Wave B T6) wired as the canonical init path via `rac_sdk_init_phase1_proto` + `phase2_proto`
- Phase 2 (earlier): structured-output proto wired via new `dart_bridge_structured_output.dart`

### Struct field fixes (Dart FFI ↔ C ABI)

- `RacPlatformAdapterStruct`: +3 fields (`fileListDirectory`, `isNonEmptyDirectory`, `getVendorId`) → 18 fields, matches C
- `RacVadOnnxConfigStruct`: field order corrected; `frame_length` retyped to `Float`

### Bug fixes (R2)

- `FLT-E2E-R2-001`: NDK fallback bumped 25.2.9519653 → 27.0.12077973 in all 4 `android/build.gradle` files. CLOSED.
- `FLT-E2E-R2-004`: `HttpClientException` now wrapped in `SDKException.authenticationFailed` in `dart_bridge_auth.dart`. CLOSED.

### Native plumbing alignment

- `URLSessionHttpTransport.mm` — 7 Swift-parity gaps fixed: `cancelAllStreams`, `register(streamingSession:)`, `X-RAC-Range-Honored` 206 header, 24 h `timeoutIntervalForResource`, `waitsForConnectivity`, `resumeFromByte` 206 byte-count adjustment, `os_log` subsystem
- `URLSessionHttpTransport.swift` façade: added `register(streamingSession:)`, `cancelAllStreams()`
- `LlamaCppPlugin.kt`: `loadFirstAvailable(...)` swallow-helper replaced with explicit `System.loadLibrary` chain (deterministic load order)
- `RunAnywhereBridge.kt`: added `const val RAC_SUCCESS = 0`
- `RunAnywherePlugin.kt`: uses `RunAnywhereBridge.RAC_SUCCESS` constant (no magic numbers)
- `GeniePlugin.{swift,kt}`: aligned version `"0.1.6"` → `"0.3.0"` (matches `binary_config.gradle` and `genie.dart`)
- `RACommons.exports`: synced 505 → 802 symbols (canonical from commons)

### Documentation rewrites

- `sdk/runanywhere-flutter/CLAUDE.md` (402 LOC → 302 LOC)
- `sdk/runanywhere-flutter/docs/ARCHITECTURE.md` (~440 lines)
- `sdk/runanywhere-flutter/docs/Documentation.md` (~530 lines)
- All 3 in-scope package READMEs updated (`runanywhere`, `runanywhere_llamacpp`, `runanywhere_onnx`)
- Cross-doc Flutter-`symlink` stale claims removed (project CLAUDE.md, SWIFT-IOS-001-vad-route.md, issues/README.md)

### Other

- 32 redundant `EventBus.publish(...)` call-sites deleted across 6 capability files (SDK init, RAG, LLM, STT, TTS, VLM). C++ commons auto-publishes; Swift never re-published; Flutter now matches.

## F. Cross-SDK naming alignment status

<table>
<tr><th>Concern</th><th>Swift</th><th>Kotlin</th><th>RN</th><th>Web</th><th>Flutter</th><th>Status</th></tr>
<tr><td>Entry point</td><td><code>enum RunAnywhere</code></td><td><code>object RunAnywhere</code></td><td><code>RunAnywhere</code> object</td><td><code>RunAnywhere</code> object</td><td><code>class RunAnywhereSDK</code> (<code>.instance</code> singleton)</td><td>OPEN by design — Flutter uses instance singleton; others use enum/object. Cosmetic only; deferred per Wave 3 plan to avoid breaking consumers.</td></tr>
<tr><td>Public init</td><td><code>initialize()</code> + <code>completeServicesInitialization()</code></td><td>same</td><td>same</td><td>same</td><td><code>initialize()</code> (phase-2 fire-and-forget)</td><td>ALIGNED — Wave B T6 wired canonical proto path.</td></tr>
<tr><td>Streaming primitive</td><td><code>AsyncStream</code></td><td><code>Flow</code></td><td>manual <code>AsyncIterable</code></td><td><code>AsyncIterable</code></td><td><code>Stream</code> via broadcast <code>StreamController</code></td><td>ALIGNED (idiomatic per language).</td></tr>
<tr><td>Error type</td><td><code>SDKException</code> proto-backed</td><td>same</td><td>same</td><td>same</td><td><code>SDKException</code> proto-backed</td><td>ALIGNED.</td></tr>
<tr><td>Cancel semantics</td><td><code>cancelGeneration()</code> / <code>cancelVLMGeneration()</code></td><td>same</td><td>same</td><td>same</td><td>renamed in this wave to match</td><td>ALIGNED (post-Wave-4).</td></tr>
<tr><td>Tool API verbs</td><td><code>registerTool</code> / <code>unregisterTool</code> / <code>getRegisteredTools</code> / <code>clearTools</code></td><td>same</td><td>same</td><td>same</td><td>renamed in this wave to match</td><td>ALIGNED (post-Wave-4).</td></tr>
</table>
