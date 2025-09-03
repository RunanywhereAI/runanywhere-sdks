import Foundation
import RunAnywhere
import LLM
import os

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
    private let logger = Logger(subsystem: "com.runanywhere.llmswift", category: "LLMSwiftServiceProvider")

    // MARK: - Singleton for easy registration

    public static let shared = LLMSwiftServiceProvider()

    /// Super simple registration - just call this in your app
    public static func register() {
        Task { @MainActor in
            ModuleRegistry.shared.registerLLM(shared)
        }
    }

    // MARK: - LLMServiceProvider Protocol

    public var name: String {
        "LLMSwift (llama.cpp)"
    }

    public func canHandle(modelId: String?) -> Bool {
        // LLMSwift handles GGUF/GGML models
        guard let modelId = modelId else { return true }

        // Check for GGUF/GGML models or llama-based models
        let supportedPrefixes = ["llama", "mistral", "phi", "gemma", "qwen", "tinyllama", "codellama", "vicuna"]
        let supportedExtensions = [".gguf", ".ggml", ".bin"]

        let lowercasedId = modelId.lowercased()

        // Check prefixes
        let hasPrefix = supportedPrefixes.contains(where: { lowercasedId.contains($0) })

        // Check extensions
        let hasExtension = supportedExtensions.contains(where: { lowercasedId.hasSuffix($0) })

        return hasPrefix || hasExtension
    }

    public func createLLMService(configuration: LLMConfiguration) async throws -> LLMService {
        logger.info("Creating LLMSwift service")

        // Create the service
        let service = LLMSwiftService()

        // Initialize with model path if provided
        if let modelId = configuration.modelId {
            logger.info("Initializing with model: \(modelId)")

            // The modelId might be a path or just an identifier
            // In a real implementation, you'd resolve this to an actual path
            try await service.initialize(modelPath: modelId)
        } else {
            logger.info("No model specified, service will need to be initialized with a model later")
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
    public static func autoRegister() {
        LLMSwiftServiceProvider.register()
    }
}
