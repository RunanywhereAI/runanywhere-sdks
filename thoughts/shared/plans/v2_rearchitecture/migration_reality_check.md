# Migration Reality Check: Legacy vs New Architecture
**Date:** 2026-04-19

> Agent-authored deep analysis comparing `sdk/runanywhere-*/` (legacy)
> vs `frontends/*` (new) to answer: "Can we just swap the C++ bridge
> and delete the rest?" Short answer: **no**.

## TL;DR

- Legacy Swift public API: **540+ declarations across 19 files**
- New Swift public API: **~25 declarations across 4 files**
- Production iOS app (`RunAnywhereAIApp.swift`) references ~40 legacy
  symbols not present in the new frontend. Swapping `import RunAnywhere`
  → `import RunAnywhereCore` produces ~40 compile errors on day one.
- `rac_compat.h` covers ~20 basic L3 function aliases. Legacy Swift
  bridge calls ~85 distinct C functions across 26 extension namespaces.
  The delta is not shimmable.
- ~30% of legacy Swift is Apple-framework platform code (AudioCapture,
  AudioPlayback, Foundation Models, CoreML Diffusion, Alamofire
  download, Sentry, Keychain) with no C equivalent and no port yet.

Honest total effort: **104–158 person-days** (5–7 months single
engineer, 10–14 weeks with two parallel tracks).

## Per-SDK public API surface

### Swift

**Legacy** (`sdk/runanywhere-swift/Sources/RunAnywhere/Public/`): 19 files, 540+ public declarations. Entry point is `public enum RunAnywhere` (`RunAnywhere.swift:57`) extended by 19 files covering:

Lifecycle: `initialize()` (line 197), `completeServicesInitialization()` (line 316), `reset()` (line 146), `ensureServicesReady()`.

State properties: `isSDKInitialized`, `areServicesReady`, `isActive`, `version`, `environment`, `deviceId`, `isAuthenticated`, `isDeviceRegistered()`, `getUserId()`, `getOrganizationId()`.

Method groups via extension files:
- LLM: `chat()`, `generate()`, `generateStream()`, `generateStructured()`, `generateWithTools()`
- STT: `transcribe()`, `transcribeStream()`
- TTS: `synthesize()`, `synthesizeStream()`, `loadTTSVoice()`
- VAD: `detectSpeech()`, `loadVADModel()`
- VoiceAgent: `startVoiceSession()`, `LiveTranscriptionSession`
- VLM: `generateVision()`, `loadVLMModel()`
- Diffusion: `generateImage()`
- Models: `loadModel()`, `loadSTTModel()`, `loadTTSVoice()`, `unloadModel()`, `availableModels()`, `getCurrentModelId()`, `cancelGeneration()`, `discoverDownloadedModels()`, `registerModel()`, `flushPendingRegistrations()`, `fetchModelAssignments()`, `getModelsForFramework()`, `getModelsForCategory()`
- LoRA: `loadLoraAdapter()`, `registerLoraAdapter()`, `removeLoraAdapter()`, `clearLoraAdapters()`
- RAG: `ragQuery()`
- Storage: `getStorageInfo()`
- Logging: `configureLogging()`, `setLocalLoggingEnabled()`, `setLogLevel()`, `setSentryLoggingEnabled()`, `addLogDestination()`, `setDebugMode()`, `flushLogs()`

Plus ~40 public types: `LLMConfiguration`, `LLMOptions`, `LLMGenerationResult`, `STTConfiguration`, `STTResult`, `TTSConfiguration`, `VADConfiguration`, `VoiceAgentConfiguration`, `VLMConfiguration`, `DiffusionRequest`, `ModelInfo`, `InferenceFramework`, `LoRAAdapterConfig`, `RAGConfiguration`, `StorageInfo`, `DownloadProgress`, `EventBus`, `SDKEnvironment`, `SDKError`, `SDKEvent`, etc.

**New Swift** (`frontends/swift/Sources/RunAnywhere/`): 4 files, ~25 public declarations:

