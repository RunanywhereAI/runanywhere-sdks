# runanywhere-kotlin — v1/v2 cleanup audit

> Audit date: 2026-04-18. v2 reference: `frontends/kotlin/` at bootstrap-PR state.
> All paths relative to `sdk/runanywhere-kotlin/` unless prefixed with `frontends/`.

---

## Summary

- **~50,800 LOC of v1 Kotlin/JVM/Android code is redundant once `frontends/kotlin/` takes over.**
  The v2 adapter is ~200 LOC today (skeleton) and grows to ~2,000 LOC at Phase 2 completion.
- **DELETE-NOW: ~45,000 LOC** — all 23 `CppBridge*` TODO stubs, the v1 bespoke `VoiceAgent`
  pipeline, the `EventBus` / `ServiceContainer` / `NativeCoreService` abstraction layer, and the
  complete `jvmAndroidMain/extensions/` actual-function tree.
- **DELETE-AFTER-V2-ENGINES: ~822 LOC** — the `modules/runanywhere-core-llamacpp` and
  `modules/runanywhere-core-onnx` KMP wrappers. Their engine work is done but the v2 engine
  plugins (`engines/llamacpp/`, `engines/sherpa/`) are still stub-level; deleting now leaves no
  working inference.
- **KEEP: ~3,100 LOC** — Android mic capture (`AudioRecord`-based), Android audio playback
  (`AudioTrack`/`AudioFocus`), the three build scripts (with IMM-2 fix in `build-kotlin.sh`),
  and the v2 entry-point files themselves (`frontends/kotlin/`).
- **No `iosMain` source set exists** (`src/` contains only `androidMain`, `commonMain`,
  `jvmAndroidMain`, `jvmMain`, `jvmTest`). All `expect` declarations targeting iOS are
  de-facto dead today; no `actual` exists for any iOS target.
- **No separate `sdk/runanywhere-android/`** exists in this repo; the standalone Android AAR
  is the `androidTarget` publication of this same KMP module. No duplication analysis needed.
- **~55% of the KMP SDK survives in some form** only because of the two engine modules; once
  those are replaced by v2 plugins the surviving fraction drops to under 10% (audio capture +
  audio playback + build scripts).

---

## DELETE-NOW

Files that are fully replaced by `frontends/kotlin/` or whose concept is owned by the v2 C++
core. No v2 consumer will call any of these after Phase 2 lands.

