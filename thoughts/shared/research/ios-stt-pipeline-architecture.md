# iOS Speech-to-Text Pipeline Architecture Analysis

## Executive Summary

This document provides a comprehensive analysis of the iOS Speech-to-Text (STT) implementation in the RunAnywhere SDK and sample application. The architecture follows a clean, modular design with event-driven initialization, plugin-based extension, and a provider pattern for different STT implementations. The implementation centers around WhisperKit integration with sophisticated error handling and audio processing optimizations.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Core Components](#core-components)
3. [WhisperKit Integration](#whisperkit-integration)
4. [Audio Pipeline](#audio-pipeline)
5. [Service Registration & Discovery](#service-registration--discovery)
6. [UI Integration Patterns](#ui-integration-patterns)
7. [Event System & Lifecycle](#event-system--lifecycle)
8. [Configuration & Parameters](#configuration--parameters)
9. [Error Handling & Resilience](#error-handling--resilience)
10. [Performance Optimizations](#performance-optimizations)
11. [Implementation Details for IntelliJ Plugin](#implementation-details-for-intellij-plugin)

## Architecture Overview

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    iOS Sample App                               │
├─────────────────────────────────────────────────────────────────┤
│ ChatViewModel │ AudioCapture │ UI Components                    │
├─────────────────────────────────────────────────────────────────┤
│                      RunAnywhere SDK                            │
├─────────────────────────────────────────────────────────────────┤
│ STTComponent │ ModuleRegistry │ EventBus │ ServiceContainer     │
├─────────────────────────────────────────────────────────────────┤
│                   WhisperKit Module                             │
├─────────────────────────────────────────────────────────────────┤
│ WhisperKitServiceProvider │ WhisperKitService │ WhisperKitAdapter│
├─────────────────────────────────────────────────────────────────┤
│                      WhisperKit Framework                       │
└─────────────────────────────────────────────────────────────────┘
```

### Key Design Patterns

1. **Plugin Architecture**: Uses ModuleRegistry for dynamic STT provider registration
2. **Provider Pattern**: STTServiceProvider protocol enables multiple STT implementations
3. **Event-Driven Initialization**: Component lifecycle managed through EventBus
4. **Service Wrapper Pattern**: Protocol-based services wrapped for BaseComponent compatibility
5. **Clean Architecture**: Clear separation between components, services, and adapters

## Core Components

### 1. STTComponent (Main Orchestrator)

**Location**: `Sources/RunAnywhere/Components/STT/STTComponent.swift`

The STTComponent is the primary orchestrator for speech-to-text operations, inheriting from BaseComponent and managing the entire STT lifecycle.

```swift
@MainActor
public final class STTComponent: BaseComponent<STTServiceWrapper> {
    public override class var componentType: SDKComponent { .stt }

    private let sttConfiguration: STTConfiguration
    private var isModelLoaded = false
    private var modelPath: String?
}
```

**Key Responsibilities**:
- Service lifecycle management through provider discovery
- Audio format conversion and validation
- Event publishing for initialization stages
- Error handling and recovery
- Streaming and batch transcription support

**Public API Methods**:
```swift
// Batch transcription
func transcribe(_ audioData: Data, format: AudioFormat = .wav, language: String? = nil) async throws -> STTOutput

// Audio buffer transcription
func transcribe(_ audioBuffer: AVAudioPCMBuffer, language: String? = nil) async throws -> STTOutput

// VAD-aware transcription
func transcribeWithVAD(_ audioData: Data, format: AudioFormat = .wav, vadOutput: VADOutput) async throws -> STTOutput

// Streaming transcription
func streamTranscribe<S: AsyncSequence>(_ audioStream: S, language: String? = nil) -> AsyncThrowingStream<String, Error>
```

### 2. STTHandler (Processing Logic)

**Location**: `Sources/RunAnywhere/Capabilities/Voice/Handlers/STTHandler.swift`

Handles the actual transcription processing with analytics and speaker diarization support.

```swift
public class STTHandler {
    private let voiceAnalytics: VoiceAnalyticsService?
    private let sttAnalytics: STTAnalyticsService?

    public func transcribeAudio(
        samples: [Float],
        service: STTService,
        options: STTOptions,
        speakerDiarization: SpeakerDiarizationService?,
        continuation: AsyncThrowingStream<ModularPipelineEvent, Error>.Continuation
    ) async throws -> String
}
```

**Key Features**:
- Analytics tracking (timing, accuracy, performance)
- Speaker diarization integration
- Audio format conversion utilities
- Error tracking and reporting

### 3. Data Models & Configuration

**STTConfiguration**: Component configuration with validation
```swift
public struct STTConfiguration: ComponentConfiguration, ComponentInitParameters {
    public let modelId: String?
    public let language: String
    public let sampleRate: Int
    public let enablePunctuation: Bool
    public let enableDiarization: Bool
    public let vocabularyList: [String]
    public let maxAlternatives: Int
    public let enableTimestamps: Bool
    public let useGPUIfAvailable: Bool
}
```

**STTOptions**: Transcription request parameters
```swift
public struct STTOptions: Sendable {
    public let language: String
    public let detectLanguage: Bool
    public let enablePunctuation: Bool
    public let enableDiarization: Bool
    public let maxSpeakers: Int?
    public let enableTimestamps: Bool
    public let vocabularyFilter: [String]
    public let audioFormat: AudioFormat
}
```

**STTOutput**: Structured transcription result
```swift
public struct STTOutput: ComponentOutput {
    public let text: String
    public let confidence: Float
    public let wordTimestamps: [WordTimestamp]?
    public let detectedLanguage: String?
    public let alternatives: [TranscriptionAlternative]?
    public let metadata: TranscriptionMetadata
    public let timestamp: Date
}
```

## WhisperKit Integration

### WhisperKit Module Architecture

The WhisperKit integration is implemented as a separate module that registers with the main SDK:

```
WhisperKitTranscription Module
├── WhisperKitServiceProvider (Registration)
├── WhisperKitService (Core Logic)
├── WhisperKitAdapter (Framework Integration)
└── WhisperKitStorageStrategy (Model Management)
```

### 1. WhisperKitServiceProvider (Registration Point)

**Location**: `Modules/WhisperKitTranscription/Sources/WhisperKitTranscription/WhisperKitServiceProvider.swift`

Simple, singleton-based registration pattern:

```swift
public final class WhisperKitServiceProvider: STTServiceProvider {
    public static let shared = WhisperKitServiceProvider()

    // Super simple registration - just call this in your app
    public static func register() {
        Task { @MainActor in
            ModuleRegistry.shared.registerSTT(shared)
        }
    }

    public var name: String { "WhisperKit" }

    public func canHandle(modelId: String?) -> Bool {
        guard let modelId = modelId else { return true }
        let whisperPrefixes = ["whisper", "openai-whisper", "whisper-tiny", "whisper-base", "whisper-small", "whisper-medium", "whisper-large"]
        return whisperPrefixes.contains(where: { modelId.lowercased().contains($0) })
    }

    public func createSTTService(configuration: STTConfiguration) async throws -> STTService {
        let service = WhisperKitService()

        if let modelId = configuration.modelId {
            try await service.initialize(modelPath: modelId)
        } else {
            try await service.initialize(modelPath: nil)
        }

        return service
    }
}
```

### 2. WhisperKitService (Core Implementation)

**Location**: `Modules/WhisperKitTranscription/Sources/WhisperKitTranscription/WhisperKitService.swift`

The core service implementing the STTService protocol with WhisperKit:

```swift
public class WhisperKitService: STTService {
    private var whisperKit: WhisperKit?
    private var isInitialized: Bool = false
    private var currentModelPath: String?

    // Protocol requirements
    public var isReady: Bool { isInitialized && whisperKit != nil }
    public var currentModel: String? { currentModelPath }
}
```

**Initialization Process**:
```swift
public func initialize(modelPath: String?) async throws {
    // Skip if already initialized with same model
    if isInitialized && whisperKit != nil && currentModelPath == (modelPath ?? "whisper-base") {
        return
    }

    let whisperKitModelName = mapModelIdToWhisperKitName(modelPath ?? "whisper-base")

    // Initialize WhisperKit with fallback strategy
    do {
        whisperKit = try await WhisperKit(
            model: whisperKitModelName,
            verbose: true,
            logLevel: .info,
            prewarm: true
        )
    } catch {
        // Fallback to base model
        whisperKit = try await WhisperKit(
            model: "openai_whisper-base",
            verbose: true,
            logLevel: .info,
            prewarm: true
        )
    }

    currentModelPath = modelPath ?? "whisper-base"
    isInitialized = true
}
```

**Model Mapping Strategy**:
```swift
private func mapModelIdToWhisperKitName(_ modelId: String) -> String {
    switch modelId.lowercased() {
    case "whisper-tiny", "tiny":
        return "openai_whisper-tiny"
    case "whisper-base", "base":
        return "openai_whisper-base"
    case "whisper-small", "small":
        return "openai_whisper-small"
    case "whisper-medium", "medium":
        return "openai_whisper-medium"
    case "whisper-large", "large":
        return "openai_whisper-large-v3"
    default:
        return "openai_whisper-base"
    }
}
```

**Transcription Implementation**:
```swift
public func transcribe(audioData: Data, options: STTOptions) async throws -> STTTranscriptionResult {
    // Convert Data to Float array
    let audioSamples = audioData.withUnsafeBytes { buffer in
        Array(buffer.bindMemory(to: Float.self))
    }

    let result = try await transcribeInternal(samples: audioSamples, options: options)

    return STTTranscriptionResult(
        transcript: result.text,
        confidence: result.confidence,
        timestamps: nil,
        language: result.language,
        alternatives: nil
    )
}
```

**Advanced Audio Processing**:
```swift
private func transcribeWithSamples(_ audioSamples: [Float], options: STTOptions, originalDuration: Double) async throws -> STTResult {
    // Conservative decoding options to prevent garbled output
    let noSpeechThresh: Float = audioSamples.count < 32000 ? 0.3 : 0.6  // Adaptive threshold

    let decodingOptions = DecodingOptions(
        task: .transcribe,
        language: "en",  // Force English to avoid detection issues
        temperature: 0.0,  // Conservative temperature
        temperatureFallbackCount: 1,  // Minimal fallbacks
        sampleLength: 224,  // Standard length
        usePrefillPrompt: false,  // Disable prefill
        detectLanguage: false,  // Force English
        skipSpecialTokens: true,  // Clean output
        withoutTimestamps: true,  // Clean text
        compressionRatioThreshold: 2.4,  // Stricter compression
        logProbThreshold: -1.0,  // Conservative log probability
        noSpeechThreshold: noSpeechThresh  // Adaptive threshold
    )

    let transcriptionResults = try await whisperKit.transcribe(
        audioArray: audioSamples,
        decodeOptions: decodingOptions
    )

    // Validate and clean result
    var transcribedText = transcriptionResults.first?.text ?? ""

    if isGarbledOutput(transcribedText) {
        transcribedText = "" // Reject garbled output
    }

    return STTResult(
        text: transcribedText,
        language: transcriptionResults.first?.language ?? options.language,
        confidence: transcribedText.isEmpty ? 0.0 : 0.95,
        duration: originalDuration
    )
}
```

**Garbled Output Detection**:
```swift
private func isGarbledOutput(_ text: String) -> Bool {
    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedText.isEmpty else { return false }

    // Check for common garbled patterns
    let garbledPatterns = [
        "^[\\(\\)\\-\\.\\s]+$",  // Only punctuation and spaces
        "^[\\-]{10,}",          // Many consecutive dashes
        "^[\\(]{5,}",           // Many consecutive parentheses
        "^\\s*\\[.*\\]\\s*$",   // Text wrapped in brackets
        "^\\s*<.*>\\s*$",       // Text wrapped in angle brackets
    ]

    for pattern in garbledPatterns {
        if trimmedText.range(of: pattern, options: .regularExpression) != nil {
            return true
        }
    }

    // Check character composition - if >70% punctuation, likely garbled
    let punctuationCount = trimmedText.filter { $0.isPunctuation }.count
    let totalCount = trimmedText.count
    if totalCount > 5 && Double(punctuationCount) / Double(totalCount) > 0.7 {
        return true
    }

    return false
}
```

### 3. Streaming Support

```swift
public func streamTranscribe<S: AsyncSequence>(
    audioStream: S,
    options: STTOptions,
    onPartial: @escaping (String) -> Void
) async throws -> STTTranscriptionResult where S.Element == Data {
    // Streaming implementation with context preservation
    let minAudioLength = 8000  // 500ms at 16kHz
    let contextOverlap = 1600   // 100ms overlap

    // Process audio stream with buffering and context
    var audioBuffer = Data()
    var lastTranscript = ""

    for await chunk in audioStream {
        audioBuffer.append(chunk)

        if audioBuffer.count >= minAudioLength {
            // Process with context overlap
            let floatArray = audioBuffer.withUnsafeBytes { buffer in
                Array(buffer.bindMemory(to: Float.self))
            }

            let results = try await whisperKit.transcribe(
                audioArray: floatArray,
                decodeOptions: streamingDecodingOptions
            )

            if let result = results.first {
                let newText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !newText.isEmpty && newText != lastTranscript {
                    onPartial(newText)
                    lastTranscript = newText
                }
            }

            // Keep context overlap
            audioBuffer = Data(audioBuffer.suffix(contextOverlap))
        }
    }

    return STTTranscriptionResult(
        transcript: lastTranscript,
        confidence: 0.95,
        timestamps: nil,
        language: options.language,
        alternatives: nil
    )
}
```

## Audio Pipeline

### VoiceAudioChunk (Audio Data Structure)

**Location**: `Sources/RunAnywhere/Public/Models/Voice/AudioChunk.swift`

```swift
public struct VoiceAudioChunk {
    /// The audio samples as Float32 array
    public let samples: [Float]

    /// Timestamp when this chunk was captured
    public let timestamp: TimeInterval

    /// Sample rate of the audio (e.g., 16000 for 16kHz)
    public let sampleRate: Int

    /// Number of channels (1 for mono, 2 for stereo)
    public let channels: Int

    /// Sequence number for ordering chunks
    public let sequenceNumber: Int

    /// Whether this is the final chunk in a stream
    public let isFinal: Bool
}
```

### AudioCapture (Microphone Integration)

**Location**: `RunAnywhereAI/Core/Services/Audio/AudioCapture.swift`

The AudioCapture class handles microphone input and provides audio streams for processing:

```swift
public class AudioCapture: NSObject {
    private var audioEngine: AVAudioEngine?
    private var streamContinuation: AsyncStream<VoiceAudioChunk>.Continuation?
    private var sequenceNumber: Int = 0
    private var audioBuffer: [Float] = []
    private let minBufferSize = 1600 // 0.1 seconds at 16kHz

    public func startContinuousCapture() -> AsyncStream<VoiceAudioChunk> {
        return AsyncStream { continuation in
            self.streamContinuation = continuation

            Task {
                let hasPermission = await AudioCapture.requestMicrophonePermission()
                guard hasPermission else {
                    continuation.finish()
                    return
                }

                try self.startAudioEngine()
                self.isRecording = true
            }
        }
    }
}
```

**Audio Engine Setup**:
```swift
private func startAudioEngine() throws {
    // Configure audio session
    let audioSession = AVAudioSession.sharedInstance()
    try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
    try audioSession.setActive(true)

    audioEngine = AVAudioEngine()
    let inputNode = audioEngine.inputNode
    let inputFormat = inputNode.outputFormat(forBus: 0)

    // Create 16kHz mono format
    let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: 16000,
                                   channels: 1,
                                   interleaved: false)

    // Install tap with conversion
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
        self?.processAudioBuffer(buffer)
    }

    try audioEngine.start()
}
```

**Audio Processing Pipeline**:
```swift
private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
    guard let channelData = buffer.floatChannelData else { return }

    let frameLength = Int(buffer.frameLength)
    let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))

    audioBuffer.append(contentsOf: samples)

    // Send chunks of audio data (100ms chunks = 1600 samples at 16kHz)
    while audioBuffer.count >= minBufferSize {
        let chunkSamples = Array(audioBuffer.prefix(minBufferSize))
        audioBuffer.removeFirst(minBufferSize)

        let chunk = VoiceAudioChunk(
            samples: chunkSamples,
            timestamp: Date().timeIntervalSince1970,
            sampleRate: 16000,
            channels: 1,
            sequenceNumber: sequenceNumber,
            isFinal: false
        )

        sequenceNumber += 1
        streamContinuation?.yield(chunk)
    }
}
```

## Service Registration & Discovery

### ModuleRegistry (Plugin System)

**Location**: `Sources/RunAnywhere/Core/ModuleRegistry.swift`

The ModuleRegistry provides a central plugin system for registering STT providers:

```swift
@MainActor
public final class ModuleRegistry {
    public static let shared = ModuleRegistry()

    private var sttProviders: [STTServiceProvider] = []

    /// Register a Speech-to-Text provider (e.g., WhisperKit)
    public func registerSTT(_ provider: STTServiceProvider) {
        sttProviders.append(provider)
        print("[ModuleRegistry] Registered STT provider: \(provider.name)")
    }

    /// Get an STT provider for the specified model
    public func sttProvider(for modelId: String? = nil) -> STTServiceProvider? {
        if let modelId = modelId {
            return sttProviders.first { $0.canHandle(modelId: modelId) }
        }
        return sttProviders.first
    }

    public var hasSTT: Bool { !sttProviders.isEmpty }
}
```

### STTServiceProvider Protocol

```swift
public protocol STTServiceProvider {
    /// Create an STT service for the given configuration
    func createSTTService(configuration: STTConfiguration) async throws -> STTService

    /// Check if this provider can handle the given model
    func canHandle(modelId: String?) -> Bool

    /// Provider name for identification
    var name: String { get }
}
```

### Registration in iOS App

**Location**: `RunAnywhereAI/App/RunAnywhereAIApp.swift`

```swift
private func initializeSDK() async {
    do {
        // Register WhisperKit for Speech-to-Text
        WhisperKitServiceProvider.register()
        logger.info("✅ WhisperKit registered for Speech-to-Text")

        // Initialize the SDK
        try await RunAnywhere.initialize(
            apiKey: "demo-api-key",
            baseURL: "https://api.runanywhere.ai",
            environment: .development
        )

        isSDKInitialized = true
    } catch {
        logger.error("❌ SDK initialization failed: \(error)")
        initializationError = error
    }
}
```

## UI Integration Patterns

### ChatViewModel Integration

The ChatViewModel doesn't directly use STT but demonstrates the event-driven pattern for SDK interaction:

```swift
@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var isGenerating = false
    @Published var currentInput = ""

    func sendMessage() async {
        guard canSend else { return }

        let prompt = currentInput
        currentInput = ""
        isGenerating = true

        let userMessage = Message(role: .user, content: prompt)
        messages.append(userMessage)

        // Create assistant message for streaming updates
        let assistantMessage = Message(role: .assistant, content: "")
        messages.append(assistantMessage)
        let messageIndex = messages.count - 1

        // Use SDK streaming generation
        let stream = RunAnywhere.generateStream(prompt, options: options)

        for try await token in stream {
            // Update message with streaming tokens
            messages[messageIndex] = Message(
                role: .assistant,
                content: messages[messageIndex].content + token,
                timestamp: messages[messageIndex].timestamp
            )
        }

        isGenerating = false
    }
}
```

### Voice Input Integration Pattern

While not directly shown in the current codebase, voice input would follow this pattern:

```swift
// Voice input integration pattern (conceptual)
class VoiceInputViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var transcribedText = ""

    private var audioCapture = AudioCapture()
    private var sttComponent: STTComponent?

    func startVoiceInput() async {
        guard let stt = try? await createSTTComponent() else { return }

        isRecording = true
        let audioStream = audioCapture.startContinuousCapture()

        let transcriptionStream = stt.streamTranscribe(audioStream, language: "en")

        for try await partialText in transcriptionStream {
            await MainActor.run {
                transcribedText = partialText
            }
        }
    }

    private func createSTTComponent() async throws -> STTComponent {
        let config = STTConfiguration(
            modelId: "whisper-base",
            language: "en-US",
            sampleRate: 16000,
            enablePunctuation: true
        )

        let component = STTComponent(configuration: config)
        try await component.initialize()
        return component
    }
}
```

## Event System & Lifecycle

### EventBus Architecture

The SDK uses a centralized EventBus for component communication:

```swift
public class EventBus {
    public static let shared = EventBus()

    private let eventSubject = PassthroughSubject<Event, Never>()

    public func publish<T: Event>(_ event: T) {
        eventSubject.send(event)
    }

    public func subscribe<T: Event>(to eventType: T.Type) -> AnyPublisher<T, Never> {
        eventSubject
            .compactMap { $0 as? T }
            .eraseToAnyPublisher()
    }
}
```

### Component Initialization Events

```swift
public enum ComponentInitializationEvent: Event {
    case componentChecking(component: SDKComponent, modelId: String?)
    case componentInitializing(component: SDKComponent, modelId: String?)
    case componentReady(component: SDKComponent, modelId: String?)
    case componentFailed(component: SDKComponent, error: Error)
    case componentDownloadStarted(component: SDKComponent, modelId: String)
    case componentDownloadProgress(component: SDKComponent, modelId: String, progress: Double)
    case componentDownloadCompleted(component: SDKComponent, modelId: String)
}
```

### BaseComponent Lifecycle

```swift
@MainActor
open class BaseComponent<TService: AnyObject>: Component {
    public private(set) var state: ComponentState = .notInitialized

    public func initialize() async throws {
        guard state == .notInitialized else {
            if state == .ready { return }
            throw SDKError.invalidState("Cannot initialize from state: \(state)")
        }

        updateState(.initializing)

        do {
            // Stage: Validation
            eventBus.publish(ComponentInitializationEvent.componentChecking(
                component: Self.componentType, modelId: nil
            ))
            try configuration.validate()

            // Stage: Service Creation
            eventBus.publish(ComponentInitializationEvent.componentInitializing(
                component: Self.componentType, modelId: nil
            ))
            service = try await createService()

            // Stage: Service Initialization
            try await initializeService()

            updateState(.ready)
            eventBus.publish(ComponentInitializationEvent.componentReady(
                component: Self.componentType, modelId: nil
            ))
        } catch {
            updateState(.failed)
            eventBus.publish(ComponentInitializationEvent.componentFailed(
                component: Self.componentType, error: error
            ))
            throw error
        }
    }
}
```

## Configuration & Parameters

### STT Configuration Hierarchy

```swift
// Base configuration protocol
public protocol ComponentConfiguration: Sendable {
    func validate() throws
}

// STT-specific configuration
public struct STTConfiguration: ComponentConfiguration {
    public let modelId: String?           // WhisperKit model identifier
    public let language: String           // Target language (e.g., "en-US")
    public let sampleRate: Int           // Audio sample rate (16000)
    public let enablePunctuation: Bool    // Add punctuation to output
    public let enableDiarization: Bool    // Enable speaker identification
    public let vocabularyList: [String]   // Custom vocabulary
    public let maxAlternatives: Int       // Number of alternative transcriptions
    public let enableTimestamps: Bool     // Include word-level timestamps
    public let useGPUIfAvailable: Bool    // Use GPU acceleration

    public func validate() throws {
        guard sampleRate > 0 && sampleRate <= 48000 else {
            throw SDKError.validationFailed("Sample rate must be between 1 and 48000 Hz")
        }
        guard maxAlternatives > 0 && maxAlternatives <= 10 else {
            throw SDKError.validationFailed("Max alternatives must be between 1 and 10")
        }
    }
}

// Request-time options
public struct STTOptions: Sendable {
    public let language: String
    public let detectLanguage: Bool
    public let enablePunctuation: Bool
    public let enableDiarization: Bool
    public let maxSpeakers: Int?
    public let enableTimestamps: Bool
    public let vocabularyFilter: [String]
    public let audioFormat: AudioFormat
}
```

### Audio Format Support

```swift
public enum AudioFormat {
    case wav
    case mp3
    case pcm
    case flac
    case m4a
    case aac
}

// Service audio format preferences
public enum STTServiceAudioFormat {
    case data       // Service prefers raw Data
    case floatArray // Service prefers Float array samples
}
```

## Error Handling & Resilience

### STT Error Taxonomy

```swift
public enum STTError: LocalizedError {
    case serviceNotInitialized
    case transcriptionFailed(Error)
    case streamingNotSupported
    case languageNotSupported(String)
    case modelNotFound(String)
    case audioFormatNotSupported
    case insufficientAudioData
    case noVoiceServiceAvailable
    case audioSessionNotConfigured
    case audioSessionActivationFailed
    case microphonePermissionDenied

    public var errorDescription: String? {
        switch self {
        case .serviceNotInitialized:
            return "STT service is not initialized"
        case .transcriptionFailed(let error):
            return "Transcription failed: \(error.localizedDescription)"
        case .streamingNotSupported:
            return "Streaming transcription is not supported"
        case .languageNotSupported(let language):
            return "Language not supported: \(language)"
        case .modelNotFound(let model):
            return "Model not found: \(model)"
        case .audioFormatNotSupported:
            return "Audio format is not supported"
        case .insufficientAudioData:
            return "Insufficient audio data for transcription"
        case .noVoiceServiceAvailable:
            return "No STT service available for transcription"
        case .audioSessionNotConfigured:
            return "Audio session is not configured"
        case .audioSessionActivationFailed:
            return "Failed to activate audio session"
        case .microphonePermissionDenied:
            return "Microphone permission was denied"
        }
    }
}
```

### Resilience Patterns

1. **Graceful Degradation**: Fall back to base model if specific model fails
2. **Audio Validation**: Check audio quality before processing
3. **Garbled Output Detection**: Reject nonsensical transcription results
4. **Service Recovery**: Reinitialize services after failures
5. **Permission Handling**: Graceful microphone permission management

## Performance Optimizations

### WhisperKit Optimizations

1. **Prewarm Models**: Initialize WhisperKit with `prewarm: true`
2. **Conservative Decoding**: Use optimal parameters to prevent garbled output
3. **Adaptive Thresholds**: Adjust silence detection based on audio length
4. **Context Preservation**: Maintain audio overlap for streaming accuracy
5. **Memory Management**: Cache services with smart cleanup

### Audio Processing Optimizations

1. **Efficient Buffer Management**: Use 100ms chunks for optimal latency
2. **Format Conversion**: Convert to 16kHz mono for consistency
3. **Sample Rate Adaptation**: Handle various input sample rates
4. **Memory-Efficient Streaming**: Process audio in chunks without accumulation

### Caching Strategy

```swift
// Service caching in WhisperKitAdapter
private var cachedWhisperKitService: WhisperKitService?
private var lastWhisperKitUsage: Date?
private let cacheTimeout: TimeInterval = 300 // 5 minutes

private func cleanupStaleCache() {
    if let lastUsage = lastWhisperKitUsage {
        let timeSinceLastUsage = Date().timeIntervalSince(lastUsage)
        if timeSinceLastUsage > cacheTimeout {
            Task {
                await cachedWhisperKitService?.cleanup()
                cachedWhisperKitService = nil
                lastWhisperKitUsage = nil
            }
        }
    }
}
```

## Implementation Details for IntelliJ Plugin

### Key Translation Points for JVM/Kotlin

1. **Replace WhisperKit with WhisperJNI**:
   - Map WhisperKit models to WhisperJNI model paths
   - Implement similar audio processing pipeline
   - Use Kotlin coroutines instead of Swift async/await

2. **Audio Capture Translation**:
   ```kotlin
   // Replace AVAudioEngine with javax.sound.sampled
   class AudioCapture {
       private var audioFormat: AudioFormat = AudioFormat(16000f, 16, 1, true, false)
       private var targetDataLine: TargetDataLine?
       private var audioInputStream: AudioInputStream?

       fun startContinuousCapture(): Flow<VoiceAudioChunk> = channelFlow {
           val line = AudioSystem.getLine(DataLine.Info(TargetDataLine::class.java, audioFormat)) as TargetDataLine
           line.open(audioFormat, 4096)
           line.start()

           val buffer = ByteArray(1600 * 4) // 100ms at 16kHz, 4 bytes per float

           while (isActive) {
               val bytesRead = line.read(buffer, 0, buffer.size)
               if (bytesRead > 0) {
                   val samples = buffer.toFloatArray()
                   val chunk = VoiceAudioChunk(
                       samples = samples,
                       timestamp = System.currentTimeMillis() / 1000.0,
                       sampleRate = 16000,
                       channels = 1,
                       sequenceNumber = sequenceNumber++,
                       isFinal = false
                   )
                   send(chunk)
               }
           }
       }
   }
   ```

3. **Service Provider Implementation**:
   ```kotlin
   class WhisperJNIServiceProvider : STTServiceProvider {
       companion object {
           fun register() {
               ModuleRegistry.registerSTT(WhisperJNIServiceProvider())
           }
       }

       override val name: String = "WhisperJNI"

       override fun canHandle(modelId: String?): Boolean {
           return modelId == null || modelId.contains("whisper", ignoreCase = true)
       }

       override suspend fun createSTTService(configuration: STTConfiguration): STTService {
           val service = WhisperJNIService()
           service.initialize(configuration.modelId)
           return service
       }
   }
   ```

4. **Event Bus Translation**:
   ```kotlin
   object EventBus {
       private val _events = MutableSharedFlow<Event>()
       val events: SharedFlow<Event> = _events.asSharedFlow()

       fun publish(event: Event) {
           _events.tryEmit(event)
       }

       inline fun <reified T : Event> subscribe(): Flow<T> {
           return events.filterIsInstance<T>()
       }
   }
   ```

5. **Model Mapping for WhisperJNI**:
   ```kotlin
   private fun mapModelIdToWhisperJNIPath(modelId: String): String {
       return when (modelId.lowercase()) {
           "whisper-tiny", "tiny" -> "models/ggml-tiny.bin"
           "whisper-base", "base" -> "models/ggml-base.bin"
           "whisper-small", "small" -> "models/ggml-small.bin"
           "whisper-medium", "medium" -> "models/ggml-medium.bin"
           "whisper-large", "large" -> "models/ggml-large-v3.bin"
           else -> "models/ggml-base.bin"
       }
   }
   ```

### Architecture Mapping

```
iOS Architecture              →  IntelliJ Plugin Architecture
─────────────────────────────────────────────────────────────
WhisperKit Framework         →  WhisperJNI Library
AVAudioEngine                →  javax.sound.sampled
Swift Async/Await            →  Kotlin Coroutines
@MainActor                   →  Dispatchers.Main
AsyncStream                  →  Flow/Channel
PassthroughSubject           →  MutableSharedFlow
Foundation Types             →  Kotlin Standard Library
```

### Critical Implementation Notes

1. **Thread Safety**: Use `Dispatchers.Main` for UI updates, `Dispatchers.IO` for audio processing
2. **Memory Management**: Implement proper cleanup for audio resources and JNI references
3. **Error Handling**: Map Swift errors to Kotlin exceptions with proper localization
4. **Configuration**: Store STT settings in IntelliJ's persistent state system
5. **Model Management**: Implement model downloading and caching using IntelliJ's PathManager
6. **Integration**: Hook into IntelliJ's action system and editor APIs for voice input

This architecture provides a solid foundation for implementing STT functionality in the IntelliJ plugin while maintaining the same clean separation of concerns and extensibility as the iOS implementation.
