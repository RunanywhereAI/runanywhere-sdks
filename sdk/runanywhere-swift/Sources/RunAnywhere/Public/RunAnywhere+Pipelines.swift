import Foundation

// MARK: - Public Pipeline API

/// Main public API for creating and managing AI pipelines
public extension RunAnywhere {

    /// Create a pipeline builder for easy pipeline construction
    var pipelines: PipelineBuilder {
        PipelineBuilder(sdk: self)
    }

    // MARK: - Quick Pipeline Creation

    /// Create a transcription pipeline with optional speaker diarization
    @MainActor
    func createTranscriptionPipeline(
        withDiarization: Bool = false,
        language: String = "en-US"
    ) async throws -> TranscriptionPipeline {
        return try await pipelines.buildTranscriptionPipeline(
            enableDiarization: withDiarization,
            language: language
        )
    }

    /// Create a full voice agent for conversational AI
    @MainActor
    func createVoiceAgent(
        systemPrompt: String? = nil,
        voice: String? = nil
    ) async throws -> VoiceAgentPipeline {
        return try await pipelines.buildVoiceAgentPipeline(
            systemPrompt: systemPrompt,
            voice: voice
        )
    }

    /// Create a local LLM pipeline for text generation
    @MainActor
    func createLLMPipeline(
        modelId: String? = nil,
        systemPrompt: String? = nil
    ) async throws -> LocalLLMPipeline {
        return try await pipelines.buildLocalLLMPipeline(
            modelId: modelId,
            systemPrompt: systemPrompt
        )
    }

    // MARK: - Advanced Pipeline Creation

    /// Create a custom pipeline with specific components
    @MainActor
    func createCustomPipeline(
        components: Set<SDKComponent>,
        config: CustomPipelineConfig
    ) async throws -> CustomPipeline {
        let pipeline = CustomPipeline(components: components, config: config)
        try await pipeline.initialize()
        return pipeline
    }
}

// MARK: - Pipeline Usage Examples

public extension RunAnywhere {

    /// Example: Simple transcription
    /// ```swift
    /// let pipeline = try await RunAnywhere.shared.createTranscriptionPipeline()
    /// try await pipeline.start()
    ///
    /// for await result in pipeline.processAudio(audioStream) {
    ///     print("Transcript: \(result.text)")
    /// }
    /// ```
    static func transcriptionExample() { }

    /// Example: Transcription with speaker identification
    /// ```swift
    /// let pipeline = try await RunAnywhere.shared.createTranscriptionPipeline(
    ///     withDiarization: true
    /// )
    /// try await pipeline.start()
    ///
    /// for await result in pipeline.processAudio(audioStream) {
    ///     if let speaker = result.speaker {
    ///         print("[\(speaker.name ?? speaker.id)]: \(result.text)")
    ///     }
    /// }
    /// ```
    static func diarizationExample() { }

    /// Example: Full voice conversation
    /// ```swift
    /// let agent = try await RunAnywhere.shared.createVoiceAgent(
    ///     systemPrompt: "You are a helpful assistant"
    /// )
    /// try await agent.start()
    ///
    /// for await event in agent.startConversation() {
    ///     switch event {
    ///     case .listening:
    ///         print("Listening...")
    ///     case .finalTranscript(let text):
    ///         print("User: \(text)")
    ///     case .response(let text):
    ///         print("Agent: \(text)")
    ///     default:
    ///         break
    ///     }
    /// }
    /// ```
    static func voiceAgentExample() { }

    /// Example: Local LLM text generation
    /// ```swift
    /// let llm = try await RunAnywhere.shared.createLLMPipeline(
    ///     systemPrompt: "You are a coding assistant"
    /// )
    ///
    /// // Non-streaming
    /// let response = try await llm.generate("Write a Swift function")
    ///
    /// // Streaming
    /// for await token in llm.generateStream("Explain async/await") {
    ///     print(token, terminator: "")
    /// }
    /// ```
    static func llmExample() { }
}

// MARK: - Custom Pipeline Configuration

/// Configuration for custom pipelines with specific component combinations
public struct CustomPipelineConfig: Sendable {
    // Component configurations
    public let vad: VADInitParameters?
    public let stt: STTInitParameters?
    public let diarization: SpeakerDiarizationInitParameters?
    public let llm: LLMInitParameters?
    public let tts: TTSInitParameters?

    // Pipeline behavior
    public let processingMode: ProcessingMode
    public let errorHandling: ErrorHandlingStrategy

    public enum ProcessingMode: String, Sendable {
        case sequential
        case parallel
        case streaming
    }

    public enum ErrorHandlingStrategy: String, Sendable {
        case fail
        case skip
        case retry
    }

