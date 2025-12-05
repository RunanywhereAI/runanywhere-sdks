# RunAnywhereAI iOS Sample App

A comprehensive iOS/macOS sample application demonstrating the RunAnywhere SDK for on-device AI capabilities.

## Overview

RunAnywhereAI showcases intelligent routing between on-device and cloud AI models, featuring text generation, voice AI workflows, model management, and structured output generation.

**Platform:** iOS 17.0+ / macOS 14.0+
**Architecture:** MVVM with SwiftUI
**Language:** Swift 6

---

## Features at a Glance

| Feature | Description | Frameworks Used |
|---------|-------------|-----------------|
| **Chat** | Streaming LLM text generation with analytics | LlamaCPP, Foundation Models |
| **Speech-to-Text** | Real-time audio transcription | WhisperKit, ONNX (Sherpa) |
| **Text-to-Speech** | Voice synthesis from text | ONNX (Piper TTS) |
| **Voice Assistant** | End-to-end voice AI pipeline | STT + LLM + TTS combined |
| **Quiz Generation** | Structured JSON output | LlamaCPP with schemas |
| **Model Management** | Download, load, and manage AI models | All frameworks |

---

## App Structure

### Navigation (5 Tabs)

```
┌─────────────────────────────────────────────────────────┐
│  Chat  │  STT  │  TTS  │  Voice  │  Settings           │
└─────────────────────────────────────────────────────────┘
```

1. **Chat** - Interactive LLM conversation with streaming
2. **Speech-to-Text** - Real-time transcription
3. **Text-to-Speech** - Voice synthesis
4. **Voice Assistant** - Complete voice AI pipeline
5. **Settings** - Configuration and storage management

---

## Feature Details

### 1. Chat Interface

**Files:** `Features/Chat/ChatInterfaceView.swift`, `ChatViewModel.swift`

**Capabilities:**
- Real-time streaming text generation
- Comprehensive analytics tracking:
  - Time-to-first-token (TTFT)
  - Tokens per second throughput
  - Thinking time (for reasoning models)
  - Token counts (input/output/thinking)
- Conversation persistence and history
- Markdown rendering with code syntax highlighting
- Generation interruption support
- Multi-conversation management

### 2. Speech-to-Text

**Files:** `Features/Voice/SpeechToTextView.swift`, `TranscriptionViewModel.swift`

**Capabilities:**
- Live microphone input capture
- Real-time transcription display
- Audio level visualization
- Model framework selection (WhisperKit, ONNX)
- Partial and final transcript support
- Speaker diarization via FluidAudio

### 3. Text-to-Speech

**Files:** `Features/Voice/TextToSpeechView.swift`

**Capabilities:**
- Text input for synthesis
- Multiple voice selection (Piper voices)
- Multi-language support
- Real-time audio playback

### 4. Voice Assistant

**Files:** `Features/Voice/VoiceAssistantView.swift`, `VoiceAssistantViewModel.swift`

**Capabilities:**
- Complete STT → LLM → TTS pipeline
- Independent model selection per component
- Session state management (listening, processing, speaking)
- Real-time audio level feedback
- Model status synchronization

### 5. Quiz Generation

**Files:** `Features/Quiz/QuizView.swift`, `QuizViewModel.swift`

**Capabilities:**
- Generate quiz questions from content
- JSON schema-based structured output
- Difficulty levels (easy, medium, hard)
- Card-based swipe answering interface
- Results tracking and display

### 6. Settings & Storage

**Files:** `Features/Settings/CombinedSettingsView.swift`, `StorageViewModel.swift`

**Capabilities:**
- SDK configuration (routing policy, API keys)
- Generation settings (temperature, max tokens)
- Storage usage breakdown by model
- Cache and temporary file cleanup
- Individual model deletion

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     SwiftUI Views                        │
│  (ChatInterfaceView, VoiceAssistantView, QuizView, ...) │
└────────────────────────┬────────────────────────────────┘
                         │
┌────────────────────────┴────────────────────────────────┐
│                    ViewModels (MVVM)                     │
│  (ChatViewModel, VoiceAssistantViewModel, QuizVM, ...)  │
│                  @Published + Combine                    │
└────────────────────────┬────────────────────────────────┘
                         │
┌────────────────────────┴────────────────────────────────┐
│                   Core Services                          │
│  ModelManager │ ConversationStore │ DeviceInfoService   │
└────────────────────────┬────────────────────────────────┘
                         │
