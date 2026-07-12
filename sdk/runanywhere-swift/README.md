# RunAnywhere Swift SDK

A production-grade, on-device AI SDK for iOS and macOS. The SDK enables low-latency, privacy-preserving inference for large language models, speech recognition, and voice synthesis with modular backend support.

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

The SDK provides a unified interface to multiple AI capabilities, including large language models (LLMs), speech-to-text (STT), text-to-speech (TTS), and voice activity detection (VAD). These capabilities are delivered through pluggable backend modules that can be included as needed.

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
| iOS      | 17.5+           |
| macOS    | 14.5+           |

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

**For SDK contributors:** After building the XCFrameworks, export `RUNANYWHERE_USE_LOCAL_NATIVES=1` when using the root `Package.swift`. The nested `sdk/runanywhere-swift/Package.swift` is always local and needs no override (see [Local Development & Contributing](#local-development--contributing) below).

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
// Build a proto-backed generate request via the v2 surface
var options = RALLMGenerationOptions.defaults()
options.maxTokens = 200
options.temperature = 0.7

var request = options.toRALLMGenerateRequest(
    prompt: "Explain quantum computing in simple terms"
)

let result = try await RunAnywhere.generate(request)
print("Response: \(result.text)")
print("Tokens generated: \(result.tokensGenerated)")
```

### 3. Load a Model

```swift
// Load an LLM through the canonical lifecycle (RAModelLoadRequest).
var loadRequest = RAModelLoadRequest()
loadRequest.modelID = "llama-3.2-1b-instruct-q4"
loadRequest.category = .language

let loadResult = await RunAnywhere.loadModel(loadRequest)
guard loadResult.success else {
    print("Load failed: \(loadResult.errorMessage)")
    return
}

// Check if a model is loaded for a given modality via the lifecycle service.
var current = RACurrentModelRequest()
current.category = .language
let snapshot = RunAnywhere.currentModel(current)
print("Loaded:", snapshot.found, "id=", snapshot.modelID)
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
var options = RALLMGenerationOptions.defaults()
options.maxTokens = 100
options.temperature = 0.8
options.topP = 1.0
options.stopSequences = ["END"]
options.streamingEnabled = false
options.systemPrompt = "You are a helpful assistant."
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
var options = RALLMGenerationOptions.defaults()
options.maxTokens = 150
options.streamingEnabled = true
let request = options.toRALLMGenerateRequest(
    prompt: "Write a short poem about AI"
)

let stream = try await RunAnywhere.generateStream(request)
for await event in stream {
    if event.kind == .answer {
        print(event.token, terminator: "")
    }
}
```

### Structured Output Generation

```swift
// Commons owns the full structured-output pipeline (prepare → generate →
// strip thinking tags → extract JSON → validate). Build a `RAJSONSchema`
// by populating its typed proto fields (the canonical JSON Schema text is
// produced by the read-only `jsonSchemaString` computed property).
var schema = RAJSONSchema()
schema.type = .object
schema.required = ["question", "options", "correctAnswer"]

var questionProp = RAJSONSchemaProperty()
questionProp.type = .string
schema.properties["question"] = questionProp

var optionsProp = RAJSONSchemaProperty()
optionsProp.type = .array
optionsProp.itemsSchema.type = .string
schema.properties["options"] = optionsProp

var correctAnswerProp = RAJSONSchemaProperty()
correctAnswerProp.type = .integer
schema.properties["correctAnswer"] = correctAnswerProp

let result = try await RunAnywhere.generateStructured(
    prompt: "Create a quiz question about Swift programming",
    schema: schema
)
let jsonString = String(data: result.parsedJson, encoding: .utf8) ?? ""
print("Validated JSON:", jsonString)
```

### Speech-to-Text Transcription

```swift
import RunAnywhere
import ONNXRuntime

ONNX.register()

// Load the STT model through the canonical lifecycle.
var loadRequest = RAModelLoadRequest()
loadRequest.modelID = "whisper-base-onnx"
loadRequest.category = .speechRecognition
_ = await RunAnywhere.loadModel(loadRequest)

let audioData: Data = // your audio data (16kHz, mono, Float32)
let transcription = try await RunAnywhere.transcribe(audio: audioData)
print("Transcribed: \(transcription.text)")
```

### Text-to-Speech Synthesis

```swift
// Load a TTS voice through the canonical lifecycle.
var loadRequest = RAModelLoadRequest()
loadRequest.modelID = "piper-en-us-amy"
loadRequest.category = .speechSynthesis
_ = await RunAnywhere.loadModel(loadRequest)

var options = RATTSOptions.defaults()
options.speakingRate = 1.0
options.pitch = 1.0
options.volume = 0.8

let output = try await RunAnywhere.synthesize(
    "Hello! Welcome to RunAnywhere.",
    options: options
)
```

### Voice Agent Pipeline

```swift
// Once STT, LLM, and TTS models are loaded via RAModelLoadRequest, compose
// the voice agent from the lifecycle snapshots:
try await RunAnywhere.initializeVoiceAgentWithLoadedModels()

let audioData: Data = // recorded audio
let result = try await RunAnywhere.processVoiceTurn(audioData)
print("User said:", result.transcription)
print("AI response:", result.assistantResponse)
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
                print("Event: \(event.category)")
            }
            .store(in: &cancellables)

        RunAnywhere.events.events(for: .llm)
            .sink { event in
                print("LLM Event: \(event.category)")
            }
            .store(in: &cancellables)
    }
}
```

### Model Download with Progress

```swift
// List registered models via the public proto-backed registry API.
let listResult = await RunAnywhere.listModels()
guard let model = listResult.models.models.first(where: { $0.id == "llama-3.2-1b-instruct-q4" }) else {
    return
}

