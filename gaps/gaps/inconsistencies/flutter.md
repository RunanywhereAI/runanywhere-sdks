# Flutter SDK — Open Inconsistencies & Simplification Candidates

> Updated: 2026-05-12
> Branch: `feat/v2-architecture`
> State: post-Wave-4 + Wave-B + Wave-E (commons Bug-5/9/10/11) + dead-code purge. `flutter analyze` clean. Working tree dirty (uncommitted).
> Latest E2E: **`20260512-141845`** (HEAD `ce1f6bbec`) — empirical re-test against post-Wave-E commons

## Current state summary

Structurally aligned post-Wave-4 + Wave-B + Wave-E commons fixes. `flutter analyze` clean. The `20260512-141845` re-test produced four big findings: (1) **`FLUTTER-IOS-006` CLOSED** — full grep of `06_flutter_ios/logs/ios_live.log` for `InvalidProtocolBufferException`/`invalid tag` returned zero hits; the Wave-E plugin-routing fix (commit `80feae082`) appears to have addressed the buffer-lifetime issue. (2) **`FLUTTER-IOS-001` now PASS** — no LLM streaming hang reproduced; LFM2-350M-Q4_K_M model loaded into llama.cpp cleanly. (3) **`FLUTTER-IOS-002`, `FLUTTER-ANDROID-002`, `FLUTTER-IOS-003` STILL OPEN** — System TTS routing missing on both platforms (Bug-11 fix was Kotlin-only) and Piper voice load still crashes silently. (4) **NEW BLOCKER `FLUTTER-ANDROID-003`** — JNI/OkHttp FQN mismatch: shim `okhttp_transport_adapter.cpp:557` looks up `com/runanywhere/sdk/httptransport/OkHttpHttpTransport` but the Flutter Android plugin ships only `com.runanywhere.sdk.foundation.http.OkHttpTransport`; ClassNotFound → rc=-805 → HTTP transport vtable never installs → downloads, auth, telemetry all dead → 10 of 14 Android modalities BLOCKED. `FLUTTER-ANDROID-001` cannot be re-tested while -003 blocks downloads (plugin registration is now clean — `rac_backend_llamacpp_register` rc=0 — so the original symptom looks fixed). One real inference output captured this run: iOS STT (Sherpa Whisper Tiny English). Concurrent dead-code cleanup landed in this plan: `llamacpp_error.dart` (70 LOC) deleted, `genie_error.dart` (71 LOC) deleted, `dart_bridge_model_format.dart` (149 LOC) folded into `dart_bridge_model_registry.dart` (−290 LOC net). `sdk/runanywhere-flutter/CLAUDE.md` refreshed (9 stale claims fixed).

Skip scope: `runanywhere_genie` package is deferred; do not file items about it being incomplete.

## A. Open R2 e2e bugs (post `20260512-141845-flutter-e2e`)

<table>
<tr><th>ID</th><th>Severity</th><th>Lane</th><th>Summary (empirical verdict)</th><th>Root cause</th><th>Fix owner</th></tr>
<tr>
  <td><code>FLUTTER-ANDROID-003</code></td>
  <td>BLOCKER (→ <strong>FIX LANDED 2026-05-12</strong>, pending re-E2E)</td>
  <td>05 Flutter Android</td>
  <td>FIX LANDED — created canonical <code>com/runanywhere/sdk/httptransport/OkHttpHttpTransport.kt</code> matching Kotlin SDK FQN; added <code>register</code>/<code>unregister</code>/<code>executeResumeRequest</code>/<code>cancelAllStreams</code> + <code>HttpResponse</code>/<code>StreamResponse</code> inner classes + Range-honored 206 disclosure + in-flight stream registry; updated <code>RunAnywherePlugin.kt</code> to call <code>OkHttpHttpTransport.register()</code> (Swift parity); deleted old <code>foundation/http/OkHttpTransport.kt</code>. Verified by <code>./gradlew :runanywhere:assembleDebug</code> — BUILD SUCCESSFUL in 47s.</td>
  <td>The JNI shim's <code>FindClass("com/runanywhere/sdk/httptransport/OkHttpHttpTransport")</code> at <code>sdk/runanywhere-commons/src/jni/okhttp_transport_adapter.cpp:557</code> now resolves; HTTP transport vtable installs; <code>rac_http_request_*</code> calls succeed.</td>
  <td>RESOLVED — close in next doc refresh after Flutter Android E2E confirms downloads work end-to-end.</td>
