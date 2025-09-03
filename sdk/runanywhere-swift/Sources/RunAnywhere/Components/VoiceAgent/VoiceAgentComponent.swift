import Foundation

// MARK: - Voice Agent Component

/// Voice Agent component that orchestrates VAD, STT, LLM, and TTS components
/// Can be used as a complete pipeline or with individual components
@MainActor
public final class VoiceAgentComponent: BaseComponent, @unchecked Sendable {

    // MARK: - Properties

    public override class var componentType: SDKComponent { .voiceAgent }

    // Individual components (accessible for custom orchestration)
    public private(set) var vadComponent: VADComponent?
    public private(set) var sttComponent: STTComponent?
    public private(set) var llmComponent: LLMComponent?
    public private(set) var ttsComponent: TTSComponent?

    // Configuration
    private let agentParams: VoiceAgentInitParameters

    // State
    private var isProcessing = false
    private let processQueue = DispatchQueue(label: "com.runanywhere.voiceagent", qos: .userInteractive)

    // MARK: - Initialization

    public required init(parameters: any ComponentInitParameters, serviceContainer: ServiceContainer? = nil) {
        guard let voiceParams = parameters as? VoiceAgentInitParameters else {
            fatalError("VoiceAgentComponent requires VoiceAgentInitParameters")
        }
        self.agentParams = voiceParams
        super.init(parameters: parameters, serviceContainer: serviceContainer)
    }

    // MARK: - Component Lifecycle

    public override func initialize(with parameters: any ComponentInitParameters) async throws {
        guard let params = parameters as? VoiceAgentInitParameters else {
            throw SDKError.validationFailed("Invalid parameters for VoiceAgentComponent")
        }

        try await super.initialize(with: parameters)

        // Initialize all components (all are required for voice agent)
        try await initializeComponents(params)

        await transitionTo(state: .ready)
        eventBus.publish(SDKVoiceEvent.pipelineStarted)
    }

    private func initializeComponents(_ params: VoiceAgentInitParameters) async throws {
        // Initialize VAD (required)
        vadComponent = VADComponent(parameters: params.vadParameters, serviceContainer: serviceContainer)
        try await vadComponent?.initialize(with: params.vadParameters)
        logger.info("VAD component initialized")

        // Initialize STT (required)
        sttComponent = STTComponent(parameters: params.sttParameters, serviceContainer: serviceContainer)
        try await sttComponent?.initialize(with: params.sttParameters)
        logger.info("STT component initialized")

        // Initialize LLM (required)
        llmComponent = LLMComponent(parameters: params.llmParameters, serviceContainer: serviceContainer)
        try await llmComponent?.initialize(with: params.llmParameters)
        logger.info("LLM component initialized")

        // Initialize TTS (required)
        ttsComponent = TTSComponent(parameters: params.ttsParameters, serviceContainer: serviceContainer)
        try await ttsComponent?.initialize(with: params.ttsParameters)
        logger.info("TTS component initialized")
    }

    // MARK: - Pipeline Processing

    /// Process audio through the full pipeline
    public func processAudio(_ audioData: Data) async throws -> VoiceAgentResult {
        guard state == .ready else {
            throw SDKError.notInitialized
        }

        isProcessing = true
        defer { isProcessing = false }

        var result = VoiceAgentResult()

        // VAD Processing
        if let vad = vadComponent?.getService() {
            let floatData = audioData.toFloatArray()
            let isSpeech = vad.processAudioData(floatData)
            result.speechDetected = isSpeech

            if !isSpeech {
                return result // No speech, return early
            }

            eventBus.publish(SDKVoiceEvent.speechDetected)
        }

        // STT Processing
        if let stt = sttComponent?.getService() {
            let transcription = try await stt.transcribe(
                audio: audioData,
                options: STTOptions()
            )
            result.transcription = transcription.text
            eventBus.publish(SDKVoiceEvent.transcriptionFinal(text: transcription.text))
        }

        // LLM Processing
        if let llm = llmComponent?.getService(),
           let transcript = result.transcription {
            let response = try await llm.generate(
                prompt: transcript,
                options: agentParams.generationOptions
            )
            result.response = response
            eventBus.publish(SDKVoiceEvent.responseGenerated(text: response))
        }

        // TTS Processing
        if let tts = ttsComponent?.getService(),
           let responseText = result.response {
            let audioData = try await tts.synthesize(
                text: responseText,
                options: TTSOptions()
            )
            result.synthesizedAudio = audioData
            eventBus.publish(SDKVoiceEvent.audioGenerated(data: audioData))
        }

        return result
    }