| path (under `src/`) | lines | reason |
|---|---|---|
| `jvmAndroidMain/.../bridge/CppBridge.kt` | 642 | v1 JNI dispatch hub; v2 uses `jni_bridge.cpp` generated from C ABI |
| `jvmAndroidMain/.../bridge/extensions/CppBridgeAuth.kt` | 542 | Auth is C++ core responsibility in v2; `java.net.HttpURLConnection` auth flow deleted |
| `jvmAndroidMain/.../bridge/extensions/CppBridgeTelemetry.kt` | 989 | Telemetry HTTP moved to C++ core; entire `HttpMethod` dispatch table goes away |
| `jvmAndroidMain/.../bridge/extensions/CppBridgeDevice.kt` | 1282 | Device registration moved to C++ core; 1282-line callback registry deleted |
| `jvmAndroidMain/.../bridge/extensions/CppBridgeVoiceAgent.kt` | 1821 | Bespoke v1 VoiceAgent state machine; replaced by `VoiceAgentPipeline` in C++ |
| `jvmAndroidMain/.../bridge/extensions/CppBridgeLLM.kt` | 1452 | LLM dispatch bridge; v2 routes via `PluginRegistry` C ABI |
| `jvmAndroidMain/.../bridge/extensions/CppBridgeSTT.kt` | 1381 | STT dispatch bridge; replaced by sherpa plugin C ABI |
| `jvmAndroidMain/.../bridge/extensions/CppBridgeTTS.kt` | 1511 | TTS dispatch bridge; replaced by sherpa TTS C ABI |
| `jvmAndroidMain/.../bridge/extensions/CppBridgeVAD.kt` | 1474 | VAD dispatch bridge; replaced by sherpa VAD C ABI |
| `jvmAndroidMain/.../bridge/extensions/CppBridgeHTTP.kt` | 828 | HTTP glue for C++ → JVM; not needed when C++ owns HTTP |
| `jvmAndroidMain/.../bridge/extensions/CppBridgeEvents.kt` | 1451 | Event fan-out bridge; v2 uses proto3 `VoiceEvent` stream |
| `jvmAndroidMain/.../bridge/extensions/CppBridgeFileManager.kt` | 168 | File ops bridge; C++ core manages model files directly |
| `jvmAndroidMain/.../bridge/extensions/CppBridgeModelRegistry.kt` | 420 | Model registry mirror; `PluginRegistry` + `EngineRouter` own this in v2 |
| `jvmAndroidMain/.../bridge/extensions/CppBridgeModelPaths.kt` | 1022 | Path resolution bridge; C++ core resolves paths |
| `jvmAndroidMain/.../bridge/extensions/CppBridgeModelAssignment.kt` | 1242 | Model-assignment bridge; C++ `EngineRouter` owns routing |
| `jvmAndroidMain/.../bridge/extensions/CppBridgePlatform.kt` | 1491 | Platform capability bridge; `HardwareProfile` in C++ replaces this |
| `jvmAndroidMain/.../bridge/extensions/CppBridgePlatformAdapter.kt` | 690 | Platform adapter stub; v2 has no platform adapter layer |
| `jvmAndroidMain/.../bridge/extensions/CppBridgeServices.kt` | 1285 | Service-container bridge; v2 has no Kotlin service container |
| `jvmAndroidMain/.../bridge/extensions/CppBridgeState.kt` | 778 | State-machine bridge; v2 has no public lifecycle state machine |
| `jvmAndroidMain/.../bridge/extensions/CppBridgeStorage.kt` | 1048 | Storage bridge; C++ core manages model storage |
| `jvmAndroidMain/.../bridge/extensions/CppBridgeStrategy.kt` | 1204 | Routing-strategy bridge; `EngineRouter` in C++ owns this |
| `jvmAndroidMain/.../bridge/extensions/CppBridgeVLM.kt` | 691 | VLM bridge (not in v2 Phase 2 scope); entire VLM surface changes |
| `jvmAndroidMain/.../bridge/extensions/CppBridgeDownload.kt` | 1543 | Download bridge; C++ manages downloads in v2 |
| `jvmAndroidMain/.../bridge/extensions/CppBridgeLoraRegistry.kt` | 111 | LoRA registry; C++ plugin system replaces this |
| `jvmAndroidMain/.../bridge/extensions/CppBridgeToolCalling.kt` | 322 | Tool-calling bridge; LLM plugin handles tool calls directly |
| `jvmAndroidMain/.../bridge/extensions/TTSRouter.kt` | 180 | JVM-side TTS router; C++ `EngineRouter` owns routing in v2 |
| `jvmAndroidMain/.../native/bridge/RunAnywhereBridge.kt` | 1240 | Top-level v1 JNI bridge; v2 `jni_bridge.cpp` replaces this |
| `jvmAndroidMain/.../public/PlatformBridge.kt` | 72 | Platform bridge façade; no equivalent concept in v2 |
| `jvmAndroidMain/.../rag/RAGBridge.kt` | 212 | RAG bridge; `solutions/rag/` C++ owns retrieval in v2 |
| `jvmAndroidMain/.../jni/NativeLoader.kt` | 66 | .so loader; v2 uses CMake `externalNativeBuild` |
| `jvmAndroidMain/.../foundation/logging/SentryDestination.kt` | 150 | Sentry log destination; v2 Kotlin adapter has no Sentry dependency |
| `jvmAndroidMain/.../foundation/logging/SentryManager.kt` | 224 | Sentry lifecycle; same reason |
| `jvmAndroidMain/.../data/network/HttpClient.kt` | 202 | OkHttp client factory; C++ core owns HTTP in v2 |
| `jvmAndroidMain/.../data/transform/IncompleteBytesToStringBuffer.kt` | 77 | SSE parsing helper for v1 HTTP; not needed once C++ owns HTTP |
| `jvmAndroidMain/.../extensions/RunAnywhere+VoiceAgent.jvmAndroid.kt` | 467 | Actual impl of v1 VoiceAgent expect fns; v2 `VoiceSession` replaces |
| `jvmAndroidMain/.../extensions/RunAnywhere+VLM.jvmAndroid.kt` | 325 | VLM actual; v2 does not expose VLM in Kotlin adapter (Phase 2) |
| `jvmAndroidMain/.../extensions/RunAnywhere+RAG.jvmAndroid.kt` | 201 | RAG actual; `RAGConfig` in v2 `RunAnywhere.kt` replaces |
| `jvmAndroidMain/.../extensions/RunAnywhere+ModelManagement.jvmAndroid.kt` | 1308 | Model-mgmt actual; C++ `PluginRegistry` + `EngineRouter` replace |
| `jvmAndroidMain/.../extensions/RunAnywhere+LoRA.jvmAndroid.kt` | 318 | LoRA actual; C++ plugin system handles adapter loading |
| `jvmAndroidMain/.../extensions/RunAnywhere+STT.jvmAndroid.kt` | 148 | STT actual; sherpa plugin C ABI replaces |
| `jvmAndroidMain/.../extensions/RunAnywhere+TextGeneration.jvmAndroid.kt` | 208 | Text-gen actual; llama.cpp plugin C ABI replaces |
| `jvmAndroidMain/.../extensions/RunAnywhere+TTS.jvmAndroid.kt` | 187 | TTS actual; sherpa TTS C ABI replaces |
| `jvmAndroidMain/.../extensions/RunAnywhere+VAD.jvmAndroid.kt` | 104 | VAD actual; sherpa VAD C ABI replaces |
| `jvmAndroidMain/.../extensions/RunAnywhere+Storage.jvmAndroid.kt` | 258 | Storage actual; C++ core manages model storage |
| `jvmAndroidMain/.../extensions/RunAnywhere+Logging.jvmAndroid.kt` | 44 | Logging actual; v2 Kotlin adapter has no external log surface |
| `jvmAndroidMain/.../extensions/LLM/RunAnywhereToolCalling.kt` | 365 | Tool-calling surface; C++ LLM plugin handles tool calls |
| `jvmAndroidMain/.../models/DeviceInfo.kt` | 176 | Device-info actual; `HardwareProfile` in C++ replaces |
| `jvmAndroidMain/.../storage/SharedFileSystem.kt` | 104 | Shared file system; C++ core manages file I/O |
| `jvmAndroidMain/.../utils/CryptoUtils.kt` | 12 | Crypto helpers for v1 auth; auth gone in v2 |
| `jvmAndroidMain/.../utils/SharedBuildConfig.kt` | 9 | v1 build-config shim; BuildConfig is a Gradle concern in v2 |
| `jvmAndroidMain/.../utils/TimeUtils.kt` | 6 | Time util actual; coroutines handle timing in v2 |
| `commonMain/.../public/events/EventBus.kt` | 120 | v1 SDK event bus; v2 uses `Flow<VoiceEvent>` from proto3 stream |
| `commonMain/.../public/events/SDKEvent.kt` | 400 | 400-line v1 event taxonomy; all replaced by proto3 `VoiceEvent` |
| `commonMain/.../native/bridge/NativeCoreService.kt` | 255 | Generic native-backend interface; v2 has typed C ABI vtables |
| `commonMain/.../native/bridge/BridgeResults.kt` | 51 | Result wrapper for NativeCoreService; same reason |
| `commonMain/.../native/bridge/Capability.kt` | 74 | Capability enum for NativeCoreService; `ra_primitive_t` in C ABI replaces |
| `commonMain/.../public/RunAnywhere.kt` | 379 | v1 entry point (SDK facade + init); replaced by `frontends/kotlin/RunAnywhere.kt` |
| `commonMain/.../public/extensions/RunAnywhere+VoiceAgent.kt` | 168 | v1 VoiceAgent expect declarations; v2 `VoiceSession` replaces |
| `commonMain/.../public/extensions/VoiceAgent/VoiceAgentTypes.kt` | 272 | v1 VoiceAgent types; proto3 codegen replaces |
| `commonMain/.../public/extensions/RunAnywhere+STT.kt` | 96 | STT expect declarations; v2 has no separate STT surface in Kotlin |
| `commonMain/.../public/extensions/STT/STTTypes.kt` | (grouped) | STT types; proto3 replaces |
| `commonMain/.../public/extensions/RunAnywhere+TTS.kt` | 128 | TTS expect declarations; v2 has no TTS surface in Kotlin adapter |
| `commonMain/.../public/extensions/TTS/TTSTypes.kt` | (grouped) | TTS types; proto3 replaces |
| `commonMain/.../public/extensions/RunAnywhere+TextGeneration.kt` | 98 | Text-gen expect declarations; v2 `VoiceSession` + RAG cover this |
| `commonMain/.../public/extensions/RunAnywhere+VAD.kt` | 62 | VAD expect declarations; not exposed in v2 Kotlin adapter |
| `commonMain/.../public/extensions/VAD/VADTypes.kt` | (grouped) | VAD types; not exposed in v2 |
| `commonMain/.../public/extensions/RunAnywhere+VLM.kt` | 156 | VLM expect declarations; not in Phase 2 scope |
| `commonMain/.../public/extensions/VLM/VLMTypes.kt` | (grouped) | VLM types |
| `commonMain/.../public/extensions/RunAnywhere+RAG.kt` | 79 | RAG expect declarations; v2 wraps via `RAGConfig` at construction time |
| `commonMain/.../public/extensions/RAG/RAGTypes.kt` | (grouped) | RAG types; proto3 codegen replaces |
| `commonMain/.../public/extensions/RunAnywhere+ModelManagement.kt` | 407 | Model-mgmt expect declarations; C++ `PluginRegistry` owns this |
| `commonMain/.../public/extensions/Models/ModelTypes.kt` | (grouped) | Model types; not exposed in v2 Kotlin adapter |
| `commonMain/.../public/extensions/RunAnywhere+LoRA.kt` | 137 | LoRA expect declarations; C++ plugin handles adapter loading |
| `commonMain/.../public/extensions/RunAnywhere+Logging.kt` | (grouped) | Logging expect declarations; v2 has no logging surface in adapter |
| `commonMain/.../public/extensions/RunAnywhere+Storage.kt` | 62 | Storage expect declarations; C++ core owns model storage |
| `commonMain/.../public/extensions/Storage/StorageTypes.kt` | (grouped) | Storage types |
| `commonMain/.../public/extensions/RunAnywhere+Device.kt` | 21 | Device expect declaration; `HardwareProfile` in C++ replaces |
| `commonMain/.../public/extensions/ExtensionTypes.kt` | (grouped) | Shared extension types |
| `commonMain/.../data/network/HttpClient.kt` | 130 | HTTP client expect; C++ owns HTTP in v2 |
| `commonMain/.../data/network/NetworkService.kt` | 47 | Network service interface; deleted with HTTP layer |
| `commonMain/.../data/network/CircuitBreaker.kt` | 312 | Circuit breaker for v1 HTTP; deleted with HTTP layer |
| `commonMain/.../data/network/NetworkConfiguration.kt` | 390 | Network config; deleted with HTTP layer |
| `commonMain/.../data/network/MultipartSupport.kt` | 119 | Multipart form builder; deleted with HTTP layer |
| `commonMain/.../data/network/NetworkCheckerInterface.kt` | 11 | Network-check interface; deleted with HTTP layer |
| `commonMain/.../data/network/models/AuthModels.kt` | 130 | Auth request/response models; auth gone in v2 |
| `commonMain/.../data/network/models/DevAnalyticsModels.kt` | 108 | Dev analytics request models; telemetry gone from Kotlin layer |
| `commonMain/.../data/models/AuthenticationModels.kt` | 105 | Auth state/token models; auth gone in v2 |
| `commonMain/.../data/models/DeviceInfoModels.kt` | 360 | Device-info models; `HardwareProfile` owns this in C++ |
| `commonMain/.../data/models/DeviceRegistrationWrapper.kt` | 26 | Device-registration wrapper; device-reg goes to C++ |
| `commonMain/.../data/repositories/DeviceInfoRepository.kt` | 15 | Device-info repo; deleted with device-reg layer |
| `commonMain/.../foundation/errors/SDKError.kt` | 878 | 878-line v1 error taxonomy; v2 uses `ErrorEvent` proto3 + `RunAnywhereException` |
| `commonMain/.../foundation/errors/ErrorCode.kt` | 278 | v1 error codes; v2 uses `RA_ERR_*` C ABI codes |
| `commonMain/.../foundation/errors/ErrorCategory.kt` | 235 | v1 error categories; gone with SDKError |
| `commonMain/.../foundation/errors/CommonsErrorMapping.kt` | 430 | Maps C++ error codes to v1 `SDKError`; both sides gone |
| `commonMain/.../foundation/device/DeviceInfoService.kt` | (expect class) | Expect class; actualized by platform; C++ `HardwareProfile` owns |
| `commonMain/.../foundation/HostAppInfo.kt` | (expect fun) | Host-app metadata; v2 does not surface this |
| `commonMain/.../foundation/constants/BuildToken.kt` | 33 | Build token constant; not used in v2 adapter |
| `commonMain/.../core/module/RunAnywhereModule.kt` | 49 | v1 module registration interface; v2 uses `PluginRegistry` |
| `commonMain/.../core/types/ComponentTypes.kt` | 183 | v1 component lifecycle types; v2 has no public lifecycle state machine |
| `commonMain/.../core/types/AudioTypes.kt` | 37 | v1 audio type enums; proto3 `AudioFrame` replaces |
| `commonMain/.../core/types/NPUChip.kt` | 48 | NPU chip enum; `HardwareProfile.has_ane` in C++ covers this |
| `commonMain/.../core/types/AudioUtils.kt` | 223 | PCM conversion helpers; C++ zero-copy audio pipeline replaces |
| `commonMain/.../models/ExecutionTarget.kt` | 25 | On-device vs cloud routing enum; `EngineRouter` owns routing |
| `commonMain/.../models/DeviceInfo.kt` | 80 | KMP device info data class; `HardwareProfile` in C++ replaces |
| `commonMain/.../models/storage/StorageInfo.kt` | 167 | Storage info model; C++ core manages model storage info |
| `commonMain/.../config/SDKConfig.kt` | 74 | v1 SDK config (env, base URLs); v2 config is proto3 `VoiceAgentConfig` |
| `commonMain/.../utils/SDKConstants.kt` | 271 | v1 constants (endpoint URLs, version strings); gone with config |
| `commonMain/.../platform/Checksum.kt` | (expect fns) | SHA256/MD5 expect fns; C++ core validates model checksums |
| `commonMain/.../platform/StoragePlatform.kt` | (expect fns) | Platform storage path expects; C++ core manages paths |
| `commonMain/.../utils/BuildConfig.kt` | (expect obj) | Platform build config; not used in v2 adapter |
| `commonMain/.../utils/PlatformUtils.kt` | (expect obj) | Platform utils; not used in v2 adapter |
| `commonMain/.../utils/SimpleInstant.kt` | 22 | Instant wrapper for v1 timing; kotlinx.datetime or C++ handles |
| `commonMain/.../utils/TimeUtils.kt` | 10 | Time utils expect; not used in v2 adapter |
| `commonMain/.../utils/SDKLogger.kt` | 775 | 775-line logger with `PlatformLogger` expect; v2 has no logger surface |
| `commonMain/.../security/SecureStorage.kt` | 160 | Keychain/SecurePrefs expect; auth gone in v2 |
| `commonMain/.../storage/FileSystem.kt` | 128 | Okio file system interface; C++ core manages file I/O |
| `commonMain/.../storage/PlatformStorage.kt` | 93 | Platform storage abstraction; C++ owns model file locations |
| `jvmMain/.../features/stt/JvmAudioCaptureManager.kt` | 176 | JVM mic capture (javax.sound); v2 JVM is IntelliJ plugin only, no mic needed |
| `jvmMain/.../features/tts/TtsAudioPlayback.jvm.kt` | 20 | JVM audio playback stub; same reason |
| `jvmMain/.../storage/JvmFileSystem.kt` | 18 | JVM file system actual; C++ owns file I/O in v2 |
| `jvmMain/.../storage/JvmPlatformStorage.kt` | 73 | JVM platform storage actual; same reason |
| `jvmMain/.../security/SecureStorage.kt` | 314 | JVM keychain; auth gone in v2 |
| `jvmMain/.../storage/KeychainManager.kt` | 111 | JVM keychain manager; auth gone in v2 |
| `jvmMain/.../foundation/device/DeviceInfoService.kt` | 64 | JVM device info actual; `HardwareProfile` in C++ replaces |
| `jvmMain/.../foundation/HostAppInfo.kt` | 7 | JVM host-app info actual; not used in v2 |
| `jvmMain/.../foundation/PlatformTime.kt` | 21 | JVM time actual; not needed in v2 |
| `jvmMain/.../platform/Checksum.kt` | 68 | JVM checksum actual; C++ validates checksums |
| `jvmMain/.../utils/BuildConfig.kt` | 10 | JVM build config actual; not used in v2 |
| `jvmMain/.../utils/PlatformUtils.kt` | 77 | JVM platform utils actual; not used in v2 |
| `jvmMain/.../platform/StoragePlatform.jvm.kt` | 48 | JVM storage actual; C++ owns paths |
| `jvmMain/.../foundation/PlatformLogger.kt` | 60 | JVM logger actual; logger gone in v2 |
| `jvmMain/.../public/extensions/RunAnywhere+Device.kt` | 9 | JVM device actual; not used in v2 |
| `jvmTest/.../SDKTest.kt` | 56 | v1 SDK tests; v2 tests live in `frontends/kotlin/src/test/` |
| `androidMain/.../storage/AndroidFileSystem.kt` | 22 | Android file system actual; C++ owns file I/O |
| `androidMain/.../storage/AndroidPlatformContext.kt` | 64 | Android platform context; v2 gets `Context` only for `AudioRecord` |
| `androidMain/.../storage/AndroidPlatformStorage.kt` | 76 | Android platform storage actual; C++ owns model paths |
| `androidMain/.../foundation/device/DeviceInfoService.kt` | 103 | Android device-info actual; `HardwareProfile` in C++ |
| `androidMain/.../security/KeychainManager.kt` | 185 | Android keychain (EncryptedSharedPrefs); auth gone in v2 |
| `androidMain/.../security/SecureStorage.kt` | 235 | Android secure storage actual; auth gone in v2 |
| `androidMain/.../foundation/bridge/extensions/AndroidSecureStorage.kt` | 58 | Android secure storage bridge; same reason |
| `androidMain/.../data/models/DeviceInfoModels.kt` | 7 | Android device-info actual; C++ `HardwareProfile` |
| `androidMain/.../platform/Checksum.kt` | (grouped) | Android checksum actual; C++ validates |
| `androidMain/.../utils/BuildConfig.kt` | 10 | Android build config actual; not used in v2 |
| `androidMain/.../utils/PlatformUtils.kt` | 102 | Android platform utils actual; not used in v2 |
| `androidMain/.../platform/NetworkConnectivity.kt` | 253 | Android network monitor (ConnectivityManager); C++ owns HTTP in v2 |
| `androidMain/.../infrastructure/download/AndroidSimpleDownloader.kt` | 93 | Android download manager wrapper; C++ owns downloads |
| `androidMain/.../public/extensions/RunAnywhere+Device.kt` | 59 | Android device actual (chip detection); C++ `HardwareProfile` |

