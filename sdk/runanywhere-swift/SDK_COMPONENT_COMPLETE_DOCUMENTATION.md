# RunAnywhere Swift SDK - Complete Component Documentation

This document provides exhaustive documentation of every component in the RunAnywhere Swift SDK, including all public APIs, models, implementations, pipeline usage, and related files.

## Table of Contents

1. [VADComponent (Voice Activity Detection)](#vadcomponent-voice-activity-detection)
2. [STTComponent (Speech-to-Text)](#sttcomponent-speech-to-text)
3. [LLMComponent (Language Model)](#llmcomponent-language-model)
4. [TTSComponent (Text-to-Speech)](#ttscomponent-text-to-speech)
5. [SpeakerDiarizationComponent](#speakerdiarizationcomponent)
6. [VoiceAgentComponent (Composite)](#voiceagentcomponent-composite)
7. [Pipeline System](#pipeline-system)
8. [Base Component Architecture](#base-component-architecture)
9. [Adapter System](#adapter-system)
10. [Missing Components](#missing-components)

---

## VADComponent (Voice Activity Detection)

### Purpose
Detects when speech is present in audio streams using energy-based detection with hysteresis to prevent rapid on/off switching.

### Complete File List
```
Components:
├── Sources/RunAnywhere/Components/VAD/VADComponent.swift

Protocols & Models:
├── Sources/RunAnywhere/Core/Protocols/Voice/VADService.swift

Implementations:
├── Sources/RunAnywhere/Capabilities/Voice/Strategies/VAD/SimpleEnergyVAD.swift

Pipeline Usage:
├── Sources/RunAnywhere/Public/RunAnywherePipelines.swift
├── Sources/RunAnywhere/Public/RunAnywhere+Pipelines.swift
├── Sources/RunAnywhere/Components/VoiceAgent/VoiceAgentComponent.swift
```

### Public APIs

#### Component Class
```swift
@MainActor
public final class VADComponent: BaseComponent, @unchecked Sendable {
    // Properties
    public override class var componentType: SDKComponent { .vad }

    // Public Methods
    public func getService() -> VADService?
    public override func initialize(with parameters: any ComponentInitParameters) async throws
    public override func cleanup() async throws
}
```

#### Initialization Parameters
```swift
public struct VADInitParameters: ComponentInitParameters {
    public let componentType = SDKComponent.vad
    public let modelId: String? = nil

    // Configuration
    public let energyThreshold: Float      // 0.0 to 1.0, default: 0.01
    public let sampleRate: Int            // Hz, default: 16000
    public let frameLength: Int           // samples, default: 320
    public let bufferSize: Int            // frames, default: 10
    public let silenceThreshold: Int      // frames of silence, default: 10

    // Validation
    public func validate() throws {
        guard energyThreshold >= 0 && energyThreshold <= 1.0 else {
            throw SDKError.validationFailed("Energy threshold must be between 0 and 1.0")
        }
        guard sampleRate > 0 && sampleRate <= 48000 else {
            throw SDKError.validationFailed("Sample rate must be between 1 and 48000 Hz")
        }
        guard frameLength > 0 && frameLength <= sampleRate else {
            throw SDKError.validationFailed("Frame length must be between 1 and sample rate")
        }
    }
}
```

#### Service Protocol
```swift
public protocol VADService: AnyObject {
    // Initialization
    func initialize() async throws

    // Voice Detection
    func processAudioData(_ audioData: [Float]) -> Bool

    // State Management
    func reset()
    var isSpeechActive: Bool { get }

    // Configuration
    var energyThreshold: Float { get set }
    var sampleRate: Int { get }
    var frameLength: Float { get }

    // Event Handling
    var onSpeechActivity: ((SpeechActivityEvent) -> Void)? { get set }
}

public enum SpeechActivityEvent {
    case started
    case ended
}
```

### Implementation Details

#### SimpleEnergyVAD
```swift
public class SimpleEnergyVAD: NSObject, VADService {
    // Core Properties
    public var energyThreshold: Float = 0.022
    public let sampleRate: Int
    public let frameLengthSamples: Int

    // State Tracking
    private var isActive = false
    private var isCurrentlySpeaking = false
    private var consecutiveSilentFrames = 0
    private var consecutiveVoiceFrames = 0

    // Hysteresis Parameters
    private let voiceStartThreshold = 2   // frames of voice to start
    private let voiceEndThreshold = 10    // frames of silence to end

    // Public Methods
    public func processAudioBuffer(_ buffer: AVAudioPCMBuffer)
    public func processAudioData(_ audioData: [Float]) -> Bool

    // Energy Calculation (RMS)
    private func calculateAverageEnergy(of signal: [Float]) -> Float {
        var rmsEnergy: Float = 0.0
        vDSP_rmsqv(signal, 1, &rmsEnergy, vDSP_Length(signal.count))
        return rmsEnergy
    }
}
```

### Pipeline Integration

#### TranscriptionPipeline Usage
```swift
public final class TranscriptionPipeline: Pipeline {
    private var vadComponent: VADComponent?

    public func initialize() async throws {
        let vadParams = VADInitParameters(
            energyThreshold: config.vadSensitivity,
            silenceThreshold: 500
        )
        vadComponent = VADComponent()
        try await vadComponent?.initialize(with: vadParams)
    }

    public func processAudio(_ audioStream: AsyncStream<Data>) async throws -> AsyncStream<TranscriptionResult> {
        if let vad = vadComponent?.getService() {
            let vadResult = try await vad.detectSpeech(in: audio)
            if vadResult.isSpeech {
                eventSubject.continuation.yield(.speechStarted)
                // Process with STT...
            } else if vadResult.endOfSpeech {
                eventSubject.continuation.yield(.speechEnded)
            }
        }
    }
}
```

#### VoiceAgentComponent Integration
```swift
public final class VoiceAgentComponent: BaseComponent {
    public private(set) var vadComponent: VADComponent?

    public override func initialize(with parameters: any ComponentInitParameters) async throws {
        guard let voiceParams = parameters as? VoiceAgentInitParameters else {
            throw SDKError.validationFailed("Invalid parameters")
        }

        vadComponent = VADComponent()
        try await vadComponent?.initialize(with: voiceParams.vadParameters)
    }
}
```

### Issues & Recommendations
- **❌ Pattern Inconsistency**: Uses direct `SimpleEnergyVAD` creation instead of adapter registry
- **❌ Missing VADResult**: Protocol references `VADResult` but it's not defined in VADService.swift
- **Recommendation**: Adopt adapter registry pattern like STT/LLM components

---

## STTComponent (Speech-to-Text)

### Purpose
Converts spoken audio into text transcription with optional speaker diarization, punctuation, and language detection.

### Complete File List
```
Components:
├── Sources/RunAnywhere/Components/STT/STTComponent.swift

Protocols & Models:
├── Sources/RunAnywhere/Core/Protocols/Voice/SpeechToTextService.swift

Handlers:
├── Sources/RunAnywhere/Capabilities/Voice/Handlers/STTHandler.swift

Pipeline Usage:
├── Sources/RunAnywhere/Public/RunAnywherePipelines.swift
├── Sources/RunAnywhere/Public/RunAnywhere+Pipelines.swift
├── Sources/RunAnywhere/Components/VoiceAgent/VoiceAgentComponent.swift
```

### Public APIs

#### Component Class
```swift
@MainActor
public final class STTComponent: BaseComponent, @unchecked Sendable {
    // Properties
    public override class var componentType: SDKComponent { .stt }

    // Public Methods
    public func getService() -> STTService?
    public override func initialize(with parameters: any ComponentInitParameters) async throws
    public override func cleanup() async throws
}
```

#### Initialization Parameters
```swift
public struct STTInitParameters: ComponentInitParameters {
    public let componentType = SDKComponent.stt
    public let modelId: String?

    // Configuration
    public let language: String              // default: "en-US"
    public let sampleRate: Int              // default: 16000
    public let enablePunctuation: Bool      // default: true
    public let enableDiarization: Bool      // default: false
    public let maxSpeakers: Int?            // optional
    public let enableTimestamps: Bool       // default: true
    public let vocabularyFilter: [String]   // default: []
    public let maxAlternatives: Int         // default: 1

    // Validation
    public func validate() throws {
        guard sampleRate > 0 && sampleRate <= 48000 else {
            throw SDKError.validationFailed("Sample rate must be between 1 and 48000")
        }
        guard maxAlternatives > 0 && maxAlternatives <= 10 else {
            throw SDKError.validationFailed("Max alternatives must be between 1 and 10")
        }
    }
}
```

#### Service Protocol
```swift
public protocol STTService: AnyObject {
    // Initialization
    func initialize() async throws

    // Transcription Methods
    func transcribe(audio: Data, options: STTOptions) async throws -> STTResult
    func transcribe(samples: [Float], options: STTOptions) async throws -> STTResult
    func streamTranscribe(audioStream: AsyncStream<Data>, options: STTOptions) -> AsyncThrowingStream<STTResult, Error>

    // Configuration
    var preferredAudioFormat: AudioInputFormat { get }
    var supportedLanguages: [String] { get }
    var isInitialized: Bool { get }

    // Cleanup
    func cleanup() async
}
```

#### Options & Results
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

public struct STTResult: Sendable {
    public let text: String
    public let confidence: Float
    public let segments: [STTSegment]
    public let language: String?
    public let alternatives: [STTAlternative]
    public let processingTime: TimeInterval
    public let speaker: SpeakerInfo?        // For diarization
}

public struct STTSegment: Sendable {
    public let text: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let confidence: Float
    public let speaker: SpeakerInfo?
}

public struct STTAlternative: Sendable {
    public let text: String
    public let confidence: Float
}
```

### Implementation Pattern

#### Adapter Registry Integration (CORRECT PATTERN)
```swift
public override func initialize(with parameters: any ComponentInitParameters) async throws {
    guard let sttParams = parameters as? STTInitParameters else {
        throw SDKError.validationFailed("Invalid parameters type for STT component")
    }

    try await super.initialize(with: parameters)

    guard let container = serviceContainer else {
        throw SDKError.notInitialized
    }

    // ✅ USES ADAPTER REGISTRY
    let frameworks = container.adapterRegistry.getFrameworks(for: .voiceToText)
    guard let framework = frameworks.first,
          let adapter = container.adapterRegistry.getAdapter(for: framework) else {
        throw SDKError.validationFailed("No STT adapter available")
    }

    let hardwareConfig = HardwareConfiguration()
    await adapter.configure(with: hardwareConfig)

    guard let service = try await adapter.initializeComponent(
        with: sttParams,
        for: .voiceToText
    ) as? STTService else {
        throw SDKError.validationFailed("Adapter did not return STTService")
    }
    sttService = service

    await transitionTo(state: .ready)
}
```

### Handler Implementation

#### STTHandler
```swift
public class STTHandler {
    private let logger = SDKLogger(category: "STTHandler")

    public func processTranscription(
        samples: [Float],
        stt: STTService?,
        config: STTInitParameters?,
        speakerDiarization: SpeakerDiarizationService?,
        continuation: AsyncThrowingStream<ModularPipelineEvent, Error>.Continuation
    ) async throws -> String {

        let options = STTOptions(
            language: config?.language ?? "en",
            detectLanguage: false,
            enablePunctuation: config?.enablePunctuation ?? true,
            enableDiarization: config?.enableDiarization ?? false
        )

        let result = try await performTranscription(
            samples: samples,
            service: stt!,
            options: options
        )

        if options.enableDiarization && speakerDiarization != nil {
            handleSpeakerDiarization(
                samples: samples,
                transcript: result.text,
                service: speakerDiarization!,
                continuation: continuation
            )
        }

        return result.text
    }
}
```

### Pipeline Integration

#### TranscriptionPipeline
```swift
private var sttComponent: STTComponent?

public func initialize() async throws {
    let sttParams = STTInitParameters(
        language: config.language,
        enablePunctuation: config.punctuationEnabled,
        enableDiarization: config.enableDiarization
    )
    sttComponent = STTComponent()
    try await sttComponent?.initialize(with: sttParams)
}
```

### Status
✅ **Complete**: Follows adapter registry pattern correctly
✅ **Consolidated**: All types in single SpeechToTextService.swift file

---

## LLMComponent (Language Model)

### Purpose
Processes text through language models for generation, completion, and conversational AI with streaming support.

### Complete File List
```
Components:
├── Sources/RunAnywhere/Components/LLM/LLMComponent.swift

Protocols & Models:
├── Sources/RunAnywhere/Core/Protocols/LLM/LLMService.swift

Handlers:
├── Sources/RunAnywhere/Capabilities/Voice/Handlers/VoiceLLMHandler.swift

Pipeline Usage:
├── Sources/RunAnywhere/Public/RunAnywherePipelines.swift
├── Sources/RunAnywhere/Public/RunAnywhere+Pipelines.swift
├── Sources/RunAnywhere/Components/VoiceAgent/VoiceAgentComponent.swift
```

### Public APIs

#### Component Class
```swift
@MainActor
public final class LLMComponent: BaseComponent, @unchecked Sendable {
    // Properties
    public override class var componentType: SDKComponent { .llm }

    // Public Methods
    public func getService() -> LLMService?
    public override func initialize(with parameters: any ComponentInitParameters) async throws
    public override func cleanup() async throws
}
```

#### Initialization Parameters
```swift
public struct LLMInitParameters: ComponentInitParameters {
    public let componentType = SDKComponent.llm
    public let modelId: String?

    // Model Configuration
    public let contextLength: Int              // default: 2048
    public let useGPUIfAvailable: Bool        // default: true
    public let quantizationLevel: QuantizationLevel?
    public let cacheSize: Int                 // MB, default: 100
    public let preloadContext: String?        // System prompt to preload

    // Generation Defaults
    public let temperature: Double             // default: 0.7
    public let maxTokens: Int                 // default: 100
    public let systemPrompt: String?
    public let streamingEnabled: Bool         // default: true

    public enum QuantizationLevel: String, Sendable {
        case q4_0 = "Q4_0"
        case q4_k_m = "Q4_K_M"
        case q5_k_m = "Q5_K_M"
        case q6_k = "Q6_K"
        case q8_0 = "Q8_0"
        case f16 = "F16"
        case f32 = "F32"
    }

    // Validation
    public func validate() throws {
        guard contextLength > 0 && contextLength <= 32768 else {
            throw SDKError.validationFailed("Context length must be between 1 and 32768")
        }
        guard cacheSize >= 0 && cacheSize <= 1000 else {
            throw SDKError.validationFailed("Cache size must be between 0 and 1000 MB")
        }
    }
}
```

#### Service Protocol
```swift
public protocol LLMService: AnyObject {
    // Initialization
    func initialize(modelPath: String?) async throws

    // Generation Methods
    func generate(
        prompt: String,
        options: RunAnywhereGenerationOptions
    ) async throws -> String

    func streamGenerate(
        prompt: String,
        options: RunAnywhereGenerationOptions,
        onToken: @escaping (String) -> Void
    ) async throws

    // State
    var isReady: Bool { get }
    var currentModel: String? { get }

    // Cleanup
    func cleanup() async
}
```

#### Generation Options
```swift
public struct RunAnywhereGenerationOptions {
    public let maxTokens: Int
    public let temperature: Float
    public let topP: Float
    public let topK: Int
    public let repetitionPenalty: Float
    public let stopTokens: [String]
    public let systemPrompt: String?
    public let responseFormat: ResponseFormat?
}
```

#### Error Types
```swift
public enum LLMServiceError: LocalizedError {
    case notInitialized
    case modelNotFound(String)
    case generationFailed(Error)
    case streamingNotSupported
    case contextLengthExceeded
    case invalidOptions
}
```

### Implementation Pattern

#### Adapter Registry Integration (FIXED)
```swift
public override func initialize(with parameters: any ComponentInitParameters) async throws {
    guard let llmParams = parameters as? LLMInitParameters else {
        throw SDKError.validationFailed("Invalid parameters type for LLM component")
    }

    try await super.initialize(with: parameters)

    guard let container = serviceContainer else {
        throw SDKError.notInitialized
    }

    // ✅ NOW USES ADAPTER REGISTRY (was using non-existent frameworkService)
    let frameworks = container.adapterRegistry.getFrameworks(for: .textToText)
    guard let framework = frameworks.first,
          let adapter = container.adapterRegistry.getAdapter(for: framework) else {
        throw SDKError.validationFailed("No LLM adapter available")
    }

    let hardwareConfig = HardwareConfiguration()
    await adapter.configure(with: hardwareConfig)

    guard let service = try await adapter.initializeComponent(
        with: llmParams,
        for: .textToText
    ) as? LLMService else {
        throw SDKError.validationFailed("Adapter did not return LLMService")
    }
    llmService = service

    await transitionTo(state: .ready)
}
```

### Handler Implementation

#### VoiceLLMHandler
```swift
public class VoiceLLMHandler {
    public func processWithLLM(
        transcript: String,
        llmService: LLMService?,
        config: LLMInitParameters?,
        streamingTTSHandler: StreamingTTSHandler?,
        ttsEnabled: Bool,
        ttsConfig: TTSInitParameters?,
        continuation: AsyncThrowingStream<ModularPipelineEvent, Error>.Continuation
    ) async throws -> String {

        continuation.yield(.llmThinking)

        let options = RunAnywhereGenerationOptions(
            maxTokens: config?.maxTokens ?? 100,
            temperature: Float(config?.temperature ?? 0.7),
            systemPrompt: config?.systemPrompt
        )

        if config?.streamingEnabled ?? true {
            return try await streamGenerate(
                transcript: transcript,
                llmService: llmService!,
                options: options,
                streamingTTSHandler: streamingTTSHandler,
                ttsEnabled: ttsEnabled,
                ttsConfig: ttsConfig,
                continuation: continuation
            )
        } else {
            return try await generateNonStreaming(
                transcript: transcript,
                llmService: llmService,
                options: options,
                continuation: continuation
            )
        }
    }
}
```

### Pipeline Integration

#### LocalLLMPipeline
```swift
public final class LocalLLMPipeline: Pipeline {
    private var llmComponent: LLMComponent?

    public func initialize() async throws {
        let llmParams = LLMInitParameters(
            modelId: config.modelId,
            temperature: config.temperature,
            maxTokens: config.maxTokens,
            systemPrompt: config.systemPrompt,
            streamingEnabled: config.streamingEnabled
        )

        llmComponent = LLMComponent()
        try await llmComponent?.initialize(with: llmParams)
    }

    public func generate(_ prompt: String) async throws -> String {
        guard let llm = llmComponent?.getService() else {
            throw SDKError.componentNotInitialized("LLM")
        }

        let options = RunAnywhereGenerationOptions(
            maxTokens: config.maxTokens,
            temperature: Float(config.temperature),
            systemPrompt: config.systemPrompt
        )

        return try await llm.generate(prompt: prompt, options: options)
    }
}
```

### Status
✅ **Fixed**: Now uses adapter registry pattern correctly
✅ **Complete**: Error types and service protocol defined

---

## TTSComponent (Text-to-Speech)

### Purpose
Converts text into synthesized speech with configurable voices, languages, and audio parameters.

### Complete File List
```
Components:
├── Sources/RunAnywhere/Components/TTS/TTSComponent.swift

Protocols & Models:
├── Sources/RunAnywhere/Core/Protocols/Voice/TextToSpeechService.swift

Handlers:
├── Sources/RunAnywhere/Capabilities/Voice/Handlers/StreamingTTSHandler.swift

Pipeline Usage:
├── Sources/RunAnywhere/Public/RunAnywherePipelines.swift
├── Sources/RunAnywhere/Components/VoiceAgent/VoiceAgentComponent.swift
```

### Public APIs

#### Component Class
```swift
@MainActor
public final class TTSComponent: BaseComponent, @unchecked Sendable {
    // Properties
    public override class var componentType: SDKComponent { .tts }

    // Public Methods
    public func getService() -> TextToSpeechService?
    public override func initialize(with parameters: any ComponentInitParameters) async throws
    public override func cleanup() async throws
}
```

#### Initialization Parameters
```swift
public struct TTSInitParameters: ComponentInitParameters {
    public let componentType = SDKComponent.tts
    public let modelId: String? = nil

    // Voice Configuration
    public let voice: String                   // Voice identifier
    public let language: String               // default: "en-US"
    public let speakingRate: Float           // 0.5 to 2.0, default: 1.0
    public let pitch: Float                  // 0.5 to 2.0, default: 1.0
    public let volume: Float                 // 0.0 to 1.0, default: 1.0
    public let audioFormat: AudioFormat      // default: .pcm
    public let useNeuralVoice: Bool         // default: true

    // Validation
    public func validate() throws {
        guard speakingRate >= 0.5 && speakingRate <= 2.0 else {
            throw SDKError.validationFailed("Speaking rate must be between 0.5 and 2.0")
        }
        guard pitch >= 0.5 && pitch <= 2.0 else {
            throw SDKError.validationFailed("Pitch must be between 0.5 and 2.0")
        }
        guard volume >= 0.0 && volume <= 1.0 else {
            throw SDKError.validationFailed("Volume must be between 0.0 and 1.0")
        }
    }
}
```

#### Service Protocol
```swift
public protocol TextToSpeechService: AnyObject {
    // Initialization
    func initialize() async throws

    // Synthesis Methods
    func synthesize(text: String, options: TTSOptions) async throws -> Data
    func speak(text: String, options: TTSOptions) async throws
    func synthesizeStream(text: String, options: TTSOptions) -> AsyncThrowingStream<VoiceAudioChunk, Error>

    // Playback Control
    func stop()
    func pause()
    func resume()

    // State
    var isSpeaking: Bool { get }
    var isPaused: Bool { get }

    // Voice Management
    var availableVoices: [VoiceInfo] { get }
    var currentVoice: VoiceInfo? { get set }
    var supportsStreaming: Bool { get }

    // Cleanup
    func cleanup() async
}
```

#### Options & Models
```swift
public struct TTSOptions {
    public let voice: String?
    public let language: String
    public let rate: Float               // Runtime rate (note: different from speakingRate)
    public let pitch: Float
    public let volume: Float
    public let audioFormat: AudioFormat
    public let sampleRate: Int
    public let useSSML: Bool
}

public struct VoiceInfo {
    public let id: String
    public let name: String
    public let language: String
    public let gender: VoiceGender
    public let ageGroup: VoiceAgeGroup
    public let quality: VoiceQuality
    public let isNeural: Bool
    public let attributes: VoiceAttributes
}

public enum VoiceGender: String, CaseIterable {
    case male, female, neutral
}

public enum VoiceAgeGroup: String, CaseIterable {
    case child, teen, adult, senior
}

public enum VoiceQuality: String, CaseIterable {
    case low, standard, high, premium
}

public enum AudioFormat: String, CaseIterable, Sendable {
    case pcm, wav, mp3, aac, opus, flac
}
```

### Implementation Pattern

#### Adapter Registry with Fallback
```swift
public override func initialize(with parameters: any ComponentInitParameters) async throws {
    guard let ttsParams = parameters as? TTSInitParameters else {
        throw SDKError.validationFailed("Invalid parameters type for TTS component")
    }

    try await super.initialize(with: parameters)

    guard let container = serviceContainer else {
        throw SDKError.notInitialized
    }

    // ✅ USES ADAPTER REGISTRY
    let frameworks = container.adapterRegistry.getFrameworks(for: .textToSpeech)

    if let framework = frameworks.first,
       let adapter = container.adapterRegistry.getAdapter(for: framework) {

        let hardwareConfig = HardwareConfiguration()
        await adapter.configure(with: hardwareConfig)

        if let service = try await adapter.initializeComponent(
            with: ttsParams,
            for: .textToSpeech
        ) as? TextToSpeechService {
            ttsService = service
        }
    }

    // Fallback to system TTS if no adapter available
    if ttsService == nil {
        ttsService = SystemTextToSpeechService()
        try await ttsService?.initialize()
    }

    await transitionTo(state: .ready)
}
```

### Streaming TTS Handler
```swift
public class StreamingTTSHandler {
    private var textBuffer = ""
    private let punctuationMarks: Set<Character> = [".", "!", "?", ",", ";", ":"]

    public func processToken(
        _ token: String,
        options: TTSOptions,
        continuation: AsyncThrowingStream<ModularPipelineEvent, Error>.Continuation
    ) async {
        textBuffer.append(token)

        // Check for sentence completion
        if shouldSynthesizeSentence() {
            let sentence = extractCompleteSentence()
            if !sentence.isEmpty {
                await synthesizeAndYield(
                    text: sentence,
                    options: options,
                    continuation: continuation
                )
            }
        }
    }

    public func flushRemaining(
        options: TTSOptions,
        continuation: AsyncThrowingStream<ModularPipelineEvent, Error>.Continuation
    ) async {
        let remaining = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty {
            await synthesizeAndYield(
                text: remaining,
                options: options,
                continuation: continuation
            )
            textBuffer = ""
        }
    }
}
```

### Status
✅ **Complete**: Uses adapter registry with system fallback
✅ **Property Fix**: Fixed `rate` vs `speakingRate` naming

---

## SpeakerDiarizationComponent

### Purpose
Identifies and distinguishes between different speakers in audio streams for multi-speaker scenarios.

### Complete File List
```
Components:
├── Sources/RunAnywhere/Components/SpeakerDiarization/SpeakerDiarizationComponent.swift

Services:
├── Sources/RunAnywhere/Infrastructure/Voice/Services/DefaultSpeakerDiarization.swift

Pipeline Usage:
├── Sources/RunAnywhere/Public/RunAnywherePipelines.swift
├── Sources/RunAnywhere/Capabilities/Voice/Handlers/STTHandler.swift
```

### Public APIs

#### Component Class
```swift
@MainActor
public final class SpeakerDiarizationComponent: BaseComponent, @unchecked Sendable {
    // Properties
    public override class var componentType: SDKComponent { .speakerDiarization }

    // Public Methods
    public func getService() -> SpeakerDiarizationService?
    public override func initialize(with parameters: any ComponentInitParameters) async throws
    public override func cleanup() async throws
}
```

#### Initialization Parameters (In Component File)
```swift
public struct SpeakerDiarizationInitParameters: ComponentInitParameters {
    public let componentType = SDKComponent.speakerDiarization
    public let modelId: String? = nil

    // Configuration
    public let maxSpeakers: Int                      // default: 4
    public let minSpeechDuration: TimeInterval      // seconds, default: 0.5
    public let speakerChangeThreshold: Float        // 0-1, default: 0.5
    public let clusteringAlgorithm: ClusteringAlgorithm
    public let embeddingWindowSize: TimeInterval    // seconds, default: 1.5

    public enum ClusteringAlgorithm: String, Sendable {
        case agglomerative = "agglomerative"
        case spectral = "spectral"
        case kmeans = "kmeans"
    }

    // Validation
    public func validate() throws {
        guard maxSpeakers > 0 && maxSpeakers <= 10 else {
            throw SDKError.validationFailed("Max speakers must be between 1 and 10")
        }
        guard minSpeechDuration > 0 && minSpeechDuration <= 5.0 else {
            throw SDKError.validationFailed("Min speech duration must be between 0 and 5 seconds")
        }
        guard speakerChangeThreshold >= 0.0 && speakerChangeThreshold <= 1.0 else {
            throw SDKError.validationFailed("Speaker change threshold must be between 0.0 and 1.0")
        }
        guard embeddingWindowSize > 0 && embeddingWindowSize <= 10.0 else {
            throw SDKError.validationFailed("Embedding window size must be between 0 and 10 seconds")
        }
    }
}
```

#### Service Protocol
```swift
public protocol SpeakerDiarizationService: AnyObject {
    // Speaker Detection
    func detectSpeaker(from samples: [Float], sampleRate: Int) -> SpeakerInfo
    func identifySpeaker(from audio: Data, options: SpeakerDiarizationOptions) async throws -> SpeakerInfo?

    // Speaker Management
    func getCurrentSpeaker() -> SpeakerInfo?
    func getAllSpeakers() -> [SpeakerInfo]
    func registerSpeaker(name: String?, embedding: [Float]) -> SpeakerInfo
    func reset()

    // Configuration
    var maxSpeakers: Int { get set }
    var speakerChangeThreshold: Float { get set }
}

public struct SpeakerInfo {
    public let id: String
    public var name: String?
    public let embedding: [Float]
    public let firstDetectedAt: Date
    public var lastDetectedAt: Date
    public var totalSpeakingTime: TimeInterval
}

public struct SpeakerDiarizationOptions {
    public let maxSpeakers: Int
    public let minSpeechDuration: TimeInterval
    public let clusteringAlgorithm: String
}
```

### Implementation Pattern

#### Direct Service Creation (INCONSISTENT)
```swift
public override func initialize(with parameters: any ComponentInitParameters) async throws {
    guard parameters is SpeakerDiarizationInitParameters else {
        throw SDKError.validationFailed("Invalid parameters type for Speaker Diarization")
    }

    try await super.initialize(with: parameters)

    // ❌ DIRECT SERVICE CREATION (should use adapter registry)
    if let container = serviceContainer {
        diarizationService = DefaultSpeakerDiarization()
    }

    await transitionTo(state: .ready)
}
```

### DefaultSpeakerDiarization Implementation
```swift
public class DefaultSpeakerDiarization: SpeakerDiarizationService {
    private var speakers: [SpeakerInfo] = []
    private var currentSpeaker: SpeakerInfo?

    public var maxSpeakers: Int = 4
    public var speakerChangeThreshold: Float = 0.5

    public func detectSpeaker(from samples: [Float], sampleRate: Int) -> SpeakerInfo {
        let embedding = extractEmbedding(from: samples)

        // Find closest matching speaker
        if let existingSpeaker = findClosestSpeaker(embedding: embedding) {
            existingSpeaker.lastDetectedAt = Date()
            currentSpeaker = existingSpeaker
            return existingSpeaker
        }

        // Create new speaker if under limit
        if speakers.count < maxSpeakers {
            let newSpeaker = registerSpeaker(name: nil, embedding: embedding)
            currentSpeaker = newSpeaker
            return newSpeaker
        }

        // Return least recently used speaker
        return speakers.min { $0.lastDetectedAt < $1.lastDetectedAt }!
    }

    private func extractEmbedding(from samples: [Float]) -> [Float] {
        // Simplified: Use statistical features as embedding
        var features: [Float] = []

        // Mean
        let mean = samples.reduce(0, +) / Float(samples.count)
        features.append(mean)

        // Standard deviation
        let variance = samples.map { pow($0 - mean, 2) }.reduce(0, +) / Float(samples.count)
        features.append(sqrt(variance))

        // Zero crossing rate
        var zeroCrossings = 0
        for i in 1..<samples.count {
            if (samples[i-1] > 0) != (samples[i] > 0) {
                zeroCrossings += 1
            }
        }
        features.append(Float(zeroCrossings) / Float(samples.count))

        return features
    }
}
```

### Pipeline Integration

#### TranscriptionPipeline with Diarization
```swift
if config.enableDiarization {
    diarizationComponent = SpeakerDiarizationComponent()
    try await diarizationComponent?.initialize(
        with: SpeakerDiarizationInitParameters()
    )
}

// In processAudio:
if config.enableDiarization, let diarization = diarizationComponent?.getService() {
    let speaker = try await diarization.identifySpeaker(
        from: audio,
        options: SpeakerDiarizationOptions()
    )

    if let speakerId = speaker?.id {
        eventSubject.continuation.yield(.speakerChanged(speakerId: speakerId))
    }
}
```

### Status
⚠️ **Pattern Issue**: Uses direct service creation instead of adapter registry
✅ **Complete**: Parameters and service protocol defined

---

## VoiceAgentComponent (Composite)

### Purpose
Orchestrates all voice components (VAD, STT, LLM, TTS, Speaker Diarization) to provide complete conversational AI capability.

### Complete File List
```
Components:
├── Sources/RunAnywhere/Components/VoiceAgent/VoiceAgentComponent.swift

Pipeline Processing:
├── Sources/RunAnywhere/Capabilities/Voice/Services/VoicePipelineManager.swift

Event Models:
├── Sources/RunAnywhere/Public/Models/Voice/ModularPipelineEvent.swift
├── Sources/RunAnywhere/Public/Models/Voice/ModularPipelineConfig.swift
```

### Public APIs

#### Component Class
```swift
@MainActor
public final class VoiceAgentComponent: BaseComponent, @unchecked Sendable {
    // Properties
    public override class var componentType: SDKComponent { .voiceAgent }

    // Sub-components (PUBLIC ACCESS)
    public private(set) var vadComponent: VADComponent?
    public private(set) var sttComponent: STTComponent?
    public private(set) var llmComponent: LLMComponent?
    public private(set) var ttsComponent: TTSComponent?

    // Public Methods
    public func processVoicePipeline(
        config: ModularPipelineConfig
    ) async throws -> AsyncThrowingStream<ModularPipelineEvent, Error>

    public override func initialize(with parameters: any ComponentInitParameters) async throws
    public override func cleanup() async throws
}
```

#### Initialization Parameters
```swift
public struct VoiceAgentInitParameters: ComponentInitParameters {
    public let componentType = SDKComponent.voiceAgent
    public let modelId: String? = nil

    // Sub-component parameters
    public let vadParameters: VADInitParameters
    public let sttParameters: STTInitParameters
    public let llmParameters: LLMInitParameters
    public let ttsParameters: TTSInitParameters

    // Pipeline configuration
    public let generationOptions: RunAnywhereGenerationOptions
    public let streamingEnabled: Bool

    // Validation
    public func validate() throws {
        try vadParameters.validate()
        try sttParameters.validate()
        try llmParameters.validate()
        try ttsParameters.validate()
    }
}
```

#### Pipeline Configuration
```swift
public struct ModularPipelineConfig: Sendable {
    public let components: Set<VoiceComponent>

    // Component parameters
    public let vad: VADInitParameters?
    public let stt: STTInitParameters?
    public let llm: LLMInitParameters?
    public let tts: TTSInitParameters?

    // Pipeline settings
    public let enableSpeakerDiarization: Bool
    public let continuousMode: Bool
}

public enum VoiceComponent: String, CaseIterable, Sendable {
    case vad = "vad"
    case stt = "stt"
    case llm = "llm"
    case tts = "tts"
}
```

#### Pipeline Events
```swift
public enum ModularPipelineEvent: Sendable {
    // VAD Events
    case vadSpeechStart
    case vadSpeechEnd
    case vadEnergyLevel(Float)

    // STT Events
    case sttPartialTranscript(String)
    case sttFinalTranscript(String)
    case sttSpeakerChanged(from: SpeakerInfo?, to: SpeakerInfo)

    // LLM Events
    case llmThinking
    case llmStreamStarted
    case llmStreamToken(String)
    case llmFinalResponse(String)

    // TTS Events
    case ttsStarted
    case ttsAudioChunk(VoiceAudioChunk)
    case ttsComplete

    // Error Events
    case error(Error)
    case warning(String)

    // Pipeline Events
    case pipelineStarted
    case pipelineEnded
}
```

### Implementation Details

#### Component Initialization
```swift
public override func initialize(with parameters: any ComponentInitParameters) async throws {
    guard let voiceParams = parameters as? VoiceAgentInitParameters else {
        throw SDKError.validationFailed("Invalid parameters type for Voice Agent")
    }

    try await super.initialize(with: parameters)

    // Initialize all sub-components
    vadComponent = VADComponent()
    try await vadComponent?.initialize(with: voiceParams.vadParameters)

    sttComponent = STTComponent()
    try await sttComponent?.initialize(with: voiceParams.sttParameters)

    llmComponent = LLMComponent()
    try await llmComponent?.initialize(with: voiceParams.llmParameters)

    ttsComponent = TTSComponent()
    try await ttsComponent?.initialize(with: voiceParams.ttsParameters)

    await transitionTo(state: .ready)
}
```

#### Pipeline Processing
```swift
public func processVoicePipeline(
    config: ModularPipelineConfig
) async throws -> AsyncThrowingStream<ModularPipelineEvent, Error> {

    return AsyncThrowingStream { continuation in
        Task {
            do {
                let pipeline = VoicePipelineManager(
                    vad: vadComponent?.getService(),
                    stt: sttComponent?.getService(),
                    llm: llmComponent?.getService(),
                    tts: ttsComponent?.getService(),
                    speakerDiarization: nil
                )

                // Configure pipeline with parameters
                let audioStream = AudioStreamManager.shared.startCapture()
                let eventStream = pipeline.process(audioStream: audioStream)

                for try await event in eventStream {
                    continuation.yield(event)
                }

                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}
```

### VoicePipelineManager
```swift
public class VoicePipelineManager {
    private let vad: VADService?
    private let stt: STTService?
    private let llm: LLMService?
    private let tts: TextToSpeechService?
    private let speakerDiarization: SpeakerDiarizationService?

    public func process(
        audioStream: AsyncStream<Data>
    ) -> AsyncThrowingStream<ModularPipelineEvent, Error> {

        AsyncThrowingStream { continuation in
            Task {
                for await audioData in audioStream {
                    // VAD Processing
                    if let vad = self.vad {
                        let hasVoice = vad.processAudioData(audioData.toFloatArray())

                        if hasVoice && !vad.isSpeechActive {
                            continuation.yield(.vadSpeechStart)
                        } else if !hasVoice && vad.isSpeechActive {
                            continuation.yield(.vadSpeechEnd)

                            // Trigger STT when speech ends
                            if let stt = self.stt {
                                let result = try await stt.transcribe(
                                    audio: audioData,
                                    options: STTOptions()
                                )
                                continuation.yield(.sttFinalTranscript(result.text))

                                // Process with LLM
                                if let llm = self.llm {
                                    continuation.yield(.llmThinking)
                                    let response = try await llm.generate(
                                        prompt: result.text,
                                        options: RunAnywhereGenerationOptions()
                                    )
                                    continuation.yield(.llmFinalResponse(response))

                                    // Synthesize response
                                    if let tts = self.tts {
                                        continuation.yield(.ttsStarted)
                                        let audio = try await tts.synthesize(
                                            text: response,
                                            options: TTSOptions()
                                        )
                                        continuation.yield(.ttsComplete)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
```

### Pipeline Integration

#### VoiceAgentPipeline
```swift
public final class VoiceAgentPipeline: Pipeline {
    private var voiceAgent: VoiceAgentComponent?

    public func initialize() async throws {
        let agentParams = VoiceAgentInitParameters(
            vadParameters: VADInitParameters(),
            sttParameters: STTInitParameters(language: config.language),
            llmParameters: LLMInitParameters(
                temperature: config.temperature,
                systemPrompt: config.systemPrompt,
                streamingEnabled: config.streamingEnabled
            ),
            ttsParameters: TTSInitParameters(
                voice: config.voice ?? "com.apple.ttsbundle.siri_female_en-US_compact",
                language: config.language
            )
        )

        voiceAgent = VoiceAgentComponent()
        try await voiceAgent?.initialize(with: agentParams)
    }

    public func startConversation() -> AsyncStream<ConversationEvent> {
        AsyncStream { continuation in
            Task {
                guard let agent = voiceAgent else {
                    continuation.finish()
                    return
                }

                let config = ModularPipelineConfig(
                    components: [.vad, .stt, .llm, .tts],
                    vad: VADInitParameters(),
                    stt: STTInitParameters(language: self.config.language),
                    llm: LLMInitParameters(
                        temperature: self.config.temperature,
                        systemPrompt: self.config.systemPrompt,
                        streamingEnabled: self.config.streamingEnabled
                    ),
                    tts: TTSInitParameters(
                        voice: self.config.voice ?? "com.apple.ttsbundle.siri_female_en-US_compact",
                        language: self.config.language
                    )
                )

                let eventStream = try await agent.processVoicePipeline(config: config)

                for await event in eventStream {
                    // Map pipeline events to conversation events
                    switch event {
                    case .vadSpeechStart:
                        continuation.yield(.listening)
                    case .sttFinalTranscript(let text):
                        continuation.yield(.finalTranscript(text))
                    case .llmFinalResponse(let response):
                        continuation.yield(.response(response))
                    case .ttsComplete:
                        continuation.yield(.speakingComplete)
                    default:
                        break
                    }
                }

                continuation.finish()
            }
        }
    }
}
```

### Status
✅ **Complete**: Orchestrates all voice components
⚠️ **Dependency**: Sub-components must be fixed for full functionality

---

## Pipeline System

### Purpose
High-level abstractions for common AI workflows, providing simple APIs for complex component orchestration.

### Complete File List
```
Pipeline Implementations:
├── Sources/RunAnywhere/Public/RunAnywherePipelines.swift
├── Sources/RunAnywhere/Public/RunAnywhere+Pipelines.swift

Configuration & Events:
├── Sources/RunAnywhere/Public/Models/Voice/ModularPipelineConfig.swift
├── Sources/RunAnywhere/Public/Models/Voice/ModularPipelineEvent.swift
```

### Pipeline Types

#### 1. TranscriptionPipeline
```swift
@MainActor
public final class TranscriptionPipeline: Pipeline {
    public typealias Config = TranscriptionConfig

    // Components
    private var vadComponent: VADComponent?
    private var sttComponent: STTComponent?
    private var diarizationComponent: SpeakerDiarizationComponent?

    // Configuration
    public struct TranscriptionConfig: Sendable {
        public let enableDiarization: Bool
        public let language: String
        public let vadSensitivity: Float
        public let punctuationEnabled: Bool
    }

    // Public API
    public func processAudio(
        _ audioStream: AsyncStream<Data>
    ) async throws -> AsyncStream<TranscriptionResult>
}
```

#### 2. VoiceAgentPipeline
```swift
@MainActor
public final class VoiceAgentPipeline: Pipeline {
    public typealias Config = VoiceAgentConfig

    // Components
    private var voiceAgent: VoiceAgentComponent?

    // Configuration
    public struct VoiceAgentConfig: Sendable {
        public let systemPrompt: String?
        public let voice: String?
        public let language: String
        public let temperature: Double
        public let streamingEnabled: Bool
    }

    // Public API
    public func startConversation() -> AsyncStream<ConversationEvent>
}

public enum ConversationEvent: Sendable {
    case listening
    case partialTranscript(String)
    case finalTranscript(String)
    case thinking
    case responseToken(String)
    case response(String)
    case speaking(VoiceAudioChunk)
    case speakingComplete
    case error(Error)
}
```

#### 3. LocalLLMPipeline
```swift
@MainActor
public final class LocalLLMPipeline: Pipeline {
    public typealias Config = LocalLLMConfig

    // Components
    private var llmComponent: LLMComponent?

    // Configuration
    public struct LocalLLMConfig: Sendable {
        public let modelId: String?
        public let systemPrompt: String?
        public let temperature: Double
        public let maxTokens: Int
        public let streamingEnabled: Bool
    }

    // Public API
    public func generate(_ prompt: String) async throws -> String
    public func generateStream(_ prompt: String) -> AsyncStream<String>
}
```

#### 4. CustomPipeline
```swift
@MainActor
public final class CustomPipeline: Pipeline {
    public typealias Config = CustomPipelineConfig

    // Dynamic component composition
    public let components: Set<SDKComponent>

    // All possible components
    private var vadComponent: VADComponent?
    private var sttComponent: STTComponent?
    private var diarizationComponent: SpeakerDiarizationComponent?
    private var llmComponent: LLMComponent?
    private var ttsComponent: TTSComponent?

    // Configuration
    public struct CustomPipelineConfig: Sendable {
        public let vad: VADInitParameters?
        public let stt: STTInitParameters?
        public let diarization: SpeakerDiarizationInitParameters?
        public let llm: LLMInitParameters?
        public let tts: TTSInitParameters?
        public let processingMode: ProcessingMode
        public let errorHandling: ErrorHandlingStrategy
    }

    // Public API
    public func process<Input, Output>(
        _ input: Input,
        as outputType: Output.Type
    ) async throws -> Output
}
```

### Pipeline Protocol
```swift
public protocol Pipeline: AnyObject, Sendable {
    associatedtype Config

    var state: PipelineState { get }
    var config: Config { get }

    func initialize() async throws
    func start() async throws
    func stop() async throws
    func pause() async throws
    func resume() async throws
    func cleanup() async throws

    var stateTransitions: AsyncStream<PipelineStateTransition> { get }
    var events: AsyncStream<PipelineEvent> { get }
}
```

### Pipeline States & Events
```swift
public enum PipelineState: String, Sendable {
    case uninitialized
    case initializing
    case ready
    case processing
    case paused
    case error
    case terminated
}

public enum PipelineEvent: Sendable {
    // Lifecycle
    case initialize, start, pause, resume, stop
    case error(Error)

    // Processing
    case audioDetected
    case speechStarted, speechEnded
    case transcriptionComplete(String)
    case llmProcessing, llmResponse(String)
    case ttsStarted, ttsComplete

    // Diarization
    case diarizationStarted
    case speakerDetected(count: Int)
    case speakerChanged(speakerId: String)
    case speakerIdentified(name: String?)
    case diarizationComplete(speakers: [SpeakerInfo])
}
```

### Pipeline Builder API
```swift
public extension RunAnywhere {
    @MainActor
    var pipelines: PipelineBuilder {
        PipelineBuilder(sdk: self)
    }

    @MainActor
    func createTranscriptionPipeline(
        withDiarization: Bool = false,
        language: String = "en-US"
    ) async throws -> TranscriptionPipeline

    @MainActor
    func createVoiceAgent(
        systemPrompt: String? = nil,
        voice: String? = nil
    ) async throws -> VoiceAgentPipeline

    @MainActor
    func createLLMPipeline(
        modelId: String? = nil,
        systemPrompt: String? = nil
    ) async throws -> LocalLLMPipeline
}
```

### Pipeline Presets
```swift
public struct PipelinePresets {
    public static let basicTranscription = CustomPipelineConfig(
        vad: VADInitParameters(energyThreshold: 0.5),
        stt: STTInitParameters(enablePunctuation: true)
    )

    public static let advancedTranscription = CustomPipelineConfig(
        vad: VADInitParameters(energyThreshold: 0.3),
        stt: STTInitParameters(
            enablePunctuation: true,
            enableDiarization: true
        ),
        diarization: SpeakerDiarizationInitParameters(
            maxSpeakers: 4,
            clusteringAlgorithm: .agglomerative
        )
    )

    public static let voiceAssistant = CustomPipelineConfig(
        vad: VADInitParameters(),
        stt: STTInitParameters(),
        llm: LLMInitParameters(
            temperature: 0.7,
            streamingEnabled: true
        ),
        tts: TTSInitParameters()
    )

    public static let meetingTranscription = CustomPipelineConfig(
        vad: VADInitParameters(
            energyThreshold: 0.4,
            silenceThreshold: 300
        ),
        stt: STTInitParameters(
            enablePunctuation: true,
            enableDiarization: true,
            maxAlternatives: 3
        ),
        diarization: SpeakerDiarizationInitParameters(
            maxSpeakers: 8,
            speakerChangeThreshold: 0.6,
            clusteringAlgorithm: .spectral
        )
    )
}
```

---

## Base Component Architecture

### Component Protocol
```swift
public protocol Component: AnyObject {
    static var componentType: SDKComponent { get }
    var componentId: UUID { get }
    var state: ComponentState { get }
    var error: Error? { get }
    var initializationParameters: (any ComponentInitParameters)? { get }
    var serviceContainer: ServiceContainer? { get set }

    func initialize(with parameters: any ComponentInitParameters) async throws
    func cleanup() async throws
    func transitionTo(state: ComponentState) async
}

public enum ComponentState: String, CaseIterable, Sendable {
    case notInitialized = "not_initialized"
    case checking = "checking"
    case downloading = "downloading"
    case initializing = "initializing"
    case ready = "ready"
    case error = "error"
    case terminated = "terminated"
}
```

### BaseComponent Implementation
```swift
@MainActor
open class BaseComponent: Component, @unchecked Sendable {
    public nonisolated(unsafe) var componentId: UUID = UUID()
    public private(set) var state: ComponentState = .notInitialized
    public private(set) var error: Error?
    public private(set) var initializationParameters: (any ComponentInitParameters)?
    public weak var serviceContainer: ServiceContainer?

    open class var componentType: SDKComponent {
        fatalError("Subclass must override componentType")
    }

    open func initialize(with parameters: any ComponentInitParameters) async throws {
        await transitionTo(state: .initializing)
        self.initializationParameters = parameters
        try parameters.validate()
    }

    open func cleanup() async throws {
        await transitionTo(state: .terminated)
    }

    public func transitionTo(state: ComponentState) async {
        let oldState = self.state
        self.state = state

        await EventBus.shared.publish(ComponentInitializationEvent(
            componentId: componentId,
            componentType: Self.componentType,
            state: state,
            previousState: oldState
        ))
    }
}
```

---

## Adapter System

### UnifiedFrameworkAdapter Protocol
```swift
public protocol UnifiedFrameworkAdapter {
    var framework: LLMFramework { get }
    var supportedModalities: Set<FrameworkModality> { get }
    var supportedFormats: [ModelFormat] { get }

    func canHandle(model: ModelInfo) -> Bool
    func createService(for modality: FrameworkModality) -> Any?
    func loadModel(_ model: ModelInfo, for modality: FrameworkModality) async throws -> Any
    func configure(with hardware: HardwareConfiguration) async
    func estimateMemoryUsage(for model: ModelInfo) -> Int64
    func optimalConfiguration(for model: ModelInfo) -> HardwareConfiguration
    func onRegistration()
    func getProvidedModels() -> [ModelInfo]
    func getDownloadStrategy() -> DownloadStrategy?

    func initializeComponent(
        with parameters: any ComponentInitParameters,
        for modality: FrameworkModality
    ) async throws -> Any?
}

public enum FrameworkModality: String, CaseIterable, Sendable {
    case textToText = "text_to_text"
    case voiceToText = "voice_to_text"
    case textToSpeech = "text_to_speech"
    case imageToText = "image_to_text"
    case textToImage = "text_to_image"
    // Missing: voiceActivityDetection, speakerDiarization
}
```

---

## Missing Components

### VLMComponent (Vision Language Model)
**Status**: Parameters defined, component not implemented

#### Defined Parameters
```swift
public struct VLMInitParameters: ComponentInitParameters {
    public let componentType = SDKComponent.vlm
    public let modelId: String?

    public let imageSize: CGSize
    public let maxImageCount: Int
    public let contextLength: Int
    public let temperature: Double
    public let maxTokens: Int
    public let useGPUIfAvailable: Bool
}
```

### EmbeddingComponent
**Status**: Parameters defined, component not implemented

#### Defined Parameters
```swift
public struct EmbeddingInitParameters: ComponentInitParameters {
    public let componentType = SDKComponent.embedding
    public let modelId: String?

    public let dimensions: Int
    public let normalizeEmbeddings: Bool
    public let poolingStrategy: PoolingStrategy
    public let maxSequenceLength: Int

    public enum PoolingStrategy: String, Sendable {
        case mean = "mean"
        case max = "max"
        case cls = "cls"
    }
}
```

---

## Component Status Summary

| Component | Pattern | Implementation | Pipeline Usage | Status |
|-----------|---------|----------------|----------------|---------|
| **STTComponent** | ✅ Adapter Registry | Complete | All pipelines | ✅ Ready |
| **LLMComponent** | ✅ Adapter Registry | Complete | Voice & LLM pipelines | ✅ Ready |
| **TTSComponent** | ✅ Adapter Registry | Complete | Voice pipelines | ✅ Ready |
| **VADComponent** | ❌ Direct Service | Complete | Voice & Transcription | ⚠️ Works but inconsistent |
| **SpeakerDiarizationComponent** | ❌ Direct Service | Complete | Transcription | ⚠️ Works but inconsistent |
| **VoiceAgentComponent** | N/A (Composite) | Complete | Voice pipeline | ✅ Ready |
| **VLMComponent** | - | Not implemented | - | ❌ Missing |
| **EmbeddingComponent** | - | Not implemented | - | ❌ Missing |

## Recommendations

1. **Fix VAD/SpeakerDiarization**: Adopt adapter registry pattern
2. **Add Missing Modalities**: Add `voiceActivityDetection` and `speakerDiarization` to FrameworkModality
3. **Implement VLM/Embedding**: Create component classes for defined parameters
4. **Standardize Service Protocols**: Ensure all have consistent method signatures
5. **Complete Documentation**: Add inline documentation for all public APIs
