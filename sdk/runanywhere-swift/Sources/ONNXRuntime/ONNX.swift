//
//  ONNX.swift
//  ONNXRuntime Module
//
//  Unified ONNX module - thin wrapper that calls C++ backend registration.
//  This replaces both ONNXRuntime.swift and ONNXServiceProvider.swift.
//

import CRACommons
import ONNXBackend
import RunAnywhere

// MARK: - ONNX Module

/// ONNX Runtime module for STT, TTS, and VAD services.
///
/// Provides speech-to-text, text-to-speech, and voice activity detection
/// capabilities using ONNX Runtime with models like Whisper, Piper, and Silero.
///
/// ## Registration
///
/// ```swift
/// import ONNXRuntime
///
/// // Register the backend (done automatically if auto-registration is enabled)
/// try ONNX.register()
/// ```
///
/// ## Usage
///
/// Services are accessed through the main SDK APIs - the C++ backend handles
/// service creation and lifecycle internally:
///
/// ```swift
/// // STT via public API
/// let text = try await RunAnywhere.transcribe(audioData)
///
/// // TTS via public API
/// try await RunAnywhere.speak("Hello")
/// ```
public enum ONNX {
    private static let logger = SDKLogger(category: "ONNX")

    // MARK: - Module Info

    /// Current version of the ONNX Runtime module
    public static let version = "2.0.0"

    /// ONNX Runtime library version (underlying C library)
    public static let onnxRuntimeVersion = "1.23.2"

    // MARK: - Registration State

    private static var isRegistered = false
    private static var isSherpaRegistered = false

    // MARK: - Registration

    /// Register ONNX backend with the C++ service registry.
    ///
    /// This calls `rac_backend_onnx_register()` to register the generic ONNX
    /// module (embeddings + Silero VAD), and then registers the Sherpa-ONNX
    /// engine plugin so STT (Whisper/Zipformer) and TTS (Piper/VITS) models
    /// where `framework == .sherpa` can resolve through the unified plugin
    /// router. The two plugins are peers: "onnx" owns embeddings, "sherpa"
    /// owns speech primitives.
    ///
    /// Safe to call multiple times - subsequent calls are no-ops.
    ///
    /// - Parameter priority: Ignored (C++ uses its own priority system)
    @MainActor
    public static func register(priority _: Int = 100) {
        guard !isRegistered else {
            logger.debug("ONNX already registered, returning")
            return
        }

        logger.info("Registering ONNX backend with C++ registry...")

        let result = rac_backend_onnx_register()

        // RAC_ERROR_MODULE_ALREADY_REGISTERED is OK
        if result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED {
            let errorMsg = String(cString: rac_error_message(result))
            logger.error("ONNX registration failed: \(errorMsg)")
            // Don't throw - registration failure shouldn't crash the app
            return
        }

        isRegistered = true
        logger.info("ONNX backend registered successfully (embeddings + plugin)")

        // Register the Sherpa-ONNX engine plugin for STT / TTS / VAD. The
        // `rac_backend_sherpa_register` wrapper is not exported from the
        // shipped RABackendSherpa.xcframework, so we call the plugin
        // registry directly with the entry symbol that IS exported.
        registerSherpaPlugin()
    }

    /// Register the Sherpa-ONNX unified-ABI engine plugin so the commons
    /// plugin router can resolve `framework == .sherpa` models (STT:
    /// Whisper / Zipformer / Paraformer; TTS: Piper / VITS; VAD: Silero).
    @MainActor
    private static func registerSherpaPlugin() {
        guard !isSherpaRegistered else { return }

        guard let vtable = rac_plugin_entry_sherpa() else {
            // warning level so this surfaces even when the logger is still
            // on its production default (.warning) during early-boot backend
            // registration (before Logging.shared.applyEnvironmentConfiguration
            // drops the filter to .debug in Phase 1).
            logger.warning("Sherpa plugin entry returned null — Sherpa STT/TTS/VAD will not route")
            return
        }

        let registerResult = vtable.withMemoryRebound(
            to: rac_engine_vtable_t.self, capacity: 1
        ) { typedPointer -> rac_result_t in
            return rac_plugin_register(typedPointer)
        }

        if registerResult == RAC_SUCCESS ||
           registerResult == RAC_ERROR_MODULE_ALREADY_REGISTERED {
            isSherpaRegistered = true
            logger.warning("Sherpa engine plugin registered (STT + TTS + VAD via Sherpa-ONNX)")
        } else {
            let errorMsg = String(cString: rac_error_message(registerResult))
            // The shipped RABackendSherpa.xcframework is known to be compiled
            // with `RAC_SHERPA_ROUTABLE=0` (the speech-ops #define was OFF at
            // build time), so `sherpa_capability_check()` returns
            // RAC_ERROR_BACKEND_UNAVAILABLE which the plugin registry maps to
            // RAC_ERROR_CAPABILITY_UNSUPPORTED here. Rebuilding the xcframework
            // with RAC_BACKEND_SHERPA=ON + SHERPA_ONNX_AVAILABLE=1 unblocks
            // this; until then STT / TTS via `framework == .sherpa` will fail
            // at loadModel() time with the same message.
            logger.error("Sherpa plugin registration failed: \(errorMsg)")
        }
    }

    /// Unregister the ONNX backend from C++ registry.
    ///
    /// `@MainActor` so the `isRegistered` / `isSherpaRegistered` static flags
    /// stay in the same isolation domain as `register(priority:)` and the
    /// `autoRegister` Task hop. Without this annotation, a teardown call on
    /// a background thread would race the registration path and could leave
    /// the C registry in an inconsistent state (double-unregister or skipped
    /// unregister, see comment record `mlt-003`).
    @MainActor
    public static func unregister() {
        if isSherpaRegistered {
            _ = rac_plugin_unregister("sherpa")
            isSherpaRegistered = false
            logger.info("Sherpa engine plugin unregistered")
        }

        guard isRegistered else { return }

        _ = rac_backend_onnx_unregister()
        isRegistered = false
        logger.info("ONNX backend unregistered")
    }

}

// MARK: - Auto-Registration

extension ONNX {
    /// Enable auto-registration for this module.
    /// Access this property to trigger C++ backend registration.
    public static let autoRegister: Void = {
        Task { @MainActor in
            ONNX.register()
        }
    }()
}
