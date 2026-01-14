# RunAnywhere AI - iOS Example

<p align="center">
  <img src="../../../examples/logo.svg" alt="RunAnywhere Logo" width="120"/>
</p>

<p align="center">
  <a href="https://apps.apple.com/us/app/runanywhere/id6756506307">
    <img src="https://img.shields.io/badge/App%20Store-Download-0D96F6?style=for-the-badge&logo=apple&logoColor=white" alt="Download on the App Store" />
  </a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-iOS%2017.0%2B-000000?style=flat-square&logo=apple&logoColor=white" alt="iOS 17.0+" />
  <img src="https://img.shields.io/badge/Platform-macOS%2014.0%2B-000000?style=flat-square&logo=apple&logoColor=white" alt="macOS 14.0+" />
  <img src="https://img.shields.io/badge/Swift-5.9%2B-FA7343?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.9+" />
  <img src="https://img.shields.io/badge/SwiftUI-Modern%20UI-0D96F6?style=flat-square&logo=swift&logoColor=white" alt="SwiftUI" />
  <img src="https://img.shields.io/badge/License-Apache%202.0-blue?style=flat-square" alt="License" />
</p>

**A production-ready reference app demonstrating the [RunAnywhere Swift SDK](../../../sdk/runanywhere-swift/) capabilities for on-device AI.** This app showcases how to build privacy-first, offline-capable AI features with LLM chat, speech-to-text, text-to-speech, and a complete voice assistant pipeline—all running locally on your device.

---

## Try It Now

<p align="center">
  <a href="https://apps.apple.com/us/app/runanywhere/id6756506307">
    <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" height="60"/>
  </a>
</p>

Download the app from the App Store to try it out.

---

## Screenshots

<p align="center">
  <img src="docs/screenshots/chat-interface.png" alt="Chat Interface" width="220"/>
  <img src="docs/screenshots/quiz-flow.png" alt="Structured Output" width="220"/>
  <img src="docs/screenshots/voice-ai.png" alt="Voice AI" width="220"/>
</p>

---

## Features

This sample app demonstrates the full power of the RunAnywhere SDK:

| Feature | Description | SDK Integration |
|---------|-------------|-----------------|
| **AI Chat** | Interactive LLM conversations with streaming responses | `RunAnywhere.generateStream()` |
| **Thinking Mode** | Support for models with `<think>...</think>` reasoning | Thinking tag parsing |
| **Real-time Analytics** | Token speed, generation time, inference metrics | `MessageAnalytics` |
| **Speech-to-Text** | Voice transcription with batch & live modes | `RunAnywhere.transcribe()` |
| **Text-to-Speech** | Neural voice synthesis with Piper TTS | `RunAnywhere.synthesize()` |
| **Voice Assistant** | Full STT → LLM → TTS pipeline with auto-detection | Voice Pipeline API |
| **Model Management** | Download, load, and manage multiple AI models | `RunAnywhere.downloadModel()` |
| **Storage Management** | View storage usage and delete models | `RunAnywhere.storageInfo()` |
| **Offline Support** | All features work without internet | On-device inference |
| **Cross-Platform** | Runs on iOS, iPadOS, and macOS | Universal app |

---

## Architecture

The app follows modern Apple architecture patterns:

```
┌─────────────────────────────────────────────────────────────────┐
│                        SwiftUI Views                            │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────┐ │
│  │  Chat    │ │   STT    │ │   TTS    │ │  Voice   │ │Settings│ │
│  │  View    │ │   View   │ │   View   │ │  View    │ │  View  │ │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘ └───┬────┘ │
├───────┼────────────┼────────────┼────────────┼───────────┼──────┤
│       ▼            ▼            ▼            ▼           ▼      │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────┐ │
│  │   LLM    │ │   STT    │ │   TTS    │ │  Voice   │ │Settings│ │
│  │ViewModel │ │ViewModel │ │ViewModel │ │ ViewModel│ │ViewModel
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘ └───┬────┘ │
├───────┴────────────┴────────────┴────────────┴───────────┴──────┤
│                                                                  │
│                    RunAnywhere Swift SDK                         │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Core APIs (generate, transcribe, synthesize, pipeline)   │   │
│  │  EventBus (LLMEvent, STTEvent, TTSEvent, ModelEvent)      │   │
│  │  Model Management (download, load, unload, delete)        │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │                                   │
│           ┌──────────────────┴──────────────────┐               │
│           ▼                                      ▼               │
│  ┌─────────────────┐                  ┌─────────────────┐       │
│  │   LlamaCPP      │                  │   ONNX Runtime  │       │
│  │   (LLM/GGUF)    │                  │   (STT/TTS)     │       │
│  └─────────────────┘                  └─────────────────┘       │
└─────────────────────────────────────────────────────────────────┘
```

### Key Architecture Decisions

- **MVVM Pattern** — ViewModels manage UI state with `@Observable`, SwiftUI observes changes
- **Single Entry Point** — `RunAnywhereAIApp.swift` handles SDK initialization
- **Swift Concurrency** — All async operations use async/await with structured concurrency
- **Cross-Platform** — Conditional compilation supports iOS, iPadOS, and macOS
- **Design System** — Centralized colors, typography, and spacing via `AppColors`, `AppTypography`, `AppSpacing`

---

## Project Structure

```
RunAnywhereAI/
├── RunAnywhereAI/
│   ├── App/
│   │   ├── RunAnywhereAIApp.swift        # Entry point, SDK initialization
│   │   └── ContentView.swift             # Tab navigation, main UI structure
│   │
│   ├── Core/
│   │   ├── DesignSystem/
│   │   │   ├── AppColors.swift           # Color palette
│   │   │   ├── AppSpacing.swift          # Spacing constants
│   │   │   └── Typography.swift          # Font styles
│   │   ├── Models/
│   │   │   ├── AppTypes.swift            # Shared data models
│   │   │   └── MarkdownDetector.swift    # Markdown parsing utilities
│   │   └── Services/
│   │       └── ModelManager.swift        # Model lifecycle management
│   │
│   ├── Features/
│   │   ├── Chat/
│   │   │   ├── Models/
│   │   │   │   └── Message.swift         # Chat message model
│   │   │   ├── ViewModels/
│   │   │   │   ├── LLMViewModel.swift    # Chat logic, streaming
│   │   │   │   ├── LLMViewModel+Generation.swift
│   │   │   │   └── LLMViewModel+Analytics.swift
│   │   │   └── Views/
│   │   │       ├── ChatInterfaceView.swift   # Main chat UI
│   │   │       ├── MessageBubbleView.swift   # Message rendering
│   │   │       └── ConversationListView.swift
│   │   │
│   │   ├── Voice/
│   │   │   ├── SpeechToTextView.swift    # STT UI with waveform
│   │   │   ├── STTViewModel.swift        # Batch & live transcription
│   │   │   ├── TextToSpeechView.swift    # TTS UI with playback
│   │   │   ├── TTSViewModel.swift        # Synthesis & audio playback
│   │   │   ├── VoiceAssistantView.swift  # Full voice pipeline UI
│   │   │   └── VoiceAgentViewModel.swift # STT→LLM→TTS orchestration
│   │   │
│   │   ├── Models/
│   │   │   ├── ModelSelectionSheet.swift # Model picker UI
│   │   │   └── ModelListViewModel.swift  # Download & load logic
│   │   │
│   │   ├── Storage/
│   │   │   ├── StorageView.swift         # Storage management UI
│   │   │   └── StorageViewModel.swift    # Storage info, cache clearing
│   │   │
│   │   └── Settings/
│   │       └── CombinedSettingsView.swift # Settings & storage UI
│   │
│   ├── Helpers/
│   │   ├── AdaptiveLayout.swift          # Cross-platform layout helpers
│   │   ├── CodeBlockMarkdownRenderer.swift
│   │   ├── InlineMarkdownRenderer.swift
│   │   └── SmartMarkdownRenderer.swift
│   │
│   └── Resources/
│       ├── Assets.xcassets/              # App icons, images
│       ├── RunAnywhereConfig-Debug.plist
│       └── RunAnywhereConfig-Release.plist
│
├── RunAnywhereAITests/                   # Unit tests
├── RunAnywhereAIUITests/                 # UI tests
├── docs/screenshots/                     # App screenshots
├── scripts/
│   └── build_and_run_ios_sample.sh       # Build automation
├── Package.swift                         # SPM dependency manifest
└── README.md                             # This file
```

