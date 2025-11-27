import Foundation
import RunAnywhere

/// ONNX Runtime adapter for multi-modal inference
public class ONNXAdapter: UnifiedFrameworkAdapter {
    private let logger = SDKLogger(category: "ONNXAdapter")

    // Singleton instance to ensure caching works across the app
    public static let shared = ONNXAdapter()

    // MARK: - Properties

    public let framework: LLMFramework = .onnx

    public let supportedModalities: Set<FrameworkModality> = [.voiceToText, .textToText]

    public let supportedFormats: [ModelFormat] = [.onnx, .ort]

    // Cache service instances to avoid re-initialization
    private var cachedSTTService: ONNXSTTService?
    private var cachedLLMService: Any? // Reserved for future LLM implementation

    // Track last usage for smart cleanup
    private var lastSTTUsage: Date?
    private let cacheTimeout: TimeInterval = 300 // 5 minutes

    // MARK: - UnifiedFrameworkAdapter Implementation

    public func canHandle(model: ModelInfo) -> Bool {
        // Check if model is compatible with ONNX Runtime
        let canHandle = model.compatibleFrameworks.contains(.onnx) &&
                       (model.category == .speechRecognition || model.category == .language)
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

        case .textToText:
            logger.error("LLM support not yet implemented")
            throw SDKError.unsupportedModality(modality.rawValue)

        default:
            logger.error("Unsupported modality: \(modality.rawValue)")
            throw SDKError.unsupportedModality(modality.rawValue)
        }
    }

    public func configure(with hardware: HardwareConfiguration) async {
        // ONNX Runtime will use CPU by default
        // Future: Could configure execution providers here (CoreML, etc.)
        logger.info("Hardware configuration: \(hardware.primaryAccelerator.rawValue)")
    }

    public func estimateMemoryUsage(for model: ModelInfo) -> Int64 {
        return model.memoryRequired ?? 0
    }

    public func optimalConfiguration(for model: ModelInfo) -> HardwareConfiguration {
        // For now, use CPU. Future: detect available hardware and use CoreML if available
        return HardwareConfiguration(primaryAccelerator: .cpu)
    }

    /// Called when adapter is registered with the SDK
    /// Registers the STT service provider with ModuleRegistry
    @MainActor
    public func onRegistration() {
        ModuleRegistry.shared.registerSTT(ONNXSTTServiceProvider())
        logger.info("Registered ONNXServiceProvider with ModuleRegistry")
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
    }
}