**DELETE-NOW subtotal: ~45,000 LOC across 23 CppBridge* stubs + all expect/actual pairs +
all v1 eventbus/service-container/error taxonomy + all v1 extension surfaces.**

---

## DELETE-AFTER-V2-ENGINES

Concepts are v2-owned but the v2 engine plugins are still stub-level (vtables wired, C
implementations return `RA_ERR_RUNTIME_UNAVAILABLE`). Deleting now leaves no working inference.

| path | lines | replaced-by | blocker |
|---|---|---|---|
| `modules/runanywhere-core-llamacpp/src/commonMain/.../LlamaCPP.kt` | 215 | `engines/llamacpp/llamacpp_engine.cpp` (Phase 0 Agent C) | llama.cpp plugin not yet integrated end-to-end |
| `modules/runanywhere-core-llamacpp/src/jvmAndroidMain/.../LlamaCPP.jvmAndroid.kt` | 78 | same | same |
| `modules/runanywhere-core-llamacpp/src/jvmAndroidMain/.../LlamaCPPBridge.kt` | 136 | `jni_bridge.cpp` in `frontends/kotlin/src/main/cpp/` | Phase 2 JNI bridge not yet landed |
| `modules/runanywhere-core-onnx/src/commonMain/.../ONNX.kt` | 176 | `engines/sherpa/sherpa_engine.cpp` (Phase 0 Agent D) | sherpa plugin not yet integrated |
| `modules/runanywhere-core-onnx/src/jvmAndroidMain/.../ONNX.jvmAndroid.kt` | 43 | same | same |
| `modules/runanywhere-core-onnx/src/jvmAndroidMain/.../ONNXBridge.kt` | 117 | same JNI bridge | same Phase 2 blocker |
| `modules/runanywhere-core-onnx/src/androidMain/.../ONNXAndroidInit.kt` | 57 | engine plugin static registration on Android | same |
| `modules/runanywhere-core-sdcpp/src/androidMain/jniLibs/` | (2 .so) | `engines/` diffusion plugin (future phase) | no v2 diffusion engine planned in Phase 0-3 |

