# CLAUDE.md — iOS RunAnywhereAI Example App

This file documents the iOS example application for the RunAnywhere on-device AI SDK. It serves as a detailed reference for every module, feature, architecture pattern, data flow, and build/run instruction.

---

## How to Build & Run

### Quick Build & Run (Recommended)
```bash
cd examples/ios/RunAnywhereAI/

# Simulator (handles SDK + XCFramework dependencies automatically)
./scripts/build_and_run.sh simulator "iPhone 16 Pro" --build-sdk

# Physical device
./scripts/build_and_run.sh device

# macOS Catalyst / native
./scripts/build_and_run.sh mac

# Clean build artifacts
./scripts/clean_build_and_run.sh
```

### Manual Setup
```bash
# Open via Xcode (SPM resolves dependencies automatically)
open RunAnywhereAI.xcodeproj

# Verify XCFrameworks exist (CI gate)
./scripts/verify.sh

# Quick smoke test (greps for SDK API calls, no compilation)
./scripts/smoke.sh
```

### Logging
```bash
# Simulator / Mac
log stream --predicate 'subsystem CONTAINS "com.runanywhere"' --info --debug

# Physical device
idevicesyslog | grep "com.runanywhere"
```

### App Store Release
See `docs/RELEASE_INSTRUCTIONS.md`. Key step: after building, run `./scripts/patch-framework-plist.sh` to fix `MinimumOSVersion` in ONNX Runtime / RACommons XCFrameworks before archiving.

---

## Architecture Overview

### Pattern: MVVM with Swift Observation
- **Views** are pure SwiftUI with no business logic
- **ViewModels** are `@MainActor @Observable` (or `@MainActor ObservableObject`) classes owning all state and SDK calls
- **Models** are `Codable` value types (`Message`, `Conversation`, `MessageAnalytics`, `BenchmarkTypes`, etc.)
- **Services** are singletons for cross-feature concerns (`ConversationStore`, `ModelManager`, `KeychainService`, `DeviceInfoService`)

### Navigation Structure
5-tab `TabView` in `ContentView.swift`:

| Tab | View | Purpose |
|-----|------|---------|
| 0 | `ChatInterfaceView` | LLM chat with tool calling, LoRA, analytics |
| 1 | `VisionHubView` | VLM camera + Image generation (Diffusion) |
| 2 | `VoiceAssistantView` | Full voice agent (STT + LLM + TTS pipeline) |
| 3 | `MoreHubView` | RAG, STT, TTS, VAD, Storage, Solutions, Voice Keyboard |
| 4 | `CombinedSettingsView` | Generation params, API keys, tools, storage |

### Dependency Injection
Three layers:
1. **Environment objects** from `RunAnywhereAIApp`: `ModelManager`, `FlowSessionManager`
2. **Singleton services**: `ConversationStore.shared`, `SettingsViewModel.shared`, `ModelListViewModel.shared`, `KeychainService.shared`
3. **SDK static API**: all AI calls go through the `RunAnywhere.*` namespace

### SDK Initialization Gate
The entire UI is blocked behind `isSDKInitialized` in `RunAnywhereAIApp.swift`. The boot sequence:
1. **Backend registration (synchronous, before any `await`)**: `LlamaCPP.register(priority:100)`, `ONNX.register(priority:100)`, `WhisperKitSTT.register(priority:200)`
2. `RunAnywhere.initialize()` — core C++ bridge init
3. `registerModulesAndModels()` — registers ~30 models (LLMs, VLMs, STT, TTS, VAD, embeddings, diffusion, LoRA)
4. `RunAnywhere.flushPendingRegistrations()` + `RunAnywhere.discoverDownloadedModels()`

Backends MUST be registered before any `await` to prevent a race where `loadModel()` fires with an empty provider registry.

### Cross-Platform Strategy
The app targets iOS 17+ and macOS 14+. Platform differences are handled via:
- `#if os(iOS)` / `#if os(macOS)` conditional compilation
- `AdaptiveLayout.swift` — `DeviceFormFactor` detection + `AdaptiveSizing` constants for phone/tablet/desktop
- `ViewCompatibility.swift` — shims like `navigationBarTitleDisplayModeCompat`
- `AppColors` — `UIColor`/`NSColor` bridging for dynamic colors

