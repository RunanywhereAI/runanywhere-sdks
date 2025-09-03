import Foundation

// MARK: - Pipeline Presets

/// Main pipeline presets for RunAnywhere SDK
public enum RunAnywherePipeline {
    /// VAD + STT + Speaker Diarization for multi-speaker transcription
    case transcription

    /// Full Voice Agent: VAD + STT + LLM + TTS for conversational AI
    case voiceAgent

    /// Local LLM only for text generation
    case localLLM

    /// Custom pipeline with specific components
    case custom(components: Set<SDKComponent>)
}

// MARK: - Pipeline Builder

/// Simple, clean API for creating AI pipelines
@MainActor
public final class PipelineBuilder {
    private let sdk: RunAnywhere

    public init(sdk: RunAnywhere = .shared) {
        self.sdk = sdk
    }

    // MARK: - Transcription Pipeline (VAD + STT + Diarization)

    /// Create a transcription pipeline with optional speaker diarization
    public func buildTranscriptionPipeline(
        enableDiarization: Bool = false,
        language: String = "en-US"
    ) async throws -> TranscriptionPipeline {
        let config = TranscriptionConfig(
            enableDiarization: enableDiarization,
            language: language
        )

        let pipeline = TranscriptionPipeline(config: config)
        try await pipeline.initialize()
        return pipeline
    }

    // MARK: - Voice Agent Pipeline (Full conversational AI)

    /// Create a full voice agent pipeline for conversational AI
    public func buildVoiceAgentPipeline(
        systemPrompt: String? = nil,
        voice: String? = nil,
        language: String = "en-US"
    ) async throws -> VoiceAgentPipeline {
        let config = VoiceAgentConfig(
            systemPrompt: systemPrompt,
            voice: voice,
            language: language
        )

        let pipeline = VoiceAgentPipeline(config: config)
        try await pipeline.initialize()
        return pipeline
    }

    // MARK: - Local LLM Pipeline

    /// Create a local LLM pipeline for text generation
    public func buildLocalLLMPipeline(
        modelId: String? = nil,
        systemPrompt: String? = nil,
        temperature: Double = 0.7
    ) async throws -> LocalLLMPipeline {
        let config = LocalLLMConfig(
            modelId: modelId,
            systemPrompt: systemPrompt,
            temperature: temperature
        )

        let pipeline = LocalLLMPipeline(config: config)
        try await pipeline.initialize()
        return pipeline
    }
}

// MARK: - Pipeline Configurations

/// Configuration for transcription pipeline
public struct TranscriptionConfig: Sendable {
    public let enableDiarization: Bool
    public let language: String
    public let vadSensitivity: Float
    public let punctuationEnabled: Bool

    public init(
        enableDiarization: Bool = false,
        language: String = "en-US",
        vadSensitivity: Float = 0.5,
        punctuationEnabled: Bool = true
    ) {
        self.enableDiarization = enableDiarization
        self.language = language
        self.vadSensitivity = vadSensitivity
        self.punctuationEnabled = punctuationEnabled
    }
}

/// Configuration for voice agent pipeline
public struct VoiceAgentConfig: Sendable {
    public let systemPrompt: String?
    public let voice: String?
    public let language: String
    public let temperature: Double
    public let streamingEnabled: Bool

    public init(
        systemPrompt: String? = nil,
        voice: String? = nil,
        language: String = "en-US",
        temperature: Double = 0.7,
        streamingEnabled: Bool = true
    ) {
        self.systemPrompt = systemPrompt
        self.voice = voice
        self.language = language
        self.temperature = temperature
        self.streamingEnabled = streamingEnabled
    }
}

/// Configuration for local LLM pipeline
public struct LocalLLMConfig: Sendable {
    public let modelId: String?
    public let systemPrompt: String?
    public let temperature: Double
    public let maxTokens: Int
    public let streamingEnabled: Bool

    public init(
        modelId: String? = nil,
        systemPrompt: String? = nil,
        temperature: Double = 0.7,
        maxTokens: Int = 2048,
        streamingEnabled: Bool = true
    ) {
        self.modelId = modelId
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.streamingEnabled = streamingEnabled
    }
}

// MARK: - Pipeline States

/// State management for pipelines
public enum PipelineState: String, Sendable {
    case uninitialized
    case initializing
    case ready
    case processing
    case paused
    case error
    case terminated
}

/// Pipeline state transitions with events
public struct PipelineStateTransition: Sendable {
    public let from: PipelineState
    public let to: PipelineState
    public let event: PipelineEvent
    public let timestamp: Date

    public init(from: PipelineState, to: PipelineState, event: PipelineEvent) {
        self.from = from
        self.to = to
        self.event = event
        self.timestamp = Date()
    }
}

/// Events that trigger state transitions
public enum PipelineEvent: Sendable {
    // Lifecycle events
    case initialize
    case start
    case pause
    case resume
    case stop
    case error(Error)

    // Processing events
    case audioDetected
    case speechStarted
    case speechEnded
    case transcriptionComplete(String)
    case llmProcessing
    case llmResponse(String)
    case ttsStarted
    case ttsComplete

