//
//  FoundationModelsServiceProvider.swift
//  FoundationModelsAdapter Module
//
//  Apple Foundation Models module providing LLM capabilities via Apple Intelligence.
//

import CRACommons
import Foundation
import OSLog
import RunAnywhere

// MARK: - Foundation Models Module

/// Apple Foundation Models module for LLM text generation.
///
/// Provides large language model capabilities using Apple's
/// built-in Foundation Models (Apple Intelligence) on iOS 26+ / macOS 26+.
///
/// AppleAI registers with the C++ service registry via Swift callbacks,
/// making it discoverable alongside C++ backends like LlamaCPP.
///
/// ## Registration
///
/// ```swift
/// import FoundationModelsAdapter
///
/// // Only available on iOS 26+ / macOS 26+
/// if #available(iOS 26.0, macOS 26.0, *) {
///     AppleAI.register()
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
    public static let capabilities: Set<SDKComponent> = [.llm]
    public static let defaultPriority: Int = 50 // Lower priority - prefer local models

    /// Apple AI uses the Foundation Models inference framework
    public static let inferenceFramework: InferenceFramework = .foundationModels

    // MARK: - Registration State

    private static var isRegistered = false

    /// Register Foundation Models LLM service with the C++ service registry.
    ///
    /// This registers AppleAI as a platform service in C++, making it
    /// discoverable via `CppBridge.Services.listProviders(for: .llm)`.
    @MainActor
    public static func register(priority: Int = 50) {
        guard !isRegistered else { return }

        logger.info("Registering AppleAI with C++ registry (priority: \(priority))...")

        // Register module with C++ (for module discovery)
        var moduleInfo = rac_module_info_t()
        let version = "1.0.0"
        let description = "Apple Intelligence Foundation Models"

        moduleId.withCString { idPtr in
            moduleName.withCString { namePtr in
                version.withCString { versionPtr in
                    description.withCString { descPtr in
                        moduleInfo.id = idPtr
                        moduleInfo.name = namePtr
                        moduleInfo.version = versionPtr
                        moduleInfo.description = descPtr

                        let caps: [rac_capability_t] = [RAC_CAPABILITY_TEXT_GENERATION]
                        caps.withUnsafeBufferPointer { capsPtr in
                            moduleInfo.capabilities = capsPtr.baseAddress
                            moduleInfo.num_capabilities = 1
                            _ = rac_module_register(&moduleInfo)
                        }
                    }
                }
            }
        }

        // Register service provider with C++ (via callbacks)
        let success = CppBridge.Services.registerPlatformService(
            name: moduleName,
            capability: .llm,
            priority: priority,
            canHandle: { modelId in
                canHandleModel(modelId)
            },
            create: {
                try await createService()
            }
        )

        if success {
            isRegistered = true
            logger.info("✅ AppleAI registered with C++ registry")

            // Register the built-in Foundation Models as a model entry
            registerBuiltInModel()
        } else {
            logger.error("❌ Failed to register AppleAI with C++ registry")
        }
    }

    /// Unregister Foundation Models module
    public static func unregister() {
        guard isRegistered else { return }

        CppBridge.Services.unregisterPlatformService(name: moduleName, capability: .llm)
        _ = moduleId.withCString { rac_module_unregister($0) }

        isRegistered = false
        logger.info("AppleAI unregistered")
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
            contextLength: 4096,
            supportsThinking: false,
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

// MARK: - Auto-Registration

@available(iOS 26.0, macOS 26.0, *)
extension AppleAI {
    /// Enable auto-registration for this module.
    /// Access this property to trigger registration.
    public static let autoRegister: Void = {
        Task { @MainActor in
            AppleAI.register()
        }
    }()
}

// MARK: - Public API

@available(iOS 26.0, macOS 26.0, *)
extension AppleAI {
    /// Check if this module can handle the given model ID
    public static func canHandle(modelId: String?) -> Bool {
        canHandleModel(modelId)
    }

    /// Create a FoundationModelsService instance
    public static func createService() async throws -> FoundationModelsService {
        let service = FoundationModelsService()
        try await service.initialize(modelPath: "built-in")
        return service
    }
}
