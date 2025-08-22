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

        // Access ServiceContainer through shared instance
        let container = ServiceContainer.shared

        // Try to find a model info for this modelId
        if let model = try? container.modelRegistry.getModel(by: modelId) {
            // Find adapter that can handle this model
            if let unifiedAdapter = container.adapterRegistry.findBestAdapter(for: model),
               unifiedAdapter.supportedModalities.contains(FrameworkModality.voiceToText) {
                // Create a voice service from the unified adapter
                if let voiceService = unifiedAdapter.createService(for: FrameworkModality.voiceToText) as? VoiceService {
                    return voiceService
                }
            }
        }

        // Fallback: Find any framework that supports voice-to-text
        let voiceFrameworks = container.adapterRegistry.getFrameworks(for: FrameworkModality.voiceToText)
        if let firstVoiceFramework = voiceFrameworks.first,
           let adapter = container.adapterRegistry.getAdapter(for: firstVoiceFramework) {
            if let voiceService = adapter.createService(for: FrameworkModality.voiceToText) as? VoiceService {
                return voiceService
            }
        }

        return nil
    }

    /// Find LLM service for the given model ID
    private func findLLMService(for modelId: String?) -> LLMService? {
        let container = ServiceContainer.shared

        // First, check if there's already a loaded model in the GenerationService
        if let currentModel = container.generationService.getCurrentModel() {
            return currentModel.service
        }

        // If no model is loaded and a specific modelId is requested
        guard let modelId = modelId else { return nil }

        logger.debug("Finding LLM service for model: \(modelId)")

        if let model = try? container.modelRegistry.getModel(by: modelId) {
            // Find adapter that can handle this model
            if let unifiedAdapter = container.adapterRegistry.findBestAdapter(for: model),
               unifiedAdapter.supportedModalities.contains(FrameworkModality.textToText) {
                // Create an LLM service from the unified adapter
                if let llmService = unifiedAdapter.createService(for: FrameworkModality.textToText) as? LLMService {
                    return llmService
                }
            }
        }

        // Fallback: Find any framework that supports text generation
        let textFrameworks = container.adapterRegistry.getFrameworks(for: FrameworkModality.textToText)
        if let firstTextFramework = textFrameworks.first,
           let adapter = container.adapterRegistry.getAdapter(for: firstTextFramework) {
            if let llmService = adapter.createService(for: FrameworkModality.textToText) as? LLMService {
                return llmService
            }
        }

        return nil
    }

    /// Find TTS service
    public func findTTSService() -> TextToSpeechService? {
        logger.debug("Finding TTS service")

        // Return system TTS service by default
        return SystemTextToSpeechService()
    }
}
