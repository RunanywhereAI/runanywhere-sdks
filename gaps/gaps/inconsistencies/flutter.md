# Flutter SDK — Current Inconsistencies

Updated: 2026-05-06
Branch: feat/v2-architecture @ bb63158d6

## Current state summary

Structurally the Flutter SDK is clean: proto-driven public surface, no
isolate fallbacks, `DartBridgeVAD` / `DartBridgeTTS` on lifecycle ABIs,
`extractStructuredOutput` routed through commons. Runtime e2e
(20260505-232326, Lanes 05/06) surfaced 4 regressions listed below.

## Deferred backend Flutter packages (stub or exclude OK)

The following Flutter packages wrap deferred backends and are NOT in scope.
Stubbing, excluding from the melos workspace, or deleting is acceptable —
do not file bugs about these being unimplemented.

- `sdk/runanywhere-flutter/packages/runanywhere_genie/` — Genie backend wrapper.

(No Flutter wrappers currently exist for MetalRT, WhisperKit, WhisperKit
CoreML, WhisperCPP, or Diffusion.)

## Open items (from 20260505-232326 e2e)

<table>
<tr><th>ID</th><th>Severity</th><th>Lane</th><th>Summary</th><th>Fix hint</th></tr>
<tr>
  <td><code>FLT-E2E-R2-001</code></td>
  <td>HIGH</td>
  <td>05 Flutter Android</td>
  <td>Android 16 KB page-size warning dialog lists 19 unaligned native libraries at install/launch. <code>gradle.properties</code> now pins <code>racFlutterNdkVersion=27.0.12077973</code> (same as <code>racNdkVersion</code>), so the source of the unaligned <code>.so</code> set is <strong>not</strong> the Flutter NDK pin. Likely the Flutter packaging path in <code>scripts/build-core-android.sh</code> or a Flutter Gradle plugin step is still emitting pre-aligned artifacts.</td>
  <td>Audit the Flutter Android packaging output in <code>build/</code>; confirm every <code>.so</code> dropped into <code>sdk/runanywhere-flutter/packages/*/android/src/main/jniLibs/</code> was linked with <code>-Wl,-z,max-page-size=16384</code> under NDK 27.</td>
</tr>
<tr>
  <td><code>FLT-E2E-R2-002</code></td>
  <td>HIGH</td>
  <td>05 Flutter Android</td>
  <td><code>DartBridge</code> logs 7 783 <code>InvalidProtocolBufferException</code> while decoding <code>DownloadProgress</code>. 219 MB lands on disk but the terminal COMPLETED event fails to decode; UI stalls at 91 %. Proto wire-format drift between the C++ producer and the Dart parser.</td>
  <td>Regenerate Dart proto bindings (<code>./idl/codegen/generate_dart.sh</code>) and diff <code>DownloadProgress</code> field layout against <code>rac/infrastructure/download/rac_download.h</code>.</td>
</tr>
<tr>
  <td><code>FLT-E2E-R2-003</code></td>
  <td>HIGH</td>
  <td>06 Flutter iOS</td>
  <td><code>DartBridge</code> repeatedly logs <code>rac_model_format_from_url_proto unavailable; returning UNKNOWN</code> and <code>rac_artifact_infer_from_url_proto unavailable; returning null</code> on every model-catalog entry. Symbols are declared in <code>RACommons.exports</code> and bound in <code>rac_native.dart</code>, so the breakage is a runtime <code>dlsym</code> miss — most likely <code>scripts/build-core-xcframework.sh</code>'s <code>rac_plugin_entry_whisperkit_coreml.o</code> strip step is over-removing symbols from the Flutter-consumed xcframework.</td>
  <td>Inspect <code>sdk/runanywhere-flutter/packages/runanywhere/ios/Frameworks/RACommons.xcframework/*/RACommons.framework/RACommons</code> with <code>nm -gU</code> for the two symbols; tighten the strip workaround to keep Wave D-3 entry points.</td>
</tr>
<tr>
  <td><code>FLT-E2E-R2-004</code></td>
  <td>LOW</td>
  <td>06 Flutter iOS</td>
  <td><code>rac_http_request_send</code> returns code <code>-151</code> against the localhost dev env; SDK proceeds gracefully but auth fails silently.</td>
  <td>Surface the HTTP transport error code to the developer via <code>SDKException</code> / event bus instead of swallowing it.</td>
</tr>
</table>

## Cross-SDK naming alignment gaps

<table>
<tr><th>Concern</th><th>Swift</th><th>Kotlin</th><th>RN</th><th>Web</th><th>Flutter</th><th>Status</th></tr>
<tr><td>Entry point</td><td><code>enum RunAnywhere</code></td><td><code>object RunAnywhere</code></td><td><code>RunAnywhere</code></td><td><code>RunAnywhere</code></td><td><code>class RunAnywhereSDK</code> (<code>.instance</code>)</td><td>Flutter uses instance-getter; others use enum/object. Cosmetic.</td></tr>
</table>