</tr>
<tr>
  <td><code>FLT-E2E-R2-002</code></td>
  <td>HIGH</td>
  <td>05 Flutter Android</td>
  <td>NOT REPRODUCED (20260512-141845) — no <code>InvalidProtocolBufferException</code> lines in either lane's logs. Downloads never started on Android due to <code>FLUTTER-ANDROID-003</code>; cannot exercise the ring-slot path. Tracked separately as <code>CPP-E2E-R2-004</code>.</td>
  <td>C++ ring-slot lifetime in <code>download_orchestrator.cpp:475-504</code>. Independent of this Flutter wave.</td>
  <td>C++ commons team (tracked as <code>CPP-E2E-R2-004</code>). Re-test once <code>FLUTTER-ANDROID-003</code> is fixed.</td>
</tr>
<tr>
  <td><code>FLUTTER-IOS-002</code> / <code>FLUTTER-ANDROID-002</code></td>
  <td>HIGH (→ <strong>FIX LANDED 2026-05-12</strong>, pending re-E2E)</td>
  <td>both lanes (05 + 06)</td>
  <td>FIX LANDED — iOS: new <code>PlatformPluginBridge.mm</code> (387 LOC ObjC++) + <code>PlatformPluginBridge.swift</code> (49 LOC façade) wires <code>AVSpeechSynthesizer</code> into commons <code>rac_backend_platform_register()</code> + <code>rac_plugin_register(rac_plugin_entry_platform())</code>; <code>RunAnywherePlugin.swift</code> calls <code>PlatformPluginBridge.register()</code>. Matches Swift's <code>CppBridge+Platform.swift</code> exactly. Android: <code>framework=platform</code> is Apple-only in commons (<code>sdk/runanywhere-commons/CMakeLists.txt:732</code>: <code>if(APPLE AND RAC_BUILD_PLATFORM)</code>), so System TTS row gated behind <code>Platform.isIOS || Platform.isMacOS</code> in example app (mirrors Kotlin Android example which uses local <code>android.speech.tts.TextToSpeech</code> outside the SDK).</td>
  <td>iOS: commons platform plugin now has callbacks wired and is registered with the router. Android: Apple-only by design (commons has no Android <code>framework=platform</code> route); cosmetic UI gate.</td>
  <td>Verified by <code>flutter analyze</code> clean across example app + SDK. Needs <code>pod install</code> on next iOS run to pick up the 2 new pod files. Close in next doc refresh after Flutter iOS E2E confirms TTS audio plays + Android model picker no longer shows System TTS.</td>
</tr>
<tr>
  <td><code>FLUTTER-IOS-003</code></td>
  <td>HIGH (→ <strong>FIX LANDED 2026-05-12</strong>, pending re-E2E)</td>
  <td>06 Flutter iOS</td>
  <td>FIX LANDED — root cause identified as main-Dart-isolate stack exhaustion during <code>SherpaOnnxCreateOfflineTts()</code> Piper VITS pipeline init (espeak-ng + piper_phonemize static initializers + large ONNX graph allocation). Main Dart isolate has smaller stack than typical iOS GCD threads → stack overflow / signal kill / iOS watchdog (no Dart exception, consistent with OS-level termination at 14:42:16.752, 550ms after load start). STT didn't crash because Sherpa Whisper init path is simpler (no espeak/phonemize). Fix: wrapped <code>rac_model_lifecycle_load_proto</code> in <code>Isolate.run</code> inside <code>dart_bridge_model_lifecycle.dart</code>'s <code>load()</code> method — worker isolate gets fresh ~1MB+ stack, matches Swift <code>Task</code> / Kotlin <code>withContext(Dispatchers.IO)</code> / RN worker pattern (already used by <code>HttpClientAdapter.rawRequest</code> at <code>http_client_adapter.dart:229</code>).</td>
  <td>Was: silent C++ stack exhaustion in sherpa-onnx Piper init on main Dart isolate. Now: heavy init runs on dedicated worker isolate; failures (if any) propagate as structured <code>SDKException</code> instead of OS-level termination.</td>
  <td>Verified <code>flutter analyze</code> clean across all packages + example app. Runtime verification requires E2E re-run on Flutter iOS lane.</td>