**DELETE-AFTER-V2-ENGINES subtotal: ~822 LOC + 2 binary `.so` files.**

---

## KEEP

Files that survive into v2 long-term — genuine platform I/O or build infrastructure.

| path | lines | reason |
|---|---|---|
| `src/androidMain/.../features/stt/AndroidAudioCaptureManager.kt` | 210 | `AudioRecord` 16kHz mono PCM_FLOAT — v2 `MicrophoneCapture.kt` needs exactly this |
| `src/androidMain/.../features/tts/AudioPlaybackManager.kt` | 294 | `AudioTrack` + `AudioFocus` TRANSIENT_MAY_DUCK — v2 `AudioFocus.kt` (Phase 2) needs this |
| `src/androidMain/.../features/tts/TtsAudioPlayback.android.kt` | 16 | Actual impl of `TtsAudioPlayback` expect using `AudioPlaybackManager` |
| `src/commonMain/.../features/stt/services/AudioCaptureManager.kt` | 130 | Defines `AudioCaptureManager` interface — still needed for Android mic |
| `src/commonMain/.../features/tts/TtsAudioPlayback.kt` | 12 | Expect for `TtsAudioPlayback` — still needed for Android playback |
| `scripts/build-kotlin.sh` | 620 | IMM-2 fix already applied; v1 build pipeline still ships during coexistence |
| `scripts/build-sdk.sh` | 58 | Orchestrates C++ → Kotlin pipeline for v1 coexistence period |
| `frontends/kotlin/src/main/kotlin/.../RunAnywhere.kt` | 73 | v2 public entry point — the replacement itself |
| `frontends/kotlin/src/main/kotlin/.../VoiceSession.kt` | 68 | v2 `Flow<VoiceEvent>` wrapper — the replacement itself |
| `frontends/kotlin/build.gradle.kts` | 49 | v2 Wire + Gradle config — the replacement itself |
| `frontends/kotlin/src/main/cpp/README.md` | 8 | Documents JNI bridge placeholder for Phase 2 |