Entry: `RunAnywhere.solution(_:)`, `RunAnywhere.configure(_:)`, `RunAnywhere.loadPlugin(at:)`, `RunAnywhere.registeredPluginCount`.

Config types: `SolutionConfig`, `VoiceAgentConfig`, `RAGConfig`, `WakeWordConfig`.

Session: `VoiceSession` with `run()` → `AsyncThrowingStream<Event, Error>`, `stop()`, `feedAudio(samples:sampleRateHz:)`, `bargeIn()`.

Event types: `VoiceSession.Event` (8 cases), `VoiceSession.TokenKind` (3), `VoiceSession.PipelineState` (5), `VoiceSession.VADKind` (5).

`RunAnywhereError` with 5 cases. `RegistrationBuilder` with `register(_ name: String)`; `apply()` is a TODO stub.

**Missing from new Swift that production uses**: `initialize()`, `reset()`, `isActive`, `registerModel()`, `flushPendingRegistrations()`, `discoverDownloadedModels()`, `loadModel()`, `loadSTTModel()`, `loadTTSVoice()`, `unloadModel()`, `availableModels()`, `chat()`, `generate()`, `generateStream()`, `generateStructured()`, `generateWithTools()`, `transcribe()`, `transcribeStream()`, `synthesize()`, `synthesizeStream()`, `detectSpeech()`, `loadVLMModel()`, `generateVision()`, `generateImage()`, `ragQuery()`, `loadLoraAdapter()`, `registerLoraAdapter()`, `startVoiceSession()`, `LiveTranscriptionSession`, `SDKEnvironment`, `EventBus`, `ModelInfo`, `ModelCategory`, `InferenceFramework`, `ModelArtifactType`, `LLMConfiguration`, `STTConfiguration`, `TTSConfiguration`, `VoiceAgentConfiguration`, `DiffusionRequest`, `DiffusionResult`, `VLMConfiguration`, `LoRAAdapterConfig`.

### Kotlin

**Legacy** (`sdk/runanywhere-kotlin/`): 161 files, ~41,180 lines. Mirrors Swift 1-for-1. Bridge files alone exceed 15,000 lines:
- `CppBridgeVoiceAgent.kt` (1591 lines) — full voice agent state machine
- `CppBridgeTTS.kt` (1316 lines)
- `CppBridgeLLM.kt` (1279 lines)
- 23 other `CppBridge*.kt` files

**New Kotlin** (`frontends/kotlin/`): `RunAnywhere.kt` + `VoiceSession.kt`, ~200 lines. 6 JNI methods only. Non-VoiceAgent configs produce error immediately.

### Dart

**New Dart** (`frontends/dart/`): ~280 lines. **Critical gap**: event callback wiring is an explicit not-implemented stub at `voice_session.dart:107–113`. The pipeline is created and `ra_pipeline_run` is called, but no event callback is registered — all events are discarded. This makes Dart non-functional for production even after other gaps close.

### TypeScript / React Native

**New TS** (`frontends/ts/`): ~200 lines. Requires external injection of `NativePipelineBindings` before any pipeline call works. No default binding exists.

### Web

**New Web** (`frontends/web/`): Async init. WASM build of new core is a listed follow-up.

## Where does business logic live in legacy?

### Swift: NOT a thin bridge — ~30% is non-bridge platform Swift

91 Swift files. Substantial platform services with no equivalent in `frontends/swift/`:

- `AudioCaptureManager.swift` (482 lines) — full AVAudioEngine mic capture
- `AudioPlaybackManager.swift` (216 lines) — PCM playback via AVAudioPlayerNode
- `SystemFoundationModelsService.swift` (236 lines) — Apple Foundation Models
- `DiffusionPlatformService.swift` (325 lines) — CoreML StableDiffusion
- `AlamofireDownloadService.swift` (387 lines) — download with Alamofire
- `CppBridge+Platform.swift` (501 lines) — registers Swift closures with legacy C++ platform backend
- `SentryManager.swift` + `SentryDestination.swift` — Sentry telemetry
- `KeychainManager.swift` — Keychain API key storage

