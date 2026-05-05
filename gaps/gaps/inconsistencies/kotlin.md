# Kotlin SDK — Current Inconsistencies

Updated: 2026-05-04 (Discovery H)
Branch: `feat/v2-architecture` @ `9226feb2c`
Build status: **PASS** (`compileKotlinJvm` ✅, `compileDebugKotlinAndroid` ✅, `detekt` ✅ 0 issues, `ktlintCheck` ✅ 0 issues)

## Current state summary

Kotlin SDK lives under `sdk/runanywhere-kotlin/` with 134 hand-written `.kt`
files (~23,328 LOC) across `commonMain` (54 files), `jvmAndroidMain` (57),
`androidMain` (13), `jvmMain` (9), plus ~190 Wire-generated proto files in
`commonMain/generated/`. All blocker compilation issues from Discovery G
(`KeychainManager.kt` / `StoredTokens`, duplicate `SecureStorage.kt`) are
resolved — both JVM and Android compile cleanly with 0 detekt / 0 ktlint
issues. Proto typealiases are in place for `SDKEnvironment`, `SDKEvent`,
`EventCategory`, tool-calling types, LLM options, LoRA state, VoiceAgent
config, and ModelInfo/etc. `EventBus` is wired to
`rac_sdk_event_subscribe` via `EventBusBridge.kt`. Proto facades
(`CppBridgeLLMProto`, `CppBridgeSTTProto`, `CppBridgeTTSProto`,
`CppBridgeVADProto`, `CppBridgeVLMProto`, `CppBridgeLoraProto`,
`CppBridgeDiffusionProto`, `CppBridgeRAGProto`, `CppBridgeEmbeddingsProto`,
`CppBridgeVoiceAgentProto`, `CppBridgeStorageProto`,
`CppBridgeModelLifecycleProto`, `CppBridgeDownloadProto`) own handles
directly. KOT-SECURE-01 is fixed (Wave H-1 Row H1-04): Android secure
storage now uses `EncryptedSharedPreferences` (AES-256-GCM values +
AES-256-SIV keys over an Android-Keystore master key) with a one-shot
migrator that drains the legacy plaintext+Base64 store on first get/set.
KOT-SECURE-02 is fixed (Wave H-1 Row H1-05): the JVM target now ships a
file-per-key AES-GCM 256 `JvmSecureStorage` under `~/.runanywhere/secure/`
with a persistent 32-byte master key (0600 POSIX perms) and an auto-install
path on non-Android JVMs. One HIGH-priority issue remains: the SDK carries
~3,500+ LOC of
zero-caller dead code — huge facades (`CppBridgePlatform` 1431 LOC,
`CppBridgeState` 652 LOC, `CppBridgeModelPaths` 831 LOC), dead modules
(`FileSystem` interface + impls, `PlatformStorage` + impls,
`NetworkConnectivity`, `RAGBridge`, `LLMStreamAdapter`, `AudioCaptureManager`
+ Android/Jvm actuals, `AudioUtils`, `CppBridgeHTTP`, `CppBridgeLlmThinking`,
`ComponentTypes`, `SDKConstants.{API,Storage,Defaults,SecureStorage,ErrorCodes,Environment}`,
`BuildConfig` + actuals, `PlatformUtils` + actuals, `SimpleInstant`,
`CryptoUtils`, entire `foundation/protoext/` directory, `PlatformLogger`
expect/actual). A few moderate issues remain around VLM legacy lifecycle
(KOT-05), `getFrameworksForCapability` Kotlin-side SDKComponent mapping (KOT-12),
`currentDiffusionFramework` stub returning null (KOT-14), and the
`CppBridge.Environment` enum that duplicates the canonical `SDKEnvironment` proto. The
`commonMain`/`jvmAndroidMain` split is largely clean but leaks in both
directions (file-system / platform-storage / audio capture / device-info
still in `expect` + per-platform actuals but are unused).

## Confirmed gaps (each is a single agent task)

### KOT-DEAD-AUDIOCAPTURE: `AudioCaptureManager` + `AndroidAudioCaptureManager` + `JvmAudioCaptureManager` unused (priority: MED)
- **Symptom**: `AudioCaptureManager` interface + `AudioChunk` + `AudioCaptureError` + `createAudioCaptureManager()`
  (`commonMain/.../features/stt/services/AudioCaptureManager.kt`, 131 LOC) + two platform actuals
  (`AndroidAudioCaptureManager.kt` 211 LOC, `JvmAudioCaptureManager.kt` 177 LOC). No in-SDK callers:
  `grep -rn "AudioCaptureManager\|AudioChunk\|AudioCaptureError"` returns only the definitions themselves.
  The example Android app has its own `AudioCaptureService.kt` and uses native `AudioRecord` directly.
