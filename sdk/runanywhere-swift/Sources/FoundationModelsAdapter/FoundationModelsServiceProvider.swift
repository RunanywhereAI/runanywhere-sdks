//
//  FoundationModelsModule.swift
//  FoundationModelsAdapter Module
//
//  Apple Foundation Models module providing LLM capabilities via Apple Intelligence.
//

import Foundation
import OSLog
import RunAnywhere

// MARK: - Foundation Models Module

/// Apple Foundation Models module for LLM text generation.
///
/// Provides large language model capabilities using Apple's
/// built-in Foundation Models (Apple Intelligence) on iOS 26+ / macOS 26+.
///
/// ## Registration
///
/// ```swift
/// import FoundationModelsAdapter
///
/// // Only available on iOS 26+ / macOS 26+
/// if #available(iOS 26.0, macOS 26.0, *) {
///     // Option 1: Direct registration
///     AppleAI.register()
///
///     // Option 2: Via ModuleRegistry
///     ModuleRegistry.shared.register(AppleAI.self)
///
///     // Option 3: Via RunAnywhere
///     RunAnywhere.register(AppleAI.self)
/// }
/// ```
@available(iOS 26.0, macOS 26.0, *)
public enum AppleAI: RunAnywhereModule {
    private static let logger = Logger(
        subsystem: "com.runanywhere.FoundationModels",
        category: "FoundationModels"
    )

    // MARK: - RunAnywhereModule Conformance

    public static let moduleId = "appleai"
    public static let moduleName = "Apple Foundation Models"
    public static let capabilities: Set<CapabilityType> = [.llm]
    public static let defaultPriority: Int = 50 // Lower priority - prefer local models

    /// Register Foundation Models LLM service with the SDK
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

// MARK: - Legacy Alias

/// Legacy alias for backward compatibility
@available(iOS 26.0, macOS 26.0, *)
@available(*, deprecated, renamed: "AppleAI")
public typealias FoundationModels = AppleAI

// MARK: - Auto-Discovery Registration

@available(iOS 26.0, macOS 26.0, *)
extension AppleAI {
    /// Enable auto-discovery for this module.
    /// Access this property to trigger registration.
    public static let autoRegister: Void = {
        ModuleDiscovery.register(AppleAI.self)
    }()
}