    /// Process audio stream for continuous conversation
    public func processStream(_ audioStream: AsyncStream<Data>) -> AsyncThrowingStream<VoiceAgentEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    for await audioData in audioStream {
                        let result = try await processAudio(audioData)
                        continuation.yield(.processed(result))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Individual Component Access

    /// Process only through VAD
    public func detectVoiceActivity(_ audioData: Data) -> Bool {
        guard let vad = vadComponent?.getService() else { return true }
        let floatData = audioData.toFloatArray()
        return vad.processAudioData(floatData)
    }

    /// Process only through STT
    public func transcribe(_ audioData: Data) async throws -> String? {
        guard let stt = sttComponent?.getService() else { return nil }
        let result = try await stt.transcribe(audio: audioData, options: STTOptions())
        return result.text
    }

    /// Process only through LLM
    public func generateResponse(_ prompt: String) async throws -> String? {
        guard let llm = llmComponent?.getService() else { return nil }
        let result = try await llm.generate(prompt: prompt, options: agentParams.generationOptions)
        return result
    }

    /// Process only through TTS
    public func synthesizeSpeech(_ text: String) async throws -> Data? {
        guard let tts = ttsComponent?.getService() else { return nil }
        return try await tts.synthesize(text: text, options: TTSOptions())
    }

    // MARK: - Cleanup

    public override func cleanup() async throws {
        isProcessing = false

        try await vadComponent?.cleanup()
        try await sttComponent?.cleanup()
        try await llmComponent?.cleanup()
        try await ttsComponent?.cleanup()

        vadComponent = nil
        sttComponent = nil
        llmComponent = nil
        ttsComponent = nil

        try await super.cleanup()
    }
}

// MARK: - Voice Agent Initialization Parameters

/// Parameters for initializing the Voice Agent (all components are required)
public struct VoiceAgentInitParameters: ComponentInitParameters {
    public let componentType = SDKComponent.voiceAgent
    public let modelId: String? = nil // Voice agent doesn't have a single model

    // All components are required for voice agent
    public let vadParameters: VADInitParameters
    public let sttParameters: STTInitParameters
    public let llmParameters: LLMInitParameters
    public let ttsParameters: TTSInitParameters

    // Pipeline configuration
    public let generationOptions: RunAnywhereGenerationOptions
    public let streamingEnabled: Bool

    public init(
        vadParameters: VADInitParameters = VADInitParameters(),
        sttParameters: STTInitParameters = STTInitParameters(),
        llmParameters: LLMInitParameters = LLMInitParameters(),
        ttsParameters: TTSInitParameters = TTSInitParameters(),
        generationOptions: RunAnywhereGenerationOptions = RunAnywhereGenerationOptions(),
        streamingEnabled: Bool = false
    ) {
        self.vadParameters = vadParameters
        self.sttParameters = sttParameters
        self.llmParameters = llmParameters
        self.ttsParameters = ttsParameters
        self.generationOptions = generationOptions
        self.streamingEnabled = streamingEnabled
    }

    public func validate() throws {
        // Validate all component parameters
        try vadParameters.validate()
        try sttParameters.validate()
        try llmParameters.validate()
        try ttsParameters.validate()
    }
}

// MARK: - Voice Agent Result

/// Result from voice agent processing
public struct VoiceAgentResult: Sendable {
    public var speechDetected: Bool = false
    public var transcription: String?
    public var response: String?
    public var synthesizedAudio: Data?

    public init(
        speechDetected: Bool = false,
        transcription: String? = nil,
        response: String? = nil,
        synthesizedAudio: Data? = nil
    ) {
        self.speechDetected = speechDetected
        self.transcription = transcription
        self.response = response
        self.synthesizedAudio = synthesizedAudio
    }
}

// MARK: - Voice Agent Events

/// Events emitted by the voice agent
public enum VoiceAgentEvent: Sendable {
    case processed(VoiceAgentResult)
    case vadTriggered(Bool)
    case transcriptionAvailable(String)
    case responseGenerated(String)
    case audioSynthesized(Data)
    case error(Error)
}

// MARK: - Helper Extensions

private extension Data {
    func toFloatArray() -> [Float] {
        // Convert Data to Float array for VAD processing
        let count = self.count / MemoryLayout<Float>.size
        return self.withUnsafeBytes { bytes in
            Array(UnsafeBufferPointer(
                start: bytes.bindMemory(to: Float.self).baseAddress,
                count: count
            ))
        }
    }
}
