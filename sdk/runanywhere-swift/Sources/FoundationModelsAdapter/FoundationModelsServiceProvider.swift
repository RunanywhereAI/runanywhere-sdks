//
//  FoundationModelsModule.swift
//  FoundationModelsAdapter Module
//
//  Simple registration for Apple Foundation Models LLM services
//

import Foundation
import OSLog
import RunAnywhere

// MARK: - Foundation Models Module Registration

/// Foundation Models module for LLM text generation using Apple's built-in models
///
/// Usage:
/// ```swift
/// import FoundationModelsAdapter
///
/// // Register at app startup (iOS 26+ / macOS 26+ only):
/// if #available(iOS 26.0, macOS 26.0, *) {
///     FoundationModels.register()
/// }
/// ```
@available(iOS 26.0, macOS 26.0, *)
public enum FoundationModels {
    private static let logger = Logger(
        subsystem: "com.runanywhere.FoundationModels",
        category: "FoundationModels"
    )

    /// Register Foundation Models LLM service with the SDK
    @MainActor
    public static func register(priority: Int = 50) {
        ServiceRegistry.shared.registerLLM(
            name: "Apple Foundation Models",
            priority: priority,
            canHandle: { modelId in
                canHandleModel(modelId)
            },
            factory: { config in
                try await createService(config: config)
            }
        )
        logger.info("Foundation Models LLM registered")
    }

    // MARK: - Private Helpers

    private static func canHandleModel(_ modelId: String?) -> Bool {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            return false
        }

        guard let modelId = modelId, !modelId.isEmpty else {
            return false
        }

        let lowercasedId = modelId.lowercased()
        return lowercasedId.contains("foundation")
            || lowercasedId.contains("apple")
            || modelId == "foundation-models-default"
            || modelId == "foundation-models-native"
    }

    private static func createService(config: LLMConfiguration) async throws -> LLMService {
        logger.info("Creating Foundation Models service")

        let service = FoundationModelsService()
        try await service.initialize(modelPath: "built-in")

        logger.info("Foundation Models service created successfully")
        return service
    }
}
