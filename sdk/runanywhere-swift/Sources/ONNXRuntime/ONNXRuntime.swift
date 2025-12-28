import CRABackendONNX
import CRACommons
import Foundation
import RunAnywhere

/// ONNXRuntime module for RunAnywhere SDK
///
/// This module provides ONNX Runtime backend support for:
/// - Speech-to-Text (STT) using Whisper and other ONNX models
/// - Text-to-Speech (TTS) using Piper and other ONNX models
/// - Voice Activity Detection (VAD)
///
/// ## Usage
///
/// ```swift
/// import RunAnywhere
/// import ONNXRuntime
///
/// // Register the backend (done automatically if auto-registration is enabled)
/// try ONNXRuntime.registerBackend()
///
/// let service = ONNXSTTService()
/// try await service.initialize(modelPath: "/path/to/model")
///
/// let result = try await service.transcribe(
///     audioData: audioData,
///     options: STTOptions(sampleRate: 16000)
/// )
/// print("Transcribed: \(result.text)")
/// ```
public enum ONNXRuntime {
    /// Current version of the ONNX Runtime module
    /// Note: Should be kept in sync with SDK version in VERSION file
    public static let version = "2.0.0"

    /// ONNX Runtime library version (underlying C library)
    public static let onnxRuntimeVersion = "1.23.2"

    /// Whether the backend has been registered with C++ commons
    private static var isBackendRegistered = false

    /// Register the ONNX backend with the C++ commons layer.
    ///
    /// This registers the ONNX module and service providers (STT, TTS, VAD)
    /// with the runanywhere-commons module and service registries.
    ///
    /// Safe to call multiple times - subsequent calls are no-ops.
    ///
    /// - Throws: SDKError if registration fails
    public static func registerBackend() throws {
        guard !isBackendRegistered else { return }

        let result = rac_backend_onnx_register()
        if result != RAC_SUCCESS {
            let errorMessage = String(cString: rac_error_message(result))
            let fallbackError = SDKError.general(
                .initializationFailed,
                "Failed to register ONNX backend: \(errorMessage)"
            )
            throw CommonsErrorMapping.toSDKError(result) ?? fallbackError
        }

        isBackendRegistered = true
    }

    /// Unregister the ONNX backend from C++ commons.
    public static func unregisterBackend() {
        guard isBackendRegistered else { return }

        _ = rac_backend_onnx_unregister()
        isBackendRegistered = false
    }
}
