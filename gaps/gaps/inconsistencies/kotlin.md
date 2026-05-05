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
and KOT-STREAM-VAD are all wired to native commons APIs. What remains is
(a) ~1,000 LOC of audio-capture + utility cruft still on disk as expect/
actuals with zero callers, (b) KOT-05 legacy VLM trio (still calls
`racVlmCreate`/`racVlmInitialize`/`racVlmDestroy` instead of a proto-backed
`load`), (c) KOT-14 `currentDiffusionFramework` returning a `null` stub,
and (d) KOT-HARDWARE-FALLBACK invoking `getprop ro.board.platform` via
`Runtime.exec` when `racHardwareProfileGet` is unavailable.

## Confirmed gaps

### KOT-05: `CppBridgeVLMProto.loadResolvedArtifacts` still uses legacy non-proto trio (priority: MED)
- **Symptom**:
  `sdk/runanywhere-kotlin/src/jvmAndroidMain/kotlin/com/runanywhere/sdk/foundation/bridge/extensions/CppBridgeModalityProto.kt:478-498`
  calls `racVlmCreate(modelIdOrPath)`, `racVlmInitialize(handle, modelPath, visionProjectorPath)`,
  `racVlmDestroy(handle)` directly. `RunAnywhereBridge.kt:299/302/323` still declare those legacy thunks.
  Swift/Flutter have migrated to generated-proto VLM lifecycle; Kotlin hasn't.
- **Concrete steps**:
  1. Commons: add `rac_vlm_component_load_resolved_artifacts_proto` taking a `VLMLoadResolvedArtifactsRequest`
     proto (fields: `model_id`, `primary_model_path`, `vision_projector_path`).
  2. Kotlin: replace `CppBridgeModalityProto.kt:478-498` with a proto-backed `load()`, delete
     `racVlmCreate`/`racVlmInitialize`/`racVlmDestroy` from `RunAnywhereBridge.kt:299/302/323`.
- **Scope**: 1 `.proto` message + ~40 LOC Kotlin + C++ work.

### KOT-14: `currentDiffusionFramework` returns null stub (priority: LOW)
- **Symptom**:
  `jvmAndroidMain/.../RunAnywhere+Diffusion.jvmAndroid.kt:104-107`:
  ```kotlin
  actual suspend fun RunAnywhere.currentDiffusionFramework(): InferenceFramework? {
      // TODO: wire rac_diffusion_current_framework_proto once commons exposes it.
      return null
  }
  ```
  `CppBridgeDiffusionProto.capabilities()` in `CppBridgeModalityProto.kt` also returns an empty
  `DiffusionCapabilities()` on every call.
- **Concrete steps**: Commons: expose `rac_diffusion_current_framework_proto` + populate capabilities
  proto. Kotlin: replace the `return null` + hollow capabilities() with the native calls.
- **Scope**: ~10 LOC Kotlin + C++ work.

### KOT-HARDWARE-FALLBACK: `buildPlatformProfile()` Kotlin-side SoC heuristic (priority: LOW)
- **Symptom**: `jvmAndroidMain/.../RunAnywhere+Hardware.jvmAndroid.kt:42-76` — when
  `racHardwareProfileGet()` is unavailable, builds a `HardwareProfileResult` locally by invoking
  `getprop ro.board.platform` via `Runtime.exec(...)` on Android. Chip name detection should be in
  C++ `rac_hardware_profile_get` exclusively.
- **Concrete steps**: Ensure `racHardwareProfileGet()` always returns a populated proto on Android;
  delete the `buildPlatformProfile()` fallback.
- **Scope**: ~40 LOC Kotlin deletion.

### KOT-DEAD-AUDIOCAPTURE: `AudioCaptureManager` + actuals + `PlatformTime` unused (priority: LOW)
- **Symptom**: `AudioCaptureManager` interface + `AudioChunk` + `AudioCaptureError` +
  `createAudioCaptureManager()` in `commonMain/.../features/stt/services/AudioCaptureManager.kt`
  (131 LOC) + two platform actuals (`AndroidAudioCaptureManager.kt` 211 LOC,
  `JvmAudioCaptureManager.kt` 177 LOC). Zero in-SDK callers; the example Android app uses its own
  `AudioCaptureService.kt` with native `AudioRecord`. `commonMain/.../foundation/PlatformTime.kt` +
  android/jvm actuals (`currentTimeMillis` / `currentTimeISO8601` expect fns) are only used by the
  dead audio-capture code.
- **Files to delete** (6):
  - `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/features/stt/services/AudioCaptureManager.kt`
  - `sdk/runanywhere-kotlin/src/androidMain/kotlin/com/runanywhere/sdk/features/stt/AndroidAudioCaptureManager.kt`
  - `sdk/runanywhere-kotlin/src/jvmMain/kotlin/com/runanywhere/sdk/features/stt/JvmAudioCaptureManager.kt`
  - `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/foundation/PlatformTime.kt`
  - `sdk/runanywhere-kotlin/src/androidMain/kotlin/com/runanywhere/sdk/foundation/PlatformTime.kt`
  - `sdk/runanywhere-kotlin/src/jvmMain/kotlin/com/runanywhere/sdk/foundation/PlatformTime.kt`
- **Scope**: 6 files / ~550 LOC.

