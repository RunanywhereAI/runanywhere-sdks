//
//  LlamaCPPModule.swift
//  LlamaCPPRuntime Module
//
//  Simple registration for LlamaCPP LLM services
//

import Foundation
import RunAnywhere

// MARK: - LlamaCPP Module Registration

/// LlamaCPP module for LLM text generation
///
/// Usage:
/// ```swift
/// import LlamaCPPRuntime
///
/// // Register at app startup
/// LlamaCPP.register()
///
/// // Then use via RunAnywhere
/// try await RunAnywhere.loadModel("my-model-id")
/// let result = try await RunAnywhere.generate("Hello!")
/// ```
public enum LlamaCPP {
    private static let logger = SDKLogger(category: "LlamaCPP")

    /// Register LlamaCPP LLM service with the SDK
    @MainActor
    public static func register(priority: Int = 100) {
        ServiceRegistry.shared.registerLLM(
            name: "LlamaCPP",
            priority: priority,
            canHandle: { modelId in
                canHandleModel(modelId)
            },
            factory: { config in
                try await createService(config: config)
            }
        )
        logger.info("LlamaCPP LLM registered")
    }

    // MARK: - Private Helpers

    private static func canHandleModel(_ modelId: String?) -> Bool {
        guard let modelId = modelId else { return false }

        let lowercased = modelId.lowercased()

        // Check model info cache first
        if let modelInfo = ModelInfoCache.shared.modelInfo(for: modelId) {
            if modelInfo.preferredFramework == .llamaCpp {
                return true
            }
            if modelInfo.compatibleFrameworks.contains(.llamaCpp) {
                return true
            }
            if modelInfo.format == .gguf || modelInfo.format == .ggml {
                return true
            }
            return false
        }

        // Fallback: Pattern-based matching
        if lowercased.contains("gguf") || lowercased.hasSuffix(".gguf") {
            return true
        }
        if lowercased.contains("ggml") || lowercased.hasSuffix(".ggml") {
            return true
        }
        if lowercased.contains("llamacpp") || lowercased.contains("llama-cpp") || lowercased.contains("llama_cpp") {
            return true
        }

        // Check for GGUF quantization patterns
        let quantizationPattern = #"q[2-8]([_-][kK])?([_-][mMsS0])?"#
        if let regex = try? NSRegularExpression(pattern: quantizationPattern, options: []),
           regex.firstMatch(in: lowercased, range: NSRange(lowercased.startIndex..., in: lowercased)) != nil {
            return true
        }

        return false
    }

    private static func createService(config: LLMConfiguration) async throws -> LLMService {
        logger.info("Creating LlamaCPP LLM service for model: \(config.modelId ?? "unknown")")

        // Get the actual model file path from the model registry
        var modelPath: String?
        if let modelId = config.modelId {
            let allModels = try await RunAnywhere.availableModels()
            let modelInfo = allModels.first { $0.id == modelId }

            if let localPath = modelInfo?.localPath {
                modelPath = localPath.path
                logger.info("Found local model path: \(modelPath ?? "nil")")
            } else {
                logger.error("Model '\(modelId)' is not downloaded")
                throw SDKError.modelNotFound("Model '\(modelId)' is not downloaded. Please download the model first.")
            }
        }

        let service = LlamaCPPService()
        try await service.initialize(modelPath: modelPath)
        logger.info("LlamaCPP service created successfully")
        return service
    }
}
