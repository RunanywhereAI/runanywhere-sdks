//
//  Sdcpp.swift
//  SdcppRuntime Module
//
//  Thin wrapper that calls C++ sd.cpp backend registration.
//  Follows the same pattern as LlamaCPPRuntime/LlamaCPP.swift.
//

import CRACommons
import Foundation
import SdcppBackend
import os.log
import RunAnywhere

// MARK: - Sdcpp Module

/// sd.cpp module for diffusion image generation.
///
/// Provides cross-platform image generation using stable-diffusion.cpp
/// with Metal GPU acceleration on Apple platforms.
/// Supports .gguf and .safetensors model formats.
///
/// ## Registration
///
/// ```swift
/// import SdcppRuntime
///
/// // Register the backend (done automatically if auto-registration is enabled)
/// try Sdcpp.register()
/// ```
///
/// ## Usage
///
/// Diffusion services are accessed through the main SDK APIs — the C++ backend
/// handles service creation and lifecycle internally:
///
/// ```swift
/// // Generate an image via public API
/// let result = try await RunAnywhere.generateImage(prompt: "a sunset over mountains")
///
/// // Generate with progress
/// for try await progress in try await RunAnywhere.generateImageStream(prompt: "a cat") {
///     print("Step \(progress.currentStep)/\(progress.totalSteps)")
/// }
/// ```
public enum Sdcpp: RunAnywhereModule {
    private static let logger = SDKLogger(category: "Sdcpp")

    // MARK: - Module Info

    /// Current version of the Sdcpp Runtime module
    public static let version = "1.0.0"

    // MARK: - RunAnywhereModule Conformance

    public static let moduleId = "sdcpp"
    public static let moduleName = "stable-diffusion.cpp"
    public static let capabilities: Set<SDKComponent> = [.diffusion]
    public static let defaultPriority: Int = 90

    /// sd.cpp uses the stable-diffusion.cpp inference framework
    public static let inferenceFramework: InferenceFramework = .sdcpp

    // MARK: - Registration State

    private static var isRegistered = false

    // MARK: - Registration

    /// Register sd.cpp backend with the C++ service registry.
    ///
    /// This calls `rac_backend_sdcpp_register()` to register the
    /// sd.cpp diffusion service provider with the C++ commons layer.
    ///
    /// Safe to call multiple times — subsequent calls are no-ops.
    ///
    /// - Parameter priority: Ignored (C++ uses its own priority system)
    /// - Throws: SDKError if registration fails
    @MainActor
    public static func register(priority _: Int = 90) {
        guard !isRegistered else {
            logger.debug("sd.cpp already registered, returning")
            return
        }

        logger.info("Registering sd.cpp diffusion backend with C++ registry...")

        let result = rac_backend_sdcpp_register()

        // RAC_ERROR_MODULE_ALREADY_REGISTERED is OK
        if result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED {
            let errorMsg = String(cString: rac_error_message(result))
            logger.error("sd.cpp registration failed: \(errorMsg)")
            return
        }

        isRegistered = true
        logger.info("sd.cpp diffusion backend registered successfully")
    }

    /// Unregister the sd.cpp backend.
    ///
    /// Note: The C++ layer does not currently expose an unregister function
    /// for the sdcpp backend, so this only resets the Swift-side state.
    public static func unregister() {
        if isRegistered {
            isRegistered = false
            logger.info("sd.cpp diffusion backend unregistered (Swift side)")
        }
    }

    // MARK: - Model Handling

    /// Check if sd.cpp can handle a given model.
    /// Uses file extension pattern matching — actual framework info is in C++ registry.
    public static func canHandle(modelId: String?) -> Bool {
        guard let modelId = modelId else { return false }
        let lowered = modelId.lowercased()
        return lowered.hasSuffix(".gguf")
            || lowered.hasSuffix(".safetensors")
            || lowered.hasSuffix(".ckpt")
    }
}

// MARK: - Auto-Registration

extension Sdcpp {
    /// Enable auto-registration for this module.
    /// Access this property to trigger C++ backend registration.
    public static let autoRegister: Void = {
        Task { @MainActor in
            Sdcpp.register()
        }
    }()
}