---

## Quick Start

### Prerequisites

- **Xcode** 15.0 or later
- **iOS** 17.0+ / **macOS** 14.0+
- **Swift** 5.9+
- **Device/Simulator** with Apple Silicon (recommended: physical device for best performance)
- **~500MB-2GB** free storage for AI models

### Clone & Build

```bash
# Clone the repository
git clone https://github.com/RunanywhereAI/runanywhere-sdks.git
cd runanywhere-sdks/examples/ios/RunAnywhereAI

# Open in Xcode
open RunAnywhereAI.xcodeproj
```

### Run via Xcode

1. Open the project in Xcode
2. Wait for Swift Package Manager to resolve dependencies
3. Select a physical device (Apple Silicon recommended) or simulator
4. Click **Run** or press `⌘+R`

### Run via Command Line

```bash
# Build and run on simulator
./scripts/build_and_run_ios_sample.sh simulator "iPhone 16 Pro"

# Build and run on device
./scripts/build_and_run_ios_sample.sh device
```

---

## SDK Integration Examples

### Initialize the SDK

The SDK is initialized in `RunAnywhereAIApp.swift`:

```swift
import RunAnywhere
import LlamaCPPRuntime
import ONNXRuntime

@main
struct RunAnywhereAIApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .task {
            await initializeSDK()
        }
    }

    private func initializeSDK() async {
        // Initialize SDK (development mode - no API key needed)
        try RunAnywhere.initialize()

        // Register AI backends
        LlamaCPP.register(priority: 100)  // LLM backend (GGUF models)
        ONNX.register(priority: 100)      // STT/TTS backend

        // Register models
        RunAnywhere.registerModel(
            id: "smollm2-360m-q8_0",
            name: "SmolLM2 360M Q8_0",
            url: URL(string: "https://huggingface.co/...")!,
            framework: .llamaCpp,
            memoryRequirement: 500_000_000
        )
    }
}
```

### Download & Load a Model

```swift
// Download with progress tracking
for try await progress in RunAnywhere.downloadModel("smollm2-360m-q8_0") {
    print("Download: \(Int(progress.percentage * 100))%")
}

// Load into memory
try await RunAnywhere.loadModel("smollm2-360m-q8_0")
```

### Stream Text Generation

```swift
// Generate with streaming
let result = try await RunAnywhere.generateStream(
    prompt,
    options: LLMGenerationOptions(maxTokens: 512, temperature: 0.7)
)

for try await token in result.stream {
    // Display token in real-time
    displayToken(token)
}

// Get final analytics
let metrics = try await result.result.value
print("Speed: \(metrics.performanceMetrics.tokensPerSecond) tok/s")
```

### Speech-to-Text

```swift
// Load STT model
try await RunAnywhere.loadSTTModel("sherpa-onnx-whisper-tiny.en")

// Transcribe audio bytes
let transcription = try await RunAnywhere.transcribe(audioData)
print("Transcription: \(transcription.text)")
```

### Text-to-Speech

```swift
// Load TTS voice
try await RunAnywhere.loadTTSModel("vits-piper-en_US-lessac-medium")

// Synthesize speech
let result = try await RunAnywhere.synthesize(
    text,
    options: TTSOptions(rate: 1.0, pitch: 1.0)
)
// result.audioData contains WAV audio bytes
```