---

## Project Structure

```
RunAnywhereAI/
├── App/
│   ├── RunAnywhereAIApp.swift          # @main entry, SDK init, model registration
│   └── ContentView.swift               # 5-tab navigation shell
├── Core/
│   ├── DesignSystem/
│   │   ├── AppColors.swift             # Brand colors (primary: #FF5500)
│   │   ├── AppSpacing.swift            # Layout constants + AppLayout namespace
│   │   ├── Typography.swift            # Font constants (AppTypography)
│   │   └── ViewCompatibility.swift     # Cross-platform nav shims
│   ├── Models/
│   │   ├── AppTypes.swift              # SystemDeviceInfo, Int64.formattedFileSize
│   │   └── MarkdownDetector.swift      # Rendering strategy detection (plain/light/basic/rich)
│   └── Services/
│       ├── ConversationStore.swift     # Conversation persistence (JSON files in Documents/)
│       ├── DeviceInfoService.swift     # Hardware info (chip, memory, Neural Engine)
│       ├── KeychainService.swift       # Keychain wrapper for API credentials
│       └── ModelManager.swift          # Thin ObservableObject facade over SDK model APIs
├── Features/
│   ├── Chat/                           # LLM chat interface (7 ViewModel files + 4 model files + 5 view files)
│   ├── Voice/                          # STT, TTS, VAD, VoiceAgent (11 files)
│   ├── VoiceKeyboard/                  # Dictation keyboard flow (5 files)
│   ├── Vision/                         # VLM camera (2 files)
│   ├── Diffusion/                      # Image generation (2 files)
│   ├── RAG/                            # Document Q&A (3 files)
│   ├── Benchmarks/                     # Performance testing (11 files)
│   ├── Models/                         # Model browser/downloader (7 files)
│   ├── Storage/                        # Disk usage management (2 files)
│   ├── Settings/                       # App configuration (3 files)
│   └── Solutions/                      # YAML pipeline demo (1 file)
├── Shared/
│   ├── SharedConstants.swift           # IPC keys, Darwin notification names, URL scheme
│   └── SharedDataBridge.swift          # App Group UserDefaults + Darwin CFNotificationCenter
├── Extensions/
│   ├── ModelInfo+Logo.swift            # SDK ModelInfo → asset name mapping
│   └── String+Markdown.swift           # Markdown stripping, model name formatting
├── Utilities/
│   └── ModelLogoHelper.swift           # String-based logo lookup (non-ModelInfo contexts)
└── Helpers/
    ├── SmartMarkdownRenderer.swift     # Entry point: routes to plain/inline/rich renderer
    ├── InlineMarkdownRenderer.swift    # AttributedString-based inline markdown
    ├── CodeBlockMarkdownRenderer.swift # Code fence extraction + syntax-colored blocks
    └── AdaptiveLayout.swift            # Phone/tablet/desktop sizing + reusable components

RunAnywhereKeyboard/                    # Custom keyboard extension
├── KeyboardViewController.swift        # UIInputViewController, IPC via Darwin notifications
├── KeyboardView.swift                  # Full SwiftUI keyboard UI with waveform animation
├── Info.plist                          # RequestsOpenAccess: true
└── RunAnywhereKeyboard.entitlements    # App Group: group.com.runanywhere.runanywhereai

RunAnywhereActivityExtension/           # Live Activity widget extension
├── RunAnywhereActivityExtensionBundle.swift  # @main WidgetBundle
├── RunAnywhereActivityExtensionLiveActivity.swift  # Dynamic Island + Lock Screen
└── Info.plist
```

---

## Feature Details

### 1. Chat / LLM (`Features/Chat/`)

The primary feature. `LLMViewModel` is split across 7 files via extensions:

