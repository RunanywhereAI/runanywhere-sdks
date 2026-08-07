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
See `docs/RELEASE_INSTRUCTIONS.md` for the full App Store flow. The packaged
XCFrameworks already declare the canonical iOS 17.5 deployment floor; release
archives validate that metadata without post-build mutation.

#### Required Native Symbol Release Gate

Before uploading any iOS archive to TestFlight/App Store Connect, verify the
archive still exports every Swift-facing native ABI symbol. This protects
against Release stripping or stale XCFrameworks causing runtime startup errors
such as:

```text
Native proto ABI is not exported by the linked RACommons binary: rac_sdk_init_phase1_proto
```

Release archives must preserve the RunAnywhere native ABI export surface:

- `RunAnywhereExportedSymbols.txt` must contain `_rac_*` and `_ra_mlx_*`.
- The Release app target must link with `-all_load`.
- The Release app target must pass
  `-Wl,-exported_symbols_list,$(SRCROOT)/RunAnywhereExportedSymbols.txt`.
- The Release app target must use `STRIP_STYLE = non-global` so `dlsym` can
  still find the required symbols after archive post-processing.
- `RunAnywhereExportedSymbols.txt` must not be bundled into the app resources.

From `examples/ios/RunAnywhereAI/`, use this release flow:

```bash
# 1. Build the final release inputs.
xcodebuild \
  -project RunAnywhereAI.xcodeproj \
  -scheme RunAnywhereAI \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -skipPackagePluginValidation \
  -jobs "$(sysctl -n hw.logicalcpu)" \
  build

# 2. Archive directly into Xcode Organizer's archive folder.
ARCHIVE_DIR="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)"
ARCHIVE="$ARCHIVE_DIR/RunAnywhereAI-$(date +%Y%m%d-%H%M%S).xcarchive"
mkdir -p "$ARCHIVE_DIR"
xcodebuild \
  -project RunAnywhereAI.xcodeproj \
  -scheme RunAnywhereAI \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  -skipPackagePluginValidation \
  -jobs "$(sysctl -n hw.logicalcpu)" \
  archive

# 4. Open the archive in Xcode Organizer.
open -a Xcode "$ARCHIVE"
```

After archiving, run the native symbol audit against the archived app binary:

```bash
APP="$ARCHIVE/Products/Applications/RunAnywhereAI.app"
BIN="$APP/RunAnywhereAI"

nm -gjU "$BIN" 2>/dev/null \
  | rg '^_(rac|ra_mlx)_' \
  | sed 's/^_//' \
  | sort -u > /tmp/runanywhere_archive_exported_symbols.txt

SRC_DIRS=(
  ../../../sdk/runanywhere-swift/Sources/RunAnywhere
  ../../../sdk/runanywhere-swift/Sources/LlamaCPPRuntime
  ../../../sdk/runanywhere-swift/Sources/ONNXRuntime
  ../../../sdk/runanywhere-swift/Sources/MLXRuntime
)

rg -No '"(rac|ra_mlx)_[A-Za-z0-9_]+"' "${SRC_DIRS[@]}" --glob '*.swift' \
  | perl -ne 'while (/"((?:rac|ra_mlx)_[A-Za-z0-9_]+)"/g) { print "$1\n" }' \
  | sort -u > /tmp/runanywhere_expected_swift_native_symbols.from_strings

# Declared only inside a build-configuration guard this archive does not compile.
# The rg pass above is a plain text scan and does not evaluate `#if`, so without
# this filter the gate fails on every good archive over a symbol that is
# CORRECTLY absent. `ra_mlx_metal_resource_anchor` lives in MLXRuntime/MLX.swift
# under `#if RUNANYWHERE_MLX_DISTRIBUTION`, set only for the CocoaPods
# distribution build; a SwiftPM archive never compiles it.
# Extend this list ONLY for a symbol confirmed guarded out of this configuration.
PACKAGING_ONLY_SYMBOLS=(
  ra_mlx_metal_resource_anchor
)