┌────────────────────────┴────────────────────────────────┐
│                  RunAnywhere SDK                         │
│  ┌──────────┬──────────┬──────────┬──────────┐         │
│  │ LlamaCPP │WhisperKit│   ONNX   │FluidAudio│         │
│  │          │          │          │          │         │
│  └──────────┴──────────┴──────────┴──────────┘         │
└─────────────────────────────────────────────────────────┘
```

---

## Supported AI Frameworks

| Framework | Models | Modality | Backend |
|-----------|--------|----------|---------|
| **LlamaCPP** | SmolLM2, Llama 2, Mistral, Qwen, LiquidAI | Text-to-Text | runanywhere-core (C++) |
| **WhisperKit** | Whisper Tiny, Whisper Base | Voice-to-Text | CoreML |
| **ONNX Runtime** | Sherpa Whisper, Piper TTS | STT & TTS | ONNX |
| **FluidAudio** | Speaker Diarization | Voice Processing | Native |
| **Foundation Models** | Apple Intelligence (iOS 26+) | Text-to-Text | System |

---

## Project Structure

```
RunAnywhereAI/
├── App/
│   ├── RunAnywhereAIApp.swift      # Entry point, SDK init
│   └── ContentView.swift           # Tab navigation
├── Core/
│   ├── DesignSystem/               # Colors, typography, spacing
│   ├── Models/                     # Shared data types
│   └── Services/                   # ModelManager, ConversationStore
├── Features/
│   ├── Chat/                       # LLM chat interface
│   ├── Models/                     # Model browser & selection
│   ├── Voice/                      # STT, TTS, Voice Assistant
│   ├── Quiz/                       # Structured output demo
│   ├── Settings/                   # App configuration
│   └── Storage/                    # Storage management
├── Helpers/
│   └── AdaptiveLayout.swift        # Cross-platform helpers
└── Utilities/
    └── KeychainHelper.swift        # Secure storage
```

---

## Build & Run

### Prerequisites
- Xcode 15.0+
- iOS 17.0+ device or simulator
- CocoaPods (for dependencies)

### Commands

```bash
# Navigate to project
cd sdks/examples/ios/RunAnywhereAI/

# Build and run on simulator
./scripts/build_and_run.sh simulator "iPhone 16 Pro"

# Build and run on device
./scripts/build_and_run.sh device

# Clean build
./scripts/clean_build_and_run.sh

# Run SwiftLint
./swiftlint.sh

# Verify model URLs
./scripts/verify_urls.sh
```

---

## SDK Integration Examples

### Loading a Model

```swift
// Get available models
let models = await RunAnywhere.listAvailableModels()

// Load a specific model
try await RunAnywhere.loadModel("smollm2-360m-q8-0")

// Check current model
if let model = RunAnywhere.currentModel {
    print("Loaded: \(model.name)")
}
```

### Streaming Text Generation

```swift
for try await chunk in try await RunAnywhere.generate(prompt: "Hello, AI!") {
    response += chunk
    // Update UI with streamed text
}
```

### Voice Pipeline

```swift
let pipeline = ModularVoicePipeline(
    sttModelId: "whisper-base",
    llmModelId: "smollm2-360m-q8-0",
    ttsModelId: "piper-en-us-lessac-medium"
)

// Start voice interaction
await pipeline.processPipeline()
```

### Structured Output

```swift
struct Quiz: Codable {
    let questions: [Question]
}

let quiz = try await RunAnywhere.generateStructured(
    prompt: "Create a quiz about Swift programming",
    structure: Quiz.self
)
```

---

## Key Technical Highlights

- **Streaming Responses** - Real-time token output with per-token metrics
- **Cross-Platform** - Single codebase for iOS and macOS with adaptive layouts
- **Offline-First** - All processing on-device by default
- **Memory-Aware** - Model loading respects device memory constraints
- **Comprehensive Analytics** - Token throughput, TTFT, thinking time tracking
- **Speaker Diarization** - Multi-speaker identification via FluidAudio

---

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| RunAnywhere SDK | Local | Core AI functionality |
| Alamofire | 5.10.2 | Networking |
| DeviceKit | 5.6.0 | Device information |
| ZIPFoundation | 0.9.19 | Archive handling |
| GRDB | 7.6.1 | Database |
| Pulse | 4.2.7 | Logging |

---

## Related Documentation

- [RunAnywhere Swift SDK](../../../sdk/runanywhere-swift/README.md)
- [runanywhere-core C++ Library](../../../../runanywhere-core/README.md)
- [SDK CLAUDE.md](../../../CLAUDE.md)
