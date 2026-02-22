//
//  WhisperKitSTT.swift
//  WhisperKitRuntime Module
//
//  Standalone WhisperKit module for STT via Apple Neural Engine.
//  Mirrors the ONNXRuntime/ONNX.swift pattern.
//

import Foundation
import RunAnywhere

// MARK: - WhisperKit Module

/// WhisperKit module for Speech-to-Text using Apple Neural Engine.
///
/// Provides high-efficiency STT using Core ML models running on the
/// Neural Engine (`.cpuAndNeuralEngine`), ideal for background transcription
/// on iOS where GPU access is restricted.
///
/// ## Registration
///
/// ```swift
/// import WhisperKitRuntime
///
/// WhisperKitSTT.register()
/// ```
///
/// ## Usage
///
/// After registration, load a WhisperKit model and transcribe through the
/// standard RunAnywhere API:
///
/// ```swift
/// try await RunAnywhere.loadSTTModel("whisperkit-tiny.en")
/// let text = try await RunAnywhere.transcribe(audioData)
/// ```
public enum WhisperKitSTT: RunAnywhereModule {
    private static let logger = SDKLogger(category: "WhisperKit")

    // MARK: - Module Info

    public static let version = "1.0.0"

    // MARK: - RunAnywhereModule Conformance

    public static let moduleId = "whisperkit"
    public static let moduleName = "WhisperKit"
    public static let capabilities: Set<SDKComponent> = [.stt]
    public static let defaultPriority: Int = 200
    public static let inferenceFramework: InferenceFramework = .whisperKitCoreML

    // MARK: - Registration State

    private static var isRegistered = false

    // MARK: - Registration

    /// Register WhisperKit STT backend.
    ///
    /// Sets the `swiftSTTHandler` on `RunAnywhere` so that WhisperKit models
    /// are loaded and transcribed via the Swift-only path (no C++ bridge).
    ///
    /// Safe to call multiple times - subsequent calls are no-ops.
    ///
    /// - Parameter priority: Priority for this backend (default: 200, higher than ONNX at 100)
    @MainActor
    public static func register(priority _: Int = 200) {
        guard !isRegistered else {
            logger.debug("WhisperKit already registered, returning")
            return
        }

        RunAnywhere.swiftSTTHandler = WhisperKitSTTService.shared
        isRegistered = true
        logger.info("WhisperKit STT registered (Neural Engine)")
    }

    /// Unregister the WhisperKit backend.
    @MainActor
    public static func unregister() {
        guard isRegistered else { return }

        RunAnywhere.swiftSTTHandler = nil
        isRegistered = false
        logger.info("WhisperKit STT unregistered")
    }

    // MARK: - Model Handling

    /// Check if WhisperKit can handle a given model for STT
    public static func canHandleSTT(modelId: String?) -> Bool {
        guard let modelId = modelId else { return false }
        return modelId.lowercased().contains("whisperkit")
    }
}
