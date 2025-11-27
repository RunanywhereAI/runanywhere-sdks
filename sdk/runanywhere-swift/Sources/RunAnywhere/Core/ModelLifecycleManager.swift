//
//  ModelLifecycleManager.swift
//  RunAnywhere
//
//  Unified model lifecycle tracking across all modalities (LLM, STT, TTS, VLM)
//

import Foundation
import Combine

// MARK: - Model Load State

/// Represents the current state of a model
public enum ModelLoadState: Equatable, Sendable {
    case notLoaded
    case loading(progress: Double)
    case loaded
    case unloading
    case error(String)

    public var isLoaded: Bool {
        if case .loaded = self { return true }
        return false
    }

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    public static func == (lhs: ModelLoadState, rhs: ModelLoadState) -> Bool {
        switch (lhs, rhs) {
        case (.notLoaded, .notLoaded): return true
        case (.loading(let p1), .loading(let p2)): return p1 == p2
        case (.loaded, .loaded): return true
        case (.unloading, .unloading): return true
        case (.error(let e1), .error(let e2)): return e1 == e2
        default: return false
        }
    }
}

// MARK: - Loaded Model Info

/// Information about a currently loaded model
public struct LoadedModelState: Sendable {
    public let modelId: String
    public let modelName: String
    public let framework: LLMFramework
    public let modality: Modality
    public let state: ModelLoadState
    public let loadedAt: Date?
    public let memoryUsage: Int64?

    public init(
        modelId: String,
        modelName: String,
        framework: LLMFramework,
        modality: Modality,
        state: ModelLoadState,
        loadedAt: Date? = nil,
        memoryUsage: Int64? = nil
    ) {
        self.modelId = modelId
        self.modelName = modelName
        self.framework = framework
        self.modality = modality
        self.state = state
        self.loadedAt = loadedAt
        self.memoryUsage = memoryUsage
    }
}

// MARK: - Modality

/// Supported modalities for model lifecycle tracking
public enum Modality: String, CaseIterable, Sendable {
    case llm = "llm"           // Large Language Models
    case stt = "stt"           // Speech-to-Text
    case tts = "tts"           // Text-to-Speech
    case vlm = "vlm"           // Vision-Language Models
    case speakerDiarization = "speaker_diarization"
    case wakeWord = "wake_word"

    public var displayName: String {
        switch self {
        case .llm: return "Language Model"
        case .stt: return "Speech Recognition"
        case .tts: return "Text to Speech"
        case .vlm: return "Vision Model"
        case .speakerDiarization: return "Speaker Diarization"
        case .wakeWord: return "Wake Word"
        }
    }
}

// MARK: - Model Lifecycle Events

/// Events published when model lifecycle changes
public enum ModelLifecycleEvent: Sendable {
    case willLoad(modelId: String, modality: Modality)
    case loadProgress(modelId: String, modality: Modality, progress: Double)
    case didLoad(modelId: String, modality: Modality, framework: LLMFramework)
    case willUnload(modelId: String, modality: Modality)
    case didUnload(modelId: String, modality: Modality)
    case loadFailed(modelId: String, modality: Modality, error: String)
}

// MARK: - Model Lifecycle Tracker

/// Centralized tracker for model lifecycle across all modalities
/// Thread-safe actor that provides real-time state updates
@MainActor
public final class ModelLifecycleTracker: ObservableObject {

    // MARK: - Singleton

    public static let shared = ModelLifecycleTracker()

    // MARK: - Published Properties

    /// Current state of all models, keyed by modality
    @Published public private(set) var modelsByModality: [Modality: LoadedModelState] = [:]

    /// Event publisher for lifecycle changes
    public let lifecycleEvents = PassthroughSubject<ModelLifecycleEvent, Never>()

    // MARK: - Private Properties

    private let logger = SDKLogger(category: "ModelLifecycleManager")

    // MARK: - Initialization

    private init() {
        logger.info("ModelLifecycleManager initialized")
    }

    // MARK: - Public API

    /// Get currently loaded model for a specific modality
    public func loadedModel(for modality: Modality) -> LoadedModelState? {
        return modelsByModality[modality]
    }