### Voice Pipeline (STT → LLM → TTS)

```swift
// Configure voice pipeline
let config = ModularPipelineConfig(
    components: [.vad, .stt, .llm, .tts],
    stt: VoiceSTTConfig(modelId: "sherpa-onnx-whisper-tiny.en"),
    llm: VoiceLLMConfig(modelId: "smollm2-360m-q8_0", maxTokens: 256),
    tts: VoiceTTSConfig(modelId: "vits-piper-en_US-lessac-medium")
)

// Process voice through full pipeline
let pipeline = try await RunAnywhere.createVoicePipeline(config: config)
for try await event in pipeline.process(audioStream: audioStream) {
    switch event {
    case .transcription(let text):
        print("User said: \(text)")
    case .llmResponse(let response):
        print("AI response: \(response)")
    case .synthesis(let audio):
        playAudio(audio)
    }
}
```

---

## Key Screens Explained

### 1. Chat Screen (`ChatInterfaceView.swift`)

**What it demonstrates:**
- Streaming text generation with real-time token display
- Thinking mode support (`<think>...</think>` tags)
- Message analytics (tokens/sec, time to first token)
- Conversation history management
- Model selection bottom sheet integration
- Markdown rendering with code highlighting

**Key SDK APIs:**
- `RunAnywhere.generateStream()` — Streaming generation
- `RunAnywhere.generate()` — Non-streaming generation
- `RunAnywhere.cancelGeneration()` — Stop generation

### 2. Speech-to-Text Screen (`SpeechToTextView.swift`)

**What it demonstrates:**
- Batch mode: Record full audio, then transcribe
- Live mode: Real-time streaming transcription
- Audio level visualization
- Transcription metrics

**Key SDK APIs:**
- `RunAnywhere.loadSTTModel()` — Load Whisper model
- `RunAnywhere.transcribe()` — Batch transcription

### 3. Text-to-Speech Screen (`TextToSpeechView.swift`)

**What it demonstrates:**
- Neural voice synthesis with Piper TTS
- Speed and pitch controls
- Audio playback with progress
- Fun sample texts for testing

**Key SDK APIs:**
- `RunAnywhere.loadTTSModel()` — Load TTS model
- `RunAnywhere.synthesize()` — Generate speech audio

### 4. Voice Assistant Screen (`VoiceAssistantView.swift`)

**What it demonstrates:**
- Complete voice AI pipeline
- Automatic speech detection
- Model status tracking for all 3 components (STT, LLM, TTS)
- Push-to-talk and hands-free modes

**Key SDK APIs:**
- Voice Pipeline API for STT → LLM → TTS orchestration
- Component state management

### 5. Settings Screen (`CombinedSettingsView.swift`)

**What it demonstrates:**
- Generation settings (temperature, max tokens)
- Storage usage overview
- Downloaded model management
- Model deletion with confirmation
- Cache clearing

**Key SDK APIs:**
- `RunAnywhere.storageInfo()` — Get storage details
- `RunAnywhere.deleteModel()` — Remove downloaded model

---

## Testing

### Run Unit Tests

```bash
xcodebuild test -project RunAnywhereAI.xcodeproj -scheme RunAnywhereAI -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

### Run UI Tests

```bash
xcodebuild test -project RunAnywhereAI.xcodeproj -scheme RunAnywhereAIUITests -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

---

## Debugging

### Enable Verbose Logging

The app uses `os.log` for structured logging. Filter by subsystem in Console.app:

```
subsystem:com.runanywhere.RunAnywhereAI
```

### Common Log Categories

| Category | Description |
|----------|-------------|
| `RunAnywhereAIApp` | SDK initialization, model registration |
| `LLMViewModel` | LLM generation, streaming |
| `STTViewModel` | Speech transcription |
| `TTSViewModel` | Speech synthesis |
| `VoiceAgentViewModel` | Voice pipeline |
| `ModelListViewModel` | Model downloads, loading |

