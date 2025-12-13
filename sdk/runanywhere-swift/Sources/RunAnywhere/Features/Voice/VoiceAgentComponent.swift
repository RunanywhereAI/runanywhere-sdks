import Foundation

// MARK: - Voice Agent Component

/// Voice Agent component that orchestrates VAD, STT, LLM, and TTS components
/// Follows the canonical BaseComponent<ServiceWrapper> architecture pattern
@MainActor
public final class VoiceAgentComponent: BaseComponent<VoiceServiceWrapper>, @unchecked Sendable {

    // MARK: - Properties

    public override static var componentType: SDKComponent { .voiceAgent }

    // Individual components (accessible for custom orchestration)
    public private(set) var vadComponent: VADComponent?
    public private(set) var sttComponent: STTComponent?
    public private(set) var llmComponent: LLMComponent?
    public private(set) var ttsComponent: TTSComponent?

    // Configuration
    private let agentParams: VoiceAgentConfiguration
    private let logger = SDKLogger(category: "VoiceAgentComponent")

    // MARK: - Initialization

    public init(configuration: VoiceAgentConfiguration, serviceContainer: ServiceContainer? = nil) {
        self.agentParams = configuration
        super.init(configuration: configuration, serviceContainer: serviceContainer)
    }

    // MARK: - Service Creation

    public override func createService() async throws -> VoiceServiceWrapper {
        logger.info("Creating Voice Agent service")

        // Initialize all components
        try await initializeComponents()

        // Create the voice service with initialized components
        let voiceService = DefaultVoiceService(
            vadComponent: vadComponent,
            sttComponent: sttComponent,
            llmComponent: llmComponent,
            ttsComponent: ttsComponent,
            eventBus: eventBus
        )

        return VoiceServiceWrapper(voiceService)
    }

    public override func initializeService() async throws {
        // Service initialization is handled in createService
        eventBus.publish(SDKVoiceEvent.pipelineStarted)
    }

    private func initializeComponents() async throws {
        logger.debug("Initializing voice pipeline components")

        // Initialize VAD (required)
        vadComponent = VADComponent(configuration: agentParams.vadConfig)
        try await vadComponent?.initialize()
        logger.debug("VAD component initialized")

        // Initialize STT (required)
        sttComponent = STTComponent(configuration: agentParams.sttConfig)
        try await sttComponent?.initialize()
        logger.debug("STT component initialized")

        // Initialize LLM (required)
        llmComponent = LLMComponent(configuration: agentParams.llmConfig)
        try await llmComponent?.initialize()
        logger.debug("LLM component initialized")

        // Initialize TTS (required)
        ttsComponent = TTSComponent(configuration: agentParams.ttsConfig)
        try await ttsComponent?.initialize()
        logger.debug("TTS component initialized")

        logger.info("All voice pipeline components initialized successfully")
    }

    // MARK: - Helper Methods

    private var voiceService: (any VoiceService)? {
        return service?.wrappedService
    }

    // MARK: - Pipeline Processing

    /// Process audio through the full pipeline
    public func processAudio(_ audioData: Data) async throws -> VoiceAgentResult {
        try ensureReady()

        guard let voiceService = voiceService else {
            throw RunAnywhereError.componentNotReady("Voice service not available")
        }

        let startTime = Date()
        logger.info("Processing audio through voice pipeline")

        // Submit analytics event for pipeline start
        Task.detached(priority: .background) {
            await self.trackPipelineEvent(.pipelineStarted, processingTime: nil)
        }

        do {
            let result = try await voiceService.processAudio(audioData)
            let processingTime = Date().timeIntervalSince(startTime)

            // Submit success analytics
            Task.detached(priority: .background) {
                await self.trackPipelineEvent(.pipelineCompleted, processingTime: processingTime, success: true)
            }

            logger.info("Audio processed successfully in \(String(format: "%.2f", processingTime))s")
            return result
        } catch {
            let processingTime = Date().timeIntervalSince(startTime)

            // Submit failure analytics
            Task.detached(priority: .background) {
                await self.trackPipelineEvent(
                    .pipelineFailed,
                    processingTime: processingTime,
                    success: false,
                    errorMessage: error.localizedDescription
                )
            }

            logger.error("Audio processing failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Process audio stream for continuous conversation
    public func processStream(_ audioStream: AsyncStream<Data>) -> AsyncThrowingStream<VoiceAgentEvent, Error> {
        guard let voiceService = voiceService else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: RunAnywhereError.componentNotReady("Voice service not available"))
            }
        }
        return voiceService.processStream(audioStream)
    }

    // MARK: - Individual Component Access

    /// Process only through VAD
    public func detectVoiceActivity(_ audioData: Data) -> Bool {
        guard let voiceService = voiceService else { return true }
        return voiceService.detectVoiceActivity(audioData)
    }

    /// Process only through STT
    public func transcribe(_ audioData: Data) async throws -> String? {
        try ensureReady()
        guard let voiceService = voiceService else { return nil }
        return try await voiceService.transcribe(audioData)
    }

    /// Process only through LLM
    public func generateResponse(_ prompt: String) async throws -> String? {
        try ensureReady()
        guard let voiceService = voiceService else { return nil }
        return try await voiceService.generateResponse(prompt)
    }

    /// Process only through TTS
    public func synthesizeSpeech(_ text: String) async throws -> Data? {
        try ensureReady()
        guard let voiceService = voiceService else { return nil }
        return try await voiceService.synthesizeSpeech(text)
    }

    // MARK: - Analytics

    private func trackPipelineEvent(
        _ eventType: VoiceEventType,
        processingTime: TimeInterval?,
        success: Bool = true,
        errorMessage: String? = nil
    ) async {
        let deviceInfo = TelemetryDeviceInfo.current
        let eventData = VoicePipelineEventData(
            eventType: eventType,
            timestamp: Date(),
            sessionId: nil,
            vadEnabled: vadComponent != nil,
            sttModelId: agentParams.sttConfig.modelId,
            llmModelId: agentParams.llmConfig.modelId,
            ttsEnabled: ttsComponent != nil,
            processingTimeMs: processingTime.map { $0 * 1000 },
            success: success,
            errorMessage: errorMessage,
            deviceInfo: deviceInfo
        )

        let event = VoiceEvent(type: eventType, eventData: eventData)
        await AnalyticsQueueManager.shared.enqueue(event)
        await AnalyticsQueueManager.shared.flush()
    }

    // MARK: - Cleanup

    public override func performCleanup() async throws {
        logger.info("Cleaning up voice pipeline components")

        // Cleanup service
        try? await voiceService?.cleanup()

        // Clear component references
        vadComponent = nil
        sttComponent = nil
        llmComponent = nil
        ttsComponent = nil

        logger.info("Voice pipeline cleanup complete")
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