**KEEP subtotal: ~1,480 LOC (v1 audio I/O) + 190 LOC (v2 skeleton) + 678 LOC (build scripts).**

---

## INSPECT

Items where overlap or ownership is not clear-cut.

1. **`modules/runanywhere-core-sdcpp/`** — Contains only 2 binary `.so` files (`libOpenCL.so`,
   `librac_backend_sdcpp_jni.so`) and no Kotlin source. The diffusion capability is not in the
   v2 Phase 0-3 plan. **Question:** Is stable-diffusion a v2 target at all? If yes, what
   phase? If no, the `.so` files and module directory are dead weight now.

2. **`src/commonMain/.../foundation/SDKLogger.kt` (775 LOC)** — This is a large cross-platform
   logger with a `PlatformLogger` expect class actualized in both `jvmMain` and `androidMain`.
   v2 MASTER_PLAN has no mention of a Kotlin-side logger. **Question:** Does the v2 Kotlin
   adapter need any structured logging surface, or does the C++ core handle all diagnostics?

3. **`src/jvmMain/.../security/SecureStorage.kt` (314 LOC)** — Full JVM keychain
   (java.security.KeyStore). Auth is gone from the Kotlin layer in v2, but the IntelliJ plugin
   consumer may still need to store user credentials locally. **Question:** Does the IntelliJ
   plugin use this for API key storage, and does v2 have an equivalent?

