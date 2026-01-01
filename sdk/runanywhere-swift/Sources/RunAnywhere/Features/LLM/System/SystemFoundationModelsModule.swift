//
//  SystemFoundationModelsModule.swift
//  RunAnywhere SDK
//
//  Built-in Apple Foundation Models (Apple Intelligence) module.
//  Platform-specific LLM provider available on iOS 26+ / macOS 26+.
//

import CRACommons
import Foundation

// MARK: - System Foundation Models Module

/// Built-in Apple Foundation Models (Apple Intelligence) module.
///
/// This is a platform-specific (iOS 26+/macOS 26+) LLM provider that uses
/// Apple's built-in Foundation Models powered by Apple Intelligence.
///
/// SystemFoundationModels registers with the C++ service registry via Swift
/// callbacks, making it discoverable alongside C++ backends like LlamaCPP.
///
/// ## Availability
///
/// Requires:
/// - iOS 26.0+ or macOS 26.0+
/// - Apple Intelligence enabled on the device
/// - Apple Intelligence capable hardware
///
/// ## Usage
///
/// ```swift
/// import RunAnywhere
///
/// // Register (typically done at app startup)
/// if #available(iOS 26.0, macOS 26.0, *) {
///     await SystemFoundationModels.register()
/// }
///
/// // Load the built-in model
/// try await RunAnywhere.loadModel("foundation-models-default")
///
/// // Generate text
/// let response = try await RunAnywhere.chat("Hello!")
/// ```
public enum SystemFoundationModels: RunAnywhereModule {
    private static let logger = SDKLogger(category: "SystemFoundationModels")

    // MARK: - RunAnywhereModule Conformance

    public static let moduleId = "system-foundation-models"
    public static let moduleName = "System Foundation Models"
    public static let capabilities: Set<SDKComponent> = [.llm]
    public static let defaultPriority: Int = 50  // Lower than LlamaCPP (100), used as alternative

    /// System Foundation Models uses Apple's built-in Foundation Models
    public static let inferenceFramework: InferenceFramework = .foundationModels

    // MARK: - Registration State

    private static var isRegistered = false
    // swiftlint:disable:next avoid_any_type
    private static var serviceInstance: Any?  // Type-erased to avoid @available on stored property

    // MARK: - Registration

    /// Register System Foundation Models with the C++ service registry.
    ///
    /// This is a no-op on iOS < 26 / macOS < 26.
    ///
    /// - Parameter priority: Registration priority (default 50, lower than LlamaCPP)
    @MainActor
    public static func register(priority: Int = 50) {
        // Check availability at runtime
        guard #available(iOS 26.0, macOS 26.0, *) else {
            // Silently skip registration on older OS versions
            return
        }

        guard !isRegistered else { return }

        logger.info("Registering SystemFoundationModels with C++ registry (priority: \(priority))...")

        // Register module with C++ (for module discovery)
        registerModule()

        // Register service provider with C++ (via callbacks)
        let success = CppBridge.Services.registerPlatformService(
            name: moduleName,
            capability: .llm,
            priority: priority,
            canHandle: { modelId in
                canHandleModel(modelId)
            },
            create: {
                try await createServiceInternal()
            }
        )

