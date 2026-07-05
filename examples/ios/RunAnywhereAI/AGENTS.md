# AGENTS.md — iOS RunAnywhereAI Example App

This file documents the iOS example application for the RunAnywhere on-device AI SDK. It serves as a detailed reference for every module, feature, architecture pattern, data flow, and build/run instruction.

---

## How to Build & Run

### Quick Build & Run (Recommended)
```bash
cd examples/ios/RunAnywhereAI/

# Simulator (handles SDK + XCFramework dependencies automatically)
./scripts/build_and_run_ios_sample.sh simulator "iPhone 16 Pro" --build-sdk

# Physical device
./scripts/build_and_run_ios_sample.sh device

# macOS Catalyst / native
./scripts/build_and_run_ios_sample.sh mac
```

### Manual Setup
```bash
# Open via Xcode (SPM resolves dependencies automatically)
open RunAnywhereAI.xcodeproj

# Verify XCFrameworks exist locally
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

> **Layering contract (the #1 rule).** The SDK must be seamless here: every modality (LLM/STT/TTS/VAD/VLM/RAG/LoRA/Voice) is driven by **one** `RunAnywhere.*` entry point that does all the heavy lifting. This app holds **only** UI + thin SDK calls — no segmentation loops, no model/engine constants, no prompt post-processing, no multi-step bootstrap. If you need one of those, it's an SDK bug to fix down a layer (see root `AGENTS.md` → Business Logic Layering Rules).

### Pattern: MVVM with Swift Observation
- **Views** are pure SwiftUI with no business logic
- **ViewModels** are `@MainActor @Observable` (or `@MainActor ObservableObject`) classes owning all state and SDK calls
- **Models** are `Codable` value types (`Message`, `Conversation`, `MessageAnalytics`, `BenchmarkTypes`, etc.)
- **Services** are singletons for cross-feature concerns (`ConversationStore`, `KeychainService`, `DeviceInfoService`)

### Navigation Structure
5-tab `TabView` in `ContentView.swift`:

| Tab | View | Purpose |
|-----|------|---------|
| 0 | `ChatInterfaceView` | LLM chat with tool calling, LoRA, analytics |
| 1 | `VisionHubView` | VLM camera |
| 2 | `VoiceAssistantView` | Full voice agent (STT + LLM + TTS pipeline) |
| 3 | `MoreHubView` | RAG, STT, TTS, VAD, Storage, Voice Keyboard |
| 4 | `CombinedSettingsView` | Generation params, API keys, tools, storage |

> **Deferred backends.** MetalRT and Diffusion (image generation)
> are excluded from the v1 build (`RunAnywhereAIApp.swift:12`). Their
> products, registration calls, feature folders, and `generateImage` APIs are
> intentionally absent from the shipped sources.

### Dependency Injection
Three layers:
1. **Environment objects** from `RunAnywhereAIApp`: `FlowSessionManager`
2. **Singleton services**: `ConversationStore.shared`, `SettingsViewModel.shared`, `ModelListViewModel.shared`, `KeychainService.shared`
3. **SDK static API**: all AI calls go through the `RunAnywhere.*` namespace

### SDK Initialization Gate
The entire UI is blocked behind `isSDKInitialized` in `RunAnywhereAIApp.swift`. The boot sequence:
1. **Backend registration (synchronous, before any `await`)**: `LlamaCPP.register(priority:100)`, `ONNX.register(priority:100)`
2. `RunAnywhere.initialize()` — core C++ bridge init
3. `registerModulesAndModels()` — registers LLMs, VLMs, STT, TTS, VAD, embeddings, LoRA
4. `RunAnywhere.discoverDownloadedModels()` then `RunAnywhere.listModels()` (refresh registry)

Backends MUST be registered before any `await` to prevent a race where `loadModel()` fires with an empty provider registry.

### Cross-Platform Strategy
The app targets iOS 17.5+ and macOS 14.5+ (matches `Package.swift` platform floor). Platform differences are handled via:
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
│       └── KeychainService.swift       # Keychain wrapper for API credentials
├── Features/
│   ├── Chat/                           # LLM chat interface (7 ViewModel files + 4 model files + 5 view files)
│   ├── Voice/                          # STT, TTS, VAD, VoiceAgent (11 files)
│   ├── VoiceKeyboard/                  # Dictation keyboard flow (5 files)
│   ├── Vision/                         # VLM camera (2 files)
│   ├── RAG/                            # Document Q&A (3 files)
│   ├── Benchmarks/                     # Performance testing (11 files)
│   ├── Models/                         # Model browser/downloader (7 files)
│   ├── Storage/                        # Disk usage management (2 files)
│   ├── Settings/                       # App configuration (3 files)
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

**LoRA adapters**: 5 catalog entries registered at startup via `LoRAAdapterCatalog.registerAll()`. Downloaded via `URLSession` to `~/Documents/LoRA/`, validated by GGUF magic bytes (`0x47475546`). Applied via `RunAnywhere.lora.apply(RALoRAApplyRequest)` and removed via `RunAnywhere.lora.remove(RALoRARemoveRequest)` with user-adjustable scale (0.0-2.0).

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

### 8. RAG — Document Q&A (`Features/RAG/`)

PDF/JSON document ingestion → on-device embedding + LLM pipeline.

**Flow**: Select embedding + LLM models → import document → `DocumentService.extractText(from:)` → `RunAnywhere.ragCreatePipeline(config:)` → `RunAnywhere.ragIngest(text:)` → user asks question → `RunAnywhere.ragQuery(question:)` → thinking content parsed via `ThinkingContentParser`

Path resolution handles multi-file embedding models (e.g., `all-minilm-l6-v2` with `model.onnx` + `vocab.txt`).

### 9. Benchmarks (`Features/Benchmarks/`)

Deterministic performance testing across 4 modalities (LLM, STT, TTS, VLM). Each has a `BenchmarkScenarioProvider`. `BenchmarkRunner` orchestrates with cooperative cancellation. Results persisted as JSON (max 50 runs). Exportable as Markdown, JSON, or CSV.

**Synthetic inputs**: `SyntheticInputGenerator` creates silent/sine-wave audio, solid/gradient images.

**LLM scenarios**: 50/256/512 token runs with TTFT and decode speed measurement.

### 10. Models Management (`Features/Models/`)

`ModelListViewModel` (singleton) is the canonical model registry. Subscribes to `RunAnywhere.events.events` for real-time load/unload state. `ModelSelectionSheet` is the universal model picker parameterized by `ModelSelectionContext` enum (`.llm`, `.stt`, `.tts`, `.vad`, `.vlm`, `.ragEmbedding`, `.ragLLM`). Custom model registration via URL in `AddModelFromURLView`.

### 11. Storage (`Features/Storage/`)

`RunAnywhere.getStorageInfo()` → disk usage display. Per-model deletion via `RunAnywhere.deleteStoredModel()`. Cache/temp clearing via `RunAnywhere.clearCache()` / `RunAnywhere.cleanTempFiles()`.

### 12. Settings (`Features/Settings/`)

`SettingsViewModel` (singleton): temperature, maxTokens, systemPrompt (UserDefaults), API key/baseURL (Keychain), thinking mode toggle. Auto-saves via Combine `debounce(0.5s)`.

`ToolSettingsViewModel`: registers/clears demo tools via `RunAnywhere.registerTool(definition:executor:)`. Includes `SafeMathEvaluator` (recursive-descent parser) for the `calculate` tool.

---

## Markdown Rendering Pipeline

Three-layer delegation chain for AI response text:

1. **Detection** (`MarkdownDetector.swift`): Analyzes content for code blocks, headings, bold, inline code, lists. Weighted score selects strategy: `.plain` / `.light` / `.basic` / `.rich`
2. **Routing** (`SmartMarkdownRenderer.swift`): `AdaptiveMarkdownText` dispatches to `RichMarkdownText`, `MarkdownText`, or plain `Text`
3. **Rendering**:
   - `CodeBlockMarkdownRenderer.swift`: Extracts triple-backtick fenced blocks, renders with syntax-colored headers + copy button + monospaced scrollable body
   - `InlineMarkdownRenderer.swift`: `AttributedString(markdown:)` with bold → `.semibold`, italic → `.italic`, inline code → `.monospaced` + purple tint. List markers converted to Unicode bullets (`bullet/circle/triangle/dot` by indent level)

---

## SDK API Surface (as consumed by this app)

All calls go through the `RunAnywhere` enum namespace (no instances). The app
uses a mix of canonical proto-backed SDK APIs and **app-local convenience
shims** defined in `Extensions/RunAnywhere+ExampleShims.swift`. The shims
compose canonical proto requests (`RAModelLoadRequest`, `RALLMGenerateRequest`,
etc.) into ergonomic helpers; they are NOT part of the SDK public surface.

### Canonical SDK API (`sdk/runanywhere-swift`)

```swift
// Initialization
RunAnywhere.initialize(apiKey:baseURL:environment:)  // throws
RunAnywhere.discoverDownloadedModels()