    // Diarization events
    case diarizationStarted
    case speakerDetected(count: Int)
    case speakerChanged(speakerId: String)
    case speakerIdentified(name: String?)
    case diarizationComplete(speakers: [SpeakerInfo])
}

// MARK: - Base Pipeline Protocol

/// Base protocol for all pipelines
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

    /// Stream of state transitions
    var stateTransitions: AsyncStream<PipelineStateTransition> { get }

    /// Stream of pipeline events
    var events: AsyncStream<PipelineEvent> { get }
}

// MARK: - Transcription Pipeline

/// Pipeline for VAD + STT + optional Diarization
@MainActor
public final class TranscriptionPipeline: Pipeline {
    public typealias Config = TranscriptionConfig

    public private(set) var state: PipelineState = .uninitialized
    public let config: TranscriptionConfig

    private var vadComponent: VADComponent?
    private var sttComponent: STTComponent?
    private var diarizationComponent: SpeakerDiarizationComponent?

    private let stateSubject = AsyncStream<PipelineStateTransition>.makeStream()
    private let eventSubject = AsyncStream<PipelineEvent>.makeStream()

    public var stateTransitions: AsyncStream<PipelineStateTransition> {
        stateSubject.stream
    }

    public var events: AsyncStream<PipelineEvent> {
        eventSubject.stream
    }

    public init(config: TranscriptionConfig) {
        self.config = config
    }

    public func initialize() async throws {
        setState(.initializing, event: .initialize)

        // Initialize VAD
        let vadParams = VADInitParameters(
            energyThreshold: config.vadSensitivity,
            silenceThreshold: 500
        )
        vadComponent = VADComponent()
        try await vadComponent?.initialize(with: vadParams)

        // Initialize STT
        let sttParams = STTInitParameters(
            language: config.language,
            enablePunctuation: config.punctuationEnabled,
            enableDiarization: config.enableDiarization
        )
        sttComponent = STTComponent()
        try await sttComponent?.initialize(with: sttParams)

        // Initialize Diarization if enabled
        if config.enableDiarization {
            diarizationComponent = SpeakerDiarizationComponent()
            try await diarizationComponent?.initialize(with: SpeakerDiarizationInitParameters())
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
    }

    /// Process audio stream
    public func processAudio(_ audioStream: AsyncStream<Data>) async throws -> AsyncStream<TranscriptionResult> {
        AsyncStream { continuation in
            Task {
                for await audio in audioStream {
                    // Process through VAD
                    if let vad = vadComponent?.getService() {
                        let vadResult = try await vad.detectSpeech(in: audio)

                        if vadResult.isSpeech {
                            eventSubject.continuation.yield(.speechStarted)

                            // Process through STT
                            if let stt = sttComponent?.getService() {
                                let options = STTOptions(
                                    language: config.language,
                                    enablePunctuation: config.punctuationEnabled,
                                    enableDiarization: config.enableDiarization
                                )

                                let result = try await stt.transcribe(
                                    audio: audio,
                                    options: options
                                )

                                // Add diarization if enabled
                                if config.enableDiarization,
                                   let diarization = diarizationComponent?.getService() {
                                    let speaker = try await diarization.identifySpeaker(
                                        from: audio,
                                        options: SpeakerDiarizationOptions()
                                    )

                                    if let speakerId = speaker?.id {
                                        eventSubject.continuation.yield(.speakerChanged(speakerId: speakerId))
                                    }
                                }

                                continuation.yield(result)
                                eventSubject.continuation.yield(.transcriptionComplete(result.text))
                            }
                        } else if vadResult.endOfSpeech {
                            eventSubject.continuation.yield(.speechEnded)
                        }
                    }
                }
                continuation.finish()
            }
        }
    }

    private func setState(_ newState: PipelineState, event: PipelineEvent) {
        let transition = PipelineStateTransition(from: state, to: newState, event: event)
        state = newState
        stateSubject.continuation.yield(transition)
        eventSubject.continuation.yield(event)
    }
}

// MARK: - Voice Agent Pipeline

/// Full conversational AI pipeline
@MainActor
public final class VoiceAgentPipeline: Pipeline {
    public typealias Config = VoiceAgentConfig

    public private(set) var state: PipelineState = .uninitialized
    public let config: VoiceAgentConfig

    private var voiceAgent: VoiceAgentComponent?

    private let stateSubject = AsyncStream<PipelineStateTransition>.makeStream()
    private let eventSubject = AsyncStream<PipelineEvent>.makeStream()

    public var stateTransitions: AsyncStream<PipelineStateTransition> {
        stateSubject.stream
    }

    public var events: AsyncStream<PipelineEvent> {
        eventSubject.stream
    }

    public init(config: VoiceAgentConfig) {
        self.config = config
    }

    public func initialize() async throws {
        setState(.initializing, event: .initialize)

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
        try await voiceAgent?.cleanup()
    }