    public init(
        vad: VADInitParameters? = nil,
        stt: STTInitParameters? = nil,
        diarization: SpeakerDiarizationInitParameters? = nil,
        llm: LLMInitParameters? = nil,
        tts: TTSInitParameters? = nil,
        processingMode: ProcessingMode = .streaming,
        errorHandling: ErrorHandlingStrategy = .retry
    ) {
        self.vad = vad
        self.stt = stt
        self.diarization = diarization
        self.llm = llm
        self.tts = tts
        self.processingMode = processingMode
        self.errorHandling = errorHandling
    }
}

// MARK: - Custom Pipeline Implementation

/// Custom pipeline for advanced component combinations
@MainActor
public final class CustomPipeline: Pipeline {
    public typealias Config = CustomPipelineConfig

    public private(set) var state: PipelineState = .uninitialized
    public let config: CustomPipelineConfig
    public let components: Set<SDKComponent>

    // Component instances
    private var vadComponent: VADComponent?
    private var sttComponent: STTComponent?
    private var diarizationComponent: SpeakerDiarizationComponent?
    private var llmComponent: LLMComponent?
    private var ttsComponent: TTSComponent?

    private let stateSubject = AsyncStream<PipelineStateTransition>.makeStream()
    private let eventSubject = AsyncStream<PipelineEvent>.makeStream()

    public var stateTransitions: AsyncStream<PipelineStateTransition> {
        stateSubject.stream
    }

    public var events: AsyncStream<PipelineEvent> {
        eventSubject.stream
    }

    public init(components: Set<SDKComponent>, config: CustomPipelineConfig) {
        self.components = components
        self.config = config
    }

    public func initialize() async throws {
        setState(.initializing, event: .initialize)

        // Initialize only requested components
        if components.contains(.vad), let vadParams = config.vad {
            vadComponent = VADComponent()
            try await vadComponent?.initialize(with: vadParams)
        }

        if components.contains(.stt), let sttParams = config.stt {
            sttComponent = STTComponent()
            try await sttComponent?.initialize(with: sttParams)
        }

        if components.contains(.speakerDiarization), let diarizationParams = config.diarization {
            diarizationComponent = SpeakerDiarizationComponent()
            try await diarizationComponent?.initialize(with: diarizationParams)
        }

        if components.contains(.llm), let llmParams = config.llm {
            llmComponent = LLMComponent()
            try await llmComponent?.initialize(with: llmParams)
        }

        if components.contains(.tts), let ttsParams = config.tts {
            ttsComponent = TTSComponent()
            try await ttsComponent?.initialize(with: ttsParams)
        }

        setState(.ready, event: .initialize)
    }

    public func start() async throws {
        guard state == .ready else {
            throw SDKError.invalidState("Pipeline must be ready to start")
        }
        setState(.processing, event: .start)
    }

    public func stop() async throws {
        setState(.ready, event: .stop)
    }

    public func pause() async throws {
        guard state == .processing else {
            throw SDKError.invalidState("Can only pause when processing")
        }
        setState(.paused, event: .pause)
    }

    public func resume() async throws {
        guard state == .paused else {
            throw SDKError.invalidState("Can only resume when paused")
        }
        setState(.processing, event: .resume)
    }

    public func cleanup() async throws {
        setState(.terminated, event: .stop)

        try await vadComponent?.cleanup()
        try await sttComponent?.cleanup()
        try await diarizationComponent?.cleanup()
        try await llmComponent?.cleanup()
        try await ttsComponent?.cleanup()
    }

    /// Process data through the custom pipeline
    public func process<Input, Output>(
        _ input: Input,
        as outputType: Output.Type
    ) async throws -> Output {
        // This would be implemented based on the specific component combination
        // For now, throw an error indicating implementation needed
        throw SDKError.notImplemented("Custom pipeline processing needs specific implementation")
    }

    private func setState(_ newState: PipelineState, event: PipelineEvent) {
        let transition = PipelineStateTransition(from: state, to: newState, event: event)
        state = newState
        stateSubject.continuation.yield(transition)
        eventSubject.continuation.yield(event)
    }
}

// MARK: - Pipeline Presets

/// Predefined pipeline configurations for common use cases
public struct PipelinePresets {

    /// Basic transcription without speaker identification
    public static let basicTranscription = CustomPipelineConfig(
        vad: VADInitParameters(energyThreshold: 0.5),
        stt: STTInitParameters(enablePunctuation: true)
    )

    /// Advanced transcription with speaker diarization
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

    /// Full voice assistant with all components
    public static let voiceAssistant = CustomPipelineConfig(
        vad: VADInitParameters(),
        stt: STTInitParameters(),
        llm: LLMInitParameters(
            temperature: 0.7,
            streamingEnabled: true
        ),
        tts: TTSInitParameters()
    )

    /// Text-only LLM pipeline
    public static let textGeneration = CustomPipelineConfig(
        llm: LLMInitParameters(
            temperature: 0.8,
            maxTokens: 1024,
            streamingEnabled: true
        )
    )

    /// Meeting transcription with multiple speakers
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
