# RunAnywhere Swift SDK Architecture

## Overview

The RunAnywhere Swift SDK is a modular, multi-backend AI SDK for iOS/macOS that provides Speech-to-Text (STT), Text-to-Speech (TTS), Voice Activity Detection (VAD), LLM inference, and more. It consumes native binaries from `runanywhere-core` via XCFramework distribution.

---

## SDK Module Structure

```
┌─────────────────────────────────────────────────────────────────┐
│                     Swift Package Products                       │
├─────────────────────────────────────────────────────────────────┤
│  RunAnywhere          │ Core SDK (required base)                │
│  RunAnywhereONNX      │ ONNX Runtime backend (STT, TTS, VAD)    │
│  RunAnywhereWhisperKit│ CoreML-based STT (WhisperKit)           │
│  RunAnywhereLLM       │ llama.cpp backend (GGUF models)         │
│  RunAnywhereAppleAI   │ Apple Intelligence (iOS 26+)            │
│  RunAnywhereFluidAudio│ Speaker diarization                     │
└─────────────────────────────────────────────────────────────────┘
```

### Directory Layout

```
Sources/
├── RunAnywhere/                      # Core SDK
│   ├── Components/                   # AI Components
│   │   ├── STT/                      # Speech-to-Text
│   │   ├── TTS/                      # Text-to-Speech
│   │   ├── VAD/                      # Voice Activity Detection
│   │   ├── LLM/                      # Language Models
│   │   ├── VLM/                      # Vision-Language Models
│   │   ├── WakeWord/                 # Wake Word Detection
│   │   ├── SpeakerDiarization/       # Speaker ID
│   │   └── VoiceAgent/               # Full Voice Pipeline
│   ├── Core/
│   │   ├── ModuleRegistry.swift      # Plugin system
│   │   ├── EventBus.swift            # Event system
│   │   └── Analytics/                # Telemetry
│   └── Foundation/
│       ├── Configuration/            # Settings
│       └── DependencyInjection/      # Service container
├── ONNXRuntime/                      # ONNX Backend
├── WhisperKitTranscription/          # WhisperKit Backend
├── LLMSwift/                         # llama.cpp Backend
└── CRunAnywhereONNX/                 # C Bridge Headers
```

---

## Consuming runanywhere-core (XCFramework)

### Binary Target in Package.swift

```swift
.binaryTarget(
    name: "RunAnywhereONNXBinary",
    url: "https://github.com/RunanywhereAI/runanywhere-binaries/releases/download/v0.0.1-dev.xxx/RunAnywhereONNX.xcframework.zip",
    checksum: "62b2887a6d53360ed8d96a5080a98419d3c486f6be94bfe5e9f82415bb6a1fbe"
)
```

### C Bridge Layer

The `CRunAnywhereONNX` target provides Swift-compatible headers:

```
Sources/CRunAnywhereONNX/
├── module.modulemap        # Swift module definition
├── onnx_bridge_wrapper.h   # Bridge wrapper
└── types.h                 # Common types from runanywhere-core
```

**module.modulemap:**
```modulemap
module CRunAnywhereONNX {
    header "onnx_bridge_wrapper.h"
    header "types.h"
    export *
}
```

### How Swift Consumes the C API

```swift
// Import the C module
import CRunAnywhereONNX

class ONNXSTTService: STTService {
    private var backendHandle: ra_backend_handle?

    func initialize(modelPath: String?) async throws {
        // Create backend via C API
        backendHandle = ra_create_backend("onnx")

        // Initialize with JSON config
        let config = """
        {"device": "cpu", "threads": 4}
        """
        let result = ra_initialize(backendHandle, config)
        guard result == RA_SUCCESS else {
            throw ONNXError.initializationFailed(ra_get_last_error())
        }

        // Load STT model
        ra_stt_load_model(backendHandle, modelPath, "whisper", nil)
    }

    func transcribe(audioData: Data, options: STTOptions) async throws -> STTTranscriptionResult {
        // Convert audio to float array
        let samples = audioData.withUnsafeBytes { ... }

        // Call C API
        var resultPtr: UnsafeMutablePointer<CChar>?
        ra_stt_transcribe(backendHandle, samples, samples.count, 16000, "en", &resultPtr)

        // Convert result
        defer { ra_free_string(resultPtr) }
        return STTTranscriptionResult(text: String(cString: resultPtr!))
    }
}
```