| File | Responsibility |
|------|---------------|
| `LLMViewModel.swift` | Core state, `sendMessage()`, ChatML prompt builder, LoRA management |
| `LLMViewModel+Generation.swift` | Streaming (`RunAnywhere.generateStream`) and non-streaming (`RunAnywhere.generate`) paths |
| `LLMViewModel+ToolCalling.swift` | `RunAnywhere.generateWithTools`, format detection (default vs LFM2) |
| `LLMViewModel+ModelManagement.swift` | `RunAnywhere.loadModel`, model status checks |
| `LLMViewModel+Analytics.swift` | `MessageAnalytics` creation, `ConversationAnalytics` aggregation |
| `LLMViewModel+Events.swift` | Combine subscription to `RunAnywhere.events.events` for model lifecycle |
| `LLMViewModelTypes.swift` | `LLMError`, `GenerationMetricsFromSDK`, `DownloadProgressDelegate` |

**Data flow**: User input → `sendMessage()` → `prepareMessagesForSending()` (creates user + empty assistant messages) → `executeGeneration()` → `performGeneration()` → routes to streaming/non-streaming/tool-calling path → SDK call → token-by-token message update → `finalizeGeneration()` → persist to `ConversationStore`

**Tool calling**: Activated via `ToolSettingsViewModel.shared.toolCallingEnabled`. Three demo tools registered in `ToolSettingsView.swift`: `get_weather` (Open-Meteo API), `get_current_time`, `calculate` (recursive-descent `SafeMathEvaluator`). Format auto-detected per model name.

**LoRA adapters**: 5 catalog entries registered at startup via `LoRAAdapterCatalog.registerAll()`. Downloaded via `URLSession` to `~/Documents/LoRA/`, validated by GGUF magic bytes (`0x47475546`). Loaded via `RunAnywhere.lora.load(config)` with user-adjustable scale (0.0–2.0).

**Conversation persistence**: `ConversationStore` saves per-conversation JSON to `Documents/Conversations/`. Smart titles generated via Apple `FoundationModels` framework (iOS 26+). Search across title and message content.

**Analytics**: Per-message (`MessageAnalytics`) and per-conversation (`ConversationAnalytics`) tracking. Metrics include TTFT, tokens/sec, token counts, thinking mode usage, completion rate. Displayed in `ChatDetailsView` (3-tab sheet).

**Thinking mode**: Models with `supportsThinking: true` emit `<think>...</think>` tags. When thinking mode is disabled by the user, `/no_think\n` is prepended to prompts. Thinking content is extracted via `ThinkingContentParser` and shown in a collapsible section.

### 2. Voice Agent (`Features/Voice/VoiceAssistantView.swift`, `VoiceAgentViewModel.swift`)

Full STT → LLM → TTS pipeline orchestrated by the SDK.

**Setup**: User loads 3 models independently (STT, LLM, TTS) via `ModelSelectionSheet`.

**Pipeline**: `startConversation()` → `RunAnywhere.initializeVoiceAgentWithLoadedModels()` → `RunAnywhere.streamVoiceAgent()` returns `AsyncStream<RAVoiceEvent>`. Events include `.state`, `.vad`, `.userSaid`, `.assistantToken`, `.audio`, `.error`. The SDK owns the full audio pipeline internally.

**Particle animation**: Metal-rendered 2000-particle system (`VoiceAssistantParticleView.swift`). Fibonacci-lattice sphere morphs to ring during listening/speaking. Amplitude driven by real microphone level (listening) or simulated sine wave (speaking). Touch scatter with 0.92 decay.

**Types**: `VoiceSessionState` enum (`.disconnected/.connecting/.connected/.listening/.processing/.speaking/.error`), `SelectedModelInfo`, `ModelLoadState`.

### 3. Speech-to-Text (`Features/Voice/STTViewModel.swift`)

Two modes:
- **Batch**: Record audio → `RunAnywhere.transcribe(audioBuffer)` → full transcription
- **Live**: VAD-based polling at 50ms intervals; silence threshold 0.02 for 1.5s triggers `RunAnywhere.transcribe()` on accumulated buffer, then clears and continues