</tr>
<tr>
  <td><code>FLUTTER-ANDROID-001</code></td>
  <td>HIGH</td>
  <td>05 Flutter Android</td>
  <td>UNTESTABLE (20260512-141845) — plugin registration logs now clean (<code>rac_backend_llamacpp_register() returned 0 (Success)</code>) suggesting the routing fix in <code>80feae082</code> landed, but load+infer cannot be exercised because all downloads are blocked by <code>FLUTTER-ANDROID-003</code>. Re-test once -003 is fixed.</td>
  <td>Most-likely closure by Wave-E commit <code>80feae082</code> Bug-5/9 plugin routing. Pending empirical confirmation via fresh Android lane run.</td>
  <td>flutter-android-sdk / commons. Defer until <code>FLUTTER-ANDROID-003</code> resolved.</td>
</tr>
<tr>
  <td><code>FLUTTER-IOS-001</code></td>
  <td>HIGH (→ PASS pending FLUTTER-IOS-006 closure confirmation)</td>
  <td>06 Flutter iOS</td>
  <td>PASS (20260512-141845) — no LLM streaming hang reproduced. <code>Future.delayed</code> yield-loop fix in <code>runanywhere_llm.dart</code> unblocks the streaming controller. LFM2-350M-Q4_K_M loaded cleanly into llama.cpp. Evidence: <code>06_flutter_ios/logs/ios_live.log</code> (line: <code>llama_context: n_ctx_seq (1024) &lt; n_ctx_train (128000)</code>).</td>
  <td>Closed at the Dart layer; companion FLUTTER-IOS-006 (proto decode) also CLOSED.</td>
  <td>Close in next doc refresh.</td>
</tr>
<tr>
  <td><code>FLUTTER-IOS-006</code></td>
  <td>HIGH (→ CLOSED)</td>
  <td>06 Flutter iOS</td>
  <td>CLOSED (20260512-141845) — full grep of <code>06_flutter_ios/logs/ios_live.log</code> for <code>InvalidProtocolBufferException</code> / <code>invalid tag</code> returned zero hits across the entire 10 118-line session. Likely closed by Wave-E commit <code>80feae082</code> Bug-5/9 plugin routing (which probably fixed the underlying commons buffer-lifetime issue too).</td>
  <td>Closure verified empirically.</td>
  <td>Close in next doc refresh.</td>
</tr>
<tr>
  <td><code>FLUTTER-IOS-007</code></td>
  <td>LOW (→ <strong>FIX LANDED 2026-05-12</strong>, real-device re-test recommended)</td>
  <td>06 Flutter iOS</td>
  <td>FIX LANDED — root cause was ad-hoc simulator signing: declared <code>keychain-access-groups</code> entitlement requires provisioning-profile resolution, which ad-hoc-signed binaries can't honor → Security framework returns -34018. Fix: removed <code>keychain-access-groups</code> array from <code>Runner.entitlements</code> (only relevant for cross-app/extension Keychain sharing, which this app doesn't need); added <code>CODE_SIGN_STYLE = Automatic</code> to all 3 build configs in <code>Runner.xcodeproj</code> (matches Swift example pattern). <code>flutter_secure_storage</code> now uses default per-bundle-id Keychain access group, which simulator supports.</td>
  <td>n/a — fixed</td>
  <td>Verified by <code>flutter build ios --simulator --debug --no-codesign</code> (≈8.5s, codesign empty dict). Real-device test recommended to confirm flutter_secure_storage still works on device with empty entitlements (the per-bundle-id default keychain should always work without explicit declaration).</td>
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
  <td><strong>FIX LANDED 2026-05-12</strong> — <code>FLUTTER-ANDROID-003</code> resolved (see §A). New canonical-aligned <code>OkHttpHttpTransport.kt</code> at <code>com/runanywhere/sdk/httptransport/</code> matches Kotlin SDK FQN; <code>register</code>/<code>unregister</code>/<code>executeResumeRequest</code>/<code>cancelAllStreams</code> + <code>HttpResponse</code>/<code>StreamResponse</code> inner classes added; Range-honored 206 disclosure + in-flight registry implemented. <code>RunAnywherePlugin.kt</code> now calls <code>OkHttpHttpTransport.register()</code> (Swift parity).</td>
  <td>New: <code>sdk/runanywhere-flutter/packages/runanywhere/android/src/main/kotlin/com/runanywhere/sdk/httptransport/OkHttpHttpTransport.kt</code> (mirrors <code>sdk/runanywhere-kotlin/src/jvmAndroidMain/kotlin/com/runanywhere/sdk/httptransport/OkHttpHttpTransport.kt</code>).</td>
  <td>Verified by <code>./gradlew :runanywhere:assembleDebug</code> — BUILD SUCCESSFUL in 47s. Close row in next doc refresh after Flutter Android E2E confirms downloads work end-to-end.</td>
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
</table>