// Download with the closure-based progress callback. Commons owns plan →
// start → progress polling → registry import; the closure receives each
// `RADownloadProgress` snapshot in real time.
let final = try await RunAnywhere.downloadModel(model) { progress in
    let percent = Int(progress.overallProgress * 100)
    print("\(progress.stage): \(percent)%")
}
print("Local path: \(final.localPath)")
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

---

## Logging and Observability

### Configure Log Level

```swift
RunAnywhere.setLogLevel(.debug)
RunAnywhere.setLocalLoggingEnabled(true)
RunAnywhere.setDebugMode(true)
RunAnywhere.flushLogs()
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

All SDK errors are thrown as `SDKException`, which carries a typed error
`code` (`RASDKErrorCode`), a developer-facing `message`, and a `category`
identifying which subsystem produced the error.

### Error Codes

`RASDKErrorCode` covers the v2 surface, including:

- `.notInitialized`
- `.invalidAPIKey`
- `.modelNotLoaded`
- `.modelLoadFailed`
- `.generationFailed`
- `.processingFailed`
- `.networkError`
- `.cancelled`

(See `SDKException.swift` and `Generated/sdk_errors.pb.swift` for the full
list of codes and categories.)

### Handling Errors

```swift
do {
    var options = RALLMGenerationOptions.defaults()
    options.maxTokens = 64
    let request = options.toRALLMGenerateRequest(prompt: "Hello")
    let result = try await RunAnywhere.generate(request)
    print(result.text)
} catch let error as SDKException {
    switch error.code {
    case .notInitialized:
        print("Please call RunAnywhere.initialize() first")
    case .modelNotLoaded:
        print("Model not loaded. Call RunAnywhere.loadModel(_:) first.")
    case .generationFailed:
        print("Generation failed: \(error.message)")
    default:
        print("Error (\(error.category)): \(error.message)")
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
// Unload a model through the canonical lifecycle.
var unloadRequest = RAModelUnloadRequest()
unloadRequest.category = .language
_ = await RunAnywhere.unloadModel(unloadRequest)

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
var options = RALLMGenerationOptions.defaults()
options.streamingEnabled = true
let request = options.toRALLMGenerateRequest(prompt: prompt)

let stream = try await RunAnywhere.generateStream(request)
for await event in stream where event.kind == .answer {
    await MainActor.run { self.text += event.token }
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

Currently, one LLM can be loaded at a time. STT and TTS models can be loaded alongside LLM models. Use `RunAnywhere.unloadModel(RAModelUnloadRequest())` before loading a different LLM.

### How do I handle model updates?

Call `RunAnywhere.listModels()` (or `RunAnywhere.queryModels(_:)` / `RunAnywhere.downloadedModels()`) to refresh the in-memory model catalog from the registry, then call `RunAnywhere.downloadModel(_:onProgress:)` to fetch any new or updated entries alongside existing models. Model assignment discovery runs automatically as part of the SDK's Phase-2 initialization.

### Is user data sent to the cloud?

By default, only anonymous analytics (latency, error rates) are collected. Actual prompts, responses, and audio data never leave the device.

### How do I debug issues?

1. Enable debug mode: `RunAnywhere.setDebugMode(true)`
2. Check logs with Pulse integration
3. Subscribe to error events: `RunAnywhere.events.on(.error) { ... }`

### How do I send a generation request?

Build a `RALLMGenerationOptions`, call `toRALLMGenerateRequest(prompt:)` to
produce a `RALLMGenerateRequest`, and pass it to `RunAnywhere.generate(_:)`
or `RunAnywhere.generateStream(_:)`. There is no longer a separate `chat()`
convenience — the proto-backed `generate(_:)` API returns a full
`RALLMGenerationResult` with metrics.

---

## Local Development & Contributing

We welcome contributions to the RunAnywhere Swift SDK. This section explains how to set up your development environment to build the SDK from source and test your changes with the sample app.

### Prerequisites

- macOS 14.5 or later
- Xcode 26.6 (build 17F113)
- CMake 4.3.2

### First-Time Setup (Build from Source)

The SDK depends on native C++ libraries from `runanywhere-commons`. Build XCFrameworks locally so you can develop and test the SDK end-to-end.

```bash
# 1. Clone the repository
git clone https://github.com/RunanywhereAI/runanywhere-sdks.git
cd runanywhere-sdks

# 2. Build XCFrameworks (~5-15 minutes)
./sdk/runanywhere-swift/scripts/build-core-xcframework.sh
```

**What the build script does:**
1. Downloads dependencies (ONNX Runtime, Sherpa-ONNX)
2. Builds `RACommons.xcframework` (core infrastructure)
3. Builds `RABackendLLAMACPP.xcframework` (LLM backend)
4. Builds `RABackendONNX.xcframework` (STT/TTS/VAD backend)
5. Builds `RABackendSherpa.xcframework` (speech backend)
6. Builds `RABackendMLX.xcframework` (Apple MLX backend)
7. Copies frameworks to `sdk/runanywhere-swift/Binaries/`

### Understanding useLocalNatives

The root package defaults to remote release artifacts and supports an explicit local-development environment override (the nested `sdk/runanywhere-swift/Package.swift` is always local):

| Mode | Setting | Description |
|------|---------|-------------|
| **Local** | `RUNANYWHERE_USE_LOCAL_NATIVES=1` | Uses XCFrameworks from `Binaries/` (for development) |
| **Remote** | Variable unset | Downloads checksum-verified XCFramework archives from GitHub releases (default for end users) |

### Testing with the iOS Sample App

The recommended way to test SDK changes is with the sample app:

```bash
# 1. Ensure XCFrameworks are built (from previous step)

# 2. Navigate to the sample app
cd examples/ios/RunAnywhereAI

# 3. Open in Xcode
open RunAnywhereAI.xcodeproj

# 4. If Xcode shows package errors, reset caches:
#    File > Packages > Reset Package Caches

# 5. Build and Run (Cmd+R)
```

The sample app's `Package.swift` references the local SDK, which in turn uses the local frameworks from `Binaries/`. This creates a complete local development loop:

```
Sample App → Local Swift SDK → Local XCFrameworks (Binaries/)
                                      ↑
                         Built by sdk/runanywhere-swift/scripts/build-core-xcframework.sh
```

### Development Workflow

**After modifying Swift SDK code:**
- No rebuild needed --- Xcode picks up changes automatically

**After modifying runanywhere-commons (C++ code):**

```bash
./sdk/runanywhere-swift/scripts/build-core-xcframework.sh
```

### Running Tests

```bash
RUNANYWHERE_USE_LOCAL_NATIVES=1 swift test
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
4. Ensure all tests pass: `RUNANYWHERE_USE_LOCAL_NATIVES=1 swift test`
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
