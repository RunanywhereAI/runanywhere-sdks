import Foundation
import RunAnywhere

/// ONNX Runtime adapter for multi-modal inference
public class ONNXAdapter: FrameworkAdapter {
    private let logger = SDKLogger(category: "ONNXAdapter")

    // Singleton instance to ensure caching works across the app
    public static let shared = ONNXAdapter()

    // MARK: - Properties

    public let framework: LLMFramework = .onnx

    public let supportedModalities: Set<FrameworkModality> = [.voiceToText, .textToVoice, .textToText]

    public let supportedFormats: [ModelFormat] = [.onnx, .ort]

    // Cache service instances to avoid re-initialization
    private var cachedSTTService: ONNXSTTService?
    private var cachedTTSService: ONNXTTSService?

    // Track last usage for smart cleanup
    private var lastSTTUsage: Date?
    private var lastTTSUsage: Date?
    private let cacheTimeout: TimeInterval = 300 // 5 minutes

    // MARK: - FrameworkAdapter Implementation

    public func canHandle(model: ModelInfo) -> Bool {
        // Check if model is compatible with ONNX Runtime
        let canHandle = model.compatibleFrameworks.contains(.onnx) &&
                       (model.category == .speechRecognition ||
                        model.category == .speechSynthesis ||
                        model.category == .language)
        logger.debug("canHandle(\(model.name)): \(canHandle)")
        return canHandle
    }

    public func createService(for modality: FrameworkModality) -> Any? {
        logger.info("createService for modality: \(modality.rawValue)")
        switch modality {
        case .voiceToText:
            // Check if cached service should be cleaned up
            cleanupStaleCache()

            // Return cached instance if available
            if let cached = cachedSTTService {
                logger.info("Returning cached ONNXSTTService for voice-to-text")
                lastSTTUsage = Date()
                return cached
            }
            logger.info("Creating new ONNXSTTService for voice-to-text")
            let service = ONNXSTTService()
            cachedSTTService = service
            lastSTTUsage = Date()
            return service

        case .textToVoice:
            // Check if cached service should be cleaned up
            cleanupStaleCache()

            // Return cached instance if available
            if let cached = cachedTTSService {
                logger.info("Returning cached ONNXTTSService for text-to-voice")
                lastTTSUsage = Date()
                return cached
            }
            // Note: TTS service requires a model path, so we just return nil here
            // The actual service creation happens in loadModel
            logger.info("TTS service requires model path - use loadModel instead")
            return nil

        case .textToText:
            // Reserved for future LLM implementation
            logger.warning("LLM support not yet implemented")
            return nil

        default:
            logger.warning("Unsupported modality: \(modality.rawValue)")
            return nil
        }
    }

    public func loadModel(_ model: ModelInfo, for modality: FrameworkModality) async throws -> Any {
        logger.info("loadModel(\(model.name)) for modality: \(modality.rawValue)")
        switch modality {
        case .voiceToText:
            // Check if cached service should be cleaned up
            cleanupStaleCache()

            // Use cached service if available
            let service: ONNXSTTService
            if let cached = cachedSTTService {
                logger.info("Using cached ONNXSTTService for initialization")
                service = cached
            } else {
                logger.info("Creating new ONNXSTTService for initialization")
                service = ONNXSTTService()
                cachedSTTService = service
            }

            // Initialize with model path if available
            let modelPath = model.localPath?.path
            logger.debug("Model path: \(modelPath ?? "nil")")
            try await service.initialize(modelPath: modelPath)
            logger.info("ONNXSTTService initialized")
            lastSTTUsage = Date()
            return service

        case .textToVoice:
            // Check if cached service should be cleaned up
            cleanupStaleCache()

            // Get model path
            guard let modelPath = model.localPath?.path else {
                logger.error("TTS model path not available")
                throw SDKError.modelNotFound("TTS model path not available")
            }

            // Create new TTS service with model path
            logger.info("Creating ONNXTTSService with model path: \(modelPath)")
            let service = ONNXTTSService(modelPath: modelPath)
            try await service.initialize()
            cachedTTSService = service
            lastTTSUsage = Date()
            logger.info("ONNXTTSService initialized")
            return service

        case .textToText:
            logger.error("LLM support not yet implemented")
            throw SDKError.unsupportedModality(modality.rawValue)

        default:
            logger.error("Unsupported modality: \(modality.rawValue)")
            throw SDKError.unsupportedModality(modality.rawValue)
        }
    }

    public func estimateMemoryUsage(for model: ModelInfo) -> Int64 {
        return model.memoryRequired ?? 0
    }

    /// Called when adapter is registered with the SDK
    /// Registers the STT and TTS service providers with ModuleRegistry
    @MainActor
    public func onRegistration() {
        ModuleRegistry.shared.registerSTT(ONNXSTTServiceProvider())
        ModuleRegistry.shared.registerTTS(ONNXTTSServiceProvider())
        logger.info("Registered ONNXSTTServiceProvider and ONNXTTSServiceProvider with ModuleRegistry")
    }

    public func getProvidedModels() -> [ModelInfo] {
        // No pre-bundled models
        return []
    }

    public func getDownloadStrategy() -> DownloadStrategy? {
        // Return custom strategy for handling .tar.bz2 archives
        return ONNXDownloadStrategy()
    }

    public func initializeComponent(
        with parameters: any ComponentInitParameters,
        for modality: FrameworkModality
    ) async throws -> Any? {
        // Use createService for initialization
        return createService(for: modality)
    }

    // MARK: - Private Helpers

    private func cleanupStaleCache() {
        // Clean up STT service if not used recently
        if let lastUsage = lastSTTUsage,
           Date().timeIntervalSince(lastUsage) > cacheTimeout {
            logger.info("Cleaning up stale ONNXSTTService cache")
            cachedSTTService = nil
            lastSTTUsage = nil
        }

        // Clean up TTS service if not used recently
        if let lastUsage = lastTTSUsage,
           Date().timeIntervalSince(lastUsage) > cacheTimeout {
            logger.info("Cleaning up stale ONNXTTSService cache")
            cachedTTSService = nil
            lastTTSUsage = nil
        }
    }
}
