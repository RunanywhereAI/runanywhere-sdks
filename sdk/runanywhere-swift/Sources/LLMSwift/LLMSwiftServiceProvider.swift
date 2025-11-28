import Foundation
import RunAnywhere
import LLM

/// LLMSwift provider for Language Model services (llama.cpp)
///
/// Usage:
/// ```swift
/// import LLMSwift
///
/// // In your app initialization:
/// LLMSwiftServiceProvider.register()
/// ```
public final class LLMSwiftServiceProvider: LLMServiceProvider {
    private let logger = SDKLogger(category: "LLMSwiftServiceProvider")

    // MARK: - Singleton for easy registration

    public static let shared = LLMSwiftServiceProvider()

    /// Super simple registration - just call this in your app
    @MainActor
    public static func register() {
        ModuleRegistry.shared.registerLLM(shared)
    }

    // MARK: - LLMServiceProvider Protocol

    public var name: String {
        "LLMSwift (llama.cpp)"
    }

    public func canHandle(modelId: String?) -> Bool {
        // Accept nil or empty/default modelId
        guard let modelId = modelId, !modelId.isEmpty else {
            return true
        }

        // Accept "default" to use currently loaded model
        if modelId == "default" {
            return true
        }

        // Check for supported file extensions (GGUF/GGML/BIN formats)
        let supportedExtensions = [".gguf", ".ggml", ".bin"]
        let lowercasedId = modelId.lowercased()

        return supportedExtensions.contains { lowercasedId.hasSuffix($0) }
    }

    public func createLLMService(configuration: LLMConfiguration) async throws -> LLMService {
        logger.info("Creating LLMSwift service")

        // Create the service
        let service = LLMSwiftService()

        // Initialize with model path if provided
        if let modelId = configuration.modelId, !modelId.isEmpty && modelId != "default" {
            logger.info("Initializing with model: \(modelId)")
            // The modelId might be a path or just an identifier
            // In a real implementation, you'd resolve this to an actual path
            try await service.initialize(modelPath: modelId)
        } else {
            logger.info("Using default model - service will use currently loaded model or be initialized later")
        }

        logger.info("LLMSwift service created successfully")
        return service
    }

    // MARK: - Private initializer to enforce singleton

    private init() {
        logger.info("LLMSwiftServiceProvider initialized")
    }
}

// MARK: - Auto Registration Support

/// Automatic registration when module is imported
public enum LLMSwiftModule {
    /// Call this to automatically register LLMSwift with the SDK
    @MainActor
    public static func autoRegister() {
        LLMSwiftServiceProvider.register()
    }
}