{
  cat /tmp/runanywhere_expected_swift_native_symbols.from_strings
  printf '%s\n' \
    rac_proto_buffer_free \
    rac_backend_llamacpp_register \
    rac_backend_llamacpp_unregister \
    rac_backend_onnx_register \
    rac_backend_onnx_unregister \
    rac_plugin_entry_sherpa \
    rac_plugin_register \
    rac_plugin_unregister \
    rac_backend_mlx_register \
    rac_backend_mlx_unregister \
    rac_mlx_set_callbacks \
    ra_mlx_register_runtime \
    ra_mlx_runtime_is_available \
    ra_mlx_runtime_is_registered \
    ra_mlx_unregister_runtime
} | sort -u \
  | grep -vxF "$(printf '%s\n' "${PACKAGING_ONLY_SYMBOLS[@]}")" \
  > /tmp/runanywhere_expected_swift_native_symbols.txt

comm -23 \
  /tmp/runanywhere_expected_swift_native_symbols.txt \
  /tmp/runanywhere_archive_exported_symbols.txt \
  > /tmp/runanywhere_missing_swift_native_symbols.txt

test ! -s /tmp/runanywhere_missing_swift_native_symbols.txt
```

The final `test` command must pass. If it fails, inspect
`/tmp/runanywhere_missing_swift_native_symbols.txt`, rebuild the native
XCFrameworks, fix the Release linker/strip settings, and archive again before
uploading.

Also verify release configuration and secrets presence without printing secret
values:

```bash
test -f "$APP/RunAnywhereLocalSecrets.plist"
test -f "$APP/RunAnywhereConfig-Release.plist"
test ! -e "$APP/RunAnywhereExportedSymbols.txt"
```

Upload from Xcode Organizer via **Validate App** then **Distribute App > App
Store Connect > Upload**. If exporting from the command line, use the
repository's App Store Connect export options plist when present:

```bash
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "../../../build/archives/$(basename "$ARCHIVE" .xcarchive)-export" \
  -exportOptionsPlist "../../../build/archives/ExportOptions-app-store-connect.plist" \
  -allowProvisioningUpdates
```

#### Required macOS Release Gate

The shared `RunAnywhereAI` target also ships as a native Mac app. Before every
Mac App Store release:

- Increment `CURRENT_PROJECT_VERSION`; do not reuse an uploaded build number.
- Keep `MACOSX_DEPLOYMENT_TARGET = 14.5`, matching `Package.swift`.
- Build and archive the Release configuration for
  `generic/platform=macOS` with the host logical CPU count.
- Require App Sandbox, the RunAnywhere app group, camera, microphone, outbound
  network, and user-selected file entitlements.
- Require Hardened Runtime in the macOS Release build.
- Bundle `PrivacyInfo.xcprivacy`, `RunAnywhereLocalSecrets.plist`, and
  `RunAnywhereConfig-Release.plist` without printing credential values.
- Keep `RunAnywhereExportedSymbols.txt` out of the app resources and run the
  platform-filtered Swift-facing native ABI audit against
  `Contents/MacOS/RunAnywhereAI`. Every published Swift backend binary now
  carries a macOS arm64 slice.
- Verify `codesign`, `arm64`, the absence of quarantine metadata, and zero
  missing `_rac_*` / `_ra_mlx_*` symbols before opening Organizer.

Archive into Xcode Organizer's standard folder so it is visible immediately:

```bash
JOBS="$(sysctl -n hw.logicalcpu)"
ARCHIVE_DIR="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)"
ARCHIVE="$ARCHIVE_DIR/RunAnywhereAI macOS $(date +%Y-%m-%d\ %H.%M.%S).xcarchive"
mkdir -p "$ARCHIVE_DIR"

xcodebuild \
  -project RunAnywhereAI.xcodeproj \
  -scheme RunAnywhereAI \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  -skipPackagePluginValidation \
  -jobs "$JOBS" \
  archive