    /// Check if a model is loaded for a specific modality
    public func isModelLoaded(for modality: Modality) -> Bool {
        return modelsByModality[modality]?.state.isLoaded ?? false
    }

    /// Get all currently loaded models
    public func allLoadedModels() -> [LoadedModelState] {
        return modelsByModality.values.filter { $0.state.isLoaded }
    }

    /// Check if a specific model is loaded
    public func isModelLoaded(_ modelId: String) -> Bool {
        return modelsByModality.values.contains { $0.modelId == modelId && $0.state.isLoaded }
    }

    // MARK: - State Management (Internal)

    /// Called when a model starts loading
    public func modelWillLoad(
        modelId: String,
        modelName: String,
        framework: LLMFramework,
        modality: Modality
    ) {
        logger.info("Model will load: \(modelName) [\(modality.rawValue)]")

        let state = LoadedModelState(
            modelId: modelId,
            modelName: modelName,
            framework: framework,
            modality: modality,
            state: .loading(progress: 0)
        )

        modelsByModality[modality] = state
        lifecycleEvents.send(.willLoad(modelId: modelId, modality: modality))
    }

    /// Update loading progress
    public func updateLoadProgress(
        modelId: String,
        modality: Modality,
        progress: Double
    ) {
        guard var state = modelsByModality[modality], state.modelId == modelId else { return }

        modelsByModality[modality] = LoadedModelState(
            modelId: state.modelId,
            modelName: state.modelName,
            framework: state.framework,
            modality: state.modality,
            state: .loading(progress: progress),
            loadedAt: state.loadedAt,
            memoryUsage: state.memoryUsage
        )

        lifecycleEvents.send(.loadProgress(modelId: modelId, modality: modality, progress: progress))
    }

    /// Called when a model finishes loading successfully
    public func modelDidLoad(
        modelId: String,
        modelName: String,
        framework: LLMFramework,
        modality: Modality,
        memoryUsage: Int64? = nil
    ) {
        logger.info("Model loaded: \(modelName) [\(modality.rawValue)] with \(framework.rawValue)")

        let state = LoadedModelState(
            modelId: modelId,
            modelName: modelName,
            framework: framework,
            modality: modality,
            state: .loaded,
            loadedAt: Date(),
            memoryUsage: memoryUsage
        )

        modelsByModality[modality] = state
        lifecycleEvents.send(.didLoad(modelId: modelId, modality: modality, framework: framework))
    }

    /// Called when a model fails to load
    public func modelLoadFailed(
        modelId: String,
        modality: Modality,
        error: String
    ) {
        logger.error("Model load failed: \(modelId) [\(modality.rawValue)] - \(error)")

        // Keep the previous state but update to error
        if var state = modelsByModality[modality] {
            modelsByModality[modality] = LoadedModelState(
                modelId: state.modelId,
                modelName: state.modelName,
                framework: state.framework,
                modality: state.modality,
                state: .error(error),
                loadedAt: nil,
                memoryUsage: nil
            )
        }

        lifecycleEvents.send(.loadFailed(modelId: modelId, modality: modality, error: error))
    }

    /// Called when a model starts unloading
    public func modelWillUnload(modelId: String, modality: Modality) {
        logger.info("Model will unload: \(modelId) [\(modality.rawValue)]")

        if var state = modelsByModality[modality], state.modelId == modelId {
            modelsByModality[modality] = LoadedModelState(
                modelId: state.modelId,
                modelName: state.modelName,
                framework: state.framework,
                modality: state.modality,
                state: .unloading,
                loadedAt: state.loadedAt,
                memoryUsage: state.memoryUsage
            )
        }

        lifecycleEvents.send(.willUnload(modelId: modelId, modality: modality))
    }

    /// Called when a model finishes unloading
    public func modelDidUnload(modelId: String, modality: Modality) {
        logger.info("Model unloaded: \(modelId) [\(modality.rawValue)]")

        modelsByModality.removeValue(forKey: modality)
        lifecycleEvents.send(.didUnload(modelId: modelId, modality: modality))
    }

    /// Clear all loaded models (for cleanup)
    public func clearAll() {
        logger.info("Clearing all loaded models")
        modelsByModality.removeAll()
    }
}
