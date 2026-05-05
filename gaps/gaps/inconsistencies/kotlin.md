# Kotlin SDK — Current Inconsistencies

Updated: 2026-05-05 (Audit — brutal prune)
Branch: `feat/v2-architecture` @ `6217d9e67`
Build status: **PASS** (`compileKotlinJvm`, `compileDebugKotlinAndroid`, `detekt 0`, `ktlintCheck 0`)

## Current state summary

Kotlin SDK lives under `sdk/runanywhere-kotlin/` with 119 hand-written `.kt`
files across `commonMain` (44), `jvmAndroidMain` (51), `androidMain` (8),
`jvmMain` (7), plus ~190 Wire-generated proto files. Secure storage is
production-grade on both targets: Android uses `EncryptedSharedPreferences`
(AES-256-GCM values + AES-256-SIV keys over an Android-Keystore master key)
with a one-shot plaintext-migrator, and JVM uses file-per-key AES-GCM 256
under `~/.runanywhere/secure/` with a persistent 32-byte master key (0600
POSIX perms). The big dead-code facades (`CppBridgePlatform` 1431 LOC →
51 LOC, `CppBridgeModelPaths` 831 → 223, `CppBridgeState` 652 LOC → deleted)
and the dead bridges (`RAGBridge`, `LLMStreamAdapter`, `CppBridgeHTTP`,
`CppBridgeLlmThinking`, `CppBridgeState`) are all gone. The protoext
directory, `AudioUtils`, `CppBridgeEnvironment`, `CommonsErrorMapping`, and
`PlatformLogger` are all deleted. KOT-09 (structured output), KOT-10
(ModelFormat URL heuristics), KOT-12 (router frameworks-for-capability),
and KOT-STREAM-VAD are all wired to native commons APIs. KOT-14 resolved in
Wave 3a by deleting the `currentDiffusionFramework()` + `getDiffusionCapabilities()`
Kotlin `expect`/`actual` pair (no Kotlin-usable diffusion backend exists today;
iteration I will reintroduce when a non-Apple-only diffusion engine ships — see
`KOT-DIFFUSION-REWIRE`). KOT-05 resolved in Wave 3a: the VLM
`loadResolvedArtifacts` path is now proto-backed via the new
`rac_vlm_component_load_resolved_artifacts_proto` commons API, the legacy
`racVlmCreate`/`racVlmInitialize` JNI thunks and `external fun` decls are
deleted, and `racVlmDestroy` remains only as the handle-release path used
by `CppBridgeVLMProto.destroy()`. No open inconsistencies remain on this
SDK.

## Confirmed gaps

### KOT-DIFFUSION-REWIRE: Reintroduce `currentDiffusionFramework` + `getDiffusionCapabilities` when a Kotlin-usable diffusion backend ships (priority: LOW, deferred to iteration I)
- **Context**: Wave 3a (KOT-14) deleted the `currentDiffusionFramework()` and
  `getDiffusionCapabilities()` `expect`/`actual` pair plus the hollow
  `CppBridgeDiffusionProto.capabilities()` wrapper. Rationale: the only existing
  diffusion backend is `diffusion-coreml` (Apple-only), which is wired only through
  Swift. On Android/JVM today, those Kotlin APIs unconditionally returned `null` /
  empty — there was no reachable native implementation to report a framework
  or enumerate capabilities. Deleting the dead surface area prevents misleading
  API shape (consumers never got a meaningful value).
- **Reintroduction trigger**: When either (a) `diffusion-coreml` is wired to
  Kotlin/Apple via the KMP iOS/macOS source set, or (b) a non-Apple diffusion
  backend lands (e.g. ONNX-runtime SD variant, WGPU SD, NNAPI SD).