open -a Xcode "$ARCHIVE"
```

For App Store media, review one to ten screenshots in their final upload order.
Use `1320x2868` sRGB PNG/JPEG masters for the 6.9-inch iPhone family and
`2880x1800` sRGB PNG/JPEG masters for macOS. The real app UI must remain the
dominant content; branded framing and concise, factual feature copy are fine.
For the current voice-first iPhone set, use authenticated simulator captures
from llama.cpp LFM2 350M, Sherpa-ONNX Whisper Tiny, and Piper TTS. MLX may be
listed as a supported runtime, but do not present it as tested evidence unless
it was separately verified for that build. Until the llama.cpp XCFramework
gains a macOS slice, Mac copy should describe the shared model catalog instead
of claiming local llama.cpp execution.

The complete iOS and macOS flow, archive checks, screenshot paths, and upload
boundary are documented in `docs/RELEASE_INSTRUCTIONS.md`.

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

> **Deferred image generation.** Diffusion/image generation is excluded from the
> v1 build (`RunAnywhereAIApp.swift:12`). Its products, registration calls,
> feature folders, and `generateImage` APIs are intentionally absent from the
> shipped sources.

### Dependency Injection
Three layers:
1. **Environment objects** from `RunAnywhereAIApp`: `FlowSessionManager`
2. **Singleton services**: `ConversationStore.shared`, `SettingsViewModel.shared`, `ModelListViewModel.shared`, `KeychainService.shared`
3. **SDK static API**: all AI calls go through the `RunAnywhere.*` namespace

### SDK Initialization Gate
The entire UI is blocked behind `isSDKInitialized` in `RunAnywhereAIApp.swift`. The boot sequence:
1. **Backend registration (synchronous, before any `await`)**: `LlamaCPP.register(priority:100)`, Boolean-returning `MLX.register(priority:100)`, `ONNX.register(priority:100)`
2. `RunAnywhere.initialize(apiKey:baseUrl:environment:)` brings the SDK up; network work continues in the background
3. `ModelCatalogBootstrap.registerAll(mlxRegistered:)` — registers LLMs, VLMs, STT, TTS, VAD, embeddings, and LoRA while omitting every MLX row when registration failed
4. `RunAnywhere.models.refresh()` then `RunAnywhere.models.list()` (reconcile the registry with disk)

Backends MUST be registered before any `await` to prevent a race where a model load fires against an empty provider registry.
MLX execution requires a physical iOS device (or native macOS). The arm64 iOS
Simulator build is for package, compile, link, and startup validation only;
`MLX.register()` returns `false`, and the example does not seed MLX rows there.

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
│   │   ├── AppColors.swift             # Brand colors (primary: #FF6900)
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
| `LLMViewModel+Generation.swift` | Streaming (`RunAnywhere.llm.generateStream(messages:)`) and non-streaming (`RunAnywhere.llm.generate(messages:)`) paths |
| `LLMViewModel+ToolCalling.swift` | `RunAnywhere.llm.generate` with the tool registry active; the SDK runs the call/execute loop |
| `LLMViewModel+ModelManagement.swift` | `RunAnywhere.models.load(id:)`, model status checks |
| `LLMViewModel+Analytics.swift` | `MessageAnalytics` creation, `ConversationAnalytics` aggregation |
| `LLMViewModel+Events.swift` | Combine subscription to `RunAnywhere.eventBus` for model lifecycle |
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

**Pipeline**: `startConversation()` → `RunAnywhere.voice.createSession(stt:llm:tts:)` → `session.start()` opens the microphone → `session.events` yields `VoiceEvent`s (`userTranscribed`, `agentStateChanged`, `agentResponse`, `speechStarted`, `speechEnded`, `error`). The SDK owns the full audio pipeline internally, including the VAD it ensures for itself.

**Particle animation**: Metal-rendered 2000-particle system (`VoiceAssistantParticleView.swift`). Fibonacci-lattice sphere morphs to ring during listening/speaking. Amplitude driven by real microphone level (listening) or simulated sine wave (speaking). Touch scatter with 0.92 decay.

**Types**: `VoiceSessionState` enum (`.disconnected/.connecting/.connected/.listening/.processing/.speaking/.error`), `SelectedModelInfo`, `ModelLoadState`.

### 3. Speech-to-Text (`Features/Voice/STTViewModel.swift`)

Two modes:
- **Batch**: Record audio → `RunAnywhere.stt.transcribe(.pcm16(buffer, sampleRate: 16_000))` → full transcript
- **Live**: Mic chunks are yielded into `RunAnywhere.stt.transcribeStream(_:)`, which owns segmentation and emits `.partial` / `.final` events. No app-side silence detection.
- **Hybrid**: On-device first with cloud fallback through `HybridSTTRouter`.

Audio captured via `AudioCaptureManager`. SDK events monitored for model load/unload state.

### 4. Text-to-Speech (`Features/Voice/TTSViewModel.swift`)

`RunAnywhere.tts.speak(text, options: TtsOptions(speed:pitch:))` handles synthesis and playback inside the SDK and returns nothing. `RunAnywhere.tts.stop()` interrupts it. Use `tts.synthesize(_:)` when you want the `Audio` buffer instead of playback.

### 5. Voice Activity Detection (`Features/Voice/VADViewModel.swift`)

Mic chunks go straight into `RunAnywhere.vad.detectStream(_:)`, which emits `.speechStarted`, `.speechEnded`, and per-chunk `.frame(VadResult)`. Framing is the SDK's job, not the app's. Activity log limited to 50 entries.

### 6. Voice Keyboard (`Features/VoiceKeyboard/`)

Cross-process dictation system using a WisprFlow-style architecture:

**IPC channels**:
- **App Group UserDefaults** (`group.com.runanywhere.runanywhereai`): shared state (sessionState, transcribedText, audioLevel, heartbeat)
- **Darwin CFNotificationCenter**: zero-latency cross-process signals (6 notification names in `SharedConstants.DarwinNotifications`)

**Flow**: Keyboard taps "Run" → opens `runanywhere://startFlow` deep link → main app activates session → loads STT model → starts audio capture → posts `sessionReady` → user returns to host app → keyboard sends `startListening` → main app buffers audio → keyboard sends `stopListening` → main app calls `RunAnywhere.stt.transcribe(_:)` → writes result to shared UserDefaults → posts `transcriptionReady` → keyboard reads and inserts via `textDocumentProxy.insertText()`