---

## Multi-Backend Architecture

### Provider Pattern

Each AI capability uses a provider pattern for pluggable backends:

```
┌──────────────────────────────────────────────────────────────┐
│                      ModuleRegistry                           │
│  ┌─────────────┬─────────────┬─────────────┬──────────────┐ │
│  │STTProviders │TTSProviders │VADProviders │LLMProviders  │ │
│  │  priority   │  priority   │  priority   │  priority    │ │
│  └─────────────┴─────────────┴─────────────┴──────────────┘ │
└──────────────────────────────────────────────────────────────┘
                              │
         ┌────────────────────┼────────────────────┐
         ↓                    ↓                    ↓
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ ONNXSTTProvider │  │WhisperKitProvider│  │ SystemTTSProvider│
│  priority: 100  │  │  priority: 90   │  │   priority: 50  │
└─────────────────┘  └─────────────────┘  └─────────────────┘
```

### Service Provider Protocol

```swift
public protocol STTServiceProvider {
    var priority: Int { get }
    func canHandle(modelId: String) -> Bool
    func createSTTService() -> STTService
}

public protocol TTSServiceProvider {
    var priority: Int { get }
    func canHandle(modelId: String) -> Bool
    func createTTSService() -> TTSService
}
```

### ModuleRegistry (Plugin System)

```swift
public final class ModuleRegistry {
    public static let shared = ModuleRegistry()

    private var sttProviders: [(provider: STTServiceProvider, priority: Int)] = []
    private var ttsProviders: [(provider: TTSServiceProvider, priority: Int)] = []

    public func register(sttProvider: STTServiceProvider, priority: Int = 0) {
        sttProviders.append((sttProvider, priority))
        sttProviders.sort { $0.priority > $1.priority }
    }

    public func sttProvider(for modelId: String) -> STTServiceProvider? {
        sttProviders.first { $0.provider.canHandle(modelId: modelId) }?.provider
    }
}
```

### Framework Adapter Pattern

```swift
public protocol UnifiedFrameworkAdapter {
    var framework: LLMFramework { get }
    var supportedModalities: Set<FrameworkModality> { get }
    var supportedFormats: [ModelFormat] { get }

    func canHandle(model: ModelInfo) -> Bool
    func createService(for modality: FrameworkModality) -> Any?
    func loadModel(_ model: ModelInfo, for modality: FrameworkModality) async throws
}

public enum LLMFramework: String {
    case onnx
    case whisperKit
    case llamaCpp
    case coreML
    case foundationModels
}

public enum FrameworkModality {
    case voiceToText      // STT
    case textToVoice      // TTS
    case textToText       // LLM
    case visionToText     // VLM
}
```

---

## STT (Speech-to-Text) Architecture

### Core Protocol

```swift
public protocol STTService: AnyObject {
    func initialize(modelPath: String?) async throws
    func transcribe(audioData: Data, options: STTOptions) async throws -> STTTranscriptionResult
    func streamTranscribe<S: AsyncSequence>(
        audioStream: S,
        options: STTOptions,
        onPartial: @escaping (String) -> Void
    ) async throws -> STTTranscriptionResult where S.Element == Data

    var isReady: Bool { get }
    var supportsStreaming: Bool { get }
    func cleanup() async
}
```

### Configuration

```swift
public struct STTConfiguration: ComponentConfiguration {
    public var modelId: String
    public var language: String = "en-US"
    public var sampleRate: Int = 16000
    public var enablePunctuation: Bool = true
    public var enableDiarization: Bool = false
    public var enableTimestamps: Bool = false
    public var vocabularyFilter: [String]?
    public var useGPU: Bool = true
}
```

### Output Models

