//
//  LlamaCPPServiceProvider.swift
//  LlamaCPPRuntime Module
//
//  LlamaCPP module providing LLM text generation capabilities.
//

import Foundation
import RunAnywhere

// MARK: - LlamaCPP Module

/// LlamaCPP module for LLM text generation.
///
/// Provides large language model capabilities using llama.cpp
/// with GGUF models and Metal acceleration.
///
/// ## Registration
///
/// ```swift
/// import LlamaCPPRuntime
///
/// // Option 1: Direct registration
/// LlamaCPP.register()
///
/// // Option 2: Via ModuleRegistry
/// ModuleRegistry.shared.register(LlamaCPP.self)
///
/// // Option 3: Via RunAnywhere
/// RunAnywhere.register(LlamaCPP.self)
/// ```
///
/// ## Usage
///
/// ```swift
/// try await RunAnywhere.loadModel("my-model-id")
/// let result = try await RunAnywhere.generate("Hello!")
/// ```
public enum LlamaCPP: RunAnywhereModule {
    private static let logger = SDKLogger(category: "LlamaCPP")

    // MARK: - RunAnywhereModule Conformance

    public static let moduleId = "llamacpp"
    public static let moduleName = "LlamaCPP"
    public static let capabilities: Set<CapabilityType> = [.llm]
    public static let defaultPriority: Int = 100

    /// LlamaCPP uses the llama.cpp inference framework
    public static let inferenceFramework: InferenceFramework = .llamaCpp

    /// Register LlamaCPP LLM service with the SDK
    @MainActor
    public static func register(priority: Int) {
        ServiceRegistry.shared.registerLLM(
            name: moduleName,
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

        // Check model info cache first - framework is the single source of truth
        if let modelInfo = ModelInfoCache.shared.modelInfo(for: modelId) {
            return modelInfo.framework == .llamaCpp
                || modelInfo.format == .gguf
        }

        // Fallback: Pattern-based matching
        if lowercased.contains("gguf") || lowercased.hasSuffix(".gguf") {
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

// MARK: - Auto-Discovery Registration

extension LlamaCPP {
    /// Enable auto-discovery for this module.
    /// Access this property to trigger registration.
    public static let autoRegister: Void = {
        ModuleDiscovery.register(LlamaCPP.self)
    }()
}
