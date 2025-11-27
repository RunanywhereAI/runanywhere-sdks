import Foundation

/// Main capability coordinator for voice processing using the new component system
public class VoiceCapabilityService: @unchecked Sendable {
    private let logger = SDKLogger(category: "VoiceCapabilityService")

    // Services
    private let sessionManager: VoiceSessionManager
    private var analyticsService: VoiceAnalyticsService?
    private var sttAnalyticsService: STTAnalyticsService?

    // State
    private var isInitialized = false

    // Active voice agents
    private var activeAgents: [UUID: VoiceAgentComponent] = [:]
    private let agentQueue = DispatchQueue(label: "com.runanywhere.voiceagents", attributes: .concurrent)

    public init() {
        self.sessionManager = VoiceSessionManager()
    }

    /// Initialize the voice capability
    public func initialize() async throws {
        guard !isInitialized else {
            logger.debug("Voice capability already initialized")
            return
        }

        logger.info("Initializing voice capability")

        // Get analytics services from container
        analyticsService = await ServiceContainer.shared.voiceAnalytics
        sttAnalyticsService = await ServiceContainer.shared.sttAnalytics

        // Initialize sub-services
        await sessionManager.initialize()

        isInitialized = true
        logger.info("Voice capability initialized successfully")
    }

    /// Create a voice agent with the given parameters
    /// - Parameters:
    ///   - vadParams: VAD parameters (optional)
    ///   - sttParams: STT parameters (optional)
    ///   - llmParams: LLM parameters (optional)
    ///   - ttsParams: TTS parameters (optional)
    /// - Returns: Configured voice agent component
    @MainActor
    public func createVoiceAgent(
        vadParams: VADConfiguration? = nil,
        sttParams: STTConfiguration? = nil,
        llmParams: LLMConfiguration? = nil,
        ttsParams: TTSConfiguration? = nil
    ) async throws -> VoiceAgentComponent {
        logger.debug("Creating voice agent with custom parameters")

        // Create agent configuration (all components are required, use defaults if not provided)
        let agentConfig = VoiceAgentConfiguration(
            vadConfig: vadParams ?? VADConfiguration(),
            sttConfig: sttParams ?? STTConfiguration(),
            llmConfig: llmParams ?? LLMConfiguration(),
            ttsConfig: ttsParams ?? TTSConfiguration()
        )

        // Create and initialize agent
        let agent = await VoiceAgentComponent(
            configuration: agentConfig,
            serviceContainer: ServiceContainer.shared
        )

        try await agent.initialize()

        // Track agent
        let agentId = UUID()
        agentQueue.async(flags: .barrier) { [weak self] in
            self?.activeAgents[agentId] = agent
        }

        // Track analytics
        Task {
            await analyticsService?.trackPipelineCreation(
                stages: [
                    vadParams != nil ? "vad" : nil,
                    sttParams != nil ? "stt" : nil,
                    llmParams != nil ? "llm" : nil,
                    ttsParams != nil ? "tts" : nil
                ].compactMap { $0 }
            )
        }

        return agent
    }

    /// Create a full voice pipeline with all components
    public func createFullPipeline(
        sttModelId: String? = nil,
        llmModelId: String? = nil
    ) async throws -> VoiceAgentComponent {
        return try await createVoiceAgent(
            vadParams: VADConfiguration(),
            sttParams: STTConfiguration(modelId: sttModelId),
            llmParams: LLMConfiguration(modelId: llmModelId),
            ttsParams: TTSConfiguration()
        )
    }

    /// Process voice with a custom pipeline configuration
    public func processVoice(
        audioStream: AsyncStream<VoiceAudioChunk>,
        vadParams: VADConfiguration? = nil,
        sttParams: STTConfiguration? = nil,
        llmParams: LLMConfiguration? = nil,
        ttsParams: TTSConfiguration? = nil
    ) -> AsyncThrowingStream<VoiceAgentEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Create agent
                    let agent = try await createVoiceAgent(
                        vadParams: vadParams,
                        sttParams: sttParams,
                        llmParams: llmParams,
                        ttsParams: ttsParams
                    )

                    // Convert audio chunks to Data stream
                    let dataStream = AsyncStream<Data> { dataContinuation in
                        Task {
                            for await chunk in audioStream {
                                dataContinuation.yield(chunk.data)
                            }
                            dataContinuation.finish()
                        }
                    }

                    // Process through agent
                    let eventStream = await agent.processStream(dataStream)

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

    /// Find voice service for a specific model
    @MainActor
    public func findVoiceService(for modelId: String?) async -> STTService? {
        // Check if any active agent has STT with the specified model
        let agents = agentQueue.sync { Array(activeAgents.values) }
        for agent in agents {
            if let stt = agent.sttComponent?.getService() {
                return stt
            }
        }
        return nil
    }

    /// Find LLM service for a specific model
    @MainActor
    public func findLLMService(for modelId: String?) async -> LLMService? {
        // Check if any active agent has LLM with the specified model
        let agents = agentQueue.sync { Array(activeAgents.values) }
        for agent in agents {
            if let llm = agent.llmComponent?.getService() {
                return llm
            }
        }
        return nil
    }

    /// Find TTS service
    @MainActor
    public func findTTSService() async -> TTSService? {
        // Check if any active agent has TTS
        let agents = agentQueue.sync { Array(activeAgents.values) }
        for agent in agents {
            if let tts = agent.ttsComponent?.getService() {
                return tts
            }
        }
        return nil
    }

    /// Clean up all active agents
    public func cleanup() async throws {
        let agents = agentQueue.sync { Array(activeAgents.values) }

        for agent in agents {
            try await agent.cleanup()
        }

        agentQueue.async(flags: .barrier) { [weak self] in
            self?.activeAgents.removeAll()
        }
    }
}

// MARK: - Backward Compatibility

extension VoiceCapabilityService {
    /// Create a voice pipeline using the new architecture
    public func createPipeline(
        vadParams: VADConfiguration? = nil,
        sttParams: STTConfiguration? = nil,
        llmParams: LLMConfiguration? = nil,
        ttsParams: TTSConfiguration? = nil
    ) async throws -> VoiceAgentComponent {
        // Use the new VoiceAgent component which is the modern pipeline
        return try await createVoiceAgent(
            vadParams: vadParams,
            sttParams: sttParams,
            llmParams: llmParams,
            ttsParams: ttsParams
        )
    }
}
