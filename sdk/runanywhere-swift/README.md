# RunAnywhere Swift SDK

> A production-grade, on-device AI SDK for iOS, macOS, tvOS, and watchOS—enabling low-latency, privacy-preserving LLM inference, speech recognition, and voice synthesis with modular backend support.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quickstart](#quickstart)
- [Configuration](#configuration)
- [Usage Examples](#usage-examples)
- [Architecture Overview](#architecture-overview)
- [Logging & Observability](#logging--observability)
- [Error Handling](#error-handling)
- [Performance & Best Practices](#performance--best-practices)
- [FAQ](#faq)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

The **RunAnywhere Swift SDK** enables developers to run AI models directly on Apple devices without requiring network connectivity for inference. By keeping data on-device, the SDK ensures minimal latency and maximum privacy for your users.

The SDK provides a unified interface to multiple AI capabilities—including large language models (LLMs), speech-to-text (STT), text-to-speech (TTS), voice activity detection (VAD), and speaker diarization—through pluggable backend modules. Whether you're building a voice assistant, transcription app, or AI-powered productivity tool, RunAnywhere handles the complexity of model management, hardware optimization, and streaming inference.

Key differentiators:
- **Multi-backend architecture**: Choose from LlamaCPP (GGUF models), ONNX Runtime, or Apple's Foundation Models
- **Metal acceleration**: GPU-accelerated inference on Apple Silicon
- **Event-driven design**: Subscribe to SDK events for reactive UI updates
- **Production-ready**: Built-in analytics, logging, device registration, and model lifecycle management

---

## Features

### 🧠 Language Models (LLM)
- On-device text generation with streaming support
- Structured output generation with `Generatable` protocol
- System prompts and customizable generation parameters
- Support for thinking/reasoning models with token extraction
- Multiple framework backends (LlamaCPP, Apple Foundation Models)

### 🎤 Speech-to-Text (STT)
- Real-time streaming transcription
- Batch audio transcription
- Multi-language support
- Whisper-based models via ONNX Runtime

### 🔊 Text-to-Speech (TTS)
- Neural voice synthesis with ONNX models
- System voices via AVSpeechSynthesizer
- Streaming audio generation for long text
- Customizable voice, pitch, rate, and volume

### 🎙️ Voice Activity Detection (VAD)
- Energy-based speech detection
- Configurable sensitivity thresholds
- Real-time audio stream processing

### 👥 Speaker Diarization
- Identify multiple speakers in audio
- Speaker segmentation and labeling
- Integration with FluidAudio

### 🗣️ Voice Agent Pipeline
- Full VAD → STT → LLM → TTS orchestration
- Complete voice conversation flow
- Streaming and batch processing modes

### 📦 Model Management
- Automatic model discovery and catalog sync
- Download with progress tracking (download, extract, validate stages)
- In-memory model storage with file system caching
- Framework-specific model assignment

### 📊 Observability
- Comprehensive event system via `EventBus`
- Analytics and telemetry integration
- Structured logging with Pulse support
- Performance metrics (tokens/second, latency, memory)

---

## Requirements

| Platform | Minimum Version |
|----------|----------------|
| iOS      | 17.0+          |
| macOS    | 14.0+          |
| tvOS     | 17.0+          |
| watchOS  | 10.0+          |

**Swift Version:** 5.9+

**Xcode:** 15.2+

> **Note:** Some optional modules have higher requirements:
> - Apple Foundation Models (`RunAnywhereAppleAI`): iOS 26+ / macOS 26+ at runtime

---

## Local Development Setup

If you're contributing to the SDK or building from source:

```bash
# 1. Clone the repo
git clone https://github.com/RunanywhereAI/runanywhere-sdks.git
cd runanywhere-sdks/sdk/runanywhere-swift

# 2. Run first-time setup (builds all native frameworks)
./scripts/build-swift.sh --setup

# 3. Open in Xcode
open Package.swift
```

The `--setup` command will:
- Download ONNX Runtime & Sherpa-ONNX dependencies
- Build `RACommons.xcframework` (core infrastructure)
- Build `RABackendLLAMACPP.xcframework` (LLM backend)
- Build `RABackendONNX.xcframework` (STT/TTS/VAD backend)
- Copy frameworks to `Binaries/`
- Set `testLocal = true` in Package.swift

> **Note:** First-time setup takes 5-15 minutes. After that, you only need to re-run if you modify runanywhere-commons.

### Using the Sample App

To run the iOS sample app with local SDK changes:

```bash
# 1. First, setup the Swift SDK
cd sdk/runanywhere-swift
./scripts/build-swift.sh --setup

# 2. Open the sample app
cd ../../examples/ios/RunAnywhereAI
open RunAnywhereAI.xcodeproj

# 3. In Xcode: File > Packages > Reset Package Caches
# 4. Build & Run!
```

### After Making Changes to runanywhere-commons

```bash
cd sdk/runanywhere-swift
./scripts/build-swift.sh --local --build-commons
```

---

## Installation

### Swift Package Manager (SPM)

Add the RunAnywhere SDK to your project using Xcode:

1. Open your project in Xcode
2. Go to **File → Add Package Dependencies...**
3. Enter the repository URL:
   ```
   https://github.com/RunanywhereAI/runanywhere-sdks
   ```
4. Select the version (e.g., `from: "0.16.0"`)
5. Choose the products you need:
   - **RunAnywhere** (required) — Core SDK
   - **RunAnywhereONNX** — ONNX Runtime for STT/TTS/VAD
   - **RunAnywhereLlamaCPP** — LLM text generation with GGUF models
   - **RunAnywhereAppleAI** — Apple Intelligence integration
   - **RunAnywhereFluidAudio** — Speaker diarization

#### Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/RunanywhereAI/runanywhere-sdks", from: "0.16.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "RunAnywhere", package: "runanywhere-sdks"),
            .product(name: "RunAnywhereLlamaCPP", package: "runanywhere-sdks"),
            // Add other modules as needed
        ]
    )
]
```

---

## Quickstart

### 1. Initialize the SDK

```swift
import RunAnywhere
import LlamaCPPRuntime  // For LLM capabilities

@main
struct MyApp: App {
    init() {
        // Register modules before initializing
        Task { @MainActor in
            // Register the LlamaCPP module for LLM support
            LlamaCPP.register()

            // Initialize the SDK
            do {
                try RunAnywhere.initialize(
                    apiKey: "<YOUR_API_KEY>",
                    baseURL: "https://api.runanywhere.ai",
                    environment: .production
                )
                print("✅ RunAnywhere SDK initialized")
            } catch {
                print("❌ SDK initialization failed: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### 2. Generate Text

```swift
// Simple chat interface
let response = try await RunAnywhere.chat("What is the capital of France?")
print(response)  // "The capital of France is Paris."

// Full generation with metrics
let result = try await RunAnywhere.generate(
    "Explain quantum computing in simple terms",
    options: LLMGenerationOptions(
        maxTokens: 200,
        temperature: 0.7
    )
)
print("Response: \(result.text)")
print("Tokens used: \(result.tokensUsed)")
print("Speed: \(result.tokensPerSecond) tok/s")
print("Latency: \(result.latencyMs)ms")
```

### 3. Load a Model

```swift
// Load an LLM model by ID
try await RunAnywhere.loadModel("llama-3.2-1b-instruct-q4")

// Check if model is loaded
let isLoaded = await RunAnywhere.isModelLoaded
```

---

## Configuration

### SDK Initialization Parameters

```swift
try RunAnywhere.initialize(
    apiKey: "<YOUR_API_KEY>",      // API key from RunAnywhere console
    baseURL: "https://api.runanywhere.ai",  // Backend URL
    environment: .production       // .development, .staging, or .production
)
```

### Environment Modes

| Environment   | Description                                        |
|---------------|----------------------------------------------------|
| `.development`| Verbose logging, mock services, local analytics    |
| `.staging`    | Testing with real services                         |
| `.production` | Minimal logging, full authentication, telemetry    |

### Generation Options

```swift
let options = LLMGenerationOptions(
    maxTokens: 100,              // Maximum tokens to generate
    temperature: 0.8,            // Sampling temperature (0.0 - 2.0)
    topP: 1.0,                   // Top-p sampling parameter
    stopSequences: ["END"],      // Stop generation at these sequences
    streamingEnabled: false,     // Enable streaming mode
    preferredFramework: .llamaCpp,  // Preferred inference framework
    systemPrompt: "You are a helpful assistant."  // System prompt
)
```

### Module Registration

Register modules at app startup before using their capabilities:

```swift
import RunAnywhere
import LlamaCPPRuntime
import ONNXRuntime
import FluidAudioDiarization

@MainActor
func setupSDK() {
    // Register modules with default priority
    LlamaCPP.register()      // LLM (priority: 100)
    ONNX.register()          // STT + TTS (priority: 100)
    FluidAudio.register()    // Speaker Diarization (priority: 100)

    // Or with custom priority (higher = preferred)
    RunAnywhere.register(LlamaCPP.self, priority: 150)

    // Or auto-register all discovered modules
    RunAnywhere.registerAllModules()
}
```

---

## Usage Examples

### Streaming Text Generation

```swift
let result = try await RunAnywhere.generateStream(
    "Write a short poem about AI",
    options: LLMGenerationOptions(maxTokens: 150)
)

// Display tokens in real-time
for try await token in result.stream {
    print(token, terminator: "")
    // Update UI with each token
}

// Get complete metrics after streaming finishes
let metrics = try await result.result.value
print("\n\nSpeed: \(metrics.tokensPerSecond) tok/s")
print("Total tokens: \(metrics.tokensUsed)")
```

### Structured Output Generation

```swift
// Define your output type
struct QuizQuestion: Generatable {
    let question: String
    let options: [String]
    let correctAnswer: Int

    static var jsonSchema: String {
        """
        {
          "type": "object",
          "properties": {
            "question": { "type": "string" },
            "options": { "type": "array", "items": { "type": "string" } },
            "correctAnswer": { "type": "integer" }
          },
          "required": ["question", "options", "correctAnswer"]
        }
        """
    }
}

// Generate structured output
let quiz: QuizQuestion = try await RunAnywhere.generateStructured(
    QuizQuestion.self,
    prompt: "Create a quiz question about Swift programming"
)
print("Q: \(quiz.question)")
```

### Speech-to-Text Transcription

```swift
import RunAnywhere
import ONNXRuntime

// Register ONNX module for STT
await ONNX.register()

// Load STT model
try await RunAnywhere.loadSTTModel("whisper-base-onnx")

// Transcribe audio data
let audioData: Data = // ... your audio data (16kHz, mono, Float32)
let transcription = try await RunAnywhere.transcribe(audioData)
print("Transcribed: \(transcription)")

// With options
let options = STTOptions(language: "en-US")
let result = try await RunAnywhere.transcribeWithOptions(audioData, options: options)
print("Text: \(result.text)")
print("Confidence: \(result.confidence ?? 0)")
```

### Text-to-Speech Synthesis

```swift
// Load TTS voice
try await RunAnywhere.loadTTSVoice("piper-en-us-amy")

// Synthesize speech
let output = try await RunAnywhere.synthesize(
    "Hello! Welcome to RunAnywhere.",
    options: TTSOptions(
        speakingRate: 1.0,
        pitch: 1.0,
        volume: 0.8
    )
)

// Play the audio data
let audioData = output.audioData
// ... play with AVAudioPlayer or audio engine
```

### Voice Agent Pipeline

```swift
// Initialize voice agent with models
try await RunAnywhere.initializeVoiceAgent(
    sttModelId: "whisper-base-onnx",
    llmModelId: "llama-3.2-1b-instruct-q4",
    ttsVoice: "com.apple.ttsbundle.siri_female_en-US_compact"
)

// Process a complete voice turn
let audioData: Data = // ... recorded audio
let result = try await RunAnywhere.processVoiceTurn(audioData)

print("User said: \(result.transcription)")
print("AI response: \(result.response)")
// result.audioResponse contains synthesized audio

// Cleanup when done
await RunAnywhere.cleanupVoiceAgent()
```

### Subscribing to Events

```swift
import Combine

class ViewModel: ObservableObject {
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Subscribe to all events
        RunAnywhere.events.events
            .receive(on: DispatchQueue.main)
            .sink { event in
                print("Event: \(event.type)")
            }
            .store(in: &cancellables)

        // Subscribe to specific category
        RunAnywhere.events.events(for: .llm)
            .sink { event in
                print("LLM Event: \(event.type)")
            }
            .store(in: &cancellables)

        // Using closure-based subscription
        let subscription = RunAnywhere.events.on(.model) { event in
            print("Model event: \(event.type)")
        }
        cancellables.insert(subscription)
    }
}
```

### Model Download with Progress

```swift
// Get available models
let models = try await RunAnywhere.availableModels()
let model = models.first { $0.id == "llama-3.2-1b-instruct-q4" }!

// Download with progress tracking
let task = try await Download.shared.downloadModel(model)

// Observe progress
for await progress in task.progress {
    let percent = Int(progress.overallProgress * 100)
    print("\(progress.stage.displayName): \(percent)%")

    if let speed = progress.speed {
        let mbps = speed / 1_000_000
        print("Speed: \(String(format: "%.1f", mbps)) MB/s")
    }
}
```

---

## Architecture Overview

The RunAnywhere SDK follows a **modular, provider-based architecture** that separates core functionality from specific backend implementations:

```
┌─────────────────────────────────────────────────────────────────┐
│                        Public API                                │
│         RunAnywhere.generate() / transcribe() / synthesize()    │
└─────────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────┼─────────────────────────────────────┐
│                    Capability Layer                              │
│    LLMCapability  │  STTCapability  │  TTSCapability  │  ...    │
└─────────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────┼─────────────────────────────────────┐
│                  ServiceRegistry                                  │
│         Routes requests to registered service providers           │
└─────────────────────────────────────────────────────────────────┘
                              │
         ┌────────────────────┼────────────────────┐
         ↓                    ↓                    ↓
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ LlamaCPP Module │  │  ONNX Module    │  │ AppleAI Module  │
│  (LLM: GGUF)    │  │ (STT + TTS)     │  │ (LLM: iOS 26+)  │
└─────────────────┘  └─────────────────┘  └─────────────────┘
         │                    │                    │
         ↓                    ↓                    ↓
┌─────────────────────────────────────────────────────────────────┐
│              Native Runtime / XCFramework                        │
│         RunAnywhereCore (C++ with Metal acceleration)            │
└─────────────────────────────────────────────────────────────────┘
```

**Key Components:**
- **ModuleRegistry**: Discovers and tracks registered modules
- **ServiceRegistry**: Routes capability requests to the appropriate provider
- **Capability Classes**: Handle business logic, events, and analytics
- **EventBus**: Pub/sub system for SDK-wide events
- **ServiceContainer**: Dependency injection container

For detailed architecture documentation, see [ARCHITECTURE.md](ARCHITECTURE.md).

---

## Logging & Observability

### Configure Log Level

```swift
// Set minimum log level
RunAnywhere.setLogLevel(.debug)  // .debug, .info, .warning, .error, .fault

// Enable local logging with Pulse
RunAnywhere.configureLocalLogging(enabled: true)

// Enable verbose debug mode
RunAnywhere.setDebugMode(true)

// Flush all pending logs
await RunAnywhere.flushAll()
```

### Log Levels

| Level     | Description                                    |
|-----------|------------------------------------------------|
| `.debug`  | Detailed information for debugging             |
| `.info`   | General operational information                |
| `.warning`| Potential issues that don't prevent operation  |
| `.error`  | Errors that affect specific operations         |
| `.fault`  | Critical errors indicating serious problems    |

### Analytics

The SDK automatically tracks key metrics:
- Generation latency and tokens/second
- Model load times and memory usage
- Error rates by category
- User session analytics (opt-in)

Analytics are batched and sent to the backend when in production/staging mode.

---

## Error Handling

All SDK errors are represented by `RunAnywhereError`, which provides:
- Typed error cases for each error category
- Detailed error descriptions
- Recovery suggestions
- Underlying error information when applicable

### Error Categories

```swift
// Initialization
case notInitialized
case invalidAPIKey(String?)
case invalidConfiguration(String)

// Models
case modelNotFound(String)
case modelLoadFailed(String, Error?)
case modelIncompatible(String, String)

// Generation
case generationFailed(String)
case generationTimeout(String?)
case contextTooLong(Int, Int)

// Network
case networkUnavailable
case downloadFailed(String, Error?)

// Storage
case insufficientStorage(Int64, Int64)
case storageFull
```

### Handling Errors

```swift
do {
    let result = try await RunAnywhere.generate("Hello")
} catch let error as RunAnywhereError {
    switch error {
    case .notInitialized:
        print("Please call RunAnywhere.initialize() first")

    case .modelNotFound(let modelId):
        print("Model '\(modelId)' not found. Download it first.")

    case .generationFailed(let reason):
        print("Generation failed: \(reason)")

    case .insufficientStorage(let required, let available):
        print("Need \(required) bytes, only \(available) available")

    default:
        print("Error: \(error.localizedDescription)")
        if let suggestion = error.recoverySuggestion {
            print("Suggestion: \(suggestion)")
        }
    }
}
```

---

## Performance & Best Practices

### Model Selection

- **Smaller models** (1-3B parameters) work well for most on-device use cases
- **Q4/Q5 quantization** provides good balance of quality and speed
- Test on target devices—performance varies significantly by hardware

### Memory Management

```swift
// Unload models when not in use
try await RunAnywhere.unloadModel()

// Check storage before downloading
let storageInfo = await RunAnywhere.getStorageInfo()
if storageInfo.availableBytes > model.downloadSize ?? 0 {
    // Safe to download
}

// Clean up temporary files periodically
try await RunAnywhere.cleanTempFiles()
```

### Threading

- SDK methods are async and safe to call from any context
- Heavy operations (model loading, generation) run on background threads
- UI updates from event subscriptions should dispatch to main thread

### Background/Foreground

- Models remain loaded during brief background transitions
- For extended background sessions, unload models to reduce memory pressure
- Re-load models when returning to foreground if needed

### Streaming for Responsiveness

```swift
// Prefer streaming for better perceived latency
let result = try await RunAnywhere.generateStream(prompt)
for try await token in result.stream {
    // Update UI immediately with each token
    await MainActor.run { self.text += token }
}
```

### Batch Operations

```swift
// Fetch model assignments once at startup
let models = try await RunAnywhere.fetchModelAssignments()

// Cache locally and avoid repeated network calls
for model in models where model.isDownloaded {
    // Model ready to use
}
```

---

## FAQ

### Q: Do I need an internet connection to use the SDK?
**A:** No, once models are downloaded, all inference happens on-device. You only need internet for:
- Initial SDK authentication
- Downloading models
- Syncing analytics (optional)

### Q: Which models are supported?
**A:** The SDK supports:
- **GGUF models** via LlamaCPP (Llama, Mistral, Phi, Qwen, etc.)
- **ONNX models** for STT (Whisper variants) and TTS (Piper voices)
- **Apple Foundation Models** on iOS 26+ (built-in, no download)

### Q: How much storage do models require?
**A:** Model sizes vary significantly:
- Small LLMs (1-3B Q4): 500MB - 2GB
- Medium LLMs (7B Q4): 3-5GB
- STT models: 50-500MB
- TTS voices: 20-100MB

### Q: Can I use multiple models simultaneously?
**A:** Currently, one LLM can be loaded at a time. STT and TTS models can be loaded alongside LLM models. Use `unloadModel()` before loading a different LLM.

### Q: How do I handle model updates?
**A:** Call `fetchModelAssignments(forceRefresh: true)` to sync the latest model catalog. New versions can be downloaded alongside existing models.

### Q: Is user data sent to the cloud?
**A:** By default, only anonymous analytics (latency, error rates) are collected. Actual prompts, responses, and audio data **never leave the device**.

### Q: How do I debug issues?
**A:**
1. Enable debug mode: `RunAnywhere.setDebugMode(true)`
2. Check logs with Pulse integration
3. Subscribe to error events: `RunAnywhere.events.on(.error) { ... }`

### Q: What's the difference between `chat()` and `generate()`?
**A:**
- `chat(_:)` returns just the text string—simple and quick
- `generate(_:options:)` returns `LLMGenerationResult` with full metrics

### Q: Can I customize model behavior?
**A:** Yes, use `LLMGenerationOptions`:
```swift
LLMGenerationOptions(
    temperature: 0.7,    // Lower = more deterministic
    maxTokens: 200,      // Limit response length
    systemPrompt: "..."  // Set AI behavior
)
```

### Q: How do I contribute?
**A:** See the [Contributing](#contributing) section below.

---

## Contributing

We welcome contributions! Here's how to get started:

### Setup

```bash
# Clone the repository
git clone https://github.com/RunanywhereAI/runanywhere-sdks.git
cd runanywhere-sdks/sdk/runanywhere-swift

# Open in Xcode
open Package.swift

# Or build from command line
swift build
```

### Running Tests

```bash
swift test
```

### Code Style

The project uses SwiftLint for code style enforcement:

```bash
# Install SwiftLint
brew install swiftlint

# Run linter
swiftlint
```

### Pull Requests

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes with tests
4. Ensure all tests pass: `swift test`
5. Run linter: `swiftlint`
6. Commit with a descriptive message
7. Push and open a Pull Request

### Reporting Issues

Open an issue on GitHub with:
- SDK version (check with `RunAnywhere.getSDKVersion()`)
- Platform and OS version
- Steps to reproduce
- Expected vs actual behavior
- Relevant logs (with sensitive info redacted)

### Questions & Support

- **Discord**: https://discord.gg/pxRkYmWh
- **Email**: founders@runanywhere.ai
- **GitHub Issues**: https://github.com/RunanywhereAI/runanywhere-sdks/issues

---

## License

Copyright © 2025 RunAnywhere AI. All rights reserved.

See the repository for license terms. For commercial licensing inquiries, contact founders@runanywhere.ai.

---

**Built with ❤️ by the RunAnywhere team**
