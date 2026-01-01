//
//  ONNX.swift
//  ONNXRuntime Module
//
//  Unified ONNX module - thin wrapper that calls C++ backend registration.
//  This replaces both ONNXRuntime.swift and ONNXServiceProvider.swift.
//

import CRACommons
import Foundation
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
public enum ONNX: RunAnywhereModule {
    private static let logger = SDKLogger(category: "ONNX")

    // MARK: - Module Info

    /// Current version of the ONNX Runtime module
    public static let version = "2.0.0"

    /// ONNX Runtime library version (underlying C library)
    public static let onnxRuntimeVersion = "1.23.2"

    // MARK: - RunAnywhereModule Conformance

    public static let moduleId = "onnx"
    public static let moduleName = "ONNX Runtime"
    public static let capabilities: Set<SDKComponent> = [.stt, .tts, .vad]
    public static let defaultPriority: Int = 100

    /// ONNX uses the ONNX Runtime inference framework
    public static let inferenceFramework: InferenceFramework = .onnx

    // MARK: - Strategy Access (via C++ Bridge)

    /// Find model path using C++ storage strategy
    /// - Parameters:
    ///   - modelId: Model identifier
    ///   - modelFolder: Model folder URL
    /// - Returns: Resolved model path, or nil if not found
    public static func findModelPath(modelId: String, in modelFolder: URL) -> URL? {
        return CppBridge.Strategy.findModelPath(
            framework: inferenceFramework,
            modelId: modelId,
            modelFolder: modelFolder
        )
    }

    /// Detect model in folder using C++ storage strategy
    /// - Parameter modelFolder: Model folder URL
    /// - Returns: Storage details if model detected
    public static func detectModel(in modelFolder: URL) -> ModelStorageDetails? {
        return CppBridge.Strategy.detectModel(
            framework: inferenceFramework,
            modelFolder: modelFolder
        )
    }

    /// Validate model storage using C++ strategy
    /// - Parameter modelFolder: Model folder URL
    /// - Returns: True if storage is valid
    public static func isValidStorage(at modelFolder: URL) -> Bool {
        return CppBridge.Strategy.isValidStorage(
            framework: inferenceFramework,
            modelFolder: modelFolder
        )
    }

    // MARK: - Registration State

    private static var isRegistered = false

    // MARK: - Registration

    /// Register ONNX backend with the C++ service registry.
    ///
    /// This calls `rac_backend_onnx_register()` to register all ONNX
    /// service providers (STT, TTS, VAD) with the C++ commons layer.
    ///
    /// Safe to call multiple times - subsequent calls are no-ops.
    ///
    /// - Parameter priority: Ignored (C++ uses its own priority system)
    /// - Throws: SDKError if registration fails
    @MainActor
    public static func register(priority: Int = 100) {
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
        logger.info("ONNX backend registered successfully (STT + TTS + VAD)")
    }

    /// Unregister the ONNX backend from C++ registry.
    public static func unregister() {
        guard isRegistered else { return }

        _ = rac_backend_onnx_unregister()
        isRegistered = false
        logger.info("ONNX backend unregistered")
    }

    // MARK: - Model Handling

    /// Check if ONNX can handle a given model for STT
    public static func canHandleSTT(modelId: String?) -> Bool {
        guard let modelId = modelId else { return false }

        // Check model info cache for framework and category
        if let modelInfo = ModelInfoCache.shared.modelInfo(for: modelId) {
            return modelInfo.framework == .onnx && modelInfo.category == .speechRecognition
        }

        // Fallback: check for STT model patterns
        let lowercased = modelId.lowercased()
        return lowercased.contains("whisper") ||
               lowercased.contains("zipformer") ||
               lowercased.contains("paraformer")
    }

    /// Check if ONNX can handle a given model for TTS
    public static func canHandleTTS(modelId: String?) -> Bool {
        guard let modelId = modelId else { return false }

        // Check model info cache for framework and category
        if let modelInfo = ModelInfoCache.shared.modelInfo(for: modelId) {
            return modelInfo.framework == .onnx && modelInfo.category == .speechSynthesis
        }

        // Fallback: check for TTS model patterns
        let lowercased = modelId.lowercased()
        return lowercased.contains("piper") || lowercased.contains("vits")
    }

    /// Check if ONNX can handle VAD (always true for Silero VAD)
    public static func canHandleVAD(modelId: String?) -> Bool {
        return true  // ONNX Silero VAD is the default
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
