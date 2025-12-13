//
//  ModelLifecycleTracker.swift
//  RunAnywhere SDK
//
//  Centralized tracker for model lifecycle state across all modalities
//

import Combine
import Foundation

/// Centralized tracker for model lifecycle across all modalities
/// Thread-safe @MainActor class that provides real-time state updates
@MainActor
public final class ModelLifecycleTracker: ObservableObject {

    // MARK: - Singleton

    /// Shared singleton instance for convenient access
    public static let shared = ModelLifecycleTracker()

    // MARK: - Published Properties

    /// Current state of non-LLM models (STT, TTS) keyed by modality
    /// LLM state is queried from ModelLoadingService
    @Published public private(set) var modelsByModality: [Modality: LoadedModelState] = [:]

    /// Event publisher for lifecycle changes
    public let lifecycleEvents = PassthroughSubject<ModelLifecycleEvent, Never>()

    // MARK: - Private Properties

    private let logger = SDKLogger(category: "ModelLifecycleTracker")

    // Reference to ModelLoadingService for querying LLM state
    private var modelLoadingService: ModelLoadingService {
        ServiceContainer.shared.modelLoadingService
    }

    // MARK: - Initialization

    private init() {
        logger.info("ModelLifecycleTracker initialized")
    }

    // MARK: - Public Query API

    /// Get currently loaded model for a specific modality
    /// - Parameter modality: The modality to query
    /// - Returns: The loaded model state, or nil if no model is loaded
    public func loadedModel(for modality: Modality) -> LoadedModelState? {
        // For LLM modality, return the cached state (still needed for UI updates)
        // The actual service is queried from ModelLoadingService
        return modelsByModality[modality]
    }

    /// Check if a model is loaded for a specific modality
    /// - Parameter modality: The modality to check
    /// - Returns: True if a model is currently loaded
    public func isModelLoaded(for modality: Modality) -> Bool {
        return modelsByModality[modality]?.state.isLoaded ?? false
    }

    /// Get all currently loaded models
    /// - Returns: Array of all loaded model states
    public func allLoadedModels() -> [LoadedModelState] {
        return modelsByModality.values.filter { $0.state.isLoaded }
    }

    /// Check if a specific model is loaded (by ID)
    /// - Parameter modelId: The model identifier
    /// - Returns: True if the model is loaded
    public func isModelLoaded(_ modelId: String) -> Bool {
        return modelsByModality.values.contains { $0.modelId == modelId && $0.state.isLoaded }
    }

    /// Get the modality for a loaded model
    /// - Parameter modelId: The model identifier
    /// - Returns: The modality if the model is loaded
    public func modality(for modelId: String) -> Modality? {
        for (modality, state) in modelsByModality where state.modelId == modelId {
            return modality
        }
        return nil
    }

    // MARK: - State Management (Loading)