4. **`build.gradle.kts` (top-level KMP)** — Contains `jvm` target (IntelliJ plugin consumer),
   `androidTarget`, NDK version pinned to `27.0.12077973`, and the `useLocalNatives`/
   `testLocal` property logic. In v2 the `frontends/kotlin/build.gradle.kts` is JVM-only with
   Wire. **Question:** Does the v2 Kotlin frontend need to also produce a KMP artifact (JVM +
   Android in one Gradle module), or will IntelliJ plugin and Android app depend on different
   artifacts?

5. **`src/androidMain/.../platform/NetworkConnectivity.kt` (253 LOC)** — Wraps
   `ConnectivityManager` to detect network state. C++ owns HTTP in v2, but Android requires
   `ACCESS_NETWORK_STATE` permission and the network callback is JVM-only. **Question:** Does
   the v2 Kotlin adapter need to expose a network-state gate before attempting pipeline start,
   or is this entirely a C++ concern?

---

## iosMain / iOS expect decls

`src/` contains no `iosMain` directory. The `build.gradle.kts` declares only `jvm` and
`androidTarget` — no `iosArm64()`, `iosSimulatorArm64()`, or `iosX64()` calls.

Every `expect` declaration in `commonMain` therefore has **no iOS actual**. The full list of
broken expect → iOS actual pairs (all currently unactualized for iOS):

