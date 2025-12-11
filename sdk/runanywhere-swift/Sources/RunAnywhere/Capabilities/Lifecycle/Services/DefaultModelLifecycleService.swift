//
//  DefaultModelLifecycleService.swift
//  RunAnywhere SDK
//
//  Default implementation of the ModelLifecycleService protocol
//

import Combine
import Foundation

/// Default implementation of ModelLifecycleService
/// Coordinates between ModelLoadingService and ModelLifecycleTracker
public actor DefaultModelLifecycleService: ModelLifecycleService {

    // MARK: - Properties

    private let configuration: LifecycleConfiguration
    private let loadingService: ModelLoadingService
    private let registry: ModelRegistry
    private let adapterRegistry: AdapterRegistry
    private let logger = SDKLogger(category: "DefaultModelLifecycleService")

    // PassthroughSubject is thread-safe, so nonisolated(unsafe) is appropriate here
    private nonisolated(unsafe) let _lifecycleEvents = PassthroughSubject<ModelLifecycleEvent, Never>()

    // MARK: - Initialization

    public init(
        configuration: LifecycleConfiguration = .default,
        registry: ModelRegistry,
        adapterRegistry: AdapterRegistry
    ) {
        self.configuration = configuration
        self.registry = registry
        self.adapterRegistry = adapterRegistry
        self.loadingService = ModelLoadingService(
            registry: registry,
            adapterRegistry: adapterRegistry
        )
    }

    // MARK: - ModelLifecycleService - Loading

    public func loadModel(
        _ modelId: String,
        modality: Modality,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> LoadedModel {
        logger.info("Loading model: \(modelId) for modality: \(modality.rawValue)")

        // Get model info for tracking
        guard let modelInfo = registry.getModel(by: modelId) else {
            throw LifecycleError.modelNotFound(modelId: modelId)
        }

        let framework = modelInfo.preferredFramework ?? .llamaCpp

        // Notify tracker (on main actor)
        await MainActor.run {
            ModelLifecycleTracker.shared.modelWillLoad(
                modelId: modelId,
                modelName: modelInfo.name,
                framework: framework,
                modality: modality
            )
        }

        _lifecycleEvents.send(.willLoad(modelId: modelId, modality: modality))

        do {
            // Perform the actual load
            let loadedModel = try await loadingService.loadModel(modelId, onProgress: onProgress)

            // Notify tracker of success
            await MainActor.run {
                ModelLifecycleTracker.shared.modelDidLoad(
                    modelId: modelId,
                    modelName: modelInfo.name,
                    framework: framework,
                    modality: modality,
                    memoryUsage: modelInfo.memoryRequired,
                    llmService: loadedModel.service
                )
            }

            _lifecycleEvents.send(.didLoad(modelId: modelId, modality: modality, framework: framework))

            logger.info("Model loaded successfully: \(modelId)")
            return loadedModel

        } catch {
            // Notify tracker of failure
            await MainActor.run {
                ModelLifecycleTracker.shared.modelLoadFailed(
                    modelId: modelId,
                    modality: modality,
                    error: error.localizedDescription
                )
            }

            _lifecycleEvents.send(.loadFailed(modelId: modelId, modality: modality, error: error.localizedDescription))

            logger.error("Failed to load model: \(modelId) - \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - ModelLifecycleService - Unloading

    public func unloadModel(_ modelId: String) async throws {
        logger.info("Unloading model: \(modelId)")

        // Find the modality for this model
        let modality = await MainActor.run {
            ModelLifecycleTracker.shared.modality(for: modelId)
        }

        if let modality = modality {
            await MainActor.run {
                ModelLifecycleTracker.shared.modelWillUnload(modelId: modelId, modality: modality)
            }
            _lifecycleEvents.send(.willUnload(modelId: modelId, modality: modality))
        }

        try await loadingService.unloadModel(modelId)

        if let modality = modality {
            await MainActor.run {
                ModelLifecycleTracker.shared.modelDidUnload(modelId: modelId, modality: modality)
            }
            _lifecycleEvents.send(.didUnload(modelId: modelId, modality: modality))
        }

        logger.info("Model unloaded: \(modelId)")
    }

    public func unloadModels(for modality: Modality) async throws {
        logger.info("Unloading all models for modality: \(modality.rawValue)")

        let state = await MainActor.run {
            ModelLifecycleTracker.shared.loadedModel(for: modality)
        }

        if let state = state {
            try await unloadModel(state.modelId)
        }
    }

    public func unloadAllModels() async throws {
        logger.info("Unloading all models")

        try await loadingService.unloadAllModels()

        await MainActor.run {
            ModelLifecycleTracker.shared.clearAll()
        }
    }

    // MARK: - ModelLifecycleService - Query

    public func getLoadedModel(_ modelId: String) async -> LoadedModel? {
        return await loadingService.getLoadedModel(modelId)
    }

    public func getLoadedModel(for modality: Modality) async -> LoadedModelState? {
        return await MainActor.run {
            ModelLifecycleTracker.shared.loadedModel(for: modality)
        }
    }

    public func isModelLoaded(_ modelId: String) async -> Bool {
        return await loadingService.isModelLoaded(modelId)
    }

    public func isModelLoaded(for modality: Modality) async -> Bool {
        return await MainActor.run {
            ModelLifecycleTracker.shared.isModelLoaded(for: modality)
        }
    }

    public func getAllLoadedModels() async -> [LoadedModelState] {
        return await MainActor.run {
            ModelLifecycleTracker.shared.allLoadedModels()
        }
    }

    // MARK: - ModelLifecycleService - Service Access

    public func getLLMService(for modelId: String) async -> (any LLMService)? {
        // First check the tracker cache
        let cached = await MainActor.run {
            ModelLifecycleTracker.shared.llmService(for: modelId)
        }
        if let cached = cached {
            return cached
        }

        // Fall back to loaded model
        if let loaded = await loadingService.getLoadedModel(modelId) {
            return loaded.service
        }

        return nil
    }

    public func getSTTService(for modelId: String) async -> (any STTService)? {
        return await MainActor.run {
            ModelLifecycleTracker.shared.sttService(for: modelId)
        }
    }

    public func getTTSService(for modelId: String) async -> (any TTSService)? {
        return await MainActor.run {
            ModelLifecycleTracker.shared.ttsService(for: modelId)
        }
    }

    // MARK: - ModelLifecycleService - Lifecycle Events

    public nonisolated var lifecycleEvents: AnyPublisher<ModelLifecycleEvent, Never> {
        _lifecycleEvents.eraseToAnyPublisher()
    }

    // MARK: - ModelLifecycleService - Memory Management

    public func estimateMemoryUsage(for modelId: String) async -> Int64 {
        guard let modelInfo = registry.getModel(by: modelId) else {
            return 0
        }
        return modelInfo.memoryRequired ?? 0
    }

    public func getTotalMemoryUsage() async -> Int64 {
        return await MainActor.run {
            ModelLifecycleTracker.shared.totalMemoryUsage()
        }
    }

    public func handleMemoryPressure() async {
        logger.warning("Memory pressure detected")

        let available = ProcessInfo.processInfo.physicalMemory
        _lifecycleEvents.send(.memoryPressure(availableBytes: Int64(available)))

        // If auto-unload is enabled, unload least recently used models
        if configuration.autoUnloadOnMemoryPressure {
            let totalUsage = await getTotalMemoryUsage()
            if totalUsage > configuration.memoryPressureThreshold && configuration.memoryPressureThreshold > 0 {
                logger.info("Auto-unloading models due to memory pressure")
                // Unload oldest loaded model
                let models = await getAllLoadedModels()
                if let oldest = models.sorted(by: { ($0.loadedAt ?? Date.distantPast) < ($1.loadedAt ?? Date.distantPast) }).first {
                    try? await unloadModel(oldest.modelId)
                }
            }
        }
    }

    // MARK: - ModelLifecycleService - Cleanup

    public func cleanup() async {
        logger.info("Cleaning up ModelLifecycleService")
        try? await unloadAllModels()
    }
}
