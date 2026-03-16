//
//  MetalRT.swift
//  MetalRTRuntime Module
//
//  Unified MetalRT module - thin wrapper that calls C++ backend registration.
//  MetalRT provides high-performance LLM, STT, TTS, and VLM inference using
//  custom Metal GPU kernels on Apple silicon.
//

import CRACommons
import Foundation
import MetalRTBackend
import os.log
import RunAnywhere

// MARK: - MetalRT Module

/// MetalRT module for high-performance on-device inference.
///
/// Provides LLM, STT (Whisper), TTS (Kokoro), and VLM capabilities using
/// custom Metal GPU kernels optimized for Apple silicon.
///
/// ## Registration
///
/// ```swift
/// import MetalRTRuntime
///
/// // Register the backend
/// MetalRT.register()
/// ```
///
/// ## Usage
///
/// Models must be registered with `.metalrt` framework:
///
/// ```swift
/// RunAnywhere.registerModel(
///     id: "qwen3-0.6b-metalrt",
///     name: "Qwen3 0.6B (MetalRT)",
///     url: modelURL,
///     framework: .metalrt,
///     modality: .textGeneration,
///     memoryRequirement: 400_000_000
/// )
/// ```
public enum MetalRT: RunAnywhereModule {
    private static let logger = SDKLogger(category: "MetalRT")

    // MARK: - Module Info

    /// Current version of the MetalRT Runtime module
    public static let version = "1.0.0"

    // MARK: - RunAnywhereModule Conformance

    public static let moduleId = "metalrt"
    public static let moduleName = "MetalRT"
    public static let capabilities: Set<SDKComponent> = [.llm, .stt, .tts]
    public static let defaultPriority: Int = 100

    /// MetalRT uses custom Metal GPU kernels
    public static let inferenceFramework: InferenceFramework = .metalrt

    // MARK: - Registration State

    private static var isRegistered = false

    // MARK: - Registration

    /// Register MetalRT backend with the C++ service registry.
    ///
    /// This calls `rac_backend_metalrt_register()` to register the MetalRT
    /// service providers (LLM, STT, TTS, VLM) with the C++ commons layer.
    ///
    /// Safe to call multiple times - subsequent calls are no-ops.
    ///
    /// - Parameter priority: Ignored (C++ uses its own priority system)
    @MainActor
    public static func register(priority _: Int = 100) {
        guard !isRegistered else {
            logger.debug("MetalRT already registered, returning")
            return
        }

        logger.info("Registering MetalRT backend with C++ registry...")

        let result = rac_backend_metalrt_register()

        if result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED {
            let errorMsg = String(cString: rac_error_message(result))
            logger.error("MetalRT registration failed: \(errorMsg)")
            return
        }

        isRegistered = true
        logger.info("MetalRT backend registered successfully (LLM, STT, TTS, VLM)")
    }

    /// Unregister the MetalRT backend from C++ registry.
    public static func unregister() {
        guard isRegistered else { return }
        _ = rac_backend_metalrt_unregister()
        isRegistered = false
        logger.info("MetalRT backend unregistered")
    }

    // MARK: - Model Handling

    /// Check if MetalRT can handle a given model.
    /// MetalRT only handles models explicitly registered with .metalrt framework.
    public static func canHandle(modelId _: String?) -> Bool {
        // Framework-hint only — we never auto-detect from file extension
        return false
    }
}

// MARK: - Auto-Registration

extension MetalRT {
    /// Enable auto-registration for this module.
    /// Access this property to trigger C++ backend registration.
    public static let autoRegister: Void = {
        Task { @MainActor in
            MetalRT.register()
        }
    }()
}