`CppBridge.swift:14–27` documents the 5-phase init that registers Swift callbacks with C++. None of those 5 phases exist in the new frontend.

### Kotlin: Even heavier

`CppBridgeVoiceAgent.kt` (1591 lines) contains the full multi-step voice agent state machine: VAD event handling, STT result processing, LLM streaming integration, TTS queue management, barge-in logic, transcript accumulation. This is business logic, not marshaling. The new `VoiceSession.kt` (157 lines) correctly delegates all of this to `ra_pipeline_*` in C++ — but requires the C++ pipeline to be feature-complete before Kotlin can drop the legacy bridge.

## Does "just swap the C++ bridge" work?

**No.** Three reasons:

**Reason 1: Production iOS app does not compile against new frontend.**

`examples/ios/RunAnywhereAI/RunAnywhereAI/App/RunAnywhereAIApp.swift` calls:
- `RunAnywhere.initialize()` (line 161)
- `RunAnywhere.registerModel(...)` × 30+ (starting line 198)
- `RunAnywhere.flushPendingRegistrations()` (line 111)
- `RunAnywhere.discoverDownloadedModels()` (line 112)
- `RunAnywhere.isActive` (line 120)
- `LlamaCPP.register(priority:)`, `ONNX.register(priority:)`, `WhisperKitSTT.register(priority:)` (lines 89–91)

Swapping `import RunAnywhere` → `import RunAnywhereCore` produces ~40 compile errors. Zero of the required symbols exist in the new frontend.

**Reason 2: `rac_compat.h` covers a narrow subset of the legacy C surface.**

`core/abi/rac_compat.h` provides typedef aliases for ~20 basic L3 function names. The legacy Swift bridge calls ~85 distinct C functions across 26 `CppBridge+*.swift` extension files. The delta includes: `rac_model_registry_*`, `rac_model_assignment_*`, `rac_model_paths_*`, `rac_download_orchestrator_*`, `rac_auth_manager_*`, `rac_platform_*`, `rac_lora_registry_*`, `rac_tool_calling_*`, `rac_structured_output_*`, `rac_vlm_*`, `rac_diffusion_*`, `rac_server_*`, and the `rac_llm_service_ops_t` / `rac_tts_service_ops_t` vtable-based service registration system. None shimmed.

**Reason 3: Non-bridge platform code must be independently ported.**

`AudioCaptureManager.swift`, `AudioPlaybackManager.swift`, `SystemFoundationModelsService.swift`, `DiffusionPlatformService.swift`, `AlamofireDownloadService.swift`, `CppBridge+Platform.swift` are Swift services wrapping Apple frameworks. Swapping the C bridge does not port them.

## Still-gapped capabilities in new `core/`

| Gap | Blocks |
|---|---|
| LLM tool-calling executor | `generateWithTools()` |
| LLM LoRA adapter load executor | `loadLoraAdapter()` |
| LLM KV-cache context injection | Advanced context management |
| TTS streaming synthesis | `synthesizeStream()` |
| STT batch transcription | `transcribe()` full-file |
| VLM (image+text inference) | `generateVision()` |
| Diffusion (text→image, etc.) | `generateImage()` |
| Platform callbacks (Foundation Models, System TTS, CoreML) | iOS system-backend features |
| Device manager | Device analytics and registration |
| OpenAI HTTP server | Desktop/server integrations |
| Voice agent state machine (WAITING_WAKEWORD → LISTENING → …) | Full multi-step state machine |
| JNI bridges for new ABI | Kotlin SDK migration |
| WASM build of new core | Web SDK migration |

## Realistic target folder structure

