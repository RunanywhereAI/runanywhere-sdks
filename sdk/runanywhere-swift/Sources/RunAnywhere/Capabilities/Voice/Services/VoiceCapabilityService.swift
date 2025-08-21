import Foundation
import os

/// Main capability coordinator for voice processing
public class VoiceCapabilityService {
    private let logger = SDKLogger(category: "VoiceCapabilityService")

    // Services
    private let sessionManager: VoiceSessionManager
    private let analyticsService: VoiceAnalyticsService

    // State
    private var isInitialized = false

    public init() {
        self.sessionManager = VoiceSessionManager()
        self.analyticsService = VoiceAnalyticsService()
    }

    /// Initialize the voice capability
    public func initialize() async throws {
        guard !isInitialized else {
            logger.debug("Voice capability already initialized")
            return
        }

        logger.info("Initializing voice capability")

        // Initialize sub-services
        await sessionManager.initialize()
        await analyticsService.initialize()

        isInitialized = true
        logger.info("Voice capability initialized successfully")
    }

    /// Create a voice pipeline with the given configuration
    /// - Parameter config: Pipeline configuration
    /// - Returns: Configured voice pipeline manager
    public func createPipeline(config: ModularPipelineConfig) -> VoicePipelineManager {
        logger.debug("Creating voice pipeline with config: \(config.components)")

        // Track pipeline creation
        analyticsService.trackPipelineCreation(config: config)

        // Create and return pipeline
        return VoicePipelineManager(
            config: config,
            vadService: nil,
            voiceService: findVoiceService(for: config.stt?.modelId),
            llmService: findLLMService(for: config.llm?.modelId),
            ttsService: findTTSService(),
            speakerDiarization: nil,
            segmentationStrategy: nil
        )
    }

    /// Process voice with the given configuration
    /// - Parameters:
    ///   - audioStream: Stream of audio chunks
    ///   - config: Pipeline configuration
    /// - Returns: Stream of pipeline events
    public func processVoice(
        audioStream: AsyncStream<VoiceAudioChunk>,
        config: ModularPipelineConfig
    ) -> AsyncThrowingStream<ModularPipelineEvent, Error> {
        let pipeline = createPipeline(config: config)
        return pipeline.process(audioStream: audioStream)
    }

    /// Check if the voice capability is healthy
    /// - Returns: True if healthy, false otherwise
    public func isHealthy() -> Bool {
        return isInitialized && sessionManager.isHealthy() && analyticsService.isHealthy()
    }

    /// Get current metrics for voice processing
    /// - Returns: Voice metrics
    public func getMetrics() -> VoiceMetrics {
        return analyticsService.getMetrics()
    }

    // MARK: - Service Discovery

    /// Find voice service for the given model ID
    public func findVoiceService(for modelId: String?) -> VoiceService? {
        guard let modelId = modelId else { return nil }

        logger.debug("Finding voice service for model: \(modelId)")

        // This would integrate with the SDK's model loading service
        // For now, return nil - actual implementation would use ServiceContainer
        return nil
    }

    /// Find LLM service for the given model ID
    private func findLLMService(for modelId: String?) -> LLMService? {
        guard let modelId = modelId else { return nil }

        logger.debug("Finding LLM service for model: \(modelId)")

        // This would integrate with the SDK's model loading service
        // For now, return nil - actual implementation would use ServiceContainer
        return nil
    }

    /// Find TTS service
    public func findTTSService() -> TextToSpeechService? {
        logger.debug("Finding TTS service")

        // Return system TTS service by default
        // In actual implementation, this would check available services
        return nil
    }
}
