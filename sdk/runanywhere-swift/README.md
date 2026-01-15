# RunAnywhere Swift SDK

A production-grade, on-device AI SDK for iOS, macOS, tvOS, and watchOS. The SDK enables low-latency, privacy-preserving inference for large language models, speech recognition, and voice synthesis with modular backend support.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Usage Examples](#usage-examples)
- [Architecture](#architecture)
- [Logging and Observability](#logging-and-observability)
- [Error Handling](#error-handling)
- [Performance Guidelines](#performance-guidelines)
- [FAQ](#faq)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

The RunAnywhere Swift SDK enables developers to run AI models directly on Apple devices without requiring network connectivity for inference. By keeping data on-device, the SDK ensures minimal latency and maximum privacy for your users.

The SDK provides a unified interface to multiple AI capabilities, including large language models (LLMs), speech-to-text (STT), text-to-speech (TTS), voice activity detection (VAD), and speaker diarization. These capabilities are delivered through pluggable backend modules that can be included as needed.

### Key Capabilities

- **Multi-backend architecture** - Choose from LlamaCPP (GGUF models), ONNX Runtime, or Apple Foundation Models
- **Metal acceleration** - GPU-accelerated inference on Apple Silicon
- **Event-driven design** - Subscribe to SDK events for reactive UI updates
- **Production-ready** - Built-in analytics, logging, device registration, and model lifecycle management

---

## Features

### Language Models (LLM)

- On-device text generation with streaming support
- Structured output generation with `Generatable` protocol
- System prompts and customizable generation parameters
- Support for thinking/reasoning models with token extraction
- Multiple framework backends (LlamaCPP, Apple Foundation Models)

### Speech-to-Text (STT)

- Real-time streaming transcription
- Batch audio transcription
- Multi-language support
- Whisper-based models via ONNX Runtime

### Text-to-Speech (TTS)

- Neural voice synthesis with ONNX models
- System voices via AVSpeechSynthesizer
- Streaming audio generation for long text
- Customizable voice, pitch, rate, and volume

### Voice Activity Detection (VAD)

- Energy-based speech detection
- Configurable sensitivity thresholds
- Real-time audio stream processing

### Speaker Diarization

- Identify multiple speakers in audio
- Speaker segmentation and labeling
- Integration with FluidAudio

### Voice Agent Pipeline

- Full VAD to STT to LLM to TTS orchestration
- Complete voice conversation flow
- Streaming and batch processing modes

### Model Management

- Automatic model discovery and catalog sync
- Download with progress tracking (download, extract, validate stages)
- In-memory model storage with file system caching
- Framework-specific model assignment

### Observability

- Comprehensive event system via `EventBus`
- Analytics and telemetry integration
- Structured logging with Pulse support
- Performance metrics (tokens per second, latency, memory)

---

## Requirements

| Platform | Minimum Version |
|----------|-----------------|
| iOS      | 17.0+           |
| macOS    | 14.0+           |
| tvOS     | 17.0+           |
| watchOS  | 10.0+           |

**Swift Version:** 5.9+

**Xcode:** 15.2+

Some optional modules have higher runtime requirements:
- Apple Foundation Models (`RunAnywhereAppleAI`): iOS 26+ / macOS 26+ at runtime

---

## Installation

### Swift Package Manager (Recommended)

Add the RunAnywhere SDK to your project using Xcode:

1. Open your project in Xcode
2. Go to **File > Add Package Dependencies...**
3. Enter the repository URL:
   ```
   https://github.com/RunanywhereAI/runanywhere-sdks
   ```
4. Select the version (e.g., `from: "1.0.0"`)
5. Choose the products you need:
   - **RunAnywhere** (required) - Core SDK
   - **RunAnywhereONNX** - ONNX Runtime for STT/TTS/VAD
   - **RunAnywhereLlamaCPP** - LLM text generation with GGUF models

### Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/RunanywhereAI/runanywhere-sdks", from: "1.0.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "RunAnywhere", package: "runanywhere-sdks"),
            .product(name: "RunAnywhereLlamaCPP", package: "runanywhere-sdks"),
            .product(name: "RunAnywhereONNX", package: "runanywhere-sdks"),
        ]
    )
]
```

### Package Structure

This repository contains **two** `Package.swift` files for different use cases:

| File | Location | Purpose |
|------|----------|---------|
| **Root Package.swift** | `runanywhere-sdks/Package.swift` | For external SPM consumers. Downloads pre-built XCFrameworks from GitHub releases. |
| **Local Package.swift** | `runanywhere-sdks/sdk/runanywhere-swift/Package.swift` | For SDK developers. Uses local XCFrameworks from `Binaries/` directory. |

**For app developers:** Use the root-level package via the GitHub URL (as shown above).

**For SDK contributors:** Use the local package with `testLocal = true` after running the setup script.

---

## Quick Start

### 1. Initialize the SDK

```swift
import RunAnywhere
import LlamaCPPRuntime

@main
struct MyApp: App {
    init() {
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
            } catch {
                print("SDK initialization failed: \(error)")
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
    apiKey: "<YOUR_API_KEY>",
    baseURL: "https://api.runanywhere.ai",
    environment: .production
)
```

### Environment Modes

| Environment     | Description                                      |
|-----------------|--------------------------------------------------|
| `.development`  | Verbose logging, mock services, local analytics  |
| `.staging`      | Testing with real services                       |
| `.production`   | Minimal logging, full authentication, telemetry  |

### Generation Options

```swift
let options = LLMGenerationOptions(
    maxTokens: 100,
    temperature: 0.8,
    topP: 1.0,
    stopSequences: ["END"],
    streamingEnabled: false,
    preferredFramework: .llamaCpp,
    systemPrompt: "You are a helpful assistant."
)
```

### Module Registration

Register modules at app startup before using their capabilities:

```swift
import RunAnywhere
import LlamaCPPRuntime
import ONNXRuntime

@MainActor
func setupSDK() {
    LlamaCPP.register()   // LLM (priority: 100)
    ONNX.register()       // STT + TTS (priority: 100)
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

for try await token in result.stream {
    print(token, terminator: "")
}

let metrics = try await result.result.value
print("\nSpeed: \(metrics.tokensPerSecond) tok/s")
```

### Structured Output Generation

```swift
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

let quiz: QuizQuestion = try await RunAnywhere.generateStructured(
    QuizQuestion.self,
    prompt: "Create a quiz question about Swift programming"
)
```

### Speech-to-Text Transcription

```swift
import RunAnywhere
import ONNXRuntime

await ONNX.register()
try await RunAnywhere.loadSTTModel("whisper-base-onnx")

let audioData: Data = // your audio data (16kHz, mono, Float32)
let transcription = try await RunAnywhere.transcribe(audioData)
print("Transcribed: \(transcription)")
```

### Text-to-Speech Synthesis

```swift
try await RunAnywhere.loadTTSVoice("piper-en-us-amy")

let output = try await RunAnywhere.synthesize(
    "Hello! Welcome to RunAnywhere.",
    options: TTSOptions(
        speakingRate: 1.0,
        pitch: 1.0,
        volume: 0.8
    )
)
```

### Voice Agent Pipeline

```swift
try await RunAnywhere.initializeVoiceAgent(
    sttModelId: "whisper-base-onnx",
    llmModelId: "llama-3.2-1b-instruct-q4",
    ttsVoice: "com.apple.ttsbundle.siri_female_en-US_compact"
)

let audioData: Data = // recorded audio
let result = try await RunAnywhere.processVoiceTurn(audioData)

print("User said: \(result.transcription)")
print("AI response: \(result.response)")

await RunAnywhere.cleanupVoiceAgent()
```

### Subscribing to Events

```swift
import Combine

class ViewModel: ObservableObject {
    private var cancellables = Set<AnyCancellable>()

    init() {
        RunAnywhere.events.events
            .receive(on: DispatchQueue.main)
            .sink { event in
                print("Event: \(event.type)")
            }
            .store(in: &cancellables)

        RunAnywhere.events.events(for: .llm)
            .sink { event in
                print("LLM Event: \(event.type)")
            }
            .store(in: &cancellables)
    }
}
```

### Model Download with Progress

```swift
let models = try await RunAnywhere.availableModels()
let model = models.first { $0.id == "llama-3.2-1b-instruct-q4" }!

let task = try await Download.shared.downloadModel(model)

for await progress in task.progress {
    let percent = Int(progress.overallProgress * 100)
    print("\(progress.stage.displayName): \(percent)%")
}
```

---

## Architecture

The RunAnywhere SDK follows a modular, provider-based architecture that separates core functionality from specific backend implementations:

```
+------------------------------------------------------------------+
|                         Public API                                |
|        RunAnywhere.generate() / transcribe() / synthesize()       |
+------------------------------------------------------------------+
                               |
+------------------------------------------------------------------+
|                      Capability Layer                             |
|     LLMCapability  |  STTCapability  |  TTSCapability  |  ...    |
+------------------------------------------------------------------+
                               |
+------------------------------------------------------------------+
|                     ServiceRegistry                               |
|          Routes requests to registered service providers          |
+------------------------------------------------------------------+
                               |
          +--------------------+--------------------+
          v                    v                    v
+------------------+  +------------------+  +------------------+
|  LlamaCPP Module |  |   ONNX Module    |  | AppleAI Module   |
|   (LLM: GGUF)    |  |  (STT + TTS)     |  |  (LLM: iOS 26+)  |
+------------------+  +------------------+  +------------------+
          |                    |                    |
          v                    v                    v
+------------------------------------------------------------------+
|               Native Runtime / XCFramework                        |
|          RunAnywhereCore (C++ with Metal acceleration)            |
+------------------------------------------------------------------+
```

**Key Components:**

- **ModuleRegistry** - Discovers and tracks registered modules
- **ServiceRegistry** - Routes capability requests to the appropriate provider
- **Capability Classes** - Handle business logic, events, and analytics
- **EventBus** - Pub/sub system for SDK-wide events
- **ServiceContainer** - Dependency injection container

For detailed architecture documentation, see [ARCHITECTURE.md](ARCHITECTURE.md).

---

## Logging and Observability

### Configure Log Level

```swift
RunAnywhere.setLogLevel(.debug)
RunAnywhere.configureLocalLogging(enabled: true)
RunAnywhere.setDebugMode(true)
await RunAnywhere.flushAll()
```

### Log Levels

| Level      | Description                                    |
|------------|------------------------------------------------|
| `.debug`   | Detailed information for debugging             |
| `.info`    | General operational information                |
| `.warning` | Potential issues that don't prevent operation  |
| `.error`   | Errors that affect specific operations         |
| `.fault`   | Critical errors indicating serious problems    |

### Analytics

The SDK automatically tracks key metrics:

- Generation latency and tokens per second
- Model load times and memory usage
- Error rates by category
- User session analytics (opt-in)

---

## Error Handling

All SDK errors are represented by `SDKError`, which provides:

- Typed error cases for each error category
- Detailed error descriptions
- Recovery suggestions
- Underlying error information when applicable

### Error Categories

```swift
case notInitialized
case invalidAPIKey(String?)
case invalidConfiguration(String)
case modelNotFound(String)
case modelLoadFailed(String, Error?)
case modelIncompatible(String, String)
case generationFailed(String)
case generationTimeout(String?)
case contextTooLong(Int, Int)
case networkUnavailable
case downloadFailed(String, Error?)
case insufficientStorage(Int64, Int64)
case storageFull
```

### Handling Errors

```swift
do {
    let result = try await RunAnywhere.generate("Hello")
} catch let error as SDKError {
    switch error.code {
    case .notInitialized:
        print("Please call RunAnywhere.initialize() first")
    case .modelNotFound:
        print("Model not found. Download it first.")
    case .generationFailed:
        print("Generation failed: \(error.message)")
    default:
        print("Error: \(error.localizedDescription)")
        if let suggestion = error.recoverySuggestion {
            print("Suggestion: \(suggestion)")
        }
    }
}
```

---

## Performance Guidelines

### Model Selection

- Smaller models (1-3B parameters) work well for most on-device use cases
- Q4/Q5 quantization provides good balance of quality and speed
- Test on target devices; performance varies significantly by hardware

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

### Streaming for Responsiveness

```swift
let result = try await RunAnywhere.generateStream(prompt)
for try await token in result.stream {
    await MainActor.run { self.text += token }
}
```

---

## FAQ

### Do I need an internet connection to use the SDK?

No, once models are downloaded, all inference happens on-device. You only need internet for:
- Initial SDK authentication
- Downloading models
- Syncing analytics (optional)

### Which models are supported?

The SDK supports:
- **GGUF models** via LlamaCPP (Llama, Mistral, Phi, Qwen, etc.)
- **ONNX models** for STT (Whisper variants) and TTS (Piper voices)
- **Apple Foundation Models** on iOS 26+ (built-in, no download)

### How much storage do models require?

Model sizes vary significantly:
- Small LLMs (1-3B Q4): 500MB - 2GB
- Medium LLMs (7B Q4): 3-5GB
- STT models: 50-500MB
- TTS voices: 20-100MB

### Can I use multiple models simultaneously?

Currently, one LLM can be loaded at a time. STT and TTS models can be loaded alongside LLM models. Use `unloadModel()` before loading a different LLM.

### How do I handle model updates?

Call `fetchModelAssignments(forceRefresh: true)` to sync the latest model catalog. New versions can be downloaded alongside existing models.

### Is user data sent to the cloud?

By default, only anonymous analytics (latency, error rates) are collected. Actual prompts, responses, and audio data never leave the device.

### How do I debug issues?

1. Enable debug mode: `RunAnywhere.setDebugMode(true)`
2. Check logs with Pulse integration
3. Subscribe to error events: `RunAnywhere.events.on(.error) { ... }`

### What's the difference between chat() and generate()?

- `chat(_:)` returns just the text string
- `generate(_:options:)` returns `LLMGenerationResult` with full metrics

---

## Contributing

We welcome contributions to the RunAnywhere Swift SDK. This section explains how to set up your development environment and test your changes.

### Prerequisites

- macOS 14.0 or later
- Xcode 15.2 or later
- CMake 3.21+ (for building native frameworks)

### First-Time Setup

1. **Clone the repository:**

   ```bash
   git clone https://github.com/RunanywhereAI/runanywhere-sdks.git
   cd runanywhere-sdks/sdk/runanywhere-swift
   ```

2. **Run the setup script:**

   This downloads dependencies, builds all native frameworks, and configures the SDK for local development:

   ```bash
   ./scripts/build-swift.sh --setup
   ```

   The setup process will:
   - Download ONNX Runtime and Sherpa-ONNX dependencies
   - Build `RACommons.xcframework` (core infrastructure)
   - Build `RABackendLLAMACPP.xcframework` (LLM backend)
   - Build `RABackendONNX.xcframework` (STT/TTS/VAD backend)
   - Copy frameworks to `Binaries/`
   - Ensure `testLocal = true` in the local Package.swift

   First-time setup takes approximately 5-15 minutes depending on your machine.

3. **Open the LOCAL SDK package in Xcode:**

   ```bash
   # IMPORTANT: Open the local Package.swift, NOT the root one
   open Package.swift
   ```

   If you encounter package resolution issues, go to **File > Packages > Reset Package Caches**.

> **Note:** The repository has two Package.swift files:
> - `sdk/runanywhere-swift/Package.swift` - **Use this for local development** (has `testLocal = true`)
> - `runanywhere-sdks/Package.swift` - For external SPM consumers (downloads from releases)

### Testing with the Sample App

The iOS/macOS sample app is the recommended way to test SDK changes:

1. **Ensure the SDK is set up** (complete the First-Time Setup above)

2. **Open the sample app:**

   ```bash
   cd ../../examples/ios/RunAnywhereAI
   open RunAnywhereAI.xcodeproj
   ```

3. **Reset package caches if needed:** File > Packages > Reset Package Caches

4. **Build and run** on your device or simulator

### Rebuilding After Changes

**After modifying Swift SDK code:**

No rebuild needed. Xcode will pick up the changes automatically.

**After modifying runanywhere-commons (C++ code):**

```bash
cd sdk/runanywhere-swift
./scripts/build-swift.sh --local --build-commons
```

### Build Script Reference

The `build-swift.sh` script supports the following commands:

| Command           | Description                                               |
|-------------------|-----------------------------------------------------------|
| `--setup`         | First-time setup: downloads deps, builds all frameworks   |
| `--local`         | Use local frameworks from `Binaries/`                     |
| `--remote`        | Use remote frameworks from GitHub releases                |
| `--build-commons` | Rebuild runanywhere-commons from source                   |
| `--clean`         | Clean build artifacts before building                     |
| `--release`       | Build in release mode (default: debug)                    |
| `--skip-build`    | Only setup frameworks, skip swift build                   |
| `--set-local`     | Set `testLocal = true` in Package.swift                   |
| `--set-remote`    | Set `testLocal = false` in Package.swift                  |

### Running Tests

```bash
swift test
```

### Code Style

The project uses SwiftLint for code style enforcement:

```bash
brew install swiftlint
swiftlint
```

### Pull Request Process

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes with tests
4. Ensure all tests pass: `swift test`
5. Run linter: `swiftlint`
6. Commit with a descriptive message
7. Push and open a Pull Request

### Reporting Issues

Open an issue on GitHub with:
- SDK version (check with `RunAnywhere.version`)
- Platform and OS version
- Steps to reproduce
- Expected vs actual behavior
- Relevant logs (with sensitive info redacted)

### Contact

- **Discord:** https://discord.gg/pxRkYmWh
- **Email:** san@runanywhere.ai
- **GitHub Issues:** https://github.com/RunanywhereAI/runanywhere-sdks/issues

---

## License

Copyright 2025 RunAnywhere AI. All rights reserved.

See the repository for license terms. For commercial licensing inquiries, contact san@runanywhere.ai.
