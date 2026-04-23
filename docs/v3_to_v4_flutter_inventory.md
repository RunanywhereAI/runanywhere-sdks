# v3 → v4 Flutter Static `RunAnywhere` Inventory

Phase C (v2 close-out) audit of the god-class
`packages/runanywhere/lib/public/runanywhere.dart` (2,621 LOC).
Maps every public static symbol to its target v4 capability, lists
private helpers that move to `lib/internal/`, and catalogs the
static state and reverse-dependencies that block deletion.

## 1. Public symbol → target capability

| Static symbol (old) | Category | Target v4 call | File target |
|---|---|---|---|
| `isSDKInitialized` getter | Lifecycle | `RunAnywhereSDK.instance.isInitialized` | `runanywhere_v4.dart` |
| `isActive` getter | Lifecycle | `RunAnywhereSDK.instance.isActive` | `runanywhere_v4.dart` |
| `initParams` getter | Lifecycle | `RunAnywhereSDK.instance.initParams` | `runanywhere_v4.dart` |
| `environment` getter | Lifecycle | `RunAnywhereSDK.instance.environment` | `runanywhere_v4.dart` |
| `getCurrentEnvironment()` | Lifecycle | `RunAnywhereSDK.instance.environment` | `runanywhere_v4.dart` |
| `version` getter | Lifecycle | `RunAnywhereSDK.instance.version` | `runanywhere_v4.dart` |
| `events` getter | Events | `RunAnywhereSDK.instance.events` | `runanywhere_v4.dart` |
| `initialize(...)` | Lifecycle | `RunAnywhereSDK.instance.initialize(...)` | `runanywhere_v4.dart` |
| `initializeWithParams(...)` | Lifecycle | `RunAnywhereSDK.instance.initializeWithParams(...)` | `runanywhere_v4.dart` |
| `reset()` | Lifecycle | `RunAnywhereSDK.instance.reset()` | `runanywhere_v4.dart` |
| `serviceContainer` getter | Lifecycle (internal) | kept on `RunAnywhereSDK` (private) | `runanywhere_v4.dart` |
| `availableModels()` | Models | `RunAnywhereSDK.instance.models.available()` | `capabilities/runanywhere_models.dart` |
| `registerModel(...)` | Models | `RunAnywhereSDK.instance.models.register(...)` | `capabilities/runanywhere_models.dart` |
| `registerMultiFileModel(...)` | Models | `RunAnywhereSDK.instance.models.registerMultiFile(...)` | `capabilities/runanywhere_models.dart` |
| `updateModelDownloadStatus(...)` | Models | `RunAnywhereSDK.instance.models.updateDownloadStatus(...)` | `capabilities/runanywhere_models.dart` |
| `removeModel(...)` | Models | `RunAnywhereSDK.instance.models.remove(...)` | `capabilities/runanywhere_models.dart` |
| `refreshDiscoveredModels()` | Models | `RunAnywhereSDK.instance.models.refresh()` | `capabilities/runanywhere_models.dart` |
| `currentModelId` getter | LLM | `RunAnywhereSDK.instance.llm.currentModelId` | `capabilities/runanywhere_llm.dart` |
| `isModelLoaded` getter | LLM | `RunAnywhereSDK.instance.llm.isLoaded` | `capabilities/runanywhere_llm.dart` |
| `currentLLMModel()` | LLM | `RunAnywhereSDK.instance.llm.currentModel()` | `capabilities/runanywhere_llm.dart` |
| `loadModel(id)` | LLM | `RunAnywhereSDK.instance.llm.load(id)` | `capabilities/runanywhere_llm.dart` |
| `unloadModel()` | LLM | `RunAnywhereSDK.instance.llm.unload()` | `capabilities/runanywhere_llm.dart` |
| `chat(prompt)` | LLM | `RunAnywhereSDK.instance.llm.chat(prompt)` | `capabilities/runanywhere_llm.dart` |
| `generate(prompt, options)` | LLM | `RunAnywhereSDK.instance.llm.generate(...)` | `capabilities/runanywhere_llm.dart` |
| `generateStream(prompt, options)` | LLM | `RunAnywhereSDK.instance.llm.generateStream(...)` | `capabilities/runanywhere_llm.dart` |
| `cancelGeneration()` | LLM | `RunAnywhereSDK.instance.llm.cancel()` | `capabilities/runanywhere_llm.dart` |
| `currentSTTModelId` getter | STT | `RunAnywhereSDK.instance.stt.currentModelId` | `capabilities/runanywhere_stt.dart` |
| `isSTTModelLoaded` getter | STT | `RunAnywhereSDK.instance.stt.isLoaded` | `capabilities/runanywhere_stt.dart` |
| `currentSTTModel()` | STT | `RunAnywhereSDK.instance.stt.currentModel()` | `capabilities/runanywhere_stt.dart` |
| `loadSTTModel(id)` | STT | `RunAnywhereSDK.instance.stt.load(id)` | `capabilities/runanywhere_stt.dart` |
| `unloadSTTModel()` | STT | `RunAnywhereSDK.instance.stt.unload()` | `capabilities/runanywhere_stt.dart` |
| `transcribe(bytes)` | STT | `RunAnywhereSDK.instance.stt.transcribe(bytes)` | `capabilities/runanywhere_stt.dart` |
| `transcribeWithResult(bytes)` | STT | `RunAnywhereSDK.instance.stt.transcribeWithResult(bytes)` | `capabilities/runanywhere_stt.dart` |
| `currentTTSVoiceId` getter | TTS | `RunAnywhereSDK.instance.tts.currentVoiceId` | `capabilities/runanywhere_tts.dart` |
| `isTTSVoiceLoaded` getter | TTS | `RunAnywhereSDK.instance.tts.isLoaded` | `capabilities/runanywhere_tts.dart` |
| `currentTTSVoice()` | TTS | `RunAnywhereSDK.instance.tts.currentVoice()` | `capabilities/runanywhere_tts.dart` |
| `loadTTSVoice(id)` | TTS | `RunAnywhereSDK.instance.tts.loadVoice(id)` | `capabilities/runanywhere_tts.dart` |
| `unloadTTSVoice()` | TTS | `RunAnywhereSDK.instance.tts.unloadVoice()` | `capabilities/runanywhere_tts.dart` |
| `synthesize(text, rate, pitch, volume)` | TTS | `RunAnywhereSDK.instance.tts.synthesize(text, rate, pitch, volume)` | `capabilities/runanywhere_tts.dart` |
| `isVLMModelLoaded` getter | VLM | `RunAnywhereSDK.instance.vlm.isLoaded` | `capabilities/runanywhere_vlm.dart` |
| `currentVLMModelId` getter | VLM | `RunAnywhereSDK.instance.vlm.currentModelId` | `capabilities/runanywhere_vlm.dart` |
| `loadVLMModel(id)` | VLM | `RunAnywhereSDK.instance.vlm.load(id)` | `capabilities/runanywhere_vlm.dart` |
| `loadVLMModelById(id)` | VLM | `RunAnywhereSDK.instance.vlm.loadById(id)` | `capabilities/runanywhere_vlm.dart` |
| `loadVLMModelWithPath(...)` | VLM | `RunAnywhereSDK.instance.vlm.loadWithPath(...)` | `capabilities/runanywhere_vlm.dart` |
| `unloadVLMModel()` | VLM | `RunAnywhereSDK.instance.vlm.unload()` | `capabilities/runanywhere_vlm.dart` |
| `cancelVLMGeneration()` | VLM | `RunAnywhereSDK.instance.vlm.cancel()` | `capabilities/runanywhere_vlm.dart` |
| `describeImage(image, prompt)` | VLM | `RunAnywhereSDK.instance.vlm.describe(image, prompt)` | `capabilities/runanywhere_vlm.dart` |
| `askAboutImage(q, image)` | VLM | `RunAnywhereSDK.instance.vlm.askAbout(q, image)` | `capabilities/runanywhere_vlm.dart` |
| `processImage(image, prompt)` | VLM | `RunAnywhereSDK.instance.vlm.processImage(image, prompt)` | `capabilities/runanywhere_vlm.dart` |
| `processImageStream(image, prompt)` | VLM | `RunAnywhereSDK.instance.vlm.processImageStream(image, prompt)` | `capabilities/runanywhere_vlm.dart` |
| `isVoiceAgentReady` getter | Voice | `RunAnywhereSDK.instance.voice.isReady` | `capabilities/runanywhere_voice.dart` |
| `getVoiceAgentComponentStates()` | Voice | `RunAnywhereSDK.instance.voice.componentStates()` | `capabilities/runanywhere_voice.dart` |
| `initializeVoiceAgentWithLoadedModels()` | Voice | `RunAnywhereSDK.instance.voice.initializeWithLoadedModels()` | `capabilities/runanywhere_voice.dart` |
| `cleanupVoiceAgent()` | Voice | `RunAnywhereSDK.instance.voice.cleanup()` | `capabilities/runanywhere_voice.dart` |
| `downloadModel(id)` | Downloads | `RunAnywhereSDK.instance.downloads.start(id)` | `capabilities/runanywhere_downloads.dart` |
| `deleteStoredModel(id)` | Downloads | `RunAnywhereSDK.instance.downloads.delete(id)` | `capabilities/runanywhere_downloads.dart` |
| `getStorageInfo()` | Downloads/Storage | `RunAnywhereSDK.instance.downloads.getStorageInfo()` | `capabilities/runanywhere_downloads.dart` |
| `getDownloadedModelsWithInfo()` | Downloads | `RunAnywhereSDK.instance.downloads.list()` | `capabilities/runanywhere_downloads.dart` |
| (Tools) `RunAnywhereToolCalling.*` | Tools | `RunAnywhereSDK.instance.tools.*` | `capabilities/runanywhere_tools.dart` (NEW) |
| (RAG) `RunAnywhereRAG.rag*` | RAG | `RunAnywhereSDK.instance.rag.*` | `capabilities/runanywhere_rag.dart` (NEW) |