    /// Start conversational session
    public func startConversation() -> AsyncStream<ConversationEvent> {
        AsyncStream { continuation in
            Task {
                guard let agent = voiceAgent else {
                    continuation.finish()
                    return
                }

                // Process voice pipeline
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
                        eventSubject.continuation.yield(.speechStarted)
                        continuation.yield(.listening)

                    case .vadSpeechEnd:
                        eventSubject.continuation.yield(.speechEnded)

                    case .sttPartialTranscript(let text):
                        continuation.yield(.partialTranscript(text))

                    case .sttFinalTranscript(let text):
                        eventSubject.continuation.yield(.transcriptionComplete(text))
                        continuation.yield(.finalTranscript(text))

                    case .llmThinking:
                        eventSubject.continuation.yield(.llmProcessing)
                        continuation.yield(.thinking)

                    case .llmStreamToken(let token):
                        continuation.yield(.responseToken(token))

                    case .llmFinalResponse(let response):
                        eventSubject.continuation.yield(.llmResponse(response))
                        continuation.yield(.response(response))

                    case .ttsAudioChunk(let chunk):
                        eventSubject.continuation.yield(.ttsStarted)
                        continuation.yield(.speaking(chunk))

                    case .ttsComplete:
                        eventSubject.continuation.yield(.ttsComplete)
                        continuation.yield(.speakingComplete)

                    default:
                        break
                    }
                }

                continuation.finish()
            }
        }
    }

    private func setState(_ newState: PipelineState, event: PipelineEvent) {
        let transition = PipelineStateTransition(from: state, to: newState, event: event)
        state = newState
        stateSubject.continuation.yield(transition)
        eventSubject.continuation.yield(event)
    }
}

// MARK: - Local LLM Pipeline

/// Pipeline for local text generation
@MainActor
public final class LocalLLMPipeline: Pipeline {
    public typealias Config = LocalLLMConfig

    public private(set) var state: PipelineState = .uninitialized
    public let config: LocalLLMConfig

    private var llmComponent: LLMComponent?

    private let stateSubject = AsyncStream<PipelineStateTransition>.makeStream()
    private let eventSubject = AsyncStream<PipelineEvent>.makeStream()

    public var stateTransitions: AsyncStream<PipelineStateTransition> {
        stateSubject.stream
    }

    public var events: AsyncStream<PipelineEvent> {
        eventSubject.stream
    }

    public init(config: LocalLLMConfig) {
        self.config = config
    }

    public func initialize() async throws {
        setState(.initializing, event: .initialize)

        let llmParams = LLMInitParameters(
            modelId: config.modelId,
            temperature: config.temperature,
            maxTokens: config.maxTokens,
            systemPrompt: config.systemPrompt,
            streamingEnabled: config.streamingEnabled
        )

        llmComponent = LLMComponent()
        try await llmComponent?.initialize(with: llmParams)

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
        try await llmComponent?.cleanup()
    }

    /// Generate text from prompt
    public func generate(_ prompt: String) async throws -> String {
        guard state == .ready || state == .processing else {
            throw SDKError.invalidState("Pipeline must be ready")
        }

        eventSubject.continuation.yield(.llmProcessing)

        guard let llm = llmComponent?.getService() else {
            throw SDKError.componentNotInitialized("LLM")
        }

        let options = RunAnywhereGenerationOptions(
            maxTokens: config.maxTokens,
            temperature: Float(config.temperature),
            systemPrompt: config.systemPrompt
        )

        let response = try await llm.generate(prompt: prompt, options: options)
        eventSubject.continuation.yield(.llmResponse(response))

        return response
    }

    /// Stream text generation
    public func generateStream(_ prompt: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                guard let llm = llmComponent?.getService() else {
                    continuation.finish()
                    return
                }

                eventSubject.continuation.yield(.llmProcessing)

                let options = RunAnywhereGenerationOptions(
                    maxTokens: config.maxTokens,
                    temperature: Float(config.temperature),
                    systemPrompt: config.systemPrompt
                )

                var fullResponse = ""

                try await llm.streamGenerate(
                    prompt: prompt,
                    options: options,
                    onToken: { token in
                        fullResponse += token
                        continuation.yield(token)
                    }
                )

                eventSubject.continuation.yield(.llmResponse(fullResponse))
                continuation.finish()
            }
        }
    }

    private func setState(_ newState: PipelineState, event: PipelineEvent) {
        let transition = PipelineStateTransition(from: state, to: newState, event: event)
        state = newState
        stateSubject.continuation.yield(transition)
        eventSubject.continuation.yield(event)
    }
}

// MARK: - Conversation Events

/// Events for conversational AI
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

// MARK: - Transcription Result

/// Result from transcription pipeline
public struct TranscriptionResult: Sendable {
    public let text: String
    public let speaker: SpeakerInfo?
    public let confidence: Float
    public let timestamp: Date

    public init(
        text: String,
        speaker: SpeakerInfo? = nil,
        confidence: Float = 1.0,
        timestamp: Date = Date()
    ) {
        self.text = text
        self.speaker = speaker
        self.confidence = confidence
        self.timestamp = timestamp
    }
}
