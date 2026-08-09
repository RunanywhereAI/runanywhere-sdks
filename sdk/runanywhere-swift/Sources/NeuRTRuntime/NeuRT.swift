//
//  NeuRT.swift
//  NeuRTRuntime Module
//
//  Thin wrapper that registers the NeuRT engine (Apple Neural Engine text
//  generation + CoreML diffusion) with the commons plugin registry. Mirrors
//  ONNX.swift's Sherpa registration: the shipped RABackendNeuRT.xcframework
//  exports only the `rac_plugin_entry_neurt` entry symbol, so we register by
//  handing its vtable to `rac_plugin_register(...)`.
//

import CRACommons
import NeuRTBackend
import RunAnywhere

// MARK: - NeuRT Module

/// NeuRT backend module — Apple Neural Engine inference.
///
/// Serves on-device text generation on the Apple Neural Engine and image
/// generation (diffusion) over CoreML. Import this module and register it to
/// route `framework == .coreml` model loads through the commons plugin router.
///
/// The ENGINE id is `neurt` but the FRAMEWORK case is `.coreml`: the engine is
/// named for the implementing runtime, not for Apple's framework. commons maps
/// `INFERENCE_FRAMEWORK_COREML` to `RAC_ENGINE_ID_NEURT` in
/// `engine_name_for_framework()`; there is no `.neurt` framework case.
///
/// ## Registration
///
/// ```swift
/// import NeuRTRuntime
///
/// // Register the backend (also happens automatically via `autoRegister`).
/// NeuRT.register()
/// ```
public enum NeuRT {
    private static let logger = SDKLogger(category: "NeuRT")

    // MARK: - Module Info

    /// Current version of the NeuRT Runtime module.
    public static let version = "1.0.0"

    // MARK: - Registration State

    @MainActor private static var isRegistered = false

    // MARK: - Registration

    /// Register the NeuRT engine plugin with the commons plugin registry.
    ///
    /// Safe to call multiple times — subsequent calls are no-ops, and a native
    /// "already registered" result is treated as success.
    ///
    /// - Parameter priority: Ignored (C++ uses its own priority system).
    @MainActor
    public static func register(priority _: Int = 100) {
        guard !isRegistered else {
            logger.debug("NeuRT already registered, returning")
            return
        }

        guard let vtable = rac_plugin_entry_neurt() else {
            // warning level so this surfaces even under the production default
            // (.warning) during early-boot backend registration.
            logger.warning("NeuRT plugin entry returned null — ANE LLM/diffusion will not route")
            return
        }

        let registerResult = vtable.withMemoryRebound(
            to: rac_engine_vtable_t.self, capacity: 1
        ) { typedPointer -> rac_result_t in
            return rac_plugin_register(typedPointer)
        }

        if registerResult == RAC_SUCCESS {
            // This module registered the plugin, so it owns teardown.
            // warning level (matching ONNX's Sherpa registration) so backend
            // wiring is visible at early boot, when the logger is still on its
            // production .warning default.
            isRegistered = true
            logger.warning("NeuRT engine plugin registered (ANE text generation + CoreML diffusion)")
        } else if registerResult == RAC_ERROR_MODULE_ALREADY_REGISTERED {
            // Already present (e.g. the commons static bootstrap registered it):
            // available, but not owned here, so teardown is left to whoever
            // registered it first. Deliberately do NOT set isRegistered.
            logger.warning("NeuRT engine plugin already registered; leaving ownership with the existing registrant")
        } else {
            let errorMsg = String(cString: rac_error_message(registerResult))
            logger.error("NeuRT plugin registration failed: \(errorMsg)")
        }
    }

    /// Unregister the NeuRT engine plugin from the commons registry.
    ///
    /// `@MainActor` so the `isRegistered` flag stays in the same isolation
    /// domain as `register(priority:)` and the `autoRegister` Task hop.
    @MainActor
    public static func unregister() {
        // Only tear down a registration this module owns; if NeuRT was already
        // registered by the static bootstrap, leave it in place.
        guard isRegistered else { return }

        let result = rac_plugin_unregister("neurt")
        if result == RAC_SUCCESS {
            isRegistered = false
            logger.info("NeuRT engine plugin unregistered")
        } else {
            // Keep ownership so a later retry can still tear it down.
            let errorMsg = String(cString: rac_error_message(result))
            logger.error("NeuRT plugin unregistration failed: \(errorMsg)")
        }
    }
}

// MARK: - Auto-Registration

extension NeuRT {
    /// Enable auto-registration for this module.
    /// Access this property to trigger backend registration.
    public static let autoRegister: Void = {
        Task { @MainActor in
            NeuRT.register()
        }
    }()
}