Audio captured via `AudioCaptureManager`. SDK events monitored for model load/unload state.

### 4. Text-to-Speech (`Features/Voice/TTSViewModel.swift`)

`RunAnywhere.speak(text, options: TTSOptions(rate:pitch:))` — SDK handles both synthesis and playback internally. Returns `TTSSpeakResult` with duration, format, audio size. `RunAnywhere.stopSpeaking()` for interruption.

### 5. Voice Activity Detection (`Features/Voice/VADViewModel.swift`)

Detection loop runs every 30ms. Buffers 1024 bytes (512 Int16 samples = 32ms at 16kHz), converts to `[Float]`, calls `RunAnywhere.detectSpeech(in: samples)` → `Bool`. Activity log limited to 50 entries.

### 6. Voice Keyboard (`Features/VoiceKeyboard/`)

Cross-process dictation system using a WisprFlow-style architecture:

**IPC channels**:
- **App Group UserDefaults** (`group.com.runanywhere.runanywhereai`): shared state (sessionState, transcribedText, audioLevel, heartbeat)
- **Darwin CFNotificationCenter**: zero-latency cross-process signals (6 notification names in `SharedConstants.DarwinNotifications`)

**Flow**: Keyboard taps "Run" → opens `runanywhere://startFlow` deep link → main app activates session → loads STT model → starts audio capture → posts `sessionReady` → user returns to host app → keyboard sends `startListening` → main app buffers audio → keyboard sends `stopListening` → main app calls `RunAnywhere.transcribe()` → writes result to shared UserDefaults → posts `transcriptionReady` → keyboard reads and inserts via `textDocumentProxy.insertText()`

**Live Activity**: `DictationActivityAttributes` with `ContentState` (phase, elapsedSeconds, transcript, wordCount). Updates Dynamic Island compact/expanded + Lock Screen views.

**Heartbeat**: 1-second timestamp writes. Keyboard checks freshness (3s timeout) to detect main app crash.

### 7. Vision / VLM (`Features/Vision/`)

Real-time camera-based image description. `AVCaptureSession` with BGRA pixel format. Three modes:
- **Single capture**: `RunAnywhere.processImageStream(VLMImage(pixelBuffer:), prompt:, maxTokens: 200)` → token stream
- **Photo library**: Same pipeline from selected image
- **Auto-streaming**: Captures frame every 2.5s, shorter prompt (maxTokens: 100)

### 8. Diffusion / Image Generation (`Features/Diffusion/`)

Text-to-image via CoreML Stable Diffusion 1.5. `RunAnywhere.generateImage(prompt:options:)` with step-by-step progress callback. Resolution capped at 512px. Raw RGBA `Data` decoded to `CGImage` via `CGDataProvider`.

### 9. RAG — Document Q&A (`Features/RAG/`)

PDF/JSON document ingestion → on-device embedding + LLM pipeline.

**Flow**: Select embedding + LLM models → import document → `DocumentService.extractText(from:)` → `RunAnywhere.ragCreatePipeline(config:)` → `RunAnywhere.ragIngest(text:)` → user asks question → `RunAnywhere.ragQuery(question:)` → thinking content parsed via `ThinkingContentParser`

Path resolution handles multi-file embedding models (e.g., `all-minilm-l6-v2` with `model.onnx` + `vocab.txt`).

### 10. Benchmarks (`Features/Benchmarks/`)

Deterministic performance testing across 5 modalities (LLM, STT, TTS, VLM, Diffusion). Each has a `BenchmarkScenarioProvider`. `BenchmarkRunner` orchestrates with cooperative cancellation. Results persisted as JSON (max 50 runs). Exportable as Markdown, JSON, or CSV.

**Synthetic inputs**: `SyntheticInputGenerator` creates silent/sine-wave audio, solid/gradient images.

**LLM scenarios**: 50/256/512 token runs with TTFT and decode speed measurement.

### 11. Models Management (`Features/Models/`)