## G. Empirical Flutter re-validation verdict (run `20260512-141845-flutter-e2e`, HEAD `ce1f6bbec`)

<table>
<tr><th>Bug</th><th>Severity</th><th>Lane</th><th>Likely-closure source</th><th>Empirical verdict</th><th>Evidence</th></tr>
<tr><td><code>FLUTTER-IOS-006</code></td><td>HIGH</td><td>06</td><td>Bug-5/9 plugin routing (<code>80feae082</code>)</td><td><strong>CLOSED</strong> — not reproduced; 0 hits for <code>InvalidProtocolBufferException</code>/<code>invalid tag</code> in 10 118-line iOS session log.</td><td><code>06_flutter_ios/logs/ios_live.log</code></td></tr>
<tr><td><code>FLUTTER-IOS-001</code></td><td>HIGH</td><td>06</td><td>Dart-side <code>Future.delayed</code> yield-loop fix (already merged in <code>runanywhere_llm.dart</code>)</td><td><strong>PASS</strong> — no streaming hang reproduced; model loaded cleanly.</td><td><code>06_flutter_ios/logs/ios_live.log</code> (llama_context warning at 14:30:19)</td></tr>
<tr><td><code>FLUTTER-IOS-002</code> / <code>FLUTTER-ANDROID-002</code></td><td>HIGH</td><td>both</td><td>Bug-10 sherpa plugin route (<code>ad03b541e</code>) — speculated cross-platform closure</td><td><strong>FIX LANDED 2026-05-12</strong> — iOS gets PlatformPluginBridge (AVSpeechSynthesizer + rac_plugin_register); Android gates System TTS row (Apple-only by design). Pending re-E2E.</td><td>flutter analyze clean; 2 new pod files; example-app gates verified</td></tr>
<tr><td><code>FLUTTER-IOS-003</code></td><td>HIGH</td><td>06</td><td>Bug-9 sherpa archive extraction (<code>80feae082</code>)</td><td><strong>FIX LANDED 2026-05-12</strong> — wrapped lifecycle load in Isolate.run to give Sherpa Piper init a fresh worker stack (matches Swift Task / Kotlin Dispatchers.IO). Pending re-E2E.</td><td><code>dart_bridge_model_lifecycle.dart</code> load() now dispatches via Isolate.run</td></tr>
<tr><td><code>FLUTTER-ANDROID-001</code></td><td>HIGH</td><td>05</td><td>Bug-5/9 plugin routing (<code>80feae082</code>)</td><td><strong>UNTESTABLE</strong> — plugin registration logs are now clean (<code>rac_backend_llamacpp_register</code> rc=0) suggesting routing fix landed, but downloads dead due to <code>FLUTTER-ANDROID-003</code>; cannot exercise load+infer.</td><td><code>05_flutter_android/agent_report.md</code></td></tr>
<tr><td><code>FLT-E2E-R2-002</code></td><td>HIGH</td><td>05</td><td>commons (independent)</td><td><strong>NOT REPRODUCED</strong> — but downloads never started on Android (-003 blocker); cannot exercise.</td><td><code>05_flutter_android/logs/android_live.log</code> — 0 <code>InvalidProtocolBufferException</code> hits</td></tr>
<tr><td><strong><code>FLUTTER-ANDROID-003</code></strong> (NEW)</td><td>BLOCKER</td><td>05</td><td>n/a (NEW regression discovered this run)</td><td><strong>FIX LANDED 2026-05-12</strong> — canonical-aligned <code>OkHttpHttpTransport.kt</code> at correct FQN; pending re-E2E to confirm downloads work. (Detail in §A.)</td><td><code>05_flutter_android/agent_report.md</code>; Gradle BUILD SUCCESSFUL</td></tr>
<tr><td><strong><code>FLUTTER-IOS-007</code></strong> (NEW)</td><td>LOW</td><td>06</td><td>n/a (Simulator-only Keychain entitlement)</td><td><strong>OPEN</strong> — falls back gracefully; not blocking. (Detail in §A.)</td><td><code>06_flutter_ios/logs/ios_live.log</code> (-34018 entitlement warnings)</td></tr>
</table>

**Run summary**: 1 real inference output captured (iOS STT, Sherpa Whisper Tiny English). 2 models downloaded + loaded on iOS (LFM2-350M-Q4_K_M + Sherpa Whisper). 0 models downloaded on Android (blocked by -003). Full report: `test_workflows/logs/20260512-141845-flutter-e2e/REPORT.md`.