```swift
public struct STTTranscriptionResult {
    public let text: String
    public let confidence: Float?
    public let language: String?
    public let segments: [STTSegment]?
    public let alternatives: [STTAlternative]?
}

public struct STTSegment {
    public let text: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let speakerId: String?
    public let confidence: Float?
}
```

### Available Backends

| Backend | Framework | Format | Features |
|---------|-----------|--------|----------|
| **ONNX Runtime** | `.onnx` | `.onnx` | Batch + streaming, multi-language |
| **WhisperKit** | `.whisperKit` | `.mlmodel` | CoreML optimized, Apple Silicon |

### STT Component

```swift
public final class STTComponent: BaseComponent {
    private var service: STTService?

    public func initialize(with configuration: STTConfiguration) async throws {
        // Get provider from registry
        guard let provider = ModuleRegistry.shared.sttProvider(for: configuration.modelId) else {
            throw STTError.noProviderFound
        }

        // Create and initialize service
        service = provider.createSTTService()
        try await service?.initialize(modelPath: configuration.modelPath)

        eventBus.publish(.componentInitialized(component: "STT"))
    }

    public func transcribe(_ audio: Data, options: STTOptions) async throws -> STTTranscriptionResult {
        guard let service, service.isReady else {
            throw STTError.notInitialized
        }
        return try await service.transcribe(audioData: audio, options: options)
    }
}
```

---

## TTS (Text-to-Speech) Architecture

### Core Protocol

```swift
public protocol TTSService: AnyObject {
    func initialize() async throws
    func synthesize(text: String, options: TTSOptions) async throws -> Data
    func synthesizeStream(
        text: String,
        options: TTSOptions,
        onChunk: @escaping (Data) -> Void
    ) async throws

    var isSynthesizing: Bool { get }
    var availableVoices: [String] { get }
    func stop()
    func cleanup() async
}
```

### Configuration

```swift
public struct TTSConfiguration: ComponentConfiguration {
    public var voice: String?
    public var language: String = "en-US"
    public var speakingRate: Float = 1.0     // 0.5 - 2.0
    public var pitch: Float = 1.0            // 0.5 - 2.0
    public var volume: Float = 1.0           // 0.0 - 1.0
    public var audioFormat: AudioFormat = .pcmFloat32
    public var useNeuralVoice: Bool = true
    public var enableSSML: Bool = false
}
```

### Output Models

```swift
public struct TTSOutput {
    public let audioData: Data
    public let format: AudioFormat
    public let duration: TimeInterval
    public let sampleRate: Int
    public let phonemeTimestamps: [PhonemeTimestamp]?
}
```

### Available Backends

| Backend | Framework | Features |
|---------|-----------|----------|
| **System TTS** | AVSpeechSynthesizer | Built-in, no download |
| **ONNX Runtime** | `.onnx` | Neural voices, streaming |

### System TTS (Built-in)

```swift
public final class SystemTTSService: TTSService {
    private let synthesizer = AVSpeechSynthesizer()

    public func synthesize(text: String, options: TTSOptions) async throws -> Data {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: options.language)
        utterance.rate = options.rate
        utterance.pitchMultiplier = options.pitch
        utterance.volume = options.volume

        // Capture audio to buffer
        return try await withCheckedThrowingContinuation { continuation in
            synthesizer.write(utterance) { buffer in
                // Convert buffer to Data
            }
        }
    }
}
```

---

## Voice Agent Pipeline

The VoiceAgentComponent orchestrates the full voice AI pipeline:

```
┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐
│   VAD   │ → │   STT   │ → │   LLM   │ → │   TTS   │
│ Detect  │    │Transcribe│   │ Process │    │Synthesize│
│ Speech  │    │  Audio  │    │  Text   │    │  Audio  │
└─────────┘    └─────────┘    └─────────┘    └─────────┘
     ↓              ↓              ↓              ↓
 isSpeech      "Hello"       "Hi there"      [audio]
```

### VoiceAgentComponent

