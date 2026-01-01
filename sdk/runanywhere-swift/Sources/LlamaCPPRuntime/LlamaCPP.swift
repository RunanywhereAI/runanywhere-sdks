//
//  LlamaCPP.swift
//  LlamaCPPRuntime Module
//
//  Unified LlamaCPP module - thin wrapper that calls C++ backend registration.
//  This replaces both LlamaCPPRuntime.swift and LlamaCPPServiceProvider.swift.
//

import CRACommons
import Foundation
import LlamaCPPBackend
import os.log
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
/// // Register the backend (done automatically if auto-registration is enabled)
/// try LlamaCPP.register()
/// ```
///
/// ## Usage
///
/// LLM services are accessed through the main SDK APIs - the C++ backend handles
/// service creation and lifecycle internally:
///
/// ```swift
/// // Generate text via public API
/// let response = try await RunAnywhere.chat("Hello!")
///
/// // Stream text via public API
/// for try await token in try await RunAnywhere.streamChat("Tell me a story") {
///     print(token, terminator: "")
/// }
/// ```
public enum LlamaCPP: RunAnywhereModule {
    private static let logger = SDKLogger(category: "LlamaCPP")

    // MARK: - Module Info

    /// Current version of the LlamaCPP Runtime module
    public static let version = "2.0.0"

    /// LlamaCPP library version (underlying C++ library)
    public static let llamaCppVersion = "b7199"

    // MARK: - RunAnywhereModule Conformance

    public static let moduleId = "llamacpp"
    public static let moduleName = "LlamaCPP"
    public static let capabilities: Set<SDKComponent> = [.llm]
    public static let defaultPriority: Int = 100

    /// LlamaCPP uses the llama.cpp inference framework
    public static let inferenceFramework: InferenceFramework = .llamaCpp

    // MARK: - Registration State

    private static var isRegistered = false

    // MARK: - Registration

    /// Register LlamaCPP backend with the C++ service registry.
    ///
    /// This calls `rac_backend_llamacpp_register()` to register the
    /// LlamaCPP service provider with the C++ commons layer.
    ///
    /// Safe to call multiple times - subsequent calls are no-ops.
    ///
    /// - Parameter priority: Ignored (C++ uses its own priority system)
    /// - Throws: SDKError if registration fails
    @MainActor
    public static func register(priority: Int = 100) {
        guard !isRegistered else {
            logger.debug("LlamaCPP already registered, returning")
            return
        }

        logger.info("Registering LlamaCPP backend with C++ registry...")

        let result = rac_backend_llamacpp_register()

        // RAC_ERROR_MODULE_ALREADY_REGISTERED is OK
        if result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED {
            let errorMsg = String(cString: rac_error_message(result))
            logger.error("LlamaCPP registration failed: \(errorMsg)")
            // Don't throw - registration failure shouldn't crash the app
            return
        }

        isRegistered = true
        logger.info("LlamaCPP backend registered successfully")
    }

    /// Unregister the LlamaCPP backend from C++ registry.
    public static func unregister() {
        guard isRegistered else { return }

        _ = rac_backend_llamacpp_unregister()
        isRegistered = false
        logger.info("LlamaCPP backend unregistered")
    }

    // MARK: - Model Handling

    /// Check if LlamaCPP can handle a given model
    /// Uses file extension pattern matching - actual framework info is in C++ registry
    public static func canHandle(modelId: String?) -> Bool {
        guard let modelId = modelId else { return false }
        return modelId.lowercased().hasSuffix(".gguf")
    }
}

// MARK: - Auto-Registration

extension LlamaCPP {
    /// Enable auto-registration for this module.
    /// Access this property to trigger C++ backend registration.
    public static let autoRegister: Void = {
        Task { @MainActor in
            LlamaCPP.register()
        }
    }()
}