- **Concrete reintroduction steps**:
  1. Commons: add `rac_diffusion_current_framework_proto` (returns
     `InferenceFrameworkResponse`) and `rac_diffusion_capabilities_proto` (returns
     `DiffusionCapabilities`) to the C ABI, routed through the diffusion component.
  2. JNI: expose matching thunks in `runanywhere_commons_jni.cpp` +
     `RunAnywhereBridge.kt`.
  3. Kotlin: restore the `expect suspend fun RunAnywhere.currentDiffusionFramework()`
     and `expect suspend fun RunAnywhere.getDiffusionCapabilities()` declarations in
     `commonMain/.../RunAnywhere+Diffusion.kt`, and wire the proto-backed actuals
     in `jvmAndroidMain/.../RunAnywhere+Diffusion.jvmAndroid.kt` through a new
     `CppBridgeDiffusionProto.currentFramework()` + `capabilities()` helper.
  4. Cross-SDK: mirror to Flutter, React Native, Web.
- **Scope**: 2 new proto APIs + 2 JNI thunks + ~30 LOC Kotlin + C++ work.

### KOT-JNI-ORPHAN: 20 `external fun` declarations in `RunAnywhereBridge.kt` have no matching C thunk (priority: HIGH)
- **Symptom**: Surfaced by Wave 1 CPP-06 JNI audit. 20 `external fun` entries in
  `sdk/runanywhere-kotlin/src/jvmAndroidMain/kotlin/com/runanywhere/sdk/native/bridge/RunAnywhereBridge.kt`
  declare native symbols that were never present in `runanywhere_commons_jni.cpp` (neither at the Wave 1
  baseline commit nor after CPP-06 deletions). Compile succeeds because Kotlin only links `external fun`
  at runtime — the first call into any of these would throw `UnsatisfiedLinkError`. Of the 20, 15 have
  at least one Kotlin caller (`grep -rn RunAnywhereBridge.<fn>`), so the failure mode is a runtime
  crash in the corresponding code path.
- **Affected declarations** (all preceded by `external fun`):
  - `racDownloadCancel` / `racDownloadStart` / `racDownloadGetProgress`
  - `racHttpTransportRegisterOkHttp` / `racHttpTransportUnregisterOkHttp`
  - `racLoraCatalogGetProto` / `racLoraCatalogListProto` / `racLoraCatalogMarkDownloadCompletedProto`
    / `racLoraCatalogQueryProto`
  - `racModelRegistryGet` / `racModelRegistryGetAll` / `racModelRegistryGetDownloaded`
    / `racModelRegistryRemove` / `racModelRegistrySave` / `racModelRegistryUpdateDownloadStatus`
  - `racRegistryGetPluginApiVersion` / `racRegistryGetPluginCount` / `racRegistryGetRegisteredNames`
    / `racRegistryLoadPlugin` / `racRegistryUnloadPlugin`
- **Concrete steps** (per area): Either (a) add the matching JNI thunk in
  `sdk/runanywhere-commons/src/jni/runanywhere_commons_jni.cpp` calling the canonical proto C ABI, or
  (b) remove the `external fun` + rewrite callers onto an existing proto sibling. Preferred approach
  per area:
  1. `racDownload*` — callers already use `CppBridgeDownloadProto.*`; the three legacy thunks can be
     deleted and their callers routed through the proto facade.
  2. `racHttpTransport*OkHttp` — this is low-level JNI to hand-wire `rac_http_transport_ops_t` from
     the Kotlin side; expose as a JNI function or rewire via a C++ helper invoked at adapter register.
  3. `racLoraCatalog*Proto` — canonical `rac_lora_*_proto` thunks are already present; delete the
     4 orphan Kotlin declarations and rename the callers if needed.
  4. `racModelRegistry*` (non-proto) — all use-sites should move to `racModelRegistry*Proto`.
  5. `racRegistry*` (plugin registry) — expose the 5 `rac_plugin_*` C ABI functions as JNI thunks.
- **Validation**: `grep -cE "external fun" RunAnywhereBridge.kt` should equal the number of JNIEXPORT
  thunks in `runanywhere_commons_jni.cpp`, and `diff <(external_fun_names) <(jniexport_names)` should
  be empty.
- **Scope**: ~5 small agent tasks, one per area (download, http transport, lora catalog, model
  registry, plugin registry). Each is 10–40 LOC.

## Cross-SDK naming alignment gaps

None currently tracked.

## Example app (Android) inconsistencies

None that force SDK fixes.
