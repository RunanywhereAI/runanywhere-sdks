//
//  LlamaCPP.swift
//  LlamaCPPRuntime Module
//
//  Unified LlamaCPP module - thin wrapper that calls C++ backend registration.
//  This replaces both LlamaCPPRuntime.swift and LlamaCPPServiceProvider.swift.
//

import CRACommons
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
/// service creation and lifecycle internally. Use the canonical proto-request
/// entry points:
///
/// ```swift
/// // Generate text via public API
/// var req = RALLMGenerateRequest()
/// req.prompt = "Hello!"
/// let result = try await RunAnywhere.generate(req)
/// print(result.text)
///
/// // Stream text via public API
/// var streamReq = RALLMGenerateRequest()
/// streamReq.prompt = "Tell me a story"
/// for try await event in try await RunAnywhere.generateStream(streamReq) {
///     if event.eventKind == .token {
///         print(event.token, terminator: "")
///     }
/// }
/// ```
public enum LlamaCPP {
    private static let logger = SDKLogger(category: "LlamaCPP")

    // MARK: - Module Info

    /// Current version of the LlamaCPP Runtime module
    public static let version = "2.0.0"

    /// LlamaCPP library version (underlying C++ library)
    public static let llamaCppVersion = "b7199"

    // MARK: - Registration State

    private static var isRegistered = false

    // MARK: - Registration

    /// Register LlamaCPP backend with the C++ service registry.
    ///
    /// This calls `rac_backend_llamacpp_register()` to register the
    /// LlamaCPP service provider with the C++ commons layer. The unified
    /// llama.cpp plugin publishes a single vtable that fills both `llm_ops`
    /// and `vlm_ops` slots, so this single call covers both LLM and VLM
    /// modalities.
    ///
    /// Safe to call multiple times - subsequent calls are no-ops.
    ///
    /// - Parameter priority: Ignored (C++ uses its own priority system)
    /// - Throws: SDKException if registration fails
    @MainActor
    public static func register(priority _: Int = 100) {
        guard !isRegistered else {
            logger.debug("LlamaCPP already registered, returning")
            return
        }

        logger.info("Registering LlamaCPP backend with C++ registry...")

        // Register unified LlamaCPP backend (covers both LLM and VLM)
        let result = rac_backend_llamacpp_register()

        // RAC_ERROR_MODULE_ALREADY_REGISTERED is OK
        if result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED {
            let errorMsg = String(cString: rac_error_message(result))
            logger.error("LlamaCPP registration failed: \(errorMsg)")
            // Don't throw - registration failure shouldn't crash the app
            return
        }

        isRegistered = true
        logger.info("LlamaCPP backend registered successfully (LLM + VLM)")
    }

    /// Unregister the LlamaCPP backend from C++ registry.
    ///
    /// `@MainActor` so the `isRegistered` static flag stays in the same
    /// isolation domain as `register(priority:)` and the `autoRegister` Task
    /// hop. Without this annotation, a teardown call on a background thread
    /// would race the registration path and could leave the C registry in an
    /// inconsistent state (double-unregister or skipped unregister, see
    /// comment record `mlt-003`).
    @MainActor
    public static func unregister() {
        if isRegistered {
            _ = rac_backend_llamacpp_unregister()
            isRegistered = false
            logger.info("LlamaCPP backend unregistered")
        }
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
