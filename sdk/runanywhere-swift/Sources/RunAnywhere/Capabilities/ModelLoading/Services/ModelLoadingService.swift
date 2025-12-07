import Foundation

/// Service responsible for loading models
/// Actor ensures thread-safe access and prevents concurrent duplicate loads
public actor ModelLoadingService {
    private let registry: ModelRegistry
    private let adapterRegistry: AdapterRegistry
    private let logger = SDKLogger(category: "ModelLoadingService")

    private var loadedModels: [String: LoadedModel] = [:]
    /// Track in-flight loading tasks to prevent duplicate concurrent loads
    private var inflightLoads: [String: Task<LoadedModel, Error>] = [:]

    public init(
        registry: ModelRegistry,
        adapterRegistry: AdapterRegistry
    ) {
        self.registry = registry
        self.adapterRegistry = adapterRegistry
    }

    /// Load a model by identifier
    /// Concurrent calls for the same model will be deduplicated
    public func loadModel(_ modelId: String) async throws -> LoadedModel {
        logger.info("🚀 Loading model: \(modelId)")

        // Check if already loaded
        if let loaded = loadedModels[modelId] {
            logger.info("✅ Model already loaded: \(modelId)")
            return loaded
        }

        // Check if a load is already in progress
        if let existingTask = inflightLoads[modelId] {
            logger.info("⏳ Model load already in progress, awaiting existing task: \(modelId)")
            return try await existingTask.value
        }

        // Create a new loading task
        let loadTask = Task<LoadedModel, Error> { [weak self] in
            guard let self = self else {
                throw SDKError.invalidState("ModelLoadingService deallocated during load")
            }
            return try await self.performLoad(modelId: modelId)
        }

        // Store the task to prevent duplicate loads
        inflightLoads[modelId] = loadTask

        // Ensure task is removed when complete (success or failure)
        defer {
            Task { [weak self] in
                await self?.cleanupInflightTask(modelId: modelId)
            }
        }

        return try await loadTask.value
    }

    /// Cleanup in-flight task after completion
    private func cleanupInflightTask(modelId: String) {
        inflightLoads.removeValue(forKey: modelId)
    }

    /// Perform the actual model loading
    private func performLoad(modelId: String) async throws -> LoadedModel {
        // Double-check if loaded while we were waiting
        if let loaded = loadedModels[modelId] {
            logger.info("✅ Model loaded by another task: \(modelId)")
            return loaded
        }

        // Get model info from registry
        guard let modelInfo = registry.getModel(by: modelId) else {
            logger.error("❌ Model not found in registry: \(modelId)")
            throw SDKError.modelNotFound(modelId)
        }

        logger.info("✅ Found model in registry: \(modelInfo.name)")

        // Check if this is a built-in model (e.g., Foundation Models)
        let isBuiltIn = modelInfo.localPath?.scheme == "builtin"

        if !isBuiltIn {
            // Check model file exists for non-built-in models
            guard modelInfo.localPath != nil else {
                throw SDKError.modelNotFound("Model '\(modelId)' not downloaded")
            }
        } else {
            logger.info("🏗️ Built-in model detected, skipping file check")
        }

        // ModelLoadingService handles LLM models only
        // STT models are loaded through STTComponent → ModuleRegistry → STT providers
        if modelInfo.category == .speechRecognition || modelInfo.preferredFramework == .whisperKit {
            logger.error("❌ Cannot load STT model through ModelLoadingService")
            throw SDKError.loadingFailed(
                "Model '\(modelId)' is a speech recognition model. STT models are loaded automatically through STTComponent."
            )
        }

        // ModelLoadingService handles LLMs only; constrain to text-to-text modality
        let modality: FrameworkModality = .textToText

        // Find all adapters that can handle this model
        logger.info("🚀 Finding adapters for model (modality: \(modality))")
        let adapters = await adapterRegistry.findAllAdapters(for: modelInfo, modality: modality)

        guard !adapters.isEmpty else {
            logger.error("❌ No adapter found for model with preferred framework: \(modelInfo.preferredFramework?.rawValue ?? "none")")
            logger.error("❌ Compatible frameworks: \(modelInfo.compatibleFrameworks.map { $0.rawValue })")
            throw SDKError.frameworkNotAvailable(
                modelInfo.preferredFramework ?? .coreML
            )
        }

        logger.info("✅ Found \(adapters.count) adapter(s) capable of loading this model")

        // Try to load with each adapter (primary + fallbacks)
        var lastError: Error?
        for (index, adapter) in adapters.enumerated() {
            let isPrimary = index == 0
            logger.info(isPrimary ? "🚀 Trying primary adapter: \(adapter.framework.rawValue)" : "🔄 Trying fallback adapter: \(adapter.framework.rawValue)")

            do {
                let service = try await adapter.loadModel(modelInfo, for: modality)
                logger.info("✅ Model loaded successfully with \(adapter.framework.rawValue)")

                // Cast to LLMService (by construction: text-to-text modality)
                guard let llmService = service as? LLMService else {
                    throw SDKError.loadingFailed(
                        "Adapter '\(adapter.framework.rawValue)' did not return an LLMService for text-to-text modality"
                    )
                }

                // Create loaded model
                let loaded = LoadedModel(model: modelInfo, service: llmService)
                loadedModels[modelId] = loaded

                return loaded
            } catch {
                logger.error("❌ Failed to load model with \(adapter.framework.rawValue): \(error.localizedDescription)")
                lastError = error
                // Continue to next adapter
            }
        }

        // All adapters failed
        logger.error("❌ All adapters failed to load model")
        throw lastError ?? SDKError.loadingFailed("Failed to load model with any available adapter")
    }

    /// Unload a model
    public func unloadModel(_ modelId: String) async throws {
        guard let loaded = loadedModels[modelId] else {
            return
        }

        // Unload through service
        await loaded.service.cleanup()

        // Remove from loaded models
        loadedModels.removeValue(forKey: modelId)
    }

    /// Get currently loaded model
    public func getLoadedModel(_ modelId: String) -> LoadedModel? {
        return loadedModels[modelId]
    }
}