    /// Called when a model starts loading
    /// - Parameters:
    ///   - modelId: The model identifier
    ///   - modelName: Human-readable model name
    ///   - framework: The framework being used
    ///   - modality: The modality for this model
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
    /// - Parameters:
    ///   - modelId: The model identifier
    ///   - modality: The modality
    ///   - progress: Progress value (0.0 to 1.0)
    public func updateLoadProgress(
        modelId: String,
        modality: Modality,
        progress: Double
    ) {
        guard let state = modelsByModality[modality], state.modelId == modelId else { return }

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
    /// - Parameters:
    ///   - modelId: The model identifier
    ///   - modelName: Human-readable model name
    ///   - framework: The framework used
    ///   - modality: The modality
    ///   - memoryUsage: Optional memory usage in bytes
    ///   - llmService: Optional LLM service (ignored - queried from ModelLoadingService)
    ///   - sttService: Optional STT service to cache
    ///   - ttsService: Optional TTS service to cache
    public func modelDidLoad(
        modelId: String,
        modelName: String,
        framework: LLMFramework,
        modality: Modality,
        memoryUsage: Int64? = nil,
        llmService: (any LLMService)? = nil,
        sttService: (any STTService)? = nil,
        ttsService: (any TTSService)? = nil
    ) {
        logger.info("Model loaded: \(modelName) [\(modality.rawValue)] with \(framework.rawValue)")

        // For LLM modality, don't cache the service - it's queried from ModelLoadingService
        // For STT/TTS, cache the service since they're not managed by ModelLoadingService
        let state = LoadedModelState(
            modelId: modelId,
            modelName: modelName,
            framework: framework,
            modality: modality,
            state: .loaded,
            loadedAt: Date(),
            memoryUsage: memoryUsage,
            llmService: nil,  // Always nil - query from ModelLoadingService instead
            sttService: sttService,
            ttsService: ttsService
        )

        modelsByModality[modality] = state
        lifecycleEvents.send(.didLoad(modelId: modelId, modality: modality, framework: framework))
    }

    /// Called when a model fails to load
    /// - Parameters:
    ///   - modelId: The model identifier
    ///   - modality: The modality
    ///   - error: Error message
    public func modelLoadFailed(
        modelId: String,
        modality: Modality,
        error: String
    ) {
        logger.error("Model load failed: \(modelId) [\(modality.rawValue)] - \(error)")

        // Keep the previous state but update to error
        if let state = modelsByModality[modality] {
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

    // MARK: - State Management (Unloading)

    /// Called when a model starts unloading
    /// - Parameters:
    ///   - modelId: The model identifier
    ///   - modality: The modality
    public func modelWillUnload(modelId: String, modality: Modality) {
        logger.info("Model will unload: \(modelId) [\(modality.rawValue)]")

        if let state = modelsByModality[modality], state.modelId == modelId {
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
    /// - Parameters:
    ///   - modelId: The model identifier
    ///   - modality: The modality
    public func modelDidUnload(modelId: String, modality: Modality) {
        logger.info("Model unloaded: \(modelId) [\(modality.rawValue)]")

        modelsByModality.removeValue(forKey: modality)
        lifecycleEvents.send(.didUnload(modelId: modelId, modality: modality))
    }

    // MARK: - Service Access

    /// Get LLM service for a model ID
    /// Queries ModelLoadingService as the single source of truth
    /// - Parameter modelId: The model identifier
    /// - Returns: The LLM service if available and loaded
    public func llmService(for modelId: String) async -> (any LLMService)? {
        // Query ModelLoadingService for the actual loaded model
        guard let loadedModel = await modelLoadingService.getLoadedModel(modelId) else {
            return nil
        }

        logger.info("Found LLM service for model: \(modelId) from ModelLoadingService")
        return loadedModel.service
    }

    /// Get cached STT service for a model ID
    /// - Parameter modelId: The model identifier
    /// - Returns: The STT service if available and cached
    public func sttService(for modelId: String) -> (any STTService)? {
        guard let state = modelsByModality[.stt],
              state.modelId == modelId,
              state.state.isLoaded else {
            return nil
        }
        if state.sttService != nil {
            logger.info("Found cached STT service for model: \(modelId)")
        }
        return state.sttService
    }

    /// Get cached TTS service for a model ID
    /// - Parameter modelId: The model identifier
    /// - Returns: The TTS service if available and cached
    public func ttsService(for modelId: String) -> (any TTSService)? {
        guard let state = modelsByModality[.tts],
              state.modelId == modelId,
              state.state.isLoaded else {
            return nil
        }
        if state.ttsService != nil {
            logger.info("Found cached TTS service for model: \(modelId)")
        }
        return state.ttsService
    }

    // MARK: - Memory Management

    /// Update memory usage for a model
    /// - Parameters:
    ///   - modelId: The model identifier
    ///   - bytes: Memory usage in bytes
    public func updateMemoryUsage(modelId: String, bytes: Int64) {
        for (modality, state) in modelsByModality where state.modelId == modelId {
            modelsByModality[modality] = state.with(memoryUsage: bytes)
            lifecycleEvents.send(.memoryUsageUpdated(modelId: modelId, bytes: bytes))
            return
        }
    }

    /// Get total memory usage across all loaded models
    /// - Returns: Total memory in bytes
    public func totalMemoryUsage() -> Int64 {
        return modelsByModality.values.compactMap { $0.memoryUsage }.reduce(0, +)
    }

    // MARK: - Cleanup

    /// Clear all loaded models (for cleanup)
    public func clearAll() {
        logger.info("Clearing all loaded models")
        modelsByModality.removeAll()
    }
}