- **Files to delete**:
  - `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/features/stt/services/AudioCaptureManager.kt`
  - `sdk/runanywhere-kotlin/src/androidMain/kotlin/com/runanywhere/sdk/features/stt/AndroidAudioCaptureManager.kt`
  - `sdk/runanywhere-kotlin/src/jvmMain/kotlin/com/runanywhere/sdk/features/stt/JvmAudioCaptureManager.kt`
  - `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/foundation/PlatformTime.kt`
    (its `currentTimeMillis` + `currentTimeISO8601` expect fns are used only by the audio capture code)
  - `sdk/runanywhere-kotlin/src/androidMain/kotlin/com/runanywhere/sdk/foundation/PlatformTime.kt`
  - `sdk/runanywhere-kotlin/src/jvmMain/kotlin/com/runanywhere/sdk/foundation/PlatformTime.kt`
- **Scope**: 6 files / ~550 LOC.

### KOT-DEAD-SDKCONSTANTS: Most of `SDKConstants` is dead (priority: MED)
- **Symptom**: `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/utils/SDKConstants.kt`.
  Used externally: `SDKConstants.VERSION`, `SDK_VERSION`, `SDK_NAME`, `USER_AGENT`. Everything else is dead:
  - `Environment` (duplicate of `SDKEnvironment` proto enum) — zero callers
  - `API.*` (AUTHENTICATE, REFRESH_TOKEN, MODELS, etc.) — zero callers
  - `Defaults.*` (REQUEST_TIMEOUT_MS, STT_SAMPLE_RATE, etc.) — zero callers
  - `Storage.*` (paths) — zero callers
  - `SecureStorage.*` (keys) — zero callers
  - `ErrorCodes.*` — zero callers
  - `SDKConstants.platform` (delegates to `PlatformUtils.getPlatformName()`) — zero callers
  - `SDKConstants.version` (lowercase alias) — zero callers
- **Additional**: VERSION = "0.1.0" is hardcoded and doesn't track the canonical
  `sdk/runanywhere-commons/VERSION` (currently 0.19.13). Should either dynamic-load or be fixed by
  `sync-versions.sh`. Swift's `SDKConstants` tracks the VERSION file.
- **Concrete steps**: Delete all of `API`, `Defaults`, `Storage`, `SecureStorage`, `ErrorCodes`, `Environment`
  subobjects and the `platform` / `version` accessors. Keep `VERSION`/`SDK_VERSION`/`SDK_NAME`/`USER_AGENT`
  only. Fix VERSION hardcoded value (look up how Swift does it; our version-sync script should write it).
- **Scope**: 1 file, ~135 LOC deleted.

### KOT-DEAD-BUILDCONFIG: `BuildConfig` expect/actuals unused (priority: LOW)
- **Symptom**: `utils/BuildConfig.kt` (commonMain expect) + actuals in `androidMain` + `jvmMain` just
  read `SharedBuildConfig.VERSION_NAME` + `SharedBuildConfig.APPLICATION_ID`. `grep -rn "BuildConfig\\."` has
  zero hits outside the declarations themselves. `SharedBuildConfig` hardcodes `VERSION_NAME = "1.0.0"`,
  `APPLICATION_ID = "com.runanywhere.sdk"` which no code reads.
- **Files to delete**:
  - `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/utils/BuildConfig.kt`
  - `sdk/runanywhere-kotlin/src/androidMain/kotlin/com/runanywhere/sdk/utils/BuildConfig.kt`
  - `sdk/runanywhere-kotlin/src/jvmMain/kotlin/com/runanywhere/sdk/utils/BuildConfig.kt`
  - `sdk/runanywhere-kotlin/src/jvmAndroidMain/kotlin/com/runanywhere/sdk/utils/SharedBuildConfig.kt`
- **Scope**: 4 files / ~30 LOC.

### KOT-DEAD-PLATFORMUTILS: `PlatformUtils` expect/actuals unused (priority: LOW)
- **Symptom**: `getDeviceId/getPlatformName/getDeviceInfo/getOSVersion/getDeviceModel/getAppVersion`
  (`commonMain/.../utils/PlatformUtils.kt` + android/jvm actuals). Only `getPlatformName()` is called
  from the dead `SDKConstants.platform`. On Android the actual also has a standalone `init(context)`
  that's never called.
- **Files to delete**:
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