## 2. Private helpers that move to `lib/internal/`

| Helper | From | New home |
|---|---|---|
| `_registerDeviceIfNeeded` | Lifecycle | `lib/internal/sdk_init.dart` |
| `_authenticateWithBackend` | Lifecycle | `lib/internal/sdk_init.dart` |
| `_runDiscovery` | Models | `lib/internal/sdk_init.dart` |
| `_saveToCppRegistry` | Models | `lib/internal/model_registry_helpers.dart` |
| `_inferFormat` | Models | `lib/internal/model_registry_helpers.dart` |
| `_processImageViaBridge` | VLM | in `capabilities/runanywhere_vlm.dart` (private) |
| `_processImageStreamViaBridge` | VLM | in `capabilities/runanywhere_vlm.dart` (private) |
| `_resolveVLMModelFilePath` | VLM | in `capabilities/runanywhere_vlm.dart` (private) |
| `_findMmprojFile` | VLM | in `capabilities/runanywhere_vlm.dart` (private) |
| `_mapDownloadStage` | Downloads | in `capabilities/runanywhere_downloads.dart` (private) |
| `_getDeviceStorageInfo` | Downloads | in `capabilities/runanywhere_downloads.dart` (private) |
| `_getAppStorageInfo` | Downloads | in `capabilities/runanywhere_downloads.dart` (private) |
| `_getDirectorySize` | Downloads | in `capabilities/runanywhere_downloads.dart` (private) |
| `_normalizeStructuredData` | LLM | in `capabilities/runanywhere_llm.dart` (private) |

