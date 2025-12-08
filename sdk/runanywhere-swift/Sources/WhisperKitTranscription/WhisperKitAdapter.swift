import Foundation
import RunAnywhere

/// WhisperKit adapter for voice transcription
public class WhisperKitAdapter: UnifiedFrameworkAdapter {
    private let logger = SDKLogger(category: "WhisperKitAdapter")

    // Singleton instance to ensure caching works across the app
    public static let shared = WhisperKitAdapter()

    // MARK: - Properties

    public let framework: LLMFramework = .whisperKit

    public let supportedModalities: Set<FrameworkModality> = [.voiceToText]

    public let supportedFormats: [ModelFormat] = [.mlmodel, .mlpackage]

    // Cache service instances to avoid re-initialization
    private var cachedWhisperKitService: WhisperKitService?

    // Track last usage for smart cleanup
    private var lastWhisperKitUsage: Date?
    private let cacheTimeout: TimeInterval = 300 // 5 minutes

    // MARK: - UnifiedFrameworkAdapter Implementation

    public func canHandle(model: ModelInfo) -> Bool {
        // Check if model is for speech recognition and compatible with WhisperKit
        let canHandle = model.category == .speechRecognition &&
                       model.compatibleFrameworks.contains(.whisperKit)
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
            if let cached = cachedWhisperKitService {
                logger.info("Returning cached WhisperKitService for voice-to-text")
                lastWhisperKitUsage = Date()
                return cached
            }
            logger.info("Creating new WhisperKitService for voice-to-text")
            let service = WhisperKitService()
            cachedWhisperKitService = service
            lastWhisperKitUsage = Date()
            return service
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
            let service: WhisperKitService
            if let cached = cachedWhisperKitService {
                logger.info("Using cached WhisperKitService for initialization")
                service = cached
            } else {
                logger.info("Creating new WhisperKitService for initialization")
                service = WhisperKitService()
                cachedWhisperKitService = service
            }

            // Initialize with model path if available
            let modelPath = model.localPath?.path
            logger.debug("Model path: \(modelPath ?? "nil")")
            try await service.initialize(modelPath: modelPath)
            logger.info("WhisperKitService initialized")
            lastWhisperKitUsage = Date()
            return service
        default:
            logger.error("Unsupported modality: \(modality.rawValue)")
            throw SDKError.unsupportedModality(modality.rawValue)
        }
    }

    public func configure(with hardware: HardwareConfiguration) async {
        // WhisperKit doesn't need special hardware configuration
    }

    public func estimateMemoryUsage(for model: ModelInfo) -> Int64 {
        model.memoryRequired ?? 0
    }

    public func optimalConfiguration(for model: ModelInfo) -> HardwareConfiguration {
        HardwareConfiguration()
    }

    // MARK: - Initialization

    public init() {
        // Initialize storage strategy (handles both download and file management)
        self.storageStrategy = WhisperKitStorageStrategy()

        logger.info("WhisperKitAdapter initialized")
        logger.info("Supported modalities: \(self.supportedModalities.map { $0.rawValue }.joined(separator: ", "))")
        logger.info("Supported formats: \(self.supportedFormats.map { $0.rawValue }.joined(separator: ", "))")
    }

    // MARK: - Model Registration

    // Store storage strategy (handles download and file management)
    private let storageStrategy: WhisperKitStorageStrategy

    /// Called when adapter is registered with the SDK
    /// Registers the STT service provider with ModuleRegistry
    @MainActor
    public func onRegistration() {
        ModuleRegistry.shared.registerSTT(WhisperKitServiceProvider.shared)
        logger.info("Registered WhisperKitServiceProvider with ModuleRegistry")
    }

    /// Get models provided by this adapter
    /// Returns empty array since models come from configuration
    public func getProvidedModels() -> [ModelInfo] {
        []
    }

    /// Get storage strategy for WhisperKit models
    public func getDownloadStrategy() -> DownloadStrategy? {
        storageStrategy
    }

    /// Get storage strategy for WhisperKit models
    public func getStorageStrategy() -> ModelStorageStrategy? {
        storageStrategy
    }

    // MARK: - Cache Management

    /// Clean up stale cached services after timeout
    private func cleanupStaleCache() {
        if let lastUsage = lastWhisperKitUsage {
            let timeSinceLastUsage = Date().timeIntervalSince(lastUsage)
            if timeSinceLastUsage > cacheTimeout {
                logger.info("Cleaning up stale WhisperKit cache (unused for \(Int(timeSinceLastUsage))s)")
                Task {
                    await cachedWhisperKitService?.cleanup()
                    cachedWhisperKitService = nil
                    lastWhisperKitUsage = nil
                }
            }
        }
    }

    /// Force cleanup of cached services (can be called on memory warning)
    public func forceCleanup() async {
        logger.info("Force cleanup of cached services")
        await cachedWhisperKitService?.cleanup()
        cachedWhisperKitService = nil
        lastWhisperKitUsage = nil
    }
}