`ModelListViewModel` (singleton) is the canonical model registry. Subscribes to `RunAnywhere.events.events` for real-time load/unload state. `ModelSelectionSheet` is the universal model picker parameterized by `ModelSelectionContext` enum (`.llm`, `.stt`, `.tts`, `.vad`, `.vlm`, `.ragEmbedding`, `.ragLLM`). Custom model registration via URL in `AddModelFromURLView`.

### 12. Storage (`Features/Storage/`)

`RunAnywhere.getStorageInfo()` → disk usage display. Per-model deletion via `RunAnywhere.deleteStoredModel()`. Cache/temp clearing via `RunAnywhere.clearCache()` / `RunAnywhere.cleanTempFiles()`.

### 13. Settings (`Features/Settings/`)

`SettingsViewModel` (singleton): temperature, maxTokens, systemPrompt (UserDefaults), API key/baseURL (Keychain), thinking mode toggle. Auto-saves via Combine `debounce(0.5s)`.

`ToolSettingsViewModel`: registers/clears demo tools via `RunAnywhere.registerTool(definition:executor:)`. Includes `SafeMathEvaluator` (recursive-descent parser) for the `calculate` tool.

### 14. Solutions (`Features/Solutions/`)

Minimal demo of `RunAnywhere.solutions.run(yaml:)` — the SDK's declarative pipeline API. Two hardcoded YAML strings (voice agent, RAG) submitted to SDK, lifecycle callbacks logged.

---

## Markdown Rendering Pipeline

Three-layer delegation chain for AI response text:

1. **Detection** (`MarkdownDetector.swift`): Analyzes content for code blocks, headings, bold, inline code, lists. Weighted score selects strategy: `.plain` / `.light` / `.basic` / `.rich`
2. **Routing** (`SmartMarkdownRenderer.swift`): `AdaptiveMarkdownText` dispatches to `RichMarkdownText`, `MarkdownText`, or plain `Text`
3. **Rendering**:
   - `CodeBlockMarkdownRenderer.swift`: Extracts triple-backtick fenced blocks, renders with syntax-colored headers + copy button + monospaced scrollable body
   - `InlineMarkdownRenderer.swift`: `AttributedString(markdown:)` with bold → `.semibold`, italic → `.italic`, inline code → `.monospaced` + purple tint. List markers converted to Unicode bullets (`bullet/circle/triangle/dot` by indent level)

---

## SDK Public API Surface (as consumed by this app)

All calls go through the `RunAnywhere` enum namespace (no instances).

### Initialization
```swift
RunAnywhere.initialize(apiKey:baseURL:environment:)  // throws
RunAnywhere.registerModel(id:name:url:framework:memoryRequirement:supportsThinking:)
RunAnywhere.registerMultiFileModel(id:name:files:framework:modality:memoryRequirement:)
RunAnywhere.flushPendingRegistrations()
RunAnywhere.discoverDownloadedModels()
```

### Model Management
```swift
RunAnywhere.availableModels() -> [ModelInfo]
RunAnywhere.loadModel(modelId)          // LLM
RunAnywhere.loadSTTModel(modelId)
RunAnywhere.loadTTSModel(voiceId)
RunAnywhere.loadVADModel(modelId)
RunAnywhere.loadVLMModel(modelInfo)     // takes ModelInfo, not just ID
RunAnywhere.unloadModel()               // LLM
RunAnywhere.getCurrentModelId() -> String?
RunAnywhere.currentSTTModel / currentTTSVoiceId / currentVADModel
RunAnywhere.downloadModel(modelId) -> AsyncStream<DownloadProgress>
RunAnywhere.deleteStoredModel(id, framework:)
```

### LLM Generation
```swift
RunAnywhere.generate(prompt, options:) -> LLMGenerationResult
RunAnywhere.generateStream(prompt, options:) -> AsyncStream<RALLMStreamEvent>
RunAnywhere.generateWithTools(prompt, options:) -> LLMGenerationResult
RunAnywhere.cancelGeneration()
RunAnywhere.supportsLLMStreaming -> Bool
RunAnywhere.getRegisteredTools() -> [ToolDefinition]
RunAnywhere.registerTool(definition:executor:)
RunAnywhere.clearTools()
```

