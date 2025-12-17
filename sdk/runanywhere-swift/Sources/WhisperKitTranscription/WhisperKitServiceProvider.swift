//
//  WhisperKitModule.swift
//  WhisperKitTranscription Module
//
//  WhisperKit module providing STT capabilities using CoreML.
//

import Foundation
import RunAnywhere

// MARK: - WhisperKit Module

/// WhisperKit module for Speech-to-Text.
///
/// Provides speech recognition capabilities using WhisperKit
/// with CoreML acceleration on Apple devices.
///
/// ## Registration
///
/// ```swift
/// import WhisperKitTranscription
///
/// // Option 1: Direct registration
/// WhisperKitBackend.register()
///
/// // Option 2: Via ModuleRegistry
/// ModuleRegistry.shared.register(WhisperKitBackend.self)
///
/// // Option 3: Via RunAnywhere
/// RunAnywhere.register(WhisperKitBackend.self)
/// ```
///
/// ## Usage
///
/// ```swift
/// let text = try await RunAnywhere.transcribe(audioData)
/// ```
public enum WhisperKitBackend: RunAnywhereModule {
    private static let logger = SDKLogger(category: "WhisperKit")

    // MARK: - RunAnywhereModule Conformance

    public static let moduleId = "whisperkit"
    public static let moduleName = "WhisperKit"
    public static let inferenceFramework: InferenceFramework = .whisperKit
    public static let capabilities: Set<CapabilityType> = [.stt]
    public static let defaultPriority: Int = 100

    /// Shared strategy instance for both storage and download
    private static let sharedStrategy = WhisperKitStorageStrategy()

    /// Storage strategy for WhisperKit models (handles mlmodelc directories)
    public static var storageStrategy: ModelStorageStrategy? { sharedStrategy }

    /// Download strategy for WhisperKit models (handles multi-file HuggingFace downloads)
    public static var downloadStrategy: DownloadStrategy? { sharedStrategy }

    /// Register WhisperKit STT service with the SDK
    @MainActor
    public static func register(priority: Int) {
        ServiceRegistry.shared.registerSTT(
            name: moduleName,
            priority: priority,
            canHandle: { modelId in
                canHandleModel(modelId)
            },
            factory: { config in
                try await createService(config: config)
            }
        )
        logger.info("WhisperKit STT registered")
    }

    // MARK: - Private Helpers

    private static func canHandleModel(_ modelId: String?) -> Bool {
        guard let modelId = modelId else { return false }

        let lowercased = modelId.lowercased()

        // Check model info cache first
        if let modelInfo = ModelInfoCache.shared.modelInfo(for: modelId) {
            if modelInfo.preferredFramework == .whisperKit && modelInfo.category == .speechRecognition {
                return true
            }
            if modelInfo.compatibleFrameworks.contains(.whisperKit) && modelInfo.category == .speechRecognition {
                return true
            }
            if modelInfo.preferredFramework == .onnx || modelInfo.format == .onnx {
                return false
            }
            return false
        }

        // Fallback: Pattern-based matching
        if lowercased.contains("onnx") || lowercased.contains("glados") || lowercased.contains("distil") {
            return false
        }

        let whisperPatterns = ["whisper", "openai-whisper", "whisper-tiny", "whisper-base", "whisper-small", "whisper-medium", "whisper-large"]
        return whisperPatterns.contains(where: { lowercased.contains($0) })
    }

    private static func createService(config: STTConfiguration) async throws -> STTService {
        logger.info("Creating WhisperKit STT service")

        let service = WhisperKitService()

        if let modelId = config.modelId {
            logger.info("Initializing with model: \(modelId)")
            try await service.initialize(modelPath: modelId)
        } else {
            logger.info("Initializing with default model")
            try await service.initialize(modelPath: nil)
        }

        logger.info("WhisperKit service created successfully")
        return service
    }
}

// MARK: - Legacy Aliases

/// Legacy alias for backward compatibility
@available(*, deprecated, renamed: "WhisperKitBackend")
public typealias WhisperKitModule = WhisperKitBackend

/// Legacy alias - using WhisperKit name directly shadows the module, use WhisperKitBackend instead
@available(*, deprecated, message: "Use WhisperKitBackend to avoid shadowing the WhisperKit module")
public typealias WhisperKitProvider = WhisperKitBackend

// MARK: - Auto-Discovery Registration

extension WhisperKitBackend {
    /// Enable auto-discovery for this module.
    /// Access this property to trigger registration.
    public static let autoRegister: Void = {
        ModuleDiscovery.register(WhisperKitBackend.self)
    }()
}
