import Foundation
import RunAnywhere
import os

/// WhisperKit adapter for voice transcription
public class WhisperKitAdapter: UnifiedFrameworkAdapter {
    private let logger: Logger = Logger(subsystem: "com.runanywhere.whisperkit", category: "WhisperKitAdapter")

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
        // Check format, modality, and framework compatibility
        guard supportedFormats.contains(model.format) else {
            logger.debug("canHandle(\(model.name, privacy: .public)): false - unsupported format \(model.format.rawValue)")
            return false
        }
        guard supportedModalities.contains(model.modality) else {
            logger.debug("canHandle(\(model.name, privacy: .public)): false - unsupported modality \(model.modality.rawValue)")
            return false
        }
        guard model.compatibleFrameworks.contains(.whisperKit) else {
            logger.debug("canHandle(\(model.name, privacy: .public)): false - not compatible with WhisperKit")
            return false
        }
        logger.debug("canHandle(\(model.name, privacy: .public)): true")
        return true
    }

    public func createService(for modality: FrameworkModality) -> Any? {
        logger.info("createService for modality: \(modality.rawValue, privacy: .public)")
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
            logger.warning("Unsupported modality: \(modality.rawValue, privacy: .public)")
            return nil
        }
    }

    public func loadModel(_ model: ModelInfo, for modality: FrameworkModality) async throws -> Any {
        logger.info("loadModel(\(model.name, privacy: .public)) for modality: \(modality.rawValue, privacy: .public)")
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
            logger.debug("Model path: \(modelPath ?? "nil", privacy: .public)")
            try await service.initialize(modelPath: modelPath)
            logger.info("WhisperKitService initialized")
            lastWhisperKitUsage = Date()
            return service
        default:
            logger.error("Unsupported modality: \(modality.rawValue, privacy: .public)")
            throw SDKError.unsupportedModality(modality.rawValue)
        }
    }

    public func configure(with hardware: HardwareConfiguration) async {
        // WhisperKit doesn't need special hardware configuration
    }

    public func estimateMemoryUsage(for model: ModelInfo) -> Int64 {
        return model.memoryRequired ?? 0
    }

    public func optimalConfiguration(for model: ModelInfo) -> HardwareConfiguration {
        return HardwareConfiguration()
    }

    // MARK: - Initialization

    public init() {
        // Initialize storage strategy (handles both download and file management)
        self.storageStrategy = WhisperKitStorageStrategy()

        logger.info("WhisperKitAdapter initialized")
        logger.info("Supported modalities: \(self.supportedModalities.map { $0.rawValue }.joined(separator: ", "), privacy: .public)")
        logger.info("Supported formats: \(self.supportedFormats.map { $0.rawValue }.joined(separator: ", "), privacy: .public)")
    }

    // MARK: - Model Registration

    // Store storage strategy (handles download and file management)
    private let storageStrategy: WhisperKitStorageStrategy

    /// Called when adapter is registered with the SDK
    /// This method will be called automatically by the SDK when the adapter is registered
    public func onRegistration() {
        logger.info("✅ WhisperKitAdapter registered")
        // Models will come from remote configuration or be added by users
        // We only provide the download strategy for WhisperKit models
    }

    /// Get models provided by this adapter
    /// Returns empty array since models come from configuration
    public func getProvidedModels() -> [ModelInfo] {
        return []
    }

    /// Get storage strategy for WhisperKit models
    public func getDownloadStrategy() -> DownloadStrategy? {
        return storageStrategy
    }

    /// Get storage strategy for WhisperKit models
    public func getStorageStrategy() -> ModelStorageStrategy? {
        return storageStrategy
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