```swift
public final class VoiceAgentComponent: BaseComponent {
    private let vadComponent: VADComponent
    private let sttComponent: STTComponent
    private let llmComponent: LLMComponent
    private let ttsComponent: TTSComponent

    public func process(audioStream: AsyncStream<Data>) async throws {
        for await audioChunk in audioStream {
            // 1. VAD: Check for speech
            let vadResult = try await vadComponent.process(audioChunk)
            if !vadResult.isSpeech { continue }

            // 2. Accumulate audio during speech
            speechBuffer.append(audioChunk)

            // 3. When speech ends, transcribe
            if vadResult.isEndOfSpeech {
                let transcription = try await sttComponent.transcribe(speechBuffer)
                eventBus.publish(.transcriptionComplete(transcription.text))

                // 4. Process with LLM
                let response = try await llmComponent.generate(transcription.text)
                eventBus.publish(.responseGenerated(response))

                // 5. Synthesize response
                let audio = try await ttsComponent.synthesize(response)
                eventBus.publish(.audioGenerated(audio))
            }
        }
    }
}
```

---

## Model Selection & Configuration

### Supported Model Formats

| Format | Extension | Backend |
|--------|-----------|---------|
| ONNX | `.onnx` | ONNX Runtime |
| CoreML | `.mlmodel`, `.mlpackage` | WhisperKit, CoreML |
| GGUF | `.gguf` | LLM.swift (llama.cpp) |
| TFLite | `.tflite` | TensorFlow Lite |

### Model Discovery & Loading

```swift
// List available models
let models = try await RunAnywhere.availableModels()

// Load specific model
try await RunAnywhere.loadModel("whisper-base-onnx")

// Get service for modality
let sttService = ModuleRegistry.shared.sttProvider(for: "whisper-base-onnx")
```

---

## LlamaCPP Integration (LLM.swift)

### Package Dependency

```swift
.package(url: "https://github.com/eastriverlee/LLM.swift", from: "2.0.1")
```

### LLMSwift Adapter

```swift
public final class LLMSwiftAdapter: UnifiedFrameworkAdapter {
    public var framework: LLMFramework { .llamaCpp }
    public var supportedModalities: Set<FrameworkModality> { [.textToText] }
    public var supportedFormats: [ModelFormat] { [.gguf, .ggml] }

    public func createService(for modality: FrameworkModality) -> Any? {
        guard modality == .textToText else { return nil }
        return LLMSwiftService()
    }
}
```

### Quantization Support

Supports 20+ GGUF quantization formats:
- Q2_K, Q3_K_S/M/L
- Q4_0, Q4_1, Q4_K_S/M
- Q5_0, Q5_1, Q5_K_S/M
- Q6_K, Q8_0
- IQ2_XXS/XS, IQ3_S/XXS, IQ4_NL/XS

---

## Future: Adding llama.cpp to Core

When llama.cpp is added to runanywhere-core, the integration will mirror ONNX:

```
runanywhere-core/
├── src/backends/
│   ├── onnx/           # Existing
│   └── llamacpp/       # New backend
│       ├── llamacpp_backend.h
│       └── llamacpp_backend.cpp

Scripts:
├── build-ios-backend.sh llamacpp  # Build XCFramework

Distribution:
└── dist/RunAnywhereLlamaCPP.xcframework
```

Swift SDK consumption:

```swift
.binaryTarget(
    name: "RunAnywhereLlamaCPPBinary",
    url: "https://github.com/.../RunAnywhereLlamaCPP.xcframework.zip",
    checksum: "..."
)
```

---

## Summary

The RunAnywhere Swift SDK provides:

1. **Modular Architecture**: Six separate products for different backends
2. **Provider Pattern**: Pluggable STT/TTS/VAD/LLM implementations
3. **XCFramework Consumption**: Native C++ from runanywhere-core via binary targets
4. **Multi-Backend Support**: ONNX, WhisperKit, llama.cpp, CoreML
5. **Full Voice Pipeline**: VAD → STT → LLM → TTS orchestration
6. **Clean Protocols**: Service interfaces for each capability
7. **Configuration System**: Comprehensive options for each component
