//
//  ONNXModule.swift
//  ONNXRuntime Module
//
//  ONNX Runtime module providing STT and TTS capabilities.
//

import Foundation
import RunAnywhere

// MARK: - ONNX Module

/// ONNX Runtime module for STT and TTS services.
///
/// Provides speech-to-text and text-to-speech capabilities using
/// ONNX Runtime with models like Whisper and Piper.
///
/// ## Registration
///
/// ```swift
/// import ONNXRuntime
///
/// // Option 1: Direct registration
/// ONNX.register()
///
/// // Option 2: Via ModuleRegistry
/// ModuleRegistry.shared.register(ONNX.self)
///
/// // Option 3: Via RunAnywhere
/// RunAnywhere.register(ONNX.self)
/// ```
///
/// ## Usage
///
/// ```swift
/// try await RunAnywhere.loadSTTModel("my-onnx-model")
/// let text = try await RunAnywhere.transcribe(audioData)
/// ```
public enum ONNX: RunAnywhereModule {
    private static let logger = SDKLogger(category: "ONNX")

    // MARK: - RunAnywhereModule Conformance

    public static let moduleId = "onnx"
    public static let moduleName = "ONNX Runtime"
    public static let capabilities: Set<CapabilityType> = [.stt, .tts]
    public static let defaultPriority: Int = 100

    /// ONNX uses the ONNX Runtime inference framework
    public static let inferenceFramework: InferenceFramework = .onnx

    /// Storage strategy for ONNX models (handles nested directory structures)
    public static let storageStrategy: ModelStorageStrategy? = ONNXModelStorageStrategy()

    /// Register all ONNX services with the SDK
    @MainActor
    public static func register(priority: Int) {
        registerSTT(priority: priority)
        registerTTS(priority: priority)
        logger.info("ONNX module registered (STT + TTS)")
    }

    // MARK: - Individual Service Registration

    /// Register only ONNX STT service
    @MainActor
    public static func registerSTT(priority: Int = 100) {
        ServiceRegistry.shared.registerSTT(
            name: moduleName,
            priority: priority,
            canHandle: { modelId in
                canHandleSTT(modelId)
            },
            factory: { config in
                try await createSTTService(config: config)
            }
        )
        logger.info("ONNX STT registered")
    }

    /// Register only ONNX TTS service
    @MainActor
    public static func registerTTS(priority: Int = 100) {
        ServiceRegistry.shared.registerTTS(
            name: "ONNX TTS",
            priority: priority,
            canHandle: { modelId in
                canHandleTTS(modelId)
            },
            factory: { config in
                try await createTTSService(config: config)
            }
        )
        logger.info("ONNX TTS registered")
    }

    // MARK: - STT Helpers

    private static func canHandleSTT(_ modelId: String?) -> Bool {
        guard let modelId = modelId else { return false }

        // Framework from model info is the single source of truth
        // Models must be registered with the SDK via addModel() to be handled
        if let modelInfo = ModelInfoCache.shared.modelInfo(for: modelId) {
            return modelInfo.framework == .onnx && modelInfo.category == .speechRecognition
        }

        // Model is not registered - cannot handle unknown models
        return false
    }

    private static func createSTTService(config: STTConfiguration) async throws -> STTService {
        logger.info("Creating ONNX STT service for model: \(config.modelId ?? "unknown")")

        var modelPath: String?
        if let modelId = config.modelId {
            let allModels = try await RunAnywhere.availableModels()
            let modelInfo = allModels.first { $0.id == modelId }

            if let localPath = modelInfo?.localPath {
                modelPath = localPath.path
                logger.info("Found local model path: \(modelPath ?? "nil")")
            } else {
                logger.error("Model '\(modelId)' is not downloaded")
                throw SDKError.runtime(.modelNotFound, "Model '\(modelId)' is not downloaded. Please download the model first.")
            }
        }

        let service = ONNXSTTService()
        try await service.initialize(modelPath: modelPath)
        logger.info("ONNX STT service created successfully")
        return service
    }

    // MARK: - TTS Helpers

    private static func canHandleTTS(_ modelId: String?) -> Bool {
        guard let modelId = modelId else { return false }

        // Framework from model info is the single source of truth
        // Models must be registered with the SDK via addModel() to be handled
        if let modelInfo = ModelInfoCache.shared.modelInfo(for: modelId) {
            return modelInfo.framework == .onnx && modelInfo.category == .speechSynthesis
        }

        // Model is not registered - cannot handle unknown models
        return false
    }

    private static func createTTSService(config: TTSConfiguration) async throws -> TTSService {
        logger.info("Creating ONNX TTS service for voice: \(config.voice)")

        let modelId = config.voice

        // Get the actual model file path from the model registry
        var modelPath: String?

        let allModels: [ModelInfo]
        do {
            allModels = try await RunAnywhere.availableModels()
        } catch {
            logger.error("Failed to fetch available models: \(error)")
            throw SDKError.runtime(.modelNotFound, "Failed to query available models: \(error.localizedDescription)")
        }

        let modelInfo = allModels.first { $0.id == modelId }

        if let localPath = modelInfo?.localPath {
            modelPath = localPath.path
            logger.info("Found local model path: \(modelPath ?? "nil")")
        } else {
            logger.error("TTS Model '\(modelId)' is not downloaded")
            throw SDKError.runtime(.modelNotFound, "TTS Model '\(modelId)' is not downloaded. Please download the model first.")
        }

        guard let path = modelPath else {
            throw SDKError.runtime(.modelNotFound, "Could not find model path for: \(modelId)")
        }

        logger.info("Creating ONNXTTSService with path: \(path)")
        let service = ONNXTTSService(modelPath: path)

        do {
            try await service.initialize()
            logger.info("ONNX TTS service initialized successfully")
        } catch {
            logger.error("Failed to initialize ONNX TTS service: \(error)")
            throw error
        }

        return service
    }
}

// MARK: - Auto-Discovery Registration

extension ONNX {
    /// Enable auto-discovery for this module.
    /// Access this property to trigger registration.
    public static let autoRegister: Void = {
        ModuleDiscovery.register(ONNX.self)
    }()
}
