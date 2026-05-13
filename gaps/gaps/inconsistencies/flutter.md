# Flutter SDK — Open Inconsistencies & Simplification Candidates

> Updated: 2026-05-12
> Branch: `feat/v2-architecture`
> State: post-Wave-4 + Wave-B + Wave-E + Wave-G + Wave-H (Phase-B Swift parity + FIX-C revert). `flutter analyze` clean.
> Latest E2E: `20260512-215809` (post Wave-G + Phase-B parity + Wave-H FIX-C revert).
> Wave history: G shipped 2026-05-12 (`407d50819`) → H Phase-B parity + FIX-C revert 2026-05-12.

## Current state summary

Wave-G shipped 4 fixes (FIX-A through FIX-D) + 290 LOC dead-code purge. Wave-H empirical re-validation (`20260512-215809`) confirmed: FIX-A (`FLUTTER-ANDROID-003` HTTP transport FQN) **CLOSED** — 3 real downloads on Android (229 MB LFM2 + 62 MB Piper + 71 MB Whisper). FIX-B Android (System TTS gate) **CLOSED**; iOS **PARTIAL** (PlatformPluginBridge registers AVSpeechSynthesizer correctly but model load crashes via new -009). FIX-D (entitlement) **STILL OPEN** — 16 `-34018` hits, graceful fallback (LOW severity). FIX-C (Piper `Isolate.run`) **INVERTED → REVERTED**: the fix was the regression. Wrapping `rac_model_lifecycle_load_proto` in `Isolate.run` triggered universal model-load SIGABRTs on BOTH platforms because commons `model_lifecycle.cpp:191` publishes events from the worker thread and Dart 3.10 VM rejects cross-isolate FFI callbacks (`Cannot invoke native callback from a different isolate`). Wave-H reverted FIX-C in `dart_bridge_model_lifecycle.dart`. 3 NEW bugs discovered: `FLUTTER-ANDROID-004` BLOCKER (cross-isolate FFI callback assert; **CLOSED by revert** pending re-E2E), `FLUTTER-IOS-009` BLOCKER (same root cause; **CLOSED by revert** pending re-E2E), `FLUTTER-IOS-008` MEDIUM (download success doesn't refresh in-memory model registry — restart required; **OPEN**). `FLT-E2E-R2-002` proto flood **CLOSED** (0 hits across 20K+ log lines). `FLUTTER-IOS-006` STILL CLOSED. `FLUTTER-ANDROID-001` renamed/merged into `FLUTTER-ANDROID-004`. 10 Phase-B Swift parity items landed: INIT-001 (Phase 2 detach via `_servicesInitFuture` matching Swift `Task.detached`), EVENT-001 (`EventBus.onCategory`), LOG-001 (`LoggingConfiguration` field renames + `LogEntry` + `LogDestination` protocol), STOR-001 (4 storage methods + 2 FFI bindings), HW-001 (`getProfile()` throws), STRUCT-001 (`preparePromptForStructuredOutput()`), THINK-001 (audit no-op — Flutter already a superset), B8/B9/B10 (doc-only). Future work: commons-side fix for cross-isolate `sdk_event_publish` (`NativeCallable.listener` registration OR main-isolate event queue) to allow `Isolate.run` wrapping of heavy load paths without re-triggering `-004`/`-009`; `FLUTTER-IOS-003` Piper crash may recur post-revert and needs that commons fix.

Skip scope: `runanywhere_genie` package is deferred; do not file items about it being incomplete.

## A. Open R2 e2e bugs (post `20260512-215809` + Wave-H FIX-C revert)

<table>
<tr><th>ID</th><th>Severity</th><th>Lane</th><th>Summary (empirical verdict)</th><th>Root cause / fix path</th></tr>
<tr>
  <td><code>FLUTTER-ANDROID-003</code></td>
  <td>BLOCKER (→ <strong>CLOSED</strong>)</td>
  <td>05</td>
  <td><strong>CLOSED</strong> (Wave-H run <code>20260512-215809</code>) — 3 real downloads on Android (LFM2 229 MB + Piper 62 MB + Whisper 71 MB tar.gz) succeeded; zero <code>-805</code>/<code>-801</code>/<code>ClassNotFound</code> in 20K-line logcat. Wave-G FIX-A canonical FQN <code>OkHttpHttpTransport.kt</code> works.</td>
  <td>RESOLVED.</td>
</tr>
<tr>
  <td><code>FLT-E2E-R2-002</code></td>
  <td>HIGH (→ <strong>CLOSED</strong>)</td>
  <td>both</td>
  <td><strong>CLOSED</strong> — zero <code>InvalidProtocolBufferException</code> hits across 20K+ log lines in either lane.</td>
  <td>RESOLVED.</td>
</tr>
<tr>
  <td><code>FLUTTER-IOS-006</code></td>
  <td>HIGH (→ <strong>CLOSED</strong>)</td>
  <td>06</td>
  <td><strong>STILL CLOSED</strong> from Wave-G — zero <code>InvalidProtocolBufferException</code>/<code>invalid tag</code> hits in iOS Wave-H run logs.</td>
  <td>RESOLVED.</td>
</tr>
<tr>
  <td><code>FLUTTER-ANDROID-002</code></td>
  <td>HIGH (→ <strong>CLOSED</strong>)</td>
  <td>05</td>
  <td><strong>CLOSED</strong> — TTS picker shows only Piper rows; Speak-tab subtitle reads "Choose from Piper TTS." Android-only gate works.</td>
  <td>RESOLVED.</td>
</tr>
<tr>
  <td><code>FLUTTER-IOS-001</code></td>
  <td>HIGH (→ PASS pre-FIX-C; expected to return PASS post-revert)</td>
  <td>06</td>
  <td>Was PASS in Wave-G run. Regressed in Wave-H run via <code>FLUTTER-IOS-009</code> (cross-isolate crash). Should return to PASS after FIX-C revert. Pending re-E2E confirmation.</td>
  <td>Closed at the Dart layer (yield-loop). Wait for re-E2E.</td>
</tr>
<tr>
  <td><code>FLUTTER-IOS-002</code></td>
  <td>HIGH (→ <strong>PARTIAL</strong>)</td>
  <td>06</td>
  <td><strong>PARTIAL</strong> — Wave-G FIX-B PlatformPluginBridge correctly registers <code>AVSpeechSynthesizer</code> with commons (<code>rac_backend_platform_register</code> + <code>rac_plugin_register</code>). System TTS row visible in Speak tab. Load currently crashes via <code>FLUTTER-IOS-009</code> — not the routing fix's fault. Loads will succeed once <code>-009</code> unblocked by FIX-C revert. Pending re-E2E.</td>
  <td>Routing fix works; gated by <code>-009</code> until re-E2E.</td>
</tr>
<tr>
  <td><code>FLUTTER-IOS-003</code></td>
  <td>HIGH (→ <strong>STILL OPEN</strong>)</td>
  <td>06</td>
  <td><strong>STILL OPEN</strong> — Wave-G FIX-C (Isolate.run wrap) was reverted in Wave-H because it caused universal <code>-009</code>/<code>-004</code> on both platforms. Without the wrap, the original Piper TTS silent crash may recur on iOS. Needs commons-side fix to <code>rac_sdk_event_publish_proto</code>: register via <code>NativeCallable.listener</code> (cross-isolate-safe) OR queue events in C++ for main-isolate dispatch. Pending re-E2E to confirm whether Piper still crashes post-revert.</td>
  <td>Commons team: thread-safe event-publish refactor.</td>
</tr>
<tr>
  <td><code>FLUTTER-ANDROID-004</code> / <code>FLUTTER-IOS-009</code> (NEW Wave-H)</td>
  <td>BLOCKER (→ <strong>CLOSED by FIX-C revert</strong>, pending re-E2E)</td>
  <td>both</td>
  <td><strong>NEW Wave-H BLOCKER</strong> — same root cause on both platforms. <code>sdk/runanywhere-commons/src/core/model_lifecycle.cpp:191</code> calls <code>rac_sdk_event_publish_proto(...)</code> from the worker thread spawned by Wave-G FIX-C <code>Isolate.run</code>. Dart 3.10 VM rejects with <code>Cannot invoke native callback from a different isolate</code> (FFI callbacks registered via <code>NativeCallable.isolateLocal</code> can only fire on the registering isolate). SIGABRT on every model load (LLM/STT/TTS). Backtrace shows <code>rac_sdk_event_publish_proto+0x1c0</code> → <code>rac_model_lifecycle_load_proto+0x5f8</code>. Wave-H reverted the <code>Isolate.run</code> wrap (CLOSED pending re-E2E). Future commons-side fix needed so heavy load paths can be safely wrapped in <code>Isolate.run</code> again: switch event-publish to <code>NativeCallable.listener</code> registration OR queue events in C++ and publish on the originating isolate.</td>
  <td>Fix path: commons-side cross-isolate-safe event publish.</td>
</tr>
<tr>
  <td><code>FLUTTER-ANDROID-001</code> (renamed)</td>
  <td>HIGH (→ <strong>RENAMED to FLUTTER-ANDROID-004</strong>)</td>
  <td>05</td>
  <td>Original "no backend route" symptom is gone — plugin registration now clean (<code>rac_backend_llamacpp_register</code> rc=0). The remaining "no model load" symptom merged into <code>FLUTTER-ANDROID-004</code> (model-lifecycle cross-isolate SIGABRT). CLOSED by Wave-H FIX-C revert pending re-E2E.</td>
  <td>Tracked under <code>-004</code>.</td>
</tr>
<tr>
  <td><code>FLUTTER-IOS-007</code></td>
  <td>LOW (→ <strong>STILL OPEN</strong>)</td>
  <td>06</td>
  <td><strong>STILL OPEN</strong> — Wave-H run logged 16 hits of <code>-34018 "A required entitlement isn't present"</code>. Wave-G FIX-D entitlement removal + <code>CODE_SIGN_STYLE=Automatic</code> didn't fully suppress; SDK falls back gracefully. LOW severity. Real-device test recommended.</td>
  <td>Investigate residual -34018 path; may be platform_services probe rather than flutter_secure_storage.</td>
</tr>
<tr>
  <td><code>FLUTTER-IOS-008</code> (NEW Wave-H)</td>
  <td>MEDIUM (→ <strong>OPEN</strong>)</td>
  <td>06</td>
  <td><strong>NEW Wave-H</strong> — Download success path does NOT refresh the in-memory model registry. Freshly downloaded models do not appear in UI until the app is restarted. Fix: emit a registry-refresh event on download completion before triggering load.</td>
  <td>Flutter SDK: download → registry refresh wiring.</td>
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
<tr>
  <td>3</td>
  <td><strong>NEW (Wave-H finding)</strong>: cross-isolate <code>sdk_event_publish</code>. Commons <code>rac_sdk_event_publish_proto</code> callback is registered from Dart via <code>NativeCallable.isolateLocal</code>, so any C function that publishes events from a worker thread (e.g. <code>model_lifecycle.cpp:191</code> during load) crashes Dart 3.10 (<code>Cannot invoke native callback from a different isolate</code>). This blocks future <code>Isolate.run</code> wrappers of heavy load paths in the Flutter SDK (root cause behind reverted Wave-G FIX-C; see <code>FLUTTER-ANDROID-004</code> / <code>FLUTTER-IOS-009</code>).</td>
  <td><code>sdk/runanywhere-commons/src/core/model_lifecycle.cpp:191</code>; Dart-side registration in <code>sdk/runanywhere-flutter/packages/runanywhere/lib/native/dart_bridge_events.dart</code></td>
  <td>Commons-side fix: either (a) switch event-publish FFI callback to <code>NativeCallable.listener</code> registration so it is cross-isolate-safe, OR (b) queue events in C++ and publish them on the originating isolate's request boundary. Unblocks <code>FLUTTER-IOS-003</code> (Piper) and any other heavy-load Isolate.run wrappers.</td>
</tr>
</table>

## C. Open documentation drift

<table>
<tr><th>Doc</th><th>Item</th><th>Severity</th></tr>
<tr><td>Project root <code>CLAUDE.md</code></td><td>"Active issues" section still lists 4 SDK-level v2-architecture regressions. Confirm each is still current after this wave's resolutions.</td><td>LOW</td></tr>
<tr><td><code>gaps/gaps/inconsistencies/SWIFT-IOS-001-vad-route.md</code> ~line 166</td><td>Flutter-symlink stale claim was removed locally; sweep other docs to ensure none repeat the symlink narrative.</td><td>LOW</td></tr>
<tr><td><code>sdk/runanywhere-flutter/CLAUDE.md</code></td><td>Stale Wave-B-era claims (9 inaccuracies): capability count 20→18; deleted <code>vlmModels</code> accessor still listed; slice count narrative; folded slices <code>dev_config</code>/<code>platform_services</code>/<code>model_format</code> still listed; missing-codegen claim for <code>sdk_init</code>/<code>rac_options</code>/<code>router</code> (now regenerated); file count 104→116; schema count 26→29; verified-state date 2026-05-11→2026-05-12.</td><td>HIGH (developer-facing onboarding doc) — refreshed in companion plan execution (parallel agent).</td></tr>
</table>

## D. Simplification candidates (aggressive deletion / fold targets)

Only actionable items remain. Decided KEEPs (runanywhere_diffusion, runanywhere_embeddings, dart_bridge_diffusion, dart_bridge_embeddings, dart_bridge_solutions, dart_bridge_proto_utils, native_functions.dart) are removed from the table — git history is the audit trail.

<table>
<tr><th>#</th><th>File / construct</th><th>LOC</th><th>Recommendation</th><th>Risk</th></tr>
<tr><td>1</td><td><code>packages/runanywhere_llamacpp/lib/llamacpp_error.dart</code></td><td align="right">70</td><td>DELETED in this plan (2026-05-12) — not imported anywhere; Swift has no equivalent.</td><td>NONE</td></tr>
<tr><td>2</td><td><code>packages/runanywhere_genie/lib/genie_error.dart</code></td><td align="right">71</td><td>DELETED in this plan (2026-05-12) — not imported anywhere; Swift has no equivalent.</td><td>NONE</td></tr>
<tr><td>3</td><td><code>packages/runanywhere/lib/native/dart_bridge_model_format.dart</code></td><td align="right">149</td><td>FOLDED into <code>dart_bridge_model_registry.dart</code> in this plan (2026-05-12) — Swift handles this inline.</td><td>LOW (2 importers rewritten; <code>melos run analyze</code> pending)</td></tr>
</table>

## F. Cross-SDK naming alignment status

<table>
<tr><th>Concern</th><th>Swift</th><th>Kotlin</th><th>RN</th><th>Web</th><th>Flutter</th><th>Status</th></tr>
<tr><td>Entry point</td><td><code>enum RunAnywhere</code></td><td><code>object RunAnywhere</code></td><td><code>RunAnywhere</code> object</td><td><code>RunAnywhere</code> object</td><td><code>class RunAnywhereSDK</code> (<code>.instance</code> singleton)</td><td>OPEN by design — Flutter uses instance singleton; others use enum/object. Cosmetic only; deferred per Wave 3 plan to avoid breaking consumers.</td></tr>
<tr><td>Public init</td><td><code>initialize()</code> + <code>completeServicesInitialization()</code></td><td>same</td><td>same</td><td>same</td><td><code>initialize()</code> (phase-2 fire-and-forget)</td><td>ALIGNED — Wave B T6 wired canonical proto path.</td></tr>
<tr><td>Streaming primitive</td><td><code>AsyncStream</code></td><td><code>Flow</code></td><td>manual <code>AsyncIterable</code></td><td><code>AsyncIterable</code></td><td><code>Stream</code> via broadcast <code>StreamController</code></td><td>ALIGNED (idiomatic per language).</td></tr>
<tr><td>Error type</td><td><code>SDKException</code> proto-backed</td><td>same</td><td>same</td><td>same</td><td><code>SDKException</code> proto-backed</td><td>ALIGNED.</td></tr>
<tr><td>Cancel semantics</td><td><code>cancelGeneration()</code> / <code>cancelVLMGeneration()</code></td><td>same</td><td>same</td><td>same</td><td>renamed in this wave to match</td><td>ALIGNED (post-Wave-4).</td></tr>
<tr><td>Tool API verbs</td><td><code>registerTool</code> / <code>unregisterTool</code> / <code>getRegisteredTools</code> / <code>clearTools</code></td><td>same</td><td>same</td><td>same</td><td>renamed in this wave to match</td><td>ALIGNED (post-Wave-4).</td></tr>
<tr><td>LoRA class naming</td><td><code>RunAnywhere.lora</code></td><td><code>RunAnywhere.lora</code></td><td><code>RunAnywhere.lora</code></td><td><code>RunAnywhere.lora</code></td><td><code>RunAnywhereSDK.instance.lora</code> (type: <code>RunAnywhereLoRACapability</code>)</td><td>OPEN by design — Flutter uses <code>Capability</code> suffix on the class name; cosmetic only; deferred per Wave H plan 2026-05-12 (consumer breakage cost &gt; benefit).</td></tr>
<tr><td>Voice + VoiceAgent class separation</td><td>unified <code>RunAnywhere.voice</code> (one class)</td><td><code>RunAnywhere.voice</code> (one class)</td><td>similar</td><td>similar</td><td>separate <code>RunAnywhereVoice</code> (single-shot) + <code>RunAnywhereVoiceAgent</code> (pipeline)</td><td>OPEN by design — Flutter's split serves distinct example-app screens; unifying would require example-app refactor and break consumer ergonomics; deferred per Wave H plan 2026-05-12.</td></tr>
<tr><td>Phase-2 init detach (INIT-001)</td><td>Swift <code>Task.detached</code> in <code>initialize()</code></td><td>Kotlin <code>launch</code></td><td>similar</td><td>similar</td><td><code>_servicesInitFuture</code> assigned without await in <code>lib/public/runanywhere.dart</code></td><td>✅ ALIGNED (Wave-H 2026-05-12) — Phase 2 truly fire-and-forget; matches Swift Task.detached. Was previously eagerly-awaited despite doc claim.</td></tr>
<tr><td>EventBus per-category subscription (EVENT-001)</td><td><code>events(for: .category)</code></td><td><code>onCategory(EventCategory)</code></td><td>n/a</td><td>n/a</td><td><code>EventBus.onCategory(EventCategory)</code></td><td>✅ ALIGNED (Wave-H 2026-05-12).</td></tr>
<tr><td>Logging API (LOG-001)</td><td><code>LoggingConfiguration.minLogLevel</code> + <code>LogEntry</code> + <code>LogDestination</code> protocol</td><td>similar</td><td>similar</td><td>similar</td><td>field renames (e.g. <code>minimumLevel</code>→<code>minLogLevel</code>) + <code>LogEntry</code> class + <code>LogDestination</code> protocol + staging preset</td><td>✅ ALIGNED (Wave-H 2026-05-12).</td></tr>
<tr><td>Storage registration (STOR-001)</td><td>4 methods: <code>registerModel(URL)</code>, <code>registerArchiveModel</code>, <code>registerMultiFileModel</code>, <code>importModel</code></td><td>same</td><td>same</td><td>same</td><td>4 Swift-parity storage methods + 2 FFI bindings + 2 bridge methods</td><td>✅ ALIGNED (Wave-H 2026-05-12).</td></tr>
<tr><td>Hardware.getProfile error semantics (HW-001)</td><td>throws on failure</td><td>throws</td><td>throws</td><td>throws</td><td>now throws <code>SDKException</code> instead of returning empty fallback</td><td>✅ ALIGNED (Wave-H 2026-05-12).</td></tr>
<tr><td>Structured-output two-step prep (STRUCT-001)</td><td><code>preparePromptForStructuredOutput()</code></td><td>same</td><td>same</td><td>same</td><td><code>preparePromptForStructuredOutput()</code> helper added</td><td>✅ ALIGNED (Wave-H 2026-05-12).</td></tr>
<tr><td>Thinking-tag parser (THINK-001)</td><td>none</td><td>parser</td><td>parser</td><td>parser</td><td>parser (superset of Swift)</td><td>N/A — Flutter already a superset; audit confirmed no gap. Closed no-op (Wave-H 2026-05-12).</td></tr>
<tr><td>LoRA module exposure (LORA-001)</td><td><code>RunAnywhere.lora</code></td><td>same</td><td>same</td><td>same</td><td><code>RunAnywhereSDK.instance.lora</code> (type <code>RunAnywhereLoRACapability</code>)</td><td>DESIGN — Flutter uses Capability suffix; cosmetic; deferred (see row above).</td></tr>
<tr><td>Voice agent class split (VOICE-001)</td><td>unified</td><td>unified</td><td>similar</td><td>similar</td><td>split <code>RunAnywhereVoice</code> + <code>RunAnywhereVoiceAgent</code></td><td>DESIGN — Flutter's split serves example-app screens; deferred (see row above).</td></tr>
</table>

## G. Empirical Flutter Wave-H re-validation verdict (run `20260512-215809-flutter-h-revalidation`, HEAD `407d50819` + Phase-B uncommitted)

<table>
<tr><th>Bug</th><th>Severity</th><th>Lane</th><th>Wave-G fix shipped</th><th>Wave-H empirical verdict</th><th>Evidence</th></tr>
<tr><td><code>FLUTTER-ANDROID-003</code></td><td>BLOCKER</td><td>05</td><td>FIX-A (canonical OkHttpHttpTransport FQN)</td><td><strong>CLOSED</strong> — 3 real downloads on Android (LFM2 229MB + Piper 62MB + Whisper 71MB tar.gz); zero <code>-805</code>/<code>-801</code>/<code>ClassNotFound</code> in 20K-line logcat.</td><td><code>test_workflows/logs/20260512-215809-flutter-h-revalidation/05_flutter_android/agent_report.md</code></td></tr>
<tr><td><code>FLUTTER-ANDROID-002</code></td><td>HIGH</td><td>05</td><td>FIX-B (Android UI gate)</td><td><strong>CLOSED</strong> — TTS picker shows only Piper rows; Speak-tab subtitle reads "Choose from Piper TTS."</td><td><code>test_workflows/logs/20260512-215809-flutter-h-revalidation/05_flutter_android/screenshots/</code></td></tr>
<tr><td><code>FLUTTER-IOS-002</code></td><td>HIGH</td><td>06</td><td>FIX-B (PlatformPluginBridge)</td><td><strong>PARTIAL</strong> — bridge registers AVSpeechSynthesizer correctly; System TTS row visible. Load crashes via <code>-009</code> (not routing fault). Loads will work once <code>-009</code> re-tested post-revert.</td><td><code>test_workflows/logs/20260512-215809-flutter-h-revalidation/06_flutter_ios/logs/ios_live.log</code></td></tr>
<tr><td><code>FLUTTER-IOS-003</code></td><td>HIGH</td><td>06</td><td>FIX-C (Isolate.run wrap of lifecycle load)</td><td><strong>INVERTED → REVERTED</strong>. Fix IS the regression. Caused universal <code>-009</code>/<code>-004</code> SIGABRTs on both platforms (Dart 3.10 <code>Cannot invoke native callback from a different isolate</code>). Wave-H reverted in <code>dart_bridge_model_lifecycle.dart</code>. Original Piper crash may recur — needs commons-side fix.</td><td><code>test_workflows/logs/20260512-215809-flutter-h-revalidation/06_flutter_ios/logs/ios_live.log</code> (SIGABRT backtrace); revert: <code>sdk/runanywhere-flutter/packages/runanywhere/lib/native/dart_bridge_model_lifecycle.dart</code></td></tr>
<tr><td><code>FLUTTER-IOS-007</code></td><td>LOW</td><td>06</td><td>FIX-D (entitlement + CODE_SIGN_STYLE)</td><td><strong>STILL OPEN</strong> — 16 hits of <code>-34018 "A required entitlement isn't present"</code>; SDK falls back gracefully (LOW severity).</td><td><code>test_workflows/logs/20260512-215809-flutter-h-revalidation/06_flutter_ios/logs/ios_live.log</code></td></tr>
<tr><td><code>FLT-E2E-R2-002</code></td><td>HIGH</td><td>both</td><td>commons</td><td><strong>CLOSED</strong> — zero <code>InvalidProtocolBufferException</code> hits across 20K+ log lines in either lane.</td><td><code>test_workflows/logs/20260512-215809-flutter-h-revalidation/05_flutter_android/logs/android_live.log</code>; same for 06_flutter_ios</td></tr>
<tr><td><code>FLUTTER-IOS-006</code></td><td>HIGH</td><td>06</td><td>Wave-E plugin routing</td><td><strong>STILL CLOSED</strong> (from Wave-G).</td><td>zero <code>invalid tag</code>/<code>InvalidProtocolBufferException</code> hits in Wave-H iOS log</td></tr>
<tr><td><code>FLUTTER-IOS-001</code></td><td>HIGH</td><td>06</td><td>Dart yield-loop</td><td>Was PASS in Wave-G. Regressed in Wave-H via <code>-009</code>. Should return to PASS after FIX-C revert. Pending re-E2E.</td><td><code>test_workflows/logs/20260512-215809-flutter-h-revalidation/06_flutter_ios/logs/ios_live.log</code></td></tr>
<tr><td><code>FLUTTER-ANDROID-001</code></td><td>HIGH</td><td>05</td><td>Wave-E plugin routing</td><td><strong>RENAMED to <code>FLUTTER-ANDROID-004</code></strong> — original symptom resolved (plugin registration rc=0); remaining model-load failure merged into -004. CLOSED by Wave-H revert pending re-E2E.</td><td><code>test_workflows/logs/20260512-215809-flutter-h-revalidation/05_flutter_android/agent_report.md</code></td></tr>
<tr><td><strong><code>FLUTTER-ANDROID-004</code></strong> / <strong><code>FLUTTER-IOS-009</code></strong> (NEW Wave-H)</td><td>BLOCKER</td><td>both</td><td>n/a — caused by Wave-G FIX-C</td><td><strong>CLOSED by Wave-H FIX-C revert</strong> (pending re-E2E). Root cause: <code>model_lifecycle.cpp:191</code> publishes events from <code>Isolate.run</code> worker thread; Dart 3.10 VM aborts with <code>Cannot invoke native callback from a different isolate</code>.</td><td><code>test_workflows/logs/20260512-215809-flutter-h-revalidation/05_flutter_android/agent_report.md</code> + <code>06_flutter_ios/agent_report.md</code></td></tr>
<tr><td><strong><code>FLUTTER-IOS-008</code></strong> (NEW Wave-H)</td><td>MEDIUM</td><td>06</td><td>n/a</td><td><strong>OPEN</strong> — download success doesn't refresh in-memory model registry; restart required for UI to see freshly downloaded model.</td><td><code>test_workflows/logs/20260512-215809-flutter-h-revalidation/06_flutter_ios/agent_report.md</code></td></tr>
</table>

**Wave-H run summary**: 6 successful model downloads (3 unique × 2 lanes) but 0 real inferences this run (all loads SIGABRTed via -004/-009 before revert). Wave-H FIX-C revert is expected to unblock loads in next E2E. Bug-closure tally: 4 CLOSED (FIX-A, FIX-B Android, FLT-E2E-R2-002, FLUTTER-IOS-006), 1 PARTIAL (FIX-B iOS), 1 STILL OPEN (FIX-D), 1 INVERTED→REVERTED (FIX-C). 3 NEW bugs: 2 BLOCKER (closed by revert), 1 MEDIUM (open). Full report: `test_workflows/logs/20260512-215809-flutter-h-revalidation/REPORT.md`.