### KOT-DEAD-SDKCONSTANTS: dead subobjects on `SDKConstants` (priority: LOW)
- **Symptom**: `commonMain/.../utils/SDKConstants.kt`.
  Used externally: `SDKConstants.VERSION`, `SDK_VERSION`, `SDK_NAME`, `USER_AGENT`. Everything else is dead:
  - `Environment` (duplicate of `SDKEnvironment` proto enum) — zero callers
  - `API.*` (AUTHENTICATE, REFRESH_TOKEN, MODELS, etc.) — zero callers
  - `Defaults.*` (REQUEST_TIMEOUT_MS, STT_SAMPLE_RATE, etc.) — zero callers
  - `Storage.*` — zero callers
  - `SecureStorage.*` — zero callers
  - `ErrorCodes.*` — zero callers
  - `SDKConstants.platform` (delegates to `PlatformUtils.getPlatformName()`) — zero callers
  - `SDKConstants.version` (lowercase alias) — zero callers
- **Additional**: `VERSION = "0.1.0"` is hardcoded and doesn't track the canonical
  `sdk/runanywhere-commons/VERSION` file (currently 0.19.13). Swift's `SDKConstants.version`
  reads the VERSION file.
- **Concrete steps**: Delete `API` / `Defaults` / `Storage` / `SecureStorage` / `ErrorCodes` /
  `Environment` subobjects and `platform` / `version` accessors. Keep only
  `VERSION`/`SDK_VERSION`/`SDK_NAME`/`USER_AGENT`. Fix the hardcoded VERSION (have
  `sync-versions.sh` rewrite it, or read via Gradle resource).
- **Scope**: 1 file, ~135 LOC.

### KOT-DEAD-BUILDCONFIG: `BuildConfig` expect/actuals unused (priority: LOW)
- **Symptom**: `utils/BuildConfig.kt` (commonMain expect) + actuals in `androidMain` + `jvmMain` just
  read `SharedBuildConfig.VERSION_NAME` + `SharedBuildConfig.APPLICATION_ID`. Zero callers outside
  the declarations themselves. `SharedBuildConfig` hardcodes `VERSION_NAME = "1.0.0"`,
  `APPLICATION_ID = "com.runanywhere.sdk"` which no code reads.
- **Files to delete** (4):
  - `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/utils/BuildConfig.kt`
  - `sdk/runanywhere-kotlin/src/androidMain/kotlin/com/runanywhere/sdk/utils/BuildConfig.kt`
  - `sdk/runanywhere-kotlin/src/jvmMain/kotlin/com/runanywhere/sdk/utils/BuildConfig.kt`
  - `sdk/runanywhere-kotlin/src/jvmAndroidMain/kotlin/com/runanywhere/sdk/utils/SharedBuildConfig.kt`
- **Scope**: 4 files / ~30 LOC.

### KOT-DEAD-PLATFORMUTILS: `PlatformUtils` expect/actuals unused (priority: LOW)
- **Symptom**: `getDeviceId/getPlatformName/getDeviceInfo/getOSVersion/getDeviceModel/getAppVersion`
  (`commonMain/.../utils/PlatformUtils.kt` + android/jvm actuals). Only `getPlatformName()` is called
  from the dead `SDKConstants.platform` accessor. On Android the actual also has a standalone
  `init(context)` that's never called.
- **Files to delete** (3):
  - `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/utils/PlatformUtils.kt`
  - `sdk/runanywhere-kotlin/src/androidMain/kotlin/com/runanywhere/sdk/utils/PlatformUtils.kt`
  - `sdk/runanywhere-kotlin/src/jvmMain/kotlin/com/runanywhere/sdk/utils/PlatformUtils.kt`
- **Scope**: 3 files / ~220 LOC.

### KOT-DEAD-SIMPLEINSTANT: `SimpleInstant` / `toSimpleInstant()` helper not needed (priority: LOW)
- **Symptom**: `utils/SimpleInstant.kt` is used only in `SDKLogger.kt:28` (LogEntry.timestamp default).
  `Long.toSimpleInstant()` extension has zero callers. Replacing `SimpleInstant` with `Long` (millis)
  in `LogEntry` removes the whole data class.
- **Concrete steps**: Replace `timestamp: SimpleInstant = SimpleInstant.now()` with
  `timestamp: Long = System.currentTimeMillis()` in `SDKLogger.kt:28`, delete `SimpleInstant.kt`.
- **Scope**: 1 file / 23 LOC.

### KOT-DEAD-CRYPTOUTILS: `calculateSHA256` unused (priority: LOW)
- **Symptom**: `jvmAndroidMain/.../utils/CryptoUtils.kt` — `calculateSHA256(ByteArray): String` is
  the sole function. Zero callers. Legacy auth-token signing path is long gone.
- **Scope**: 1 file / 12 LOC.

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

| Concern | Kotlin | Swift (source of truth) | Flutter | RN | Web |
|---|---|---|---|---|---|
| `SDKConstants.VERSION` | hardcoded `"0.1.0"` | tracks `VERSION` file | pubspec-driven | package.json-driven | package.json-driven |

The `SDKConstants.VERSION` hardcoded-to-`"0.1.0"` mismatch is addressed implicitly by KOT-DEAD-SDKCONSTANTS
(either `sync-versions.sh` rewrites the const or it's read from gradle resources at build time).

## Example app (Android) inconsistencies

None that force SDK fixes.
