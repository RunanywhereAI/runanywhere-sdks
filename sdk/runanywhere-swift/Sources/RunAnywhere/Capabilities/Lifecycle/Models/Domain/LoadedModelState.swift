//
//  LoadedModelState.swift
//  RunAnywhere SDK
//
//  Information about a currently loaded model and its services
//

import Foundation

/// Information about a currently loaded model
/// Contains model metadata and cached service references for reuse
public struct LoadedModelState {
    /// The model identifier
    public let modelId: String

    /// Human-readable model name
    public let modelName: String

    /// The framework used to load this model
    public let framework: LLMFramework

    /// The modality this model serves
    public let modality: Modality

    /// Current load state
    public let state: ModelLoadState

    /// When the model was loaded
    public let loadedAt: Date?

    /// Memory usage in bytes
    public let memoryUsage: Int64?

    // MARK: - Service References

    /// Cached LLM service instance (for LLM modality)
    public let llmService: (any LLMService)?

    /// Cached STT service instance (for STT modality)
    public let sttService: (any STTService)?

    /// Cached TTS service instance (for TTS modality)
    public let ttsService: (any TTSService)?

    // MARK: - Initialization

    public init(
        modelId: String,
        modelName: String,
        framework: LLMFramework,
        modality: Modality,
        state: ModelLoadState,
        loadedAt: Date? = nil,
        memoryUsage: Int64? = nil,
        llmService: (any LLMService)? = nil,
        sttService: (any STTService)? = nil,
        ttsService: (any TTSService)? = nil
    ) {
        self.modelId = modelId
        self.modelName = modelName
        self.framework = framework
        self.modality = modality
        self.state = state
        self.loadedAt = loadedAt
        self.memoryUsage = memoryUsage
        self.llmService = llmService
        self.sttService = sttService
        self.ttsService = ttsService
    }

    // MARK: - Convenience Initializers

    /// Create a new state with updated load state
    public func with(state newState: ModelLoadState) -> LoadedModelState {
        LoadedModelState(
            modelId: modelId,
            modelName: modelName,
            framework: framework,
            modality: modality,
            state: newState,
            loadedAt: loadedAt,
            memoryUsage: memoryUsage,
            llmService: llmService,
            sttService: sttService,
            ttsService: ttsService
        )
    }

    /// Create a new state with updated memory usage
    public func with(memoryUsage newMemoryUsage: Int64?) -> LoadedModelState {
        LoadedModelState(
            modelId: modelId,
            modelName: modelName,
            framework: framework,
            modality: modality,
            state: state,
            loadedAt: loadedAt,
            memoryUsage: newMemoryUsage,
            llmService: llmService,
            sttService: sttService,
            ttsService: ttsService
        )
    }

    // MARK: - Convenience Properties

    /// Check if the model is ready for use
    public var isReady: Bool {
        state.isLoaded
    }

    /// Get the duration since the model was loaded
    public var loadedDuration: TimeInterval? {
        guard let loadedAt = loadedAt else { return nil }
        return Date().timeIntervalSince(loadedAt)
    }

    /// Get a human-readable description of memory usage
    public var memoryUsageDescription: String? {
        guard let bytes = memoryUsage else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }

    /// Get the appropriate service for this model's modality
    public var service: Any? {
        switch modality {
        case .llm:
            return llmService
        case .stt:
            return sttService
        case .tts:
            return ttsService
        default:
            return nil
        }
    }
}
