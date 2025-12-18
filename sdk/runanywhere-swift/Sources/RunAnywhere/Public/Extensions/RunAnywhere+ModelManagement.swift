import Foundation

// MARK: - Model Management

extension RunAnywhere {

    /// Load an LLM model by ID
    /// - Parameter modelId: The model identifier
    /// - Note: Events are automatically dispatched to both EventBus (for apps) and Analytics (for telemetry)
    public static func loadModel(_ modelId: String) async throws {
        // Ensure initialized
        guard isInitialized else {
            throw RunAnywhereError.notInitialized
        }

        // Ensure services are ready (O(1) after first call)
        try await ensureServicesReady()

        // LLMCapability handles all event tracking automatically
        try await serviceContainer.llmCapability.loadModel(modelId)
    }

    /// Unload the currently loaded LLM model
    /// - Note: Events are automatically dispatched to both EventBus and Analytics
    public static func unloadModel() async throws {
        guard isInitialized else {
            throw RunAnywhereError.notInitialized
        }

        // LLMCapability handles all event tracking automatically
        try await serviceContainer.llmCapability.unload()
    }

    /// Check if an LLM model is loaded
    public static var isModelLoaded: Bool {
        get async {
            await serviceContainer.llmCapability.isModelLoaded
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
            await serviceContainer.llmCapability.supportsStreaming
        }
    }

    /// Load an STT (Speech-to-Text) model by ID
    /// This loads the model into the STT capability
    /// - Parameter modelId: The model identifier (e.g., "whisper-base")
    /// - Note: Events are automatically dispatched to both EventBus and Analytics
    public static func loadSTTModel(_ modelId: String) async throws {
        // Ensure initialized
        guard isInitialized else {
            throw RunAnywhereError.notInitialized
        }

        // Ensure services are ready (O(1) after first call)
        try await ensureServicesReady()

        // STTCapability handles all event tracking automatically
        try await serviceContainer.sttCapability.loadModel(modelId)
    }

    /// Load a TTS (Text-to-Speech) voice by ID
    /// This loads the voice into the TTS capability
    /// - Parameter voiceId: The voice identifier
    /// - Note: Events are automatically dispatched to both EventBus and Analytics
    public static func loadTTSModel(_ voiceId: String) async throws {
        // Ensure initialized
        guard isInitialized else {
            throw RunAnywhereError.notInitialized
        }

        // Ensure services are ready (O(1) after first call)
        try await ensureServicesReady()

        // TTSCapability handles all event tracking automatically
        try await serviceContainer.ttsCapability.loadVoice(voiceId)
    }

    /// Get available models
    /// - Returns: Array of available models
    public static func availableModels() async throws -> [ModelInfo] {
        guard isInitialized else { throw RunAnywhereError.notInitialized }
        return await serviceContainer.modelRegistry.discoverModels()
    }

    /// Get currently loaded LLM model ID
    /// - Returns: Currently loaded model ID if any
    public static func getCurrentModelId() async -> String? {
        guard isInitialized else { return nil }
        return await serviceContainer.llmCapability.currentModelId
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
            guard let modelId = await serviceContainer.sttCapability.currentModelId else { return nil }
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
            return await serviceContainer.ttsCapability.currentVoiceId
        }
    }

    /// Cancel the current text generation
    ///
    /// Use this to stop an ongoing generation when the user navigates away
    /// or explicitly requests cancellation.
    public static func cancelGeneration() async {
        guard isInitialized else { return }
        await serviceContainer.llmCapability.cancel()
    }
}