// Model lifecycle (canonical proto-request entry points)
RunAnywhere.loadModel(_ request: RAModelLoadRequest) -> RAModelLoadResult
RunAnywhere.unloadModel(_ request: RAModelUnloadRequest) -> RAModelUnloadResult
RunAnywhere.currentModel(_ request: RACurrentModelRequest) -> RACurrentModelSnapshot
RunAnywhere.listModels() -> RAListModelsResult
RunAnywhere.queryModels(_:) / getModel(_:) / downloadedModels()
RunAnywhere.importModel(_ request: RAModelImportRequest)
RunAnywhere.downloadModel(_ model: RAModelInfo, onProgress:) async throws

// LLM
RunAnywhere.generate(_ request: RALLMGenerateRequest) -> RALLMGenerationResult
RunAnywhere.generateStream(_:) -> AsyncStream<RALLMStreamEvent>
RunAnywhere.generateWithTools(prompt:options:toolOptions:) -> RAToolCallingResult
RunAnywhere.cancelGeneration()
RunAnywhere.registerTool(_:executor:) / unregisterTool(_:) / getRegisteredTools() / clearTools()

// STT / TTS / VAD / VLM
RunAnywhere.transcribe(audio:options:) -> RATranscriptionResult
RunAnywhere.speak(text:options:) -> RATTSSpeakResult
RunAnywhere.detectVoiceActivity(_ audioData: Data) -> RAVADResult
RunAnywhere.processImage(_ image: RAVLMImage, options:) -> RAVLMResult
RunAnywhere.processImageStream(_ image: RAVLMImage, options:) -> AsyncStream<RAVLMStreamEvent>