### Memory Profiling

1. Open Xcode Instruments
2. Select your app process
3. Record memory allocations during model loading
4. Expected: ~300MB-4GB depending on model size

---

## Configuration

### Build Configurations

| Configuration | Description |
|---------------|-------------|
| `Debug` | Development build with verbose logging |
| `Release` | Optimized build for distribution |

### Environment Variables

```swift
#if DEBUG
// Development mode - uses local backend, no API key needed
try RunAnywhere.initialize()
#else
// Production mode - requires API key and backend URL
try RunAnywhere.initialize(
    apiKey: "your_api_key",
    baseURL: "https://api.runanywhere.ai",
    environment: .production
)
#endif
```

---

## Supported Models

### LLM Models (LlamaCpp/GGUF)

| Model | Size | Memory | Description |
|-------|------|--------|-------------|
| SmolLM2 360M Q8_0 | ~400MB | 500MB | Fast, lightweight chat |
| Qwen 2.5 0.5B Q6_K | ~500MB | 600MB | Multilingual, efficient |
| LFM2 350M Q4_K_M | ~200MB | 250MB | LiquidAI, ultra-compact |
| LFM2 350M Q8_0 | ~400MB | 400MB | LiquidAI, higher quality |
| Llama 2 7B Chat Q4_K_M | ~4GB | 4GB | Powerful, larger model |
| Mistral 7B Instruct Q4_K_M | ~4GB | 4GB | High quality responses |

### STT Models (ONNX/Whisper)

| Model | Size | Description |
|-------|------|-------------|
| Sherpa Whisper Tiny (EN) | ~75MB | English transcription |

### TTS Models (ONNX/Piper)

| Model | Size | Description |
|-------|------|-------------|
| Piper US English (Medium) | ~65MB | Natural American voice |
| Piper British English (Medium) | ~65MB | British accent |

---

## Known Limitations

- **Apple Silicon Recommended** — Best performance on M1/M2/M3 chips and A-series processors
- **Memory Usage** — Large models (7B+) require devices with 6GB+ RAM
- **First Load** — Initial model loading takes 1-3 seconds (cached afterward)
- **Thermal Throttling** — Extended inference may trigger device throttling on some devices

---

## Xcode 16 Notes

If you encounter sandbox errors during build:

```bash
./scripts/fix_pods_sandbox.sh
```

For Swift macro issues:

```bash
defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES
```

---

## Contributing

See [CONTRIBUTING.md](../../../CONTRIBUTING.md) for guidelines.

### Development Setup

```bash
# Fork and clone
git clone https://github.com/YOUR_USERNAME/runanywhere-sdks.git
cd runanywhere-sdks/examples/ios/RunAnywhereAI

# Open in Xcode
open RunAnywhereAI.xcodeproj

# Make changes and test
# Run tests in Xcode (⌘+U)

# Commit and push
git commit -m "feat: your feature description"
git push origin feature/your-feature

# Open Pull Request
```

---

## License

This project is licensed under the Apache License 2.0 - see [LICENSE](../../../LICENSE) for details.

---

## Support

- **Discord**: [Join our community](https://discord.gg/N359FBbDVd)
- **GitHub Issues**: [Report bugs](https://github.com/RunanywhereAI/runanywhere-sdks/issues)
- **Email**: san@runanywhere.ai
- **Twitter**: [@RunanywhereAI](https://twitter.com/RunanywhereAI)

---

## Related Documentation

- [RunAnywhere Swift SDK](../../../sdk/runanywhere-swift/README.md) — Full SDK documentation
- [Android Example App](../../android/RunAnywhereAI/README.md) — Android counterpart
- [React Native Example](../../react-native/RunAnywhereAI/README.md) — Cross-platform option
- [Main README](../../../README.md) — Project overview