| declaration | file | situation |
|---|---|---|
| `expect fun calculateSHA256(filePath: String): String` | `platform/Checksum.kt:17` | iOS has no actual; build would fail if iOS target added |
| `expect fun calculateMD5(filePath: String): String` | `platform/Checksum.kt:26` | same |
| `expect fun calculateSHA256Bytes(data: ByteArray): String` | `platform/Checksum.kt:32` | same |
| `expect fun calculateMD5Bytes(data: ByteArray): String` | `platform/Checksum.kt:38` | same |
| `expect suspend fun getPlatformStorageInfo(path: String): PlatformStorageInfo` | `platform/StoragePlatform.kt:23` | same |
| `expect fun getPlatformBaseDirectory(): String` | `platform/StoragePlatform.kt:33` | same |
| `expect fun getPlatformTempDirectory(): String` | `platform/StoragePlatform.kt:43` | same |
| `expect object PlatformUtils` | `utils/PlatformUtils.kt:6` | same |
| `expect object BuildConfig` | `utils/BuildConfig.kt:6` | same |
| `expect fun getHostAppInfo(): HostAppInfo` | `foundation/HostAppInfo.kt:15` | same |
| `expect fun currentTimeMillis(): Long` | `foundation/PlatformTime.kt:6` | same |
| `expect fun currentTimeISO8601(): String` | `foundation/PlatformTime.kt:11` | same |
| `expect class PlatformLogger(...)` | `foundation/SDKLogger.kt:475` | same |
| `expect class DeviceInfoService()` | `foundation/device/DeviceInfoService.kt:9` | same |
| `expect fun getPlatformAPILevel(): Int` | `data/models/DeviceInfoModels.kt:15` | same |
| `expect fun getPlatformOSVersion(): String` | `data/models/DeviceInfoModels.kt:21` | same |
| `expect fun createHttpClient(): HttpClient` | `data/network/HttpClient.kt:125` | same |
| `expect fun createHttpClient(config: NetworkConfiguration): HttpClient` | `data/network/HttpClient.kt:130` | same |
| `expect fun createAudioCaptureManager(): AudioCaptureManager` | `features/stt/services/AudioCaptureManager.kt:130` | same |
| `expect object TtsAudioPlayback` | `features/tts/TtsAudioPlayback.kt:6` | same |
| `expect class SecureStorageFactory` | `security/SecureStorage.kt:90` | same |
| `expect fun collectDeviceInfo(): DeviceInfo` | `models/DeviceInfo.kt:80` | same |
| All 40+ `expect fun RunAnywhere.*` in `public/extensions/` | various | same for all |