        if success {
            isRegistered = true
            logger.info("✅ SystemFoundationModels registered with C++ registry")

            // Register the built-in model entry
            registerBuiltInModelEntry()
        } else {
            logger.error("❌ Failed to register SystemFoundationModels with C++ registry")
        }
    }

    /// Unregister System Foundation Models module
    @MainActor
    public static func unregister() {
        guard isRegistered else { return }

        CppBridge.Services.unregisterPlatformService(name: moduleName, capability: .llm)
        _ = moduleId.withCString { rac_module_unregister($0) }

        serviceInstance = nil
        isRegistered = false
        logger.info("SystemFoundationModels unregistered")
    }

    // MARK: - Private: Module Registration

    private static func registerModule() {
        var moduleInfo = rac_module_info_t()
        let version = "1.0.0"
        let description = "Apple Intelligence Foundation Models (iOS 26+ / macOS 26+)"

        moduleId.withCString { idPtr in
            moduleName.withCString { namePtr in
                version.withCString { versionPtr in
                    description.withCString { descPtr in
                        moduleInfo.id = idPtr
                        moduleInfo.name = namePtr
                        moduleInfo.version = versionPtr
                        moduleInfo.description = descPtr

                        var caps: [rac_capability_t] = [RAC_CAPABILITY_TEXT_GENERATION]
                        caps.withUnsafeBufferPointer { capsPtr in
                            moduleInfo.capabilities = capsPtr.baseAddress
                            moduleInfo.num_capabilities = 1
                            _ = rac_module_register(&moduleInfo)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Private: Model Entry Registration

    @MainActor
    private static func registerBuiltInModelEntry() {
        let modelInfo = ModelInfo(
            id: "foundation-models-default",
            name: "Apple Intelligence",
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
                Requires iOS 26+ / macOS 26+ and an Apple Intelligence capable device. \
                No download required - uses on-device models.
                """,
            source: .local
        )

        Task {
            try? await CppBridge.ModelRegistry.shared.save(modelInfo)
            logger.info("Built-in Foundation Models model entry registered: \(modelInfo.id)")
        }
    }

    // MARK: - Private: Service Creation

    private static func canHandleModel(_ modelId: String?) -> Bool {
        // First check OS availability
        guard #available(iOS 26.0, macOS 26.0, *) else {
            return false
        }

        guard let modelId = modelId, !modelId.isEmpty else {
            // Don't handle nil/empty - let other providers handle default
            return false
        }

        // Priority 1: Check model registry for framework
        // Note: This is a sync check - use cached model info if available
        // The registry is async but we need sync check here for provider selection
        let lowercasedModelId = modelId.lowercased()
        if lowercasedModelId.contains("foundation-models") || lowercasedModelId == "foundation-models-default" {
            logger.debug("canHandle: model '\(modelId)' matches foundation-models pattern -> true")
            return true
        }

        // Priority 2: Check by model ID pattern (for backwards compatibility)
        let lowercasedId = modelId.lowercased()
        let matches = lowercasedId.contains("foundation")
            || lowercasedId.contains("apple-intelligence")
            || lowercasedId == "foundation-models-default"
            || lowercasedId == "foundation-models-native"
            || lowercasedId == "system-llm"

        if matches {
            logger.debug("canHandle: model '\(modelId)' matched by name pattern -> true")
        }

        return matches
    }

    @available(iOS 26.0, macOS 26.0, *)
    private static func createServiceInternal() async throws -> Any {
        logger.info("Creating Foundation Models service")

        let service = SystemFoundationModelsService()
        try await service.initialize(modelPath: "built-in")

        // Cache the service instance
        serviceInstance = service

        logger.info("Foundation Models service created successfully")
        return service
    }

    // MARK: - Public API

    /// Check if Foundation Models is available on this device
    public static var isAvailable: Bool {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            return false
        }
        return true
    }

    /// Check if this module can handle the given model ID
    public static func canHandle(modelId: String?) -> Bool {
        canHandleModel(modelId)
    }

    /// Create a SystemFoundationModelsService instance directly
    ///
    /// Use this for direct access without going through the service registry.
    @available(iOS 26.0, macOS 26.0, *)
    public static func createService() async throws -> SystemFoundationModelsService {
        let service = SystemFoundationModelsService()
        try await service.initialize(modelPath: "built-in")
        return service
    }
}

// MARK: - Auto-Registration

extension SystemFoundationModels {
    /// Enable auto-registration for this module.
    /// Access this property to trigger registration on iOS 26+.
    ///
    /// Usage:
    /// ```swift
    /// import RunAnywhere
    /// _ = SystemFoundationModels.autoRegister  // Triggers registration
    /// ```
    public static let autoRegister: Void = {
        Task { @MainActor in
            SystemFoundationModels.register()
        }
    }()
}
