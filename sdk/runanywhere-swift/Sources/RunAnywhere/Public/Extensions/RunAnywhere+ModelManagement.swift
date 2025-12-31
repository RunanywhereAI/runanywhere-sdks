import Foundation

// MARK: - Model Management

extension RunAnywhere {

    /// Load an LLM model by ID
    /// - Parameter modelId: The model identifier
    public static func loadModel(_ modelId: String) async throws {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        try await ensureServicesReady()

        // Resolve model ID to local file path
        let allModels = try await availableModels()
        guard let modelInfo = allModels.first(where: { $0.id == modelId }) else {
            throw SDKError.llm(.modelNotFound, "Model '\(modelId)' not found in registry")
        }
        guard let localPath = modelInfo.localPath else {
            throw SDKError.llm(.modelNotFound, "Model '\(modelId)' is not downloaded")
        }

        try await CapabilityManager.shared.loadLLMModel(localPath.path, modelId: modelId)
    }

    /// Unload the currently loaded LLM model
    public static func unloadModel() async throws {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        await CapabilityManager.shared.unloadLLM()
    }

    /// Check if an LLM model is loaded
    public static var isModelLoaded: Bool {
        get async {
            await CapabilityManager.shared.isLLMLoaded
        }
    }

    /// Check if the currently loaded LLM model supports streaming generation
    ///
    /// Some models (like Apple Foundation Models) don't support streaming and require
    /// non-streaming generation via `generate()` instead of `generateStream()`.
    ///
    /// - Returns: `true` if streaming is supported, `false` if you should use `generate()` instead
    /// - Note: Returns `false` if no model is loaded
    public static var supportsLLMStreaming: Bool {
        get async {
            true  // C++ layer supports streaming
        }
    }

    /// Load an STT (Speech-to-Text) model by ID
    /// This loads the model into the STT component
    /// - Parameter modelId: The model identifier (e.g., "whisper-base")
    public static func loadSTTModel(_ modelId: String) async throws {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        try await ensureServicesReady()

        // Resolve model ID to local file path
        let allModels = try await availableModels()
        guard let modelInfo = allModels.first(where: { $0.id == modelId }) else {
            throw SDKError.stt(.modelNotFound, "Model '\(modelId)' not found in registry")
        }
        guard let localPath = modelInfo.localPath else {
            throw SDKError.stt(.modelNotFound, "Model '\(modelId)' is not downloaded")
        }

        try await CapabilityManager.shared.loadSTTModel(localPath.path, modelId: modelId)
    }

    /// Load a TTS (Text-to-Speech) voice by ID
    /// This loads the voice into the TTS component
    /// - Parameter voiceId: The voice identifier
    public static func loadTTSModel(_ voiceId: String) async throws {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        try await ensureServicesReady()

        // Resolve voice ID to local file path
        let allModels = try await availableModels()
        guard let modelInfo = allModels.first(where: { $0.id == voiceId }) else {
            throw SDKError.tts(.modelNotFound, "Voice '\(voiceId)' not found in registry")
        }
        guard let localPath = modelInfo.localPath else {
            throw SDKError.tts(.modelNotFound, "Voice '\(voiceId)' is not downloaded")
        }

        try await CapabilityManager.shared.loadTTSVoice(localPath.path, voiceId: voiceId)
    }

    /// Get available models
    /// - Returns: Array of available models
    public static func availableModels() async throws -> [ModelInfo] {
        guard isInitialized else { throw SDKError.general(.notInitialized, "SDK not initialized") }
        return await serviceContainer.modelRegistry.discoverModels()
    }

    /// Get currently loaded LLM model ID
    /// - Returns: Currently loaded model ID if any
    public static func getCurrentModelId() async -> String? {
        guard isInitialized else { return nil }
        return await CapabilityManager.shared.currentLLMModelId
    }

    /// Get the currently loaded LLM model as ModelInfo
    ///
    /// This is a convenience property that combines `getCurrentModelId()` with
    /// a lookup in the available models registry.
    ///
    /// - Returns: The currently loaded ModelInfo, or nil if no model is loaded
    public static var currentLLMModel: ModelInfo? {
        get async {
            guard let modelId = await getCurrentModelId() else { return nil }
            let models = (try? await availableModels()) ?? []
            return models.first { $0.id == modelId }
        }
    }

    /// Get the currently loaded STT model as ModelInfo
    ///
    /// - Returns: The currently loaded STT ModelInfo, or nil if no STT model is loaded
    public static var currentSTTModel: ModelInfo? {
        get async {
            guard isInitialized else { return nil }
            guard let modelId = await CapabilityManager.shared.currentSTTModelId else { return nil }
            let models = (try? await availableModels()) ?? []
            return models.first { $0.id == modelId }
        }
    }

    /// Get the currently loaded TTS voice ID
    ///
    /// Note: TTS uses voices (not models), so this returns the voice identifier string.
    /// - Returns: The TTS voice ID if one is loaded, nil otherwise
    public static var currentTTSVoiceId: String? {
        get async {
            guard isInitialized else { return nil }
            return await CapabilityManager.shared.currentTTSVoiceId
        }
    }

    /// Cancel the current text generation
    ///
    /// Use this to stop an ongoing generation when the user navigates away
    /// or explicitly requests cancellation.
    public static func cancelGeneration() async {
        guard isInitialized else { return }
        await CapabilityManager.shared.cancelLLM()
    }
}
