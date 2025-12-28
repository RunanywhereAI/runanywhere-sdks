import CRABackendLlamaCPP
import CRACommons
import Foundation
import RunAnywhere

/// LlamaCPP Runtime module for RunAnywhere SDK
///
/// This module provides LlamaCPP backend support for:
/// - Text Generation (LLM) using GGUF models
///
/// ## Usage
///
/// ```swift
/// import RunAnywhere
/// import LlamaCPPRuntime
///
/// // Register the backend (done automatically if auto-registration is enabled)
/// LlamaCPPRuntime.registerBackend()
///
/// let service = LlamaCPPService()
/// try await service.initialize(modelPath: "/path/to/model.gguf")
///
/// // Synchronous generation
/// let result = try await service.generate(prompt: "Hello, world!", options: .init())
/// print("Generated: \(result)")
///
/// // Streaming generation
/// try await service.streamGenerate(prompt: "Tell me a story", options: .init()) { token in
///     print(token, terminator: "")
/// }
/// ```
public enum LlamaCPPRuntime {
    /// Current version of the LlamaCPP Runtime module
    /// Note: Should be kept in sync with SDK version in VERSION file
    public static let version = "2.0.0"

    /// LlamaCPP library version (underlying C++ library)
    public static let llamaCppVersion = "b7199"

    /// Whether the backend has been registered with C++ commons
    private static var isBackendRegistered = false

    /// Register the LlamaCPP backend with the C++ commons layer.
    ///
    /// This registers the LlamaCPP module and service provider with the
    /// runanywhere-commons module and service registries.
    ///
    /// Safe to call multiple times - subsequent calls are no-ops.
    ///
    /// - Throws: SDKError if registration fails
    public static func registerBackend() throws {
        guard !isBackendRegistered else { return }

        let result = rac_backend_llamacpp_register()
        if result != RAC_SUCCESS {
            throw SDKError.general(
                .initializationFailed,
                "Failed to register LlamaCPP backend: \(String(cString: rac_error_message(result)))"
            )
        }

        isBackendRegistered = true
    }

    /// Unregister the LlamaCPP backend from C++ commons.
    public static func unregisterBackend() {
        guard isBackendRegistered else { return }

        _ = rac_backend_llamacpp_unregister()
        isBackendRegistered = false
    }
}