**MASTER_PLAN decision:** iOS uses the Swift SDK directly (`frontends/swift/`). There is no
reason to ever add an `iosMain` source set to `sdk/runanywhere-kotlin/`. All iOS-targeting
`expect` declarations become pointless dead declarations once v2 is complete.

IMM-6 (from `implementation_plan.md`) proposes adding `iosMain` — but this is a
**contradiction with the MASTER_PLAN** which explicitly routes iOS through `frontends/swift/`.
IMM-6 should be dropped; the expect declarations should be deleted along with the rest of the
v1 KMP surface.

---

## Duplication vs sdk/runanywhere-android/

`sdk/runanywhere-android/` does **not exist** in this repository. The Android SDK is the
`androidTarget` publication of `sdk/runanywhere-kotlin/` itself, published as Maven artifact
`runanywhere-sdk-android`. There is no separate standalone Android SDK tree to audit for
duplication.

---

## Script / build infra changes

| script | lines | status | reason |
|---|---|---|---|
| `scripts/build-kotlin.sh` | 620 | **KEEP** | IMM-2 fix applied; drives v1 coexistence build during Phase 1-2 |
| `scripts/build-sdk.sh` | 58 | **KEEP** | Orchestrates `build-kotlin.sh`; same coexistence reason |
| `scripts/package-sdk.sh` | 111 | **DELETE-AFTER-V2-ENGINES** | Packages AAR+JAR from pre-built `.so`; v2 uses `cmake --preset android-release` + `externalNativeBuild` in `frontends/kotlin/build.gradle.kts`. Blocker: v2 Android packaging CMake preset not yet defined. |

The v1 build scripts depend on the JNI copy logic that `implementation_plan.md` IMM-7
proposes extracting to `scripts/copy_jni_libs.sh`. Once that extraction lands, the v1 scripts
source the shared helper; they still run unchanged for v1 coexistence.

When v2 Phase 2 is complete, the `frontends/kotlin/build.gradle.kts` `externalNativeBuild`
block (backed by `cmake --preset android-release`) replaces the entire
`build-kotlin.sh → build-sdk.sh → package-sdk.sh` pipeline for Android packaging.
NDK version pinning (IMM-5) is currently in 5 locations; once the v1 scripts are retired
only the `frontends/kotlin/build.gradle.kts` location remains.

---

## Backwards-compat shims found

1. **`runanywhere.testLocal` → `runanywhere.useLocalNatives`** — `build.gradle.kts:63-79`
   reads both property names, emitting a deprecation warning for the old name. Once v1 is
   retired this dual-property read is dead.

2. **`isJitPack` / `usePendingNamespace` group-ID branching** — `build.gradle.kts:40-47`
   switches between `com.github.RunanywhereAI.*` (JitPack), `com.runanywhere` (DNS-pending),
   and `io.github.sanchitmonga22` (current verified) at build time. v2 uses `com.runanywhere`
   directly in `frontends/kotlin/build.gradle.kts:11`. The three-way branch in the v1 file
   is a transitional shim that becomes dead once v1 is retired.

3. **`nativeLibVersion` defaults to `resolvedVersion`** — `build.gradle.kts:91-95` falls back
   to the SDK version when `runanywhere.nativeLibVersion` is unset. This was added to
   decouple native and Kotlin release cadences. v2 has no equivalent because the C++ core
   and Kotlin adapter are always built together from the same CMake tree.