**Live Activity**: `DictationActivityAttributes` with `ContentState` (phase, elapsedSeconds, transcript, wordCount). Updates Dynamic Island compact/expanded + Lock Screen views.

**Heartbeat**: 1-second timestamp writes. Keyboard checks freshness (3s timeout) to detect main app crash.

### 7. Vision / VLM (`Features/Vision/`)

Real-time camera-based image description. `AVCaptureSession` with BGRA pixel format. Three modes:
- **Single capture**: `RunAnywhere.vlm.generateStream(image: .pixelBuffer(frame), prompt:, options:)` → token stream
- **Photo library**: Same pipeline from selected image
- **Auto-streaming**: Captures frame every 2.5s, shorter prompt (maxTokens: 100)

### 8. RAG — Document Q&A (`Features/RAG/`)

PDF/JSON document ingestion → on-device embedding + LLM pipeline.

**Flow**: Select embedding + LLM models → import document → `DocumentService.extractText(from:)` → `RunAnywhere.rag.open(embeddingModel:llmModel:)` → `session.ingest(document: RagDocument(text:metadata:))` → user asks question → `session.query(question:options:)` → thinking content parsed via `ThinkingContentParser`. The session stays open across turns for the same document and model pair.

Path resolution handles multi-file embedding models (e.g., `all-minilm-l6-v2` with `model.onnx` + `vocab.txt`).

### 9. Benchmarks (`Features/Benchmarks/`)

Deterministic performance testing across 4 modalities (LLM, STT, TTS, VLM). Each has a `BenchmarkScenarioProvider`. `BenchmarkRunner` orchestrates with cooperative cancellation. Results persisted as JSON (max 50 runs). Exportable as Markdown, JSON, or CSV.

**Synthetic inputs**: `SyntheticInputGenerator` creates silent/sine-wave audio, solid/gradient images.

**LLM scenarios**: 50/256/512 token runs with TTFT and decode speed measurement.

### 10. Models Management (`Features/Models/`)

`ModelListViewModel` (singleton) is the canonical model registry. Subscribes to `RunAnywhere.eventBus.modelLifecycle` for real-time load/unload state. `ModelSelectionSheet` is the universal model picker parameterized by `ModelSelectionContext` enum (`.llm`, `.stt`, `.tts`, `.vad`, `.vlm`, `.ragEmbedding`, `.ragLLM`). Custom model registration via URL in `AddModelFromURLView`.

### 11. Storage (`Features/Storage/`)

`RunAnywhere.models.state()` supplies the used and free byte counts, and
`RunAnywhere.models.list(filter: ModelFilter(downloadedOnly: true))` supplies the
rows, filtered to entries with a real on-disk size so Apple system pseudo-models
drop out. Each row reads its own `ModelInfo` for name, local path, framework, and
`lastUsedAtUnixMs`. Per-model deletion is `RunAnywhere.models.delete(id:)`;
cache and temp clearing are `RunAnywhere.clearCache()` and
`RunAnywhere.cleanTempFiles()`.

### 12. Settings (`Features/Settings/`)

`SettingsViewModel` (singleton): temperature, maxTokens, systemPrompt (UserDefaults), API key/baseURL (Keychain), thinking mode toggle. Auto-saves via Combine `debounce(0.5s)`.

