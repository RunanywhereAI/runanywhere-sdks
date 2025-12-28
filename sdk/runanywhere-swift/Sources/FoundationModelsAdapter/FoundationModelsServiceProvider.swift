//
//  FoundationModelsServiceProvider.swift
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
///     // Option 2: Import module for auto-registration
///     import FoundationModelsAdapter // Auto-registers via ModuleDiscovery
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

    /// Apple AI uses the Foundation Models inference framework
    public static let inferenceFramework: InferenceFramework = .foundationModels

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

        // Register the built-in Foundation Models as a model entry so it appears in model lists
        registerBuiltInModel()
    }

    /// Register the built-in Foundation Models as a model entry
    @MainActor
    private static func registerBuiltInModel() {
        let modelInfo = ModelInfo(
            id: "foundation-models-default",
            name: "Apple Intelligence (Foundation Models)",
            category: .language,
            format: .unknown,
            framework: .foundationModels,
            downloadURL: nil,
            localPath: URL(string: "builtin://foundation-models"),  // Special builtin scheme
            artifactType: .builtIn,
            downloadSize: nil,
            memoryRequired: nil,  // System managed
            contextLength: 4096,
            supportsThinking: false,
            tags: ["apple", "foundation-models", "built-in", "on-device"],
            description: """
                Apple's built-in Foundation Models powered by Apple Intelligence. \
                Requires iOS 26+ / macOS 26+ and an Apple Intelligence capable device.
                """
        )

        ServiceContainer.shared.modelRegistry.registerModel(modelInfo)
        logger.info("Foundation Models model entry registered: \(modelInfo.id)")
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
            || lowercasedId == "foundation-models-default"
            || lowercasedId == "foundation-models-native"
    }

    private static func createService(config _: LLMConfiguration) async throws -> LLMService {
        logger.info("Creating Foundation Models service")

        let service = FoundationModelsService()
        try await service.initialize(modelPath: "built-in")

        logger.info("Foundation Models service created successfully")
        return service
    }
}

// MARK: - Auto-Discovery Registration

@available(iOS 26.0, macOS 26.0, *)
extension AppleAI {
    /// Enable auto-discovery for this module.
    /// Access this property to trigger registration.
    public static let autoRegister: Void = {
        ModuleDiscovery.register(AppleAI.self)
    }()
}
