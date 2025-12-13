//
//  LoadedModel.swift
//  RunAnywhere SDK
//
//  Represents a model that has been loaded and is ready for use
//

import Foundation

/// Represents a model that has been loaded and is ready for use
/// Pairs the model information with the service that can execute it
public struct LoadedModel {
    /// The model information
    public let model: ModelInfo

    /// The LLM service that can execute this model (for LLM modality)
    public let service: LLMService

    /// The modality of this loaded model
    public let modality: Modality

    /// When this model was loaded
    public let loadedAt: Date

    /// The framework used to load this model
    public var framework: LLMFramework {
        model.preferredFramework ?? .llamaCpp
    }

    // MARK: - Initialization

    public init(model: ModelInfo, service: LLMService) {
        self.model = model
        self.service = service
        self.modality = .llm
        self.loadedAt = Date()
    }

    public init(model: ModelInfo, service: LLMService, modality: Modality) {
        self.model = model
        self.service = service
        self.modality = modality
        self.loadedAt = Date()
    }

    // MARK: - Convenience Properties

    /// Model identifier
    public var modelId: String {
        model.id
    }

    /// Model name
    public var modelName: String {
        model.name
    }

    /// Check if the service is ready for use
    public var isReady: Bool {
        service.isReady
    }

    /// Estimated memory usage in bytes
    public var memoryUsage: Int64 {
        model.memoryRequired ?? 0
    }
}

// MARK: - Multi-Modal Loaded Models

/// Represents a loaded STT model
public struct LoadedSTTModel {
    /// The model information
    public let model: ModelInfo

    /// The STT service that can execute this model
    public let service: STTService

    /// When this model was loaded
    public let loadedAt: Date

    public init(model: ModelInfo, service: STTService) {
        self.model = model
        self.service = service
        self.loadedAt = Date()
    }

    public var modelId: String { model.id }
    public var modelName: String { model.name }
    public var isReady: Bool { service.isReady }
}

/// Represents a loaded TTS model
public struct LoadedTTSModel {
    /// The model information
    public let model: ModelInfo

    /// The TTS service that can execute this model
    public let service: TTSService

    /// When this model was loaded
    public let loadedAt: Date

    public init(model: ModelInfo, service: TTSService) {
        self.model = model
        self.service = service
        self.loadedAt = Date()
    }

    public var modelId: String { model.id }
    public var modelName: String { model.name }
}
