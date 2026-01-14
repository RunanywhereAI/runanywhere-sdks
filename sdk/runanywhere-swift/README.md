# RunAnywhere Swift SDK

<p align="center">
  <img src="../../examples/logo.svg" alt="RunAnywhere Logo" width="140"/>
</p>

<p align="center">
  <strong>On-Device AI for Apple Platforms</strong><br/>
  Run LLMs, Speech-to-Text, Text-to-Speech, and Voice AI pipelines locally—privacy-first, offline-capable, production-ready.
</p>

<p align="center">
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-5.9+-FA7343?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.9+" /></a>
  <a href="#"><img src="https://img.shields.io/badge/iOS-17.0+-000000?style=flat-square&logo=apple&logoColor=white" alt="iOS 17.0+" /></a>
  <a href="#"><img src="https://img.shields.io/badge/macOS-14.0+-000000?style=flat-square&logo=apple&logoColor=white" alt="macOS 14.0+" /></a>
  <a href="#"><img src="https://img.shields.io/badge/Metal-GPU%20Accelerated-8A2BE2?style=flat-square" alt="Metal GPU" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-Proprietary-blue?style=flat-square" alt="License" /></a>
</p>

---

## Quick Links

- [Architecture Overview](#architecture-overview) — How the SDK works
- [Quick Start](#quick-start) — Get running in 2 minutes
- [API Reference](Docs/Documentation.md) — Complete public API documentation
- [iOS Sample App](../../examples/ios/RunAnywhereAI/) — Full working demo
- [FAQ](#faq) — Common questions answered
- [Troubleshooting](#troubleshooting) — Problems & solutions
- [Contributing](#contributing) — How to contribute

---

## Features

### Large Language Models (LLM)
- On-device text generation with streaming support
- Multiple backends: **LlamaCPP** (GGUF models), **Apple Intelligence** (iOS 26+)
- Metal GPU acceleration on Apple Silicon
- Structured output generation with `Generatable` protocol
- System prompts and customizable generation parameters
- Support for thinking/reasoning models

### Speech-to-Text (STT)
- Real-time streaming transcription
- Batch audio transcription
- Multi-language support with Whisper models via ONNX Runtime
- Word-level timestamps and confidence scores

### Text-to-Speech (TTS)
- Neural voice synthesis with Piper TTS
- System voices via AVSpeechSynthesizer
- Streaming audio generation for long text
- Customizable voice, pitch, rate, and volume

### Voice Activity Detection (VAD)
- Energy-based speech detection with Silero VAD
- Configurable sensitivity thresholds
- Real-time audio stream processing

### Voice Agent Pipeline
- Full VAD → STT → LLM → TTS orchestration
- Complete voice conversation flow
- Push-to-talk and hands-free modes

### Infrastructure
- Automatic model discovery and download with progress tracking
- Comprehensive event system via `EventBus`
- Built-in analytics and telemetry
- Structured logging with Sentry integration
- Keychain-persisted device identity

---

## System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **iOS** | 17.0+ | 17.0+ |
| **macOS** | 14.0+ | 14.0+ |
| **tvOS** | 17.0+ | 17.0+ |
| **watchOS** | 10.0+ | 10.0+ |
| **Xcode** | 15.2+ | 16.0+ |
| **Swift** | 5.9+ | 5.10+ |
| **RAM** | 3GB | 6GB+ for 7B models |
| **Storage** | Variable | Models: 200MB–8GB |

> **Note:** Apple Silicon devices (M1/M2/M3, A14+) recommended for best performance. Metal GPU acceleration provides 3-5x speedup over CPU-only inference.

---

## Installation

### Swift Package Manager (Recommended)

Add the RunAnywhere SDK to your project in Xcode:

1. Open your project in Xcode
2. Go to **File → Add Package Dependencies...**
3. Enter the repository URL:
   ```
   https://github.com/RunanywhereAI/runanywhere-sdks
   ```
4. Select version `0.16.0` or later
5. Choose the products you need:
   - **RunAnywhere** (required) — Core SDK
   - **RunAnywhereONNX** — ONNX Runtime for STT/TTS/VAD
   - **RunAnywhereLlamaCPP** — LLM text generation with GGUF models

### Package.swift

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
            .product(name: "RunAnywhereONNX", package: "runanywhere-sdks"),
        ]
    )
]
```

---

## Quick Start

### 1. Initialize the SDK

```swift
import RunAnywhere
import LlamaCPPRuntime  // For LLM capabilities
import ONNXRuntime     // For STT/TTS capabilities

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .task {
            await initializeSDK()
        }
    }

    @MainActor
    private func initializeSDK() async {
        do {
            // 1. Initialize SDK (development mode - no API key needed)
            try RunAnywhere.initialize()

            // 2. Register backend modules
            LlamaCPP.register()  // LLM backend (GGUF models)
            ONNX.register()      // STT/TTS backend (Whisper, Piper)

            print("RunAnywhere SDK initialized")
        } catch {
            print("SDK initialization failed: \(error)")
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
print("Speed: \(result.tokensPerSecond) tok/s")
print("Latency: \(result.latencyMs)ms")
```

### 3. Streaming Generation

```swift
let result = try await RunAnywhere.generateStream(
    "Write a short poem about AI",
    options: LLMGenerationOptions(maxTokens: 150)
)

// Display tokens in real-time
for try await token in result.stream {
    print(token, terminator: "")
}

// Get final metrics
let metrics = try await result.result.value
print("\nSpeed: \(metrics.tokensPerSecond) tok/s")
```

### 4. Speech-to-Text

```swift
// Load STT model
try await RunAnywhere.loadSTTModel("sherpa-onnx-whisper-tiny.en")

// Transcribe audio data
let transcription = try await RunAnywhere.transcribe(audioData)
print("Transcription: \(transcription)")
```

### 5. Text-to-Speech

```swift
// Load TTS voice
try await RunAnywhere.loadTTSVoice("piper-en-us-amy")

// Synthesize speech
let output = try await RunAnywhere.synthesize(
    "Hello! Welcome to RunAnywhere.",
    options: TTSOptions(speakingRate: 1.0, pitch: 1.0)
)
// output.audioData contains WAV audio bytes
```

---

## Architecture Overview

The RunAnywhere SDK follows a **modular, provider-based architecture** with a C++ commons layer for cross-platform performance:

```
┌─────────────────────────────────────────────────────────────────┐
│                        Your Application                          │
├─────────────────────────────────────────────────────────────────┤
│                    RunAnywhere Swift SDK                         │
│  ┌──────────────┐  ┌───────────────┐  ┌──────────────────────┐  │
│  │ Public APIs  │  │  EventBus     │  │  ServiceRegistry     │  │
│  │ (generate,   │  │  (events,     │  │  (module discovery,  │  │
│  │  transcribe) │  │   analytics)  │  │   service routing)   │  │
│  └──────────────┘  └───────────────┘  └──────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                     C++ Bridge Layer                             │
│              CRACommons (runanywhere-commons)                    │
├────────────┬─────────────┬──────────────┬───────────────────────┤
│  LlamaCPP  │    ONNX     │  Apple AI    │   Future Backends...  │
│  Backend   │   Backend   │   Backend    │                       │
│  (LLM)     │ (STT/TTS)   │  (iOS 26+)   │                       │
└────────────┴─────────────┴──────────────┴───────────────────────┘
```

### Key Components

| Component | Description |
|-----------|-------------|
| **RunAnywhere** | Static enum providing all public SDK methods |
| **EventBus** | Combine-based event subscription for reactive UI |
| **ServiceRegistry** | Routes capability requests to registered backends |
| **ModuleRegistry** | Discovers and tracks registered backend modules |
| **CppBridge** | Swift-to-C++ interop for native performance |

### XCFramework Composition

| Framework | Size | Provides |
|-----------|------|----------|
| `RACommons.xcframework` | ~2MB | Core C++ commons, registries, events |
| `RABackendLLAMACPP.xcframework` | ~15-25MB | LLM capability (GGUF models) |
| `RABackendONNX.xcframework` | ~50-70MB | STT, TTS, VAD (ONNX models) |

> For detailed architecture documentation, see [ARCHITECTURE.md](ARCHITECTURE.md).

---

## Configuration

### SDK Initialization Parameters

```swift
// Development mode (default) - no API key needed
try RunAnywhere.initialize()

// Production mode - requires API key and backend URL
try RunAnywhere.initialize(
    apiKey: "<YOUR_API_KEY>",
    baseURL: "https://api.runanywhere.ai",
    environment: .production
)
```

### Environment Modes

| Environment | Description |
|-------------|-------------|
| `.development` | Verbose logging, local backend, no auth required |
| `.staging` | Testing with real services |
| `.production` | Minimal logging, full authentication, telemetry |

### Generation Options

```swift
let options = LLMGenerationOptions(
    maxTokens: 256,              // Maximum tokens to generate
    temperature: 0.7,            // Sampling temperature (0.0–2.0)
    topP: 0.95,                  // Top-p sampling parameter
    stopSequences: ["END"],      // Stop generation at these sequences
    systemPrompt: "You are a helpful assistant."
)
```

---

## Error Handling

The SDK provides comprehensive error handling through `SDKError`:

```swift
do {
    let response = try await RunAnywhere.generate("Hello!")
} catch let error as SDKError {
    switch error.code {
    case .notInitialized:
        print("SDK not initialized. Call RunAnywhere.initialize() first.")
    case .modelNotFound:
        print("Model not found. Download it first.")
    case .insufficientMemory:
        print("Not enough memory. Try a smaller model.")
    case .networkUnavailable:
        print("Network unavailable. Models work offline once downloaded.")
    default:
        print("Error: \(error.localizedDescription)")
        if let suggestion = error.recoverySuggestion {
            print("Suggestion: \(suggestion)")
        }
    }
}
```

### Error Categories

| Category | Description |
|----------|-------------|
| `.general` | General SDK errors |
| `.llm` | LLM generation errors |
| `.stt` | Speech-to-text errors |
| `.tts` | Text-to-speech errors |
| `.vad` | Voice activity detection errors |
| `.voiceAgent` | Voice pipeline errors |
| `.download` | Model download errors |
| `.network` | Network-related errors |
| `.authentication` | Auth and API key errors |

---

## Logging & Observability

### Configure Logging

```swift
// Set minimum log level
RunAnywhere.setLogLevel(.debug)  // .debug, .info, .warning, .error, .fault

// Enable debug mode for verbose output
RunAnywhere.setDebugMode(true)

// Flush all pending logs
await RunAnywhere.flushAll()
```

### Subscribe to Events

```swift
import Combine

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
```

---

## Performance & Best Practices

### Model Selection

| Model Size | RAM Required | Use Case |
|------------|--------------|----------|
| 360M–500M (Q8) | ~500MB | Fast, lightweight chat |
| 1B–3B (Q4/Q6) | 1–2GB | Balanced quality/speed |
| 7B (Q4) | 4–5GB | High quality, slower |

### Memory Management

```swift
// Unload models when not in use
try await RunAnywhere.unloadModel()

// Check storage before downloading
let storageInfo = await RunAnywhere.getStorageInfo()
if storageInfo.availableBytes > modelSize {
    // Safe to download
}

// Clean up temporary files
try await RunAnywhere.cleanTempFiles()
```

### Best Practices

1. **Prefer streaming** for better perceived latency
2. **Unload unused models** to free memory
3. **Handle errors gracefully** with user-friendly messages
4. **Test on target devices** — performance varies by hardware
5. **Use smaller models** for faster iteration during development

---

## Troubleshooting

### Model Download Fails

**Symptoms:** Download stuck or fails with network error

**Solutions:**
1. Check internet connection
2. Verify sufficient storage (need 2x model size)
3. Try on WiFi instead of cellular
4. Check if model URL is accessible

### Out of Memory

**Symptoms:** App crashes during model loading or inference

**Solutions:**
1. Use a smaller model (360M instead of 7B)
2. Unload unused models first
3. Close other memory-intensive apps
4. Test on device with more RAM

### Inference Too Slow

**Symptoms:** Generation takes 10+ seconds per token

**Solutions:**
1. Use Apple Silicon device for Metal acceleration
2. Reduce `maxTokens` for shorter responses
3. Use quantized models (Q4 instead of Q8)
4. Check device thermal state

### Model Not Found After Download

**Symptoms:** `modelNotFound` error even though download completed

**Solutions:**
1. Call `RunAnywhere.discoverDownloadedModels()` to refresh registry
2. Check model path in storage
3. Delete and re-download the model

---

## FAQ

### Q: Do I need an internet connection?
**A:** Only for initial model download. Once downloaded, all inference runs 100% on-device with no network required.

### Q: How much storage do models need?
**A:** Varies by model:
- Small LLMs (360M–1B): 200MB–1GB
- Medium LLMs (3B–7B Q4): 2–5GB
- STT models: 50–200MB
- TTS voices: 20–100MB

### Q: Is user data sent to the cloud?
**A:** No. All inference happens on-device. Only anonymous analytics (latency, error rates) are collected, and this can be disabled.

### Q: Which devices are supported?
**A:** iPhone/iPad with iOS 17+ and Mac with macOS 14+. Apple Silicon devices (M1/M2/M3, A14+) are recommended for best performance.

### Q: Can I use custom models?
**A:** Yes! Any GGUF model works with LlamaCPP backend. ONNX models work for STT/TTS.

---

## Contributing

We welcome contributions! The easiest way to get started is to run the iOS sample app with local SDK changes.

### First-Time Setup

```bash
# 1. Clone the repository
git clone https://github.com/RunanywhereAI/runanywhere-sdks.git
cd runanywhere-sdks/sdk/runanywhere-swift

# 2. Run first-time setup (builds all native frameworks)
# This downloads dependencies and builds:
#   - RACommons.xcframework (core infrastructure)
#   - RABackendLLAMACPP.xcframework (LLM backend)
#   - RABackendONNX.xcframework (STT/TTS/VAD backend)
./scripts/build-swift.sh --setup

# 3. Open the Swift SDK in Xcode
open Package.swift

# 4. If needed, reset package caches
# In Xcode: File > Packages > Reset Package Caches
```

> **Note:** First-time setup takes 5–15 minutes depending on your machine. After that, rebuilds are much faster.

### Testing with the iOS Sample App

The best way to test SDK changes is with the iOS/macOS sample app:

```bash
# 1. Ensure SDK is built (from previous step)
cd sdk/runanywhere-swift
./scripts/build-swift.sh --setup

# 2. Open the sample app
cd ../../examples/ios/RunAnywhereAI
open RunAnywhereAI.xcodeproj

# 3. In Xcode: File > Packages > Reset Package Caches
# 4. Select your device/simulator and click Run (Cmd+R)
```

The sample app demonstrates all SDK features:
- AI Chat with streaming
- Speech-to-Text transcription
- Text-to-Speech synthesis
- Voice Assistant pipeline
- Model management

### After Making Changes to runanywhere-commons

If you modify the C++ commons layer:

```bash
cd sdk/runanywhere-swift
./scripts/build-swift.sh --local --build-commons
```

### Build Script Options

| Command | Description |
|---------|-------------|
| `--setup` | First-time setup: downloads deps, builds all frameworks |
| `--local` | Use local frameworks from `Binaries/` |
| `--remote` | Use remote frameworks from GitHub releases |
| `--build-commons` | Rebuild runanywhere-commons from source |
| `--clean` | Clean build artifacts before building |
| `--release` | Build in release mode (default: debug) |

### Code Style

We use SwiftLint for code style enforcement:

```bash
# Install SwiftLint
brew install swiftlint

# Run linter
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
- SDK version: `RunAnywhere.version`
- Platform and OS version
- Device model
- Steps to reproduce
- Expected vs actual behavior
- Relevant logs (with sensitive info redacted)

---

## Support & Community

- **Discord**: [Join our community](https://discord.gg/pxRkYmWh)
- **GitHub Issues**: [Report bugs](https://github.com/RunanywhereAI/runanywhere-sdks/issues)
- **Email**: san@runanywhere.ai
- **Twitter**: [@RunanywhereAI](https://twitter.com/RunanywhereAI)

---

## License

Copyright © 2025 RunAnywhere AI. All rights reserved.

For commercial licensing inquiries, contact san@runanywhere.ai.

---

## Related Documentation

- [Architecture Overview](ARCHITECTURE.md) — Detailed system design
- [API Reference](Docs/Documentation.md) — Complete public API documentation
- [iOS Sample App](../../examples/ios/RunAnywhereAI/) — Production-ready demo
- [Android SDK](../runanywhere-kotlin/) — Android counterpart
- [React Native SDK](../runanywhere-react-native/) — Cross-platform option
- [Flutter SDK](../runanywhere-flutter/) — Flutter integration
