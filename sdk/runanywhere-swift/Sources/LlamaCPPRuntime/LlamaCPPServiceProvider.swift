import Foundation
import RunAnywhere

/// Service provider for LlamaCPP LLM capabilities
///
/// This provider integrates with ModuleRegistry to enable LlamaCPP-based text generation
/// through the standard LLMComponent interface.
///
/// Usage:
/// ```swift
/// import LlamaCPPRuntime
///
/// // In your app initialization:
/// LlamaCPPServiceProvider.register()
/// ```
public final class LlamaCPPServiceProvider: LLMServiceProvider {
    private static let logger = SDKLogger(category: "LlamaCPPServiceProvider")

    // MARK: - Singleton for easy registration

    public static let shared = LlamaCPPServiceProvider()

    /// Register this provider with the ModuleRegistry
    @MainActor
    public static func register(priority: Int = 100) {
        logger.info("Registering LlamaCPP service provider with priority \(priority)")
        ModuleRegistry.shared.registerLLM(shared, priority: priority)
        logger.info("LlamaCPP service provider registered")
    }

    // MARK: - LLMServiceProvider Protocol

    public var name: String {
        "LlamaCPP Core"
    }

    public func canHandle(modelId: String?) -> Bool {
        guard let modelId = modelId else { return false }

        let lowercased = modelId.lowercased()

        Self.logger.debug("Checking if can handle model: \(modelId)")

        // Handle GGUF models (primary format for llama.cpp)
        if lowercased.contains("gguf") || lowercased.hasSuffix(".gguf") {
            Self.logger.debug("Model \(modelId) matches GGUF pattern")
            return true
        }

        // Handle GGML models (older format)
        if lowercased.contains("ggml") || lowercased.hasSuffix(".ggml") {
            Self.logger.debug("Model \(modelId) matches GGML pattern")
            return true
        }

        // Handle explicit llama.cpp references
        if lowercased.contains("llamacpp") || lowercased.contains("llama-cpp") {
            Self.logger.debug("Model \(modelId) matches LlamaCPP pattern")
            return true
        }

        // Handle common model names that are typically GGUF
        if lowercased.contains("smollm") ||
           lowercased.contains("mistral") ||
           lowercased.contains("llama") ||
           lowercased.contains("phi") ||
           lowercased.contains("qwen") ||
           lowercased.contains("gemma") {
            // Only if it contains quantization patterns typical of GGUF
            if lowercased.contains("q4") || lowercased.contains("q5") ||
               lowercased.contains("q6") || lowercased.contains("q8") ||
               lowercased.contains("q2") || lowercased.contains("q3") {
                Self.logger.debug("Model \(modelId) matches common GGUF model pattern")
                return true
            }
        }

        Self.logger.debug("Model \(modelId) does not match any LlamaCPP patterns")
        return false
    }

    public func createLLMService(configuration: LLMConfiguration) async throws -> LLMService {
        Self.logger.info("Creating LlamaCPP service for model: \(configuration.modelId ?? "unknown")")

        // Get the actual model file path from the model registry
        var modelPath: String? = nil
        if let modelId = configuration.modelId {
            // Query all available models and find the one we need
            let allModels = try await RunAnywhere.availableModels()
            let modelInfo = allModels.first { $0.id == modelId }

            // Check if model is downloaded and has a local path
            if let localPath = modelInfo?.localPath {
                modelPath = localPath.path
                Self.logger.info("Found local model path: \(modelPath ?? "nil")")
            } else {
                // Model not downloaded yet
                Self.logger.error("Model '\(modelId)' is not downloaded. Please download the model first.")
                throw SDKError.modelNotFound("Model '\(modelId)' is not downloaded. Please download the model before using it.")
            }
        }

        let service = LlamaCPPService()
        try await service.initialize(modelPath: modelPath)
        return service
    }

    // MARK: - Private initializer to enforce singleton

    private init() {
        Self.logger.info("LlamaCPPServiceProvider initialized")
    }
}

// MARK: - Auto Registration Support

/// Automatic registration when module is imported
public enum LlamaCPPModule {
    /// Call this to automatically register LlamaCPP with the SDK
    @MainActor
    public static func autoRegister() {
        LlamaCPPServiceProvider.register()
    }
}