`ToolSettingsViewModel`: registers and clears demo tools via `RunAnywhere.llm.tools`. Includes `SafeMathEvaluator` (recursive-descent parser) for the `calculate` tool.

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

Every call goes through the `RunAnywhere` enum (never instantiated) and follows
the cross-SDK v3 contract in `thoughts/shared/plans/public_api_spec.md`. One
namespace per modality; the SDK owns model resolution, loading, downloading, and
orchestration behind each verb.

```swift
// Core
try RunAnywhere.initialize(apiKey:baseUrl:environment:)   // one call, both phases
RunAnywhere.isReady / .version / .deviceId
RunAnywhere.events            // AsyncStream<SdkEvent>
RunAnywhere.eventBus          // Combine publisher over raw RASDKEvent protos

// Models
RunAnywhere.models.list(filter:) / .get(id:) / .register(_:) / .download(id:)
RunAnywhere.models.load(id:options:) / .unload(category:) / .delete(id:) / .state()

// Generation
RunAnywhere.llm.generate(prompt:options:) / .generate(messages:options:)
RunAnywhere.llm.generateStream(...) / .generateStructured(prompt:schema:options:)
RunAnywhere.llm.tools.register(_:executor:) / .unregister(name:) / .list() / .clear()
RunAnywhere.vlm.generate(image:prompt:options:) / .generateStream(...)

// Audio and vision
RunAnywhere.stt.transcribe(_:options:) / .transcribeStream(_:options:) / .state()
RunAnywhere.tts.synthesize(_:options:) / .speak(_:options:) / .stop() / .voices()
RunAnywhere.vad.detect(_:options:) / .detectStream(_:options:)
RunAnywhere.diarization.diarize(_:options:)
RunAnywhere.segmentation.segment(_:options:)

// Sessions
let voice = try await RunAnywhere.voice.createSession(stt:llm:tts:)
try voice.start()             // the only thing that opens the microphone
let rag = try await RunAnywhere.rag.open(embeddingModel:llmModel:config:)

// LoRA, embeddings, rerank, storage
RunAnywhere.lora.apply(adapterId:scale:) / .remove(adapterId:) / .list()
RunAnywhere.embeddings.embed(_:options:)
RunAnywhere.rerank.rerank(query:documents:topN:)
RunAnywhere.clearCache() / .cleanTempFiles() / .deleteStorage(_:)
```

Inputs are `AudioInput` (`.pcm16`, `.float32`, `.wav`, `.file`) and `ImageInput`
(`.file`, `.bytes`, `.rawRgb`, `.uiImage`, `.cgImage`, `.pixelBuffer`). Pixel
conversion, including camera frames, belongs to the SDK: hand `ImageInput` a
`CVPixelBuffer` and do not bridge through `CIContext` in the app.

Options are `LlmOptions`, `SttOptions`, `TtsOptions`, `VadOptions`,
`EmbedOptions`, `ImageOptions`, `DiarizationOptions`, `SegmentationOptions`,
`LoadOptions`, and `RagConfig`. Every field is optional and every default comes
from the IDL.

One-shot verbs throw `SDKException`. Stream factories are
`async throws -> AsyncThrowingStream`, so they throw on preflight failure and
throw into the consumer mid-flight. No result carries a `success` flag, and no
error text hides in a payload field. Cancel a request by cancelling the Task
consuming it; there are no cancel verbs.

The older flat verbs (`loadModel`, `transcribe`, `ragQuery`, and friends) still
exist as deprecated forwarders in the SDK for one release. Do not use them here.

### App-Local Convenience Shims (`RunAnywhere+ExampleShims.swift`)

One helper remains, and it is UI plumbing with no cross-SDK parity story:

```swift
// Framework filter list for the Models tab and Add-from-URL flow, composed
// from RunAnywhere.models.list() and sorted by descending model count.
RunAnywhere.getRegisteredFrameworks() -> [RAInferenceFramework]
```

When deciding whether to add a new feature: if it requires net-new C bridge
code, it belongs in the SDK. If it is purely example-app UI plumbing composing
existing canonical proto APIs, it can live in `RunAnywhere+ExampleShims.swift`.

---

## Design System

All styling is centralized — no inline magic numbers or color literals in views:
- **Colors**: `AppColors` — brand primary `#FF6900` (the RunAnywhere logo orange), semantic tokens for text/backgrounds/bubbles/badges/status. Canonical palette: `../../DESIGN_GUIDELINE.md`.
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
