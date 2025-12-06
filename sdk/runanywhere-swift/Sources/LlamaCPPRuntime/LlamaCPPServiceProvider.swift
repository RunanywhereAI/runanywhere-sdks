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

        Self.logger.debug("Checking if can handle model: \(modelId)")

        // PRIMARY CHECK: Use cached model info from the registry (most reliable)
        // This uses the model's actual metadata rather than pattern matching
        if let modelInfo = ModelInfoCache.shared.modelInfo(for: modelId) {
            // Check if llama.cpp is the preferred framework
            if modelInfo.preferredFramework == .llamaCpp {
                Self.logger.debug("Model \(modelId) has llamaCpp as preferred framework")
                return true
            }

            // Check if llama.cpp is in compatible frameworks
            if modelInfo.compatibleFrameworks.contains(.llamaCpp) {
                Self.logger.debug("Model \(modelId) has llamaCpp in compatible frameworks")
                return true
            }

            // Check if format is GGUF or GGML (native llama.cpp formats)
            if modelInfo.format == .gguf || modelInfo.format == .ggml {
                Self.logger.debug("Model \(modelId) has GGUF/GGML format")
                return true
            }

            // Model info exists but doesn't indicate llama.cpp compatibility
            Self.logger.debug("Model \(modelId) found in cache but not llama.cpp compatible")
            return false
        }

        // FALLBACK: Pattern-based matching for models not yet in cache
        // This handles edge cases during initialization or for dynamically added models
        let lowercased = modelId.lowercased()

        // Handle GGUF models (primary format for llama.cpp)
        if lowercased.contains("gguf") || lowercased.hasSuffix(".gguf") {
            Self.logger.debug("Model \(modelId) matches GGUF pattern (fallback)")
            return true
        }

        // Handle GGML models (older format)
        if lowercased.contains("ggml") || lowercased.hasSuffix(".ggml") {
            Self.logger.debug("Model \(modelId) matches GGML pattern (fallback)")
            return true
        }

        // Handle explicit llama.cpp references
        if lowercased.contains("llamacpp") || lowercased.contains("llama-cpp") || lowercased.contains("llama_cpp") {
            Self.logger.debug("Model \(modelId) matches LlamaCPP pattern (fallback)")
            return true
        }

        // Check for GGUF quantization patterns (q2-q8 with optional suffixes like _k, _k_m, -k-m, _0)
        // These patterns strongly indicate a GGUF model that llama.cpp can handle
        // Supports both underscore and hyphen separators: q4_k_m, q4-k-m, q8_0, q8-0
        let quantizationPattern = #"q[2-8]([_-][kK])?([_-][mMsS0])?"#
        if let regex = try? NSRegularExpression(pattern: quantizationPattern, options: []),
           regex.firstMatch(in: lowercased, range: NSRange(lowercased.startIndex..., in: lowercased)) != nil {
            Self.logger.debug("Model \(modelId) matches GGUF quantization pattern (fallback)")
            return true
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
