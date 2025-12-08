import Foundation
import OSLog
import RunAnywhere

/// Foundation Models provider for Language Model services (Apple's built-in LLM)
///
/// Usage:
/// ```swift
/// import FoundationModels
///
/// // In your app initialization (iOS 26+ / macOS 26+ only):
/// if #available(iOS 26.0, macOS 26.0, *) {
///     FoundationModelsServiceProvider.register()
/// }
/// ```
@available(iOS 26.0, macOS 26.0, *)
public final class FoundationModelsServiceProvider: LLMServiceProvider {
    private let logger = Logger(
        subsystem: "com.runanywhere.FoundationModels",
        category: "FoundationModelsServiceProvider"
    )

    // MARK: - Singleton for easy registration

    public static let shared = FoundationModelsServiceProvider()

    /// Super simple registration - just call this in your app
    @MainActor
    public static func register() {
        ModuleRegistry.shared.registerLLM(shared)
    }

    // MARK: - LLMServiceProvider Protocol

    public var name: String {
        "Apple Foundation Models"
    }

    public func canHandle(modelId: String?) -> Bool {
        // Check if we're running on iOS 26+ or macOS 26+
        guard #available(iOS 26.0, macOS 26.0, *) else {
            return false
        }

        // Accept nil or empty modelId (will use default Foundation Model)
        guard let modelId = modelId, !modelId.isEmpty else {
            return false // Don't claim nil/empty - let other providers handle those
        }

        // Handle Foundation Models specific identifiers
        let lowercasedId = modelId.lowercased()
        return lowercasedId.contains("foundation")
            || lowercasedId.contains("apple")
            || modelId == "foundation-models-default"
            || modelId == "foundation-models-native"
    }

    public func createLLMService(configuration: LLMConfiguration) async throws -> LLMService {
        logger.info("Creating Foundation Models service")

        // Create the service
        let service = FoundationModelsService(hardwareConfig: nil)

        // Initialize the service (Foundation Models doesn't need a model path)
        logger.info("Initializing Foundation Models service")
        try await service.initialize(modelPath: "built-in")

        logger.info("Foundation Models service created successfully")
        return service
    }

    // MARK: - Private initializer to enforce singleton

    private init() {
        logger.info("FoundationModelsServiceProvider initialized")
    }
}

// MARK: - Auto Registration Support

/// Automatic registration when module is imported
@available(iOS 26.0, macOS 26.0, *)
public enum FoundationModelsModule {
    /// Call this to automatically register Foundation Models with the SDK
    @MainActor
    public static func autoRegister() {
        FoundationModelsServiceProvider.register()
    }
}
