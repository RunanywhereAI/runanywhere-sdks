# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Development Commands

```bash
# Build debug APK
./gradlew :app:assembleDebug

# Build release APK
./gradlew :app:assembleRelease

# Install on connected device/emulator
./gradlew :app:installDebug

# Run all tests
./gradlew :app:test

# Lint
./gradlew :app:lint

# Detekt static analysis
./gradlew detekt

# ktlint formatting check
./gradlew ktlintCheck

# ktlint auto-format
./gradlew ktlintFormat

# Full build (includes SDK modules)
./gradlew build

# Verify build (checks ANDROID_HOME, optionally rebuilds natives)
./scripts/verify.sh

# Check SDK API call coverage
./scripts/smoke.sh
```

**Build targets**: compileSdk 36, minSdk 24, targetSdk 36, JVM target 17. ABI splits: `arm64-v8a`, `x86_64`.

## SDK Module Wiring

This app does **not** consume published artifacts. It depends on local SDK source via `settings.gradle.kts`:

- `project(":runanywhere-kotlin")` → `../../../sdk/runanywhere-kotlin` (core SDK)
- `project(":runanywhere-core-llamacpp")` → `../../../sdk/runanywhere-core-llamacpp` (LLM/GGUF inference)
- `project(":runanywhere-core-onnx")` → `../../../sdk/runanywhere-core-onnx` (STT/TTS/VAD via ONNX)
- Genie NPU AAR from Maven Central (`com.qualcomm.qti:QNNSdk`) — Qualcomm Snapdragon on-device inference

Key gradle properties in `gradle.properties`:
- `runanywhere.useLocalNatives=true` — use pre-built JNI .so files from local paths
- `runanywhere.testLocal=true` — local test mode
- `runanywhere.rebuildCommons=false` — skip native rebuild

Native libraries require `useLegacyPackaging=true` and `pickFirsts` for duplicate .so resolution in `app/build.gradle.kts`.

## Architecture

### Pattern: MVVM + Jetpack Compose + Single Activity

- **Single Activity**: `MainActivity.kt` — initializes PDF resources, observes `SDKInitializationState`, renders Compose root
- **Navigation**: `AppNavigation.kt` with `NavigationRoute` object constants. Bottom tabs: Chat, Vision, Voice, More, Settings. "More" is a hub linking to STT, TTS, RAG, Benchmarks, LoRA Manager, Solutions
- **State Management**: `MutableStateFlow` / `StateFlow` in every ViewModel, consumed via `collectAsState()` in Compose
- **SDK Communication**: All SDK calls go through `RunAnywhere.*` extension functions. Events propagate via `EventBus.events` (SharedFlow) filtered by type (`LLMEvent`, `ModelEvent`, `STTEvent`, `TTSEvent`)

### SDK Initialization Flow

`RunAnywhereApplication.onCreate()` → delayed post to main looper → IO coroutine:
1. `AndroidPlatformContext.initialize(context)`
2. `RunAnywhere.initialize(apiKey, baseURL, environment)` — environment from `BuildConfig.DEBUG_MODE`, not `BuildConfig.DEBUG`
3. `RunAnywhere.completeServicesInitialization()` — device registration
4. `ModelList.setupModels()` — registers all models and backends

Falls back to development/offline mode on failure. Custom API config read from `EncryptedSharedPreferences`.

### Backend Registration Order

In `ModelList.setupModels()`:
```
LlamaCPP.register(priority = 100)  — LLM, VLM inference via GGUF
ONNX.register(priority = 100)      — STT, TTS, VAD, embeddings
Genie.register(priority = 200)     — NPU inference (Snapdragon only, higher priority)
```

## Feature Modules

### Chat / LLM (`presentation/chat/`)
- **ChatViewModel**: Streaming via `RunAnywhere.generateStream()`, non-streaming via `RunAnywhere.generate()`, tool calling via `RunAnywhereToolCalling.generateWithTools()`
- Parses `<think>...</think>` tags for thinking/reasoning mode display
- Tracks analytics: tokens/sec, TTFT (time to first token)
- Conversation persistence via `ConversationStore` (JSON files in `filesDir/Conversations/`)
- Subscribes to `EventBus.events.filterIsInstance<LLMEvent>()`
- Proto-backed generation options: `LLMGenerationOptions`

### Speech-to-Text (`presentation/stt/`)
- **SpeechToTextViewModel**: Two modes — BATCH (`RunAnywhere.transcribe()`) and LIVE (`RunAnywhere.transcribeStream()`)
- Audio capture via `AudioCaptureService` (16kHz, mono, PCM 16-bit, 100ms chunks)
- Model: Sherpa Whisper Tiny (SHERPA framework)

### Text-to-Speech (`presentation/tts/`)
- **TextToSpeechViewModel**: SDK TTS via `RunAnywhere.synthesize(TTSOptions)`, plus Android system TTS fallback
- AudioTrack playback with WAV header parsing (scans for "data" chunk marker)
- Models: Piper US/British English voices (SHERPA framework)

