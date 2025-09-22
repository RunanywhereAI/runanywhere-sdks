import Foundation

// MARK: - Voice Agent Service

/// Service wrapper for voice agent since it doesn't have an external service
public final class VoiceAgentService: @unchecked Sendable {
    public init() {}
}

// MARK: - Voice Agent Component

/// Voice Agent component that orchestrates VAD, STT, LLM, and TTS components
/// Can be used as a complete pipeline or with individual components
@MainActor
public final class VoiceAgentComponent: BaseComponent<VoiceAgentService>, @unchecked Sendable {

    // MARK: - Properties

    public override class var componentType: SDKComponent { .voiceAgent }

    // Individual components (accessible for custom orchestration)
    public private(set) var vadComponent: VADComponent?
    public private(set) var sttComponent: STTComponent?
    public private(set) var llmComponent: LLMComponent?
    public private(set) var ttsComponent: TTSComponent?

    // Configuration
    private let agentParams: VoiceAgentConfiguration

    // State
    private var isProcessing = false
    private let processQueue = DispatchQueue(label: "com.runanywhere.voiceagent", qos: .userInteractive)

    // MARK: - Initialization

    public init(configuration: VoiceAgentConfiguration, serviceContainer: ServiceContainer? = nil) {
        self.agentParams = configuration
        super.init(configuration: configuration, serviceContainer: serviceContainer)
    }

    // MARK: - Service Creation

    public override func createService() async throws -> VoiceAgentService {
        // Voice agent doesn't need an external service, it orchestrates other components
        return VoiceAgentService()
    }

    public override func initializeService() async throws {
        // Initialize all components
        try await initializeComponents()
        eventBus.publish(SDKVoiceEvent.pipelineStarted)
    }

    private func initializeComponents() async throws {
        // Initialize VAD (required)
        vadComponent = VADComponent(configuration: agentParams.vadConfig)
        try await vadComponent?.initialize()

        // Initialize STT (required)
        sttComponent = STTComponent(configuration: agentParams.sttConfig)
        try await sttComponent?.initialize()

        // Initialize LLM (required)
        llmComponent = LLMComponent(configuration: agentParams.llmConfig)
        try await llmComponent?.initialize()

        // Initialize TTS (required)
        ttsComponent = TTSComponent(configuration: agentParams.ttsConfig)
        try await ttsComponent?.initialize()
    }

    // MARK: - Pipeline Processing

    /// Process audio through the full pipeline
    public func processAudio(_ audioData: Data) async throws -> VoiceAgentResult {
        guard state == .ready else {
            throw SDKError.notInitialized("Voice agent component not initialized")
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
                audioData: audioData,
                options: STTOptions()
            )
            result.transcription = transcription.transcript
            eventBus.publish(SDKVoiceEvent.transcriptionFinal(text: transcription.transcript))
        }

        // LLM Processing
        if let llm = llmComponent?.getService(),
           let transcript = result.transcription {
            let response = try await llm.generate(
                prompt: transcript,
                options: RunAnywhereGenerationOptions(
                    maxTokens: agentParams.llmConfig.maxTokens,
                    temperature: Float(agentParams.llmConfig.temperature)
                )
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
        let result = try await stt.transcribe(audioData: audioData, options: STTOptions())
        return result.transcript
    }

    /// Process only through LLM
    public func generateResponse(_ prompt: String) async throws -> String? {
        guard let llm = llmComponent?.getService() else { return nil }
        let result = try await llm.generate(
            prompt: prompt,
            options: RunAnywhereGenerationOptions(
                maxTokens: agentParams.llmConfig.maxTokens,
                temperature: Float(agentParams.llmConfig.temperature)
            )
        )
        return result
    }

    /// Process only through TTS
    public func synthesizeSpeech(_ text: String) async throws -> Data? {
        guard let tts = ttsComponent?.getService() else { return nil }
        return try await tts.synthesize(text: text, options: TTSOptions())
    }

    // MARK: - Cleanup

    public override func performCleanup() async throws {
        isProcessing = false

        try? await vadComponent?.cleanup()
        try? await sttComponent?.cleanup()
        try? await llmComponent?.cleanup()
        try? await ttsComponent?.cleanup()

        vadComponent = nil
        sttComponent = nil
        llmComponent = nil
        ttsComponent = nil
    }
}

// VoiceAgentInitParameters has been replaced by VoiceAgentConfiguration
// which is defined in ComponentInitializationParameters.swift

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