## 3. Mutable static state

All held in `RunAnywhere` today; moved to `lib/internal/sdk_state.dart` as an instance-scoped `SdkState` singleton so capability classes can share it without going through the god-class.

| Field | Type | Semantics |
|---|---|---|
| `_initParams` | `SDKInitParams?` | Initialization arguments. |
| `_currentEnvironment` | `SDKEnvironment?` | Active env (dev/staging/prod). |
| `_isInitialized` | `bool` | True after initialize succeeds. |
| `_hasRunDiscovery` | `bool` | Tracks lazy one-shot discovery. |
| `_registeredModels` | `List<ModelInfo>` | Models registered by app at startup. |

## 4. Reverse deps (`legacy.RunAnywhere.X` back-calls) to clean up

Present before Phase C — every one of these must go away during the refactor.

| File | Symbols it calls on `RunAnywhere` |
|---|---|
| `lib/public/runanywhere_v4.dart` | `isSDKInitialized`, `initParams`, `environment`, `version`, `events`, `initialize`, `reset` |
| `lib/public/capabilities/runanywhere_llm.dart` | `isModelLoaded`, `currentModelId`, `currentLLMModel`, `loadModel`, `unloadModel`, `chat`, `generate`, `generateStream`, `cancelGeneration` |
| `lib/public/capabilities/runanywhere_stt.dart` | `isSTTModelLoaded`, `currentSTTModelId`, `currentSTTModel`, `loadSTTModel`, `unloadSTTModel`, `transcribe`, `transcribeWithResult` |
| `lib/public/capabilities/runanywhere_tts.dart` | `isTTSVoiceLoaded`, `currentTTSVoiceId`, `currentTTSVoice`, `loadTTSVoice`, `unloadTTSVoice`, `synthesize` |
| `lib/public/capabilities/runanywhere_vlm.dart` | `isVLMModelLoaded`, `currentVLMModelId`, `loadVLMModel{,ById,WithPath}`, `unloadVLMModel`, `cancelVLMGeneration`, `describeImage`, `askAboutImage`, `processImage{,Stream}` |
| `lib/public/capabilities/runanywhere_voice.dart` | `isVoiceAgentReady`, `initializeVoiceAgentWithLoadedModels`, `cleanupVoiceAgent` |
| `lib/public/capabilities/runanywhere_models.dart` | `availableModels`, `refreshDiscoveredModels` |
| `lib/public/capabilities/runanywhere_downloads.dart` | `downloadModel`, `deleteStoredModel`, `getStorageInfo`, `getDownloadedModelsWithInfo` |
| `lib/public/extensions/runanywhere_rag.dart` | `isSDKInitialized` (via `extension on RunAnywhere`) |
| `lib/public/extensions/runanywhere_lora.dart` | `isSDKInitialized` |
| `lib/public/extensions/runanywhere_frameworks.dart` | `availableModels` |
| `lib/public/extensions/runanywhere_logging.dart` | none (uses `extension on RunAnywhere` as namespace only) |
| `lib/public/extensions/runanywhere_storage.dart` | none (ext namespace only) |
| `lib/public/extensions/runanywhere_device.dart` | none (ext namespace only) |
| `lib/public/runanywhere_tool_calling.dart` | `generate`, `generateStream` (+ ext namespace) |
| `lib/infrastructure/download/download_service.dart:113,470` | `updateModelDownloadStatus` / `removeModel` |

## 5. Plan for C-2/C-3/C-4/C-5

- Build `lib/internal/sdk_state.dart` (shared mutable state) + `lib/internal/sdk_init.dart` (device registration, auth, discovery).
- Move impls into each capability class as listed above; kill `extension X on RunAnywhere` in favour of concrete classes exposed on `RunAnywhereSDK` (for Tools + RAG) or kept as their own standalone class with `static` methods (for Logging/Lora/Frameworks/Device/Storage).
- Drop `import ... runanywhere.dart as legacy;` line everywhere.
- Delete `packages/runanywhere/lib/public/runanywhere.dart` (the whole god-class).

## 6. Status (post-Phase-C close-out)

**All items above are complete.** This inventory is archived as the
audit trail for the god-class deletion — no symbol listed here remains
reachable. See `docs/migrations/v3_to_v4_flutter.md` for the canonical
v3→v4 mapping table and `docs/v2_closeout_phase_c_report.md` for the
line-count delta + verification outputs.