### KOT-05: `CppBridgeVLMProto.loadResolvedArtifacts` still uses non-proto legacy trio (priority: MED)
- **Symptom** (unchanged from Discovery G):
  `sdk/runanywhere-kotlin/src/jvmAndroidMain/kotlin/com/runanywhere/sdk/foundation/bridge/extensions/CppBridgeModalityProto.kt:478-498`
  calls `racVlmCreate(modelIdOrPath)`, `racVlmInitialize(handle, modelPath, visionProjectorPath)`,
  `racVlmDestroy(handle)` directly. `RunAnywhereBridge.kt:273-298` still declares those legacy thunks.
  Swift/Flutter have migrated to generated-proto VLM lifecycle; Kotlin hasn't.
- **Concrete steps**:
  1. Commons: add `rac_vlm_component_load_resolved_artifacts_proto` taking a `VLMLoadResolvedArtifactsRequest`
     proto (fields: `model_id`, `primary_model_path`, `vision_projector_path`).
  2. Kotlin: replace `CppBridgeModalityProto.kt:478-498` with a proto-backed `load()`, delete
     `racVlmCreate`/`racVlmInitialize`/`racVlmDestroy` from `RunAnywhereBridge.kt:273-298`.
- **Scope**: 1 `.proto` message + ~40 LOC Kotlin + C++ work.

### KOT-12: `getFrameworksForCapability` does Kotlin-side SDKComponent → ModelCategory mapping (priority: LOW)
- **Symptom** (unchanged):
  `jvmAndroidMain/.../RunAnywhere+Frameworks.jvmAndroid.kt:28-57` maps SDKComponent → Set<ModelCategory>
  in a local `when` expression, filters `CppBridgeModelRegistry.getAll()` in Kotlin.
- **Concrete steps**: Commons: expose `rac_router_frameworks_for_capability_proto`. Kotlin replaces the
  mapping + filter with a single native call.
- **Scope**: ~30 LOC Kotlin removal.

### KOT-14: `currentDiffusionFramework` returns null stub (priority: LOW)
- **Symptom** (unchanged):
  `jvmAndroidMain/.../RunAnywhere+Diffusion.jvmAndroid.kt:104-107`:
  ```kotlin
  actual suspend fun RunAnywhere.currentDiffusionFramework(): InferenceFramework? {
      // TODO: wire rac_diffusion_current_framework_proto once commons exposes it.
      return null
  }
  ```
  Also `CppBridgeDiffusionProto.capabilities()` returns an empty `DiffusionCapabilities()` on every call
  (`CppBridgeModalityProto.kt:694-697`).
- **Concrete steps**: Commons: expose `rac_diffusion_current_framework_proto` + populate capabilities
  proto. Kotlin: replace the `return null` + hollow capabilities() with the native calls.
- **Scope**: ~10 LOC Kotlin + C++ work.

### KOT-HARDWARE-FALLBACK: `RunAnywhere+Hardware.jvmAndroid.kt` has Kotlin-side SoC name heuristic (priority: LOW)
- **Symptom**: `jvmAndroidMain/.../RunAnywhere+Hardware.jvmAndroid.kt:42-76` — when
  `racHardwareProfileGet()` is unavailable, builds a `HardwareProfileResult` locally by invoking
  `getprop ro.board.platform` via `Runtime.exec(...)` on Android. Chip name detection should be in
  C++ `rac_hardware_profile_get` exclusively.
- **Concrete steps**: Ensure `racHardwareProfileGet()` always returns a populated proto on Android;
  delete the `buildPlatformProfile()` fallback.
- **Scope**: ~40 LOC Kotlin deletion.

## Items to DELETE (hard delete, no deprecation)

All confirmed dead. Grouped for batch execution:

1. **BATCH 1 — Infrastructure parallels (~720 LOC)**:
   - `commonMain/.../storage/FileSystem.kt` + `jvmAndroidMain/.../storage/SharedFileSystem.kt` +
     `androidMain/.../storage/AndroidFileSystem.kt` + `jvmMain/.../storage/JvmFileSystem.kt`
   - `commonMain/.../storage/PlatformStorage.kt` + two platform actuals
   - `commonMain/.../platform/StoragePlatform.kt` + two platform actuals
   - `androidMain/.../platform/NetworkConnectivity.kt`

2. **BATCH 2 — Dead bridges (~2.5k LOC)**:
   - `jvmAndroidMain/.../rag/RAGBridge.kt` (move `System.loadLibrary` to loader)
   - `jvmAndroidMain/.../adapters/LLMStreamAdapter.kt` (+ matching C++ JNI thunks)
   - `jvmAndroidMain/.../foundation/bridge/extensions/CppBridgeHTTP.kt`
   - `jvmAndroidMain/.../foundation/bridge/extensions/CppBridgeLlmThinking.kt` (+ 3 RunAnywhereBridge thunks)
   - `jvmAndroidMain/.../foundation/bridge/extensions/CppBridgeState.kt` (whole file)