// Voice agent
RunAnywhere.initializeVoiceAgent(_ config: RAVoiceAgentComposeConfig)
RunAnywhere.streamVoiceAgent() -> AsyncStream<RAVoiceEvent>
RunAnywhere.processVoiceTurn / cleanupVoiceAgent

// RAG / Storage / LoRA / Solutions
RunAnywhere.ragCreatePipeline(config:) / ragIngest(_:) / ragQuery(_:)
RunAnywhere.getStorageInfo() / clearCache() / cleanTempFiles() / planStorageDelete / deleteStorage
RunAnywhere.lora.{apply,remove,list,state,register,listCatalog,allRegistered,...}
RunAnywhere.solutions.run(yaml:) -> handle

// Events (canonical typed payloads)
RunAnywhere.events.events  // Combine Publisher<any SDKEvent, Never>
// Read typed payloads on RASDKEvent: event.model.kind/.modelID, event.generation.kind/.tokensUsed/...,
// event.capability, event.componentLifecycle, event.operationID. Do NOT read event.properties[String].
```

### App-Local Convenience Shims (`RunAnywhere+ExampleShims.swift`)

All previous shim wrappers (modality-specific load/unload helpers, current-model
accessors, prompt-form generation overloads, VAD ergonomics, VLM token-stream
flattening, voice-agent compose helpers, URL-form `registerModel`, etc.) have
been promoted into the canonical SDK public surface. The example app calls
those directly via `RunAnywhere.*`.

What remains in this file is strictly example-specific UI plumbing with no
cross-SDK parity story:

```swift
// Framework discovery via listModels() — composes the canonical
// RunAnywhere.listModels() proto API into the shape the Models tab and
// Add-from-URL flow want. Sorted by descending model count.
RunAnywhere.getRegisteredFrameworks() -> [RAInferenceFramework]
```

When deciding whether to add a new feature: if it requires net-new C bridge
code, it belongs in the SDK. If it is purely example-app UI plumbing composing
existing canonical proto APIs, it can live in `RunAnywhere+ExampleShims.swift`.

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
| `scripts/verify.sh` | Local gate: checks XCFrameworks exist, resolves packages, runs full xcodebuild |
| `scripts/smoke.sh` | Fast preflight: greps source for SDK API call patterns (no compilation) |
| `scripts/patch-framework-plist.sh` | Post-build: patches MinimumOSVersion in XCFramework plists for App Store |

---

## Key Configuration Files

| File | Purpose |
|------|---------|
| `Package.swift` | SPM deps: local path `../../..` → RunAnywhere + ONNX + LlamaCPP |
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