### STT / TTS / VAD
```swift
RunAnywhere.transcribe(audioData) -> String
RunAnywhere.speak(text, options: TTSOptions) -> TTSSpeakResult
RunAnywhere.stopSpeaking()
RunAnywhere.initializeVAD()
RunAnywhere.detectSpeech(in: [Float]) -> Bool
RunAnywhere.isVADReady -> Bool
```

### Voice Agent
```swift
RunAnywhere.initializeVoiceAgentWithLoadedModels()
RunAnywhere.streamVoiceAgent() -> AsyncStream<RAVoiceEvent>
RunAnywhere.getVoiceAgentComponentStates() -> ComponentStates
```

### VLM / Diffusion / RAG
```swift
RunAnywhere.processImageStream(VLMImage, prompt:, maxTokens:) -> stream result
RunAnywhere.generateImage(prompt:options:) -> image result with progress callback
RunAnywhere.ragCreatePipeline(config:) / ragIngest(text:) / ragQuery(question:)
```

### Events
```swift
RunAnywhere.events.events  // Combine Publisher<any SDKEvent, Never>
// Event types: llm_model_load_completed, llm_model_unloaded, stt_model_load_completed, etc.
// Properties: model_id, error_message, time_to_first_token_ms, tokens_per_second, etc.
```

### Storage / LoRA / Solutions
```swift
RunAnywhere.getStorageInfo() -> StorageInfo
RunAnywhere.clearCache() / cleanTempFiles()
RunAnywhere.lora.register(entry) / load(config) / remove(id) / clear() / getLoaded()
RunAnywhere.solutions.run(yaml:) -> handle
```

---

## Design System

All styling is centralized — no inline magic numbers or color literals in views:
- **Colors**: `AppColors` — brand primary `#FF5500`, semantic tokens for text/backgrounds/bubbles/badges/status
- **Spacing**: `AppSpacing` — xxSmall(2) to xxxLarge(40), icon sizes, button heights, corner radii, strokes
- **Typography**: `AppTypography` — system text styles + custom sizes + weighted/monospaced variants
- **Layout**: `AppLayout` — window sizes, content widths, animation durations
- **Adaptive**: `AdaptiveSizing` — phone/tablet/desktop scaling for all interactive elements

---

## Build Scripts

| Script | Purpose |
|--------|---------|
| `scripts/build_and_run_ios_sample.sh` | End-to-end build+deploy (simulator/device/mac) with optional SDK rebuild |
| `scripts/verify.sh` | CI gate: checks XCFrameworks exist, resolves packages, runs full xcodebuild |
| `scripts/smoke.sh` | Fast preflight: greps source for SDK API call patterns (no compilation) |
| `scripts/patch-framework-plist.sh` | Post-build: patches MinimumOSVersion in XCFramework plists for App Store |

---

## Key Configuration Files

| File | Purpose |
|------|---------|
| `Package.swift` | SPM deps: local path `../../..` → RunAnywhere + ONNX + LlamaCPP + WhisperKit |
| `Info.plist` | URL scheme `runanywhere`, background mode `audio`, Live Activities enabled |
| `RunAnywhereAI.entitlements` | macOS sandbox, camera, mic, network, app group |
| `RunAnywhereConfig-Debug.plist` | Dev API URL, debug logging, 30s timeout |
| `RunAnywhereConfig-Release.plist` | Prod API URL, warning-only logging, 15s timeout, crash reporting |
| `.swiftlint.yml` | Line length 120/150, function body 50/100, force_cast=error, TODOs require issue # |

---

## Environment Detection

```swift
#if DEBUG
// Development: RunAnywhere.initialize() with no API key (uses Supabase)
#else
// Production: requires stored API key + base URL from Settings
// fatalError if credentials missing
#endif
```

Debug/Release config plists provide `environment`, `api.baseURL`, `logging.minimumLogLevel`, etc.