3. **BATCH 3 — Slim large facades (~2k LOC)**:
   - `CppBridgePlatform.kt`: keep register/unregister, delete 1380 LOC of unused provider surface
   - `CppBridgeModelPaths.kt`: keep pathProvider/getBaseDirectory/getModelPath, delete 600 LOC of listeners + callbacks + storage helpers
   - `CppBridgeFileManager.kt`: keep register(), delete 10 dead public methods
   - `CppBridgeToolCalling.kt`: keep buildFollowupPrompt, delete 5 dead public methods
   - `CppBridgeModelRegistry.kt`: delete `ModelType`/`ModelCategory`/`ModelFormat` nested int constants; keep or inline `Framework`
   - `CppBridgeDevice.kt`: delete `PlatformType` + `RegistrationStatus` nested constants

4. **BATCH 4 — Audio capture + time utilities (~580 LOC)**:
   - `commonMain/.../features/stt/services/AudioCaptureManager.kt` + `AndroidAudioCaptureManager.kt` + `JvmAudioCaptureManager.kt`
   - `commonMain/.../foundation/PlatformTime.kt` + android/jvm actuals (only used by dead AudioCaptureManager)

5. **BATCH 5 — Utility cruft (~320 LOC)**:
   - `commonMain/.../utils/SDKConstants.kt`: strip to VERSION/SDK_VERSION/SDK_NAME/USER_AGENT
   - `commonMain/.../utils/BuildConfig.kt` + 2 actuals + `SharedBuildConfig.kt`
   - `commonMain/.../utils/PlatformUtils.kt` + 2 actuals
   - `commonMain/.../utils/SimpleInstant.kt`
   - `jvmAndroidMain/.../utils/CryptoUtils.kt`

6. **BATCH 6 — Protoext + core/types (~780 LOC)**: DONE in `765692eae`.

7. **BATCH 7 — Environment deduplication + error-mapping cleanup**: DONE in wave-h-4.

8. **BATCH 8 — VLM legacy trio (after KOT-05 commons work)**:
   - `racVlmCreate` / `racVlmInitialize` / `racVlmDestroy` thunks in `RunAnywhereBridge.kt:273-298`
   - `CppBridgeVLMProto.loadResolvedArtifacts` rewrite in `CppBridgeModalityProto.kt:478-498`

**Total dead-code reduction target: ~7,000 LOC across ~35 files.**

## Cross-SDK naming alignment gaps

Same namespace comparisons done in prior waves are still valid; spot checks:

| Concern | Kotlin | Swift (source of truth) | Flutter | RN | Web |
|---|---|---|---|---|---|
| `SDKConstants.VERSION` | hardcoded `"0.1.0"` | `SDKConstants.version` tracks `VERSION` file | pubspec-driven | package.json-driven | package.json-driven |
| `SDKEnvironment` type | proto typealias | proto typealias | proto typealias | proto typealias | proto typealias |
| `Hardware` class exposed via `.hardware` accessor | ✅ `RunAnywhere.hardware.getProfile()` | ✅ `RunAnywhere.hardware.getProfile()` | ✅ | ✅ | ✅ |
| `RunAnywhereModule` interface | Used by LlamaCPP/ONNX modules (module metadata only) | iOS has RunAnywhereModule equivalent | TBD | TBD | TBD |
| `streamVoiceAgent()` public entry | `streamVoiceAgent(): Flow<VoiceEvent>` | `streamVoiceAgent() -> AsyncStream<VoiceEvent>` | `streamVoiceAgent(): Stream<VoiceEvent>` | `streamVoiceAgent(): AsyncIterable<VoiceEvent>` | `streamVoiceAgent(): AsyncIterable<VoiceEvent>` |
| `processVoiceTurn(VoiceAgentTurnRequest) → VoiceAgentResult` | aggregates VoiceEvent stream | same | same | same | same |

**Key naming gap**: `SDKConstants.VERSION = "0.1.0"` does not match the canonical
`sdk/runanywhere-commons/VERSION` file (0.19.13). Swift reads its version from the VERSION file at
build time. Kotlin should either (a) have `sync-versions.sh` rewrite this const, or (b) read it from
`gradle.properties`. Addressed implicitly by KOT-DEAD-SDKCONSTANTS.

## Example app (Android) inconsistencies

None that force SDK fixes. Spot-checks confirm:
- Example app's `AppDeviceInfo.kt` is a clean local type (replaces deleted SDK `DeviceInfo`), no stale SDK imports.
- No references to the dead `AudioCaptureManager` / `NetworkConnectivity` / `SDKConstants.API` surfaces.
- `ModelSelectionContext` correctly moved out of SDK (KOT-15, previously resolved).
- No references to `SimpleInstant`, `BuildConfig`, `PlatformUtils`, or the protoext helpers.