### Voice Assistant (`presentation/voice/`)
- **VoiceAssistantViewModel**: Full STT → LLM → TTS pipeline
- Streaming: `RunAnywhere.streamVoiceAgent()` for proto-backed voice events
- One-shot: `RunAnywhere.processVoiceTurn()`
- Speech detection: audio level threshold (0.1f), silence timeout (1500ms)
- Continuous conversation mode with auto-resume after TTS playback

### Vision / VLM (`presentation/vlm/`)
- **VLMViewModel**: CameraX `LifecycleCameraController` for frame capture
- Frame format: RGBA_8888 bitmap → RGB byte array conversion
- Auto-streaming mode captures frames every 2.5 seconds
- Inference via `RunAnywhere.processImageStream()` for streaming token output
- Proto-backed: `VLMGenerationOptions`
- Models: SmolVLM, LFM2-VL, Qwen2-VL (LLAMA_CPP framework)

### RAG (`presentation/rag/`)
- **RAGViewModel**: Document-based retrieval-augmented generation
- Pipeline: extract text (`DocumentService.extractText`) → `RunAnywhere.ragCreatePipeline(RAGConfiguration)` → `RunAnywhere.ragIngest()` → `RunAnywhere.ragQuery()`
- Teardown: `RunAnywhere.ragDestroyPipeline()`
- Proto-backed: `RAGConfiguration`
- Embedding model: All MiniLM L6 v2 (ONNX framework)

### Benchmarks (`presentation/benchmarks/`)
- **BenchmarkViewModel**: Orchestrates via `BenchmarkRunner`
- Supports LLM, STT, TTS, VLM benchmark types
- Results persisted via `BenchmarkStore`
- Export formats: clipboard, CSV, JSON

### LoRA Adapters (`presentation/lora/`)
- **LoraViewModel**: Full lifecycle — download, load, unload, delete, compatibility check
- SDK extensions: `loadLoraAdapter`, `removeLoraAdapter`, `clearLoraAdapters`, `checkLoraCompatibility`, `downloadLoraAdapter`
- Proto-backed: `LoRAAdapterConfig`, `LoRAAdapterInfo`, `LoraCompatibilityResult`

### Model Selection (`presentation/models/`)
- **ModelSelectionViewModel**: Context-aware filtering via `ModelSelectionContext` enum (LLM, STT, TTS, VOICE, RAG_EMBEDDING, RAG_LLM, VLM)
- Download: `RunAnywhere.downloadModel(id)` returns `Flow<DownloadProgress>`
- Context-aware loading dispatches to: `loadLLMModel`, `loadSTTModel`, `loadTTSVoice`, `loadVLMModel`
- RAG contexts select by reference only (no memory load)

### Settings (`presentation/settings/`)
- **SettingsViewModel**: Storage management via `RunAnywhere.storageInfo()`, `RunAnywhere.deleteModel()`, `RunAnywhere.clearCache()`
- API config in `EncryptedSharedPreferences` (key: `runanywhere_encrypted_prefs`)
- Generation settings (temperature, maxTokens, systemPrompt) in standard `SharedPreferences`

## Data Layer

### Models & Persistence
- `ChatMessage.kt` — Serializable domain models: `ChatMessage`, `Conversation`, `MessageAnalytics`, `MessageRole`, `ToolCallInfo`, `PerformanceSummary`
- `ConversationStore.kt` — Singleton, persists conversations as JSON in `filesDir/Conversations/` using kotlinx.serialization
- `ModelList.kt` — Central model registry. All available models (LLM, STT, TTS, embedding, VLM, LoRA, Genie NPU) registered at startup

### Audio
- `AudioCaptureService.kt` — Wraps `AudioRecord`, emits PCM chunks via `callbackFlow`. 16kHz, mono, 16-bit. Calculates RMS for level visualization.

## Conventions

- **iOS is source of truth** — many ViewModels and components reference iOS equivalents in comments (e.g., "Reference: iOS ModelSelectionSheet.swift"). When behavior is unclear, check the iOS example app.
- **Proto-backed types** — SDK types use protobuf extensively. Always use the proto-generated types (`LLMGenerationOptions`, `TTSOptions`, `VLMGenerationOptions`, `RAGConfiguration`, `LoRAAdapterConfig`) rather than raw strings/maps.
- **Timber logging** — all logging uses Timber with emoji prefixes for log categories
- **Structured types over strings** — enums and sealed classes for state, errors, and categories. Never use raw strings for identifiers.
- **`BuildConfig.DEBUG_MODE`** reflects actual build type (debug vs release). `BuildConfig.DEBUG` is always true (isDebuggable enabled for release logging).

## Manifest & Permissions

- `RECORD_AUDIO` — STT, Voice features
- `CAMERA` — VLM camera capture
- `INTERNET` — model downloads, backend communication
- `largeHeap=true` — required for on-device model inference
- `extractNativeLibs=true` — JNI .so extraction
- Qualcomm FastRPC library declared for NPU access
- 16KB page size support property enabled

## Code Quality

- **Detekt** (`detekt.yml`): Focused on unused code — UnusedImports, UnusedPrivateClass, UnusedPrivateMember, UnusedPrivateProperty, GlobalCoroutineUsage, EmptyCatchBlock, NotImplementedDeclaration, VarCouldBeVal
- **ktlint** v1.5.0 with android mode enabled
- Run `./gradlew detekt` and `./gradlew ktlintCheck` before committing