```
runanywhere-sdks/
├── core/                          # New C++ core — keep as-is
├── frontends/                     # Promoted to production SDKs
│   ├── swift/                     # (replaces sdk/runanywhere-swift)
│   │   └── Sources/RunAnywhere/
│   │       ├── Adapter/           # existing RunAnywhere.swift + VoiceSession.swift
│   │       │                      # ADD: model registration, lifecycle, audio, download, Sentry
│   │       └── Platform/          # NEW: AudioCaptureManager, AudioPlaybackManager,
│   │                               # FoundationModels plugin, Diffusion plugin
│   ├── kotlin/                    # (replaces sdk/runanywhere-kotlin)
│   │   # ADD: JNI for full ABI, KMP commonMain, audio capture, download
│   ├── dart/                      # (replaces sdk/runanywhere-flutter)
│   │   # MUST: wire event callbacks (voice_session.dart:107–113 TODO)
│   ├── ts/                        # (replaces sdk/runanywhere-react-native)
│   │   # MUST: implement NativePipelineBindings TurboModule
│   └── web/                       # (replaces sdk/runanywhere-web, after WASM build)
├── examples/                      # Sample apps migrated to import frontends/*
└── sdk/                           # DELETED after all migrations complete
```

## Effort breakdown (person-days)

| Track | Days |
|---|---|
| C++ core gaps (tool executor, LoRA load, device mgr, VLM, diffusion, JNI bridge, WASM, voice state machine) | 24–36 |
| Swift SDK (lifecycle + models + audio + platform plugins + downloads + Sentry + API surface) | 38–57 |
| Swift sample app migration | 3–4 (within Swift track) |
| Kotlin SDK (JNI + KMP + audio + download + API surface) | 20–31 |
| Android sample app migration | 3–5 (within Kotlin track) |
| Dart (event wiring + API surface) | 10–15 |
| TS/RN (TurboModule + API surface) | 7–11 |
| Web (WASM + API surface) | 5–8 |
| **Total** | **104–158 days** |

Single engineer: 5–8 months. Two engineers (one C++/Swift, one Kotlin/Dart): critical path compresses to 10–16 weeks because Swift and Kotlin share C++ prerequisites.

Critical path: Swift at 38–57 days alone.

## Essential files

| File | Relevance |
|---|---|
| `sdk/runanywhere-swift/Sources/RunAnywhere/Public/RunAnywhere.swift` | Legacy Swift entry |
| `sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/CppBridge.swift` | Bridge architecture, 5-phase init |
| `sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+Platform.swift` | 501 lines platform callbacks — nothing equivalent in new frontend |
| `sdk/runanywhere-swift/Sources/RunAnywhere/Features/STT/Services/AudioCaptureManager.swift` | 482-line audio capture — must port |
| `sdk/runanywhere-swift/Sources/RunAnywhere/Features/Diffusion/DiffusionPlatformService.swift` | 325-line CoreML diffusion — must port |
| `frontends/swift/Sources/RunAnywhere/Adapter/RunAnywhere.swift` | New Swift entry — only 4 public functions |
| `frontends/swift/Sources/RunAnywhere/Adapter/VoiceSession.swift` | New Swift session — complete and production-quality |
| `frontends/swift/Sources/RunAnywhere/Adapter/RegistrationBuilder.swift` | `apply()` is TODO stub |
| `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/public/RunAnywhere.kt` | Legacy Kotlin entry, 354 lines |
| `frontends/kotlin/src/main/kotlin/com/runanywhere/adapter/VoiceSession.kt` | New Kotlin session, 157 lines |
| `frontends/dart/lib/adapter/voice_session.dart` | Dart event wiring TODO at 107–113 |
| `core/abi/ra_pipeline.h` | New pipeline ABI |
| `core/abi/ra_primitives.h` | New L3 primitives ABI |
| `core/abi/rac_compat.h` | Compat shim — covers ~20 of ~85 legacy C functions |
| `examples/ios/RunAnywhereAI/RunAnywhereAI/App/RunAnywhereAIApp.swift` | Production iOS app — 30+ `registerModel` calls, all legacy |
| `thoughts/shared/plans/v2_rearchitecture/feature_parity_audit.md` | Canonical gap table |
| `thoughts/shared/plans/v2_rearchitecture/current_state_2026-04-19.md` | What's landed vs still gapped |
