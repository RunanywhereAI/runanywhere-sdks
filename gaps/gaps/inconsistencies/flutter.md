# Flutter SDK — Current Inconsistencies

Updated: 2026-05-05 (Discovery H audit)
Branch: feat/v2-architecture @ 6217d9e67
Build status: all 4 pubspecs at 0.19.13; `SdkState` trimmed to a single
`hasRunDiscovery` flag; downloads / STT streaming / LLM streaming / VLM
streaming all consume proto-byte callbacks via
`NativeCallable.listener`; 100% of Dart capabilities read
`DartBridge.isInitialized` (zero `SdkState.shared.isInitialized`
surface).

## Current state summary

Structurally the Flutter SDK is in good shape. The public surface is
entirely generated-proto driven, isolate fallback paths are gone from
LLM/STT/TTS, both streaming adapter shims and the `native_backend`
barrel have been deleted, the `DartBridgePlatformServices` availability
checks are gone, and `DartBridgeVAD` is trimmed to a single
`processLifecycleProto` plus minimal handle state-query getters
(171 LOC, down from 523).

No TTS/VAD capabilities remain stubbed. FLT-12 landed in Wave 3c:
commons added `rac_tts_synthesize_stream_lifecycle_proto`,
`rac_tts_stop_lifecycle_proto`, `rac_vad_configure_lifecycle_proto`,
`rac_vad_start_lifecycle_proto`, `rac_vad_stop_lifecycle_proto`,
`rac_vad_reset_lifecycle_proto`. Flutter TTS `synthesizeStream` /
`stopSynthesis` and VAD `initializeVAD` / `startVAD` / `stopVAD` /
`reset` now call the new lifecycle ABIs through
`DartBridgeTTS` / `DartBridgeVAD`. Diffusion portion of the original
FLT-12 remains deferred.

## Items to DELETE

No pending deletions — FLT-11 landed in Wave 3c: `extractStructuredOutput`
now routes through commons `rac_structured_output_parse_proto` and the
~42 LOC of `_extractFirstJson` / `_findClosing` / `_isValidJson`
helpers have been removed.

## Cross-SDK naming alignment gaps

<table>
<tr><th>Concern</th><th>Swift</th><th>Kotlin</th><th>RN</th><th>Web</th><th>Flutter</th><th>Status</th></tr>
<tr><td>Entry point</td><td><code>enum RunAnywhere</code></td><td><code>object RunAnywhere</code></td><td><code>RunAnywhere</code></td><td><code>RunAnywhere</code></td><td><code>class RunAnywhereSDK</code> (<code>.instance</code>)</td><td>Flutter uses instance-getter; others use enum/object. Cosmetic.</td></tr>
<tr><td>LLM streaming</td><td><code>AsyncStream&lt;LLMStreamEvent&gt;</code></td><td><code>Flow&lt;LLMStreamEvent&gt;</code></td><td><code>AsyncIterable&lt;LLMStreamEvent&gt;</code></td><td><code>AsyncIterable&lt;LLMStreamEvent&gt;</code></td><td><code>Stream&lt;LLMStreamEvent&gt;</code></td><td>Aligned</td></tr>
<tr><td>Voice agent events</td><td><code>AsyncStream&lt;VoiceEvent&gt;</code></td><td><code>Flow&lt;VoiceEvent&gt;</code></td><td><code>AsyncIterable&lt;VoiceEvent&gt;</code></td><td><code>AsyncIterable&lt;VoiceEvent&gt;</code></td><td><code>Stream&lt;VoiceEvent&gt;</code></td><td>Aligned</td></tr>
<tr><td>Bridge layer</td><td><code>CppBridge</code> enum</td><td><code>CppBridge</code> object</td><td><code>HybridRunAnywhereCore</code> (Nitro)</td><td><code>LlamaCppBridge</code> / <code>SherpaONNXBridge</code></td><td><code>DartBridge</code> static class</td><td>Aligned</td></tr>
<tr><td>Model-format URL heuristic</td><td>commons proto (D-3)</td><td>commons proto (D-3)</td><td>commons proto (D-3)</td><td>commons proto (D-3)</td><td>commons proto via <code>DartBridgeModelFormat</code></td><td>Aligned</td></tr>
<tr><td>ffigen / auto-gen FFI</td><td>N/A (module map)</td><td>expect/actual + JNI</td><td>Nitro codegen</td><td>TypeScript <code>Offsets</code> proxy</td><td>hand-written <code>RacBindings</code></td><td>Aligned — ffigen scaffold removed (FLT-05 resolved)</td></tr>
<tr><td>Plugin ABI reported version</td><td>dynamic from native</td><td>dynamic from native</td><td>dynamic from native</td><td>dynamic</td><td>hard-coded <code>'0.19.13'</code> (aligned via FLT-07 fix)</td><td>Aligned</td></tr>
<tr><td>Structured-output extract helper</td><td>in-SDK regex</td><td>in-SDK regex</td><td>in-SDK regex</td><td>in-SDK regex</td><td>commons <code>rac_structured_output_parse_proto</code> (FLT-11 landed)</td><td>Aligned — Flutter now routes through commons; other SDKs may follow once their wiring lands</td></tr>
</table>
