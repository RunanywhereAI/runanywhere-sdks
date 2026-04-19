//
//  WhisperKitSTT.swift
//  WhisperKitRuntime Module
//
//  Standalone WhisperKit CoreML module for STT via Apple Neural Engine.
//  Registers as a C++ backend via callbacks so all transcription
//  flows through stt_component.cpp for automatic telemetry.
//

import CRACommons
import Foundation
import RunAnywhere

// MARK: - WhisperKit CoreML Module

/// WhisperKit CoreML module for Speech-to-Text using Apple Neural Engine.
///
/// Registers with the C++ backend system via callbacks, so transcription
/// goes through `rac_stt_component_transcribe` and gets automatic telemetry.
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
    private static let logger = SDKLogger(category: "WhisperKitCoreML")

    // MARK: - Module Info

    public static let version = "1.0.0"

    // MARK: - RunAnywhereModule Conformance

    public static let moduleId = "whisperkit_coreml"
    public static let moduleName = "WhisperKit CoreML"
    public static let capabilities: Set<SDKComponent> = [.stt]
    public static let defaultPriority: Int = 200
    public static let inferenceFramework: InferenceFramework = .whisperKitCoreML

    // MARK: - Registration State

    private static var isRegistered = false

    // MARK: - Registration

    /// Register WhisperKit CoreML STT backend with the C++ module/service registry.
    ///
    /// Sets up C callbacks that bridge to `WhisperKitSTTService`, then
    /// calls `rac_backend_whisperkit_coreml_register()` to register with the
    /// service registry at priority 200.
    ///
    /// Safe to call multiple times - subsequent calls are no-ops.
    ///
    /// - Parameter priority: Priority for this backend (default: 200, higher than ONNX at 100)
    @MainActor
    public static func register(priority _: Int = 200) {
        guard !isRegistered else {
            logger.debug("WhisperKit CoreML already registered, returning")
            return
        }

        var callbacks = rac_whisperkit_coreml_stt_callbacks_t()
        callbacks.can_handle = whisperKitCoreMLCanHandle
        callbacks.create = whisperKitCoreMLCreate
        callbacks.transcribe = whisperKitCoreMLTranscribe
        callbacks.destroy = whisperKitCoreMLDestroy
        callbacks.user_data = nil

        let cbResult = rac_whisperkit_coreml_stt_set_callbacks(&callbacks)
        guard cbResult == RAC_SUCCESS else {
            logger.error("Failed to set WhisperKit CoreML callbacks: \(cbResult)")
            return
        }

        let regResult = rac_backend_whisperkit_coreml_register()
        guard regResult == RAC_SUCCESS || regResult == RAC_ERROR_MODULE_ALREADY_REGISTERED else {
            logger.error("Failed to register WhisperKit CoreML backend: \(regResult)")
            return
        }

        isRegistered = true
        logger.info("WhisperKit CoreML STT registered (Neural Engine, priority=200)")
    }

    /// Unregister the WhisperKit CoreML backend.
    @MainActor
    public static func unregister() {
        guard isRegistered else { return }

        rac_backend_whisperkit_coreml_unregister()
        isRegistered = false
        logger.info("WhisperKit CoreML STT unregistered")
    }

    // MARK: - Model Handling

    /// Check if WhisperKit CoreML can handle a given model for STT
    public static func canHandleSTT(modelId: String?) -> Bool {
        guard let modelId = modelId else { return false }
        return modelId.lowercased().contains("whisperkit")
    }
}

// MARK: - C Callback Implementations

/// These are `@convention(c)` functions that bridge from the C++ vtable
/// dispatch into the Swift `WhisperKitSTTService` actor via CoreML.

private func whisperKitCoreMLCanHandle(
    _ modelId: UnsafePointer<CChar>?,
    _ userData: UnsafeMutableRawPointer?
) -> rac_bool_t {
    _ = userData
    guard let modelId = modelId else { return RAC_FALSE }
    let id = String(cString: modelId)
    return WhisperKitSTT.canHandleSTT(modelId: id) ? RAC_TRUE : RAC_FALSE
}

private func whisperKitCoreMLCreate(
    _ modelPath: UnsafePointer<CChar>?,
    _ modelId: UnsafePointer<CChar>?,
    _ userData: UnsafeMutableRawPointer?
) -> rac_handle_t? {
    _ = userData
    guard let modelPath = modelPath else { return nil }

    let path = String(cString: modelPath)
    let id = modelId.map { String(cString: $0) } ?? "unknown"

    var handle: rac_handle_t?
    let semaphore = DispatchSemaphore(value: 0)

    Task {
        do {
            try await WhisperKitSTTService.shared.loadModel(modelId: id, modelFolder: path)
            handle = Unmanaged.passRetained(WhisperKitSTTService.shared).toOpaque()
        } catch {
            let logger = SDKLogger(category: "WhisperKitCoreML")
            logger.error("Failed to load WhisperKit CoreML model: \(error)")
            handle = nil
        }
        semaphore.signal()
    }

    semaphore.wait()
    return handle
}

private func whisperKitCoreMLTranscribe(
    _ handle: rac_handle_t?,
    _ audioData: UnsafeRawPointer?,
    _ audioSize: Int,
    _ options: UnsafePointer<rac_stt_options_t>?,
    _ outResult: UnsafeMutablePointer<rac_stt_result_t>?,
    _ userData: UnsafeMutableRawPointer?
) -> rac_result_t {
    _ = userData
    guard let handle = handle, let audioData = audioData, let outResult = outResult else {
        return RAC_ERROR_NULL_POINTER
    }

    let data = Data(bytes: audioData, count: audioSize)
    let sttOptions: STTOptions
    if let opts = options, let langPtr = opts.pointee.language {
        sttOptions = STTOptions(language: String(cString: langPtr))
    } else {
        sttOptions = STTOptions()
    }

    var result: rac_result_t = RAC_ERROR_INTERNAL
    let semaphore = DispatchSemaphore(value: 0)

    Task {
        do {
            let service = Unmanaged<WhisperKitSTTService>.fromOpaque(handle).takeUnretainedValue()
            let output = try await service.transcribe(data, options: sttOptions)

            outResult.pointee.text = output.text.isEmpty ? nil : strdup(output.text)
            outResult.pointee.confidence = output.confidence
            outResult.pointee.processing_time_ms = Int64(output.metadata.processingTime * 1000)

            if let lang = output.detectedLanguage {
                outResult.pointee.detected_language = strdup(lang)
            }

            result = RAC_SUCCESS
        } catch {
            let logger = SDKLogger(category: "WhisperKitCoreML")
            logger.error("WhisperKit CoreML transcribe failed: \(error)")
            result = RAC_ERROR_INTERNAL
        }
        semaphore.signal()
    }

    semaphore.wait()
    return result
}

private func whisperKitCoreMLDestroy(
    _ handle: rac_handle_t?,
    _ userData: UnsafeMutableRawPointer?
) {
    _ = userData
    guard let handle = handle else { return }

    let semaphore = DispatchSemaphore(value: 0)

    Task {
        let service = Unmanaged<WhisperKitSTTService>.fromOpaque(handle).takeRetainedValue()
        await service.unloadModel()
        semaphore.signal()
    }

    semaphore.wait()
}
