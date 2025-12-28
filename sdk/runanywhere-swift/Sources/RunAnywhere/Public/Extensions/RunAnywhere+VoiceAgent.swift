//
//  RunAnywhere+VoiceAgent.swift
//  RunAnywhere SDK
//
//  Public API for Voice Agent operations (full voice pipeline).
//  Events are tracked via EventPublisher.
//

import Foundation

// MARK: - Voice Agent Operations

public extension RunAnywhere {

    // MARK: - Component State Management

    /// Get the current state of all voice agent components (STT, LLM, TTS)
    ///
    /// Use this to check which models are loaded and ready for the voice pipeline.
    /// This is useful for UI that needs to show the setup state before starting voice.
    ///
    /// Example:
    /// ```swift
    /// let states = await RunAnywhere.getVoiceAgentComponentStates()
    /// if states.isFullyReady {
    ///     // All models loaded, can start voice assistant
    /// } else {
    ///     // Show which components are missing: states.missingComponents
    /// }
    /// ```
    static func getVoiceAgentComponentStates() async -> VoiceAgentComponentStates {
        guard isSDKInitialized else {
            return VoiceAgentComponentStates()
        }

        // Query each capability for its current state
        async let sttLoaded = serviceContainer.sttCapability.isModelLoaded
        async let sttModelId = serviceContainer.sttCapability.currentModelId
        async let llmLoaded = serviceContainer.llmCapability.isModelLoaded
        async let llmModelId = serviceContainer.llmCapability.currentModelId
        async let ttsLoaded = serviceContainer.ttsCapability.isVoiceLoaded
        async let ttsVoiceId = serviceContainer.ttsCapability.currentVoiceId

        let (sttIsLoaded, sttId, llmIsLoaded, llmId, ttsIsLoaded, ttsId) =
            await (sttLoaded, sttModelId, llmLoaded, llmModelId, ttsLoaded, ttsVoiceId)

        let sttState: ComponentLoadState
        if sttIsLoaded, let modelId = sttId {
            sttState = .loaded(modelId: modelId)
        } else {
            sttState = .notLoaded
        }

        let llmState: ComponentLoadState
        if llmIsLoaded, let modelId = llmId {
            llmState = .loaded(modelId: modelId)
        } else {
            llmState = .notLoaded
        }

        let ttsState: ComponentLoadState
        if ttsIsLoaded, let modelId = ttsId {
            ttsState = .loaded(modelId: modelId)
        } else {
            ttsState = .notLoaded
        }

        return VoiceAgentComponentStates(stt: sttState, llm: llmState, tts: ttsState)
    }

    /// Check if all voice agent components are loaded and ready
    ///
    /// Convenience method that returns true only when STT, LLM, and TTS are all loaded.
    static var areAllVoiceComponentsReady: Bool {
        get async {
            let states = await getVoiceAgentComponentStates()
            return states.isFullyReady
        }
    }

    // MARK: - Initialization

    /// Initialize the voice agent with configuration
    static func initializeVoiceAgent(_ config: VoiceAgentConfiguration) async throws {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        try await ensureServicesReady()

        EventPublisher.shared.track(VoicePipelineEvent.pipelineStarted)

        do {
            try await serviceContainer.voiceAgentCapability.initialize(config)
            EventPublisher.shared.track(VoicePipelineEvent.pipelineCompleted(durationMs: 0))
        } catch {
            EventPublisher.shared.track(VoicePipelineEvent.pipelineFailed(error: SDKError.from(error, category: .voiceAgent)))
            throw error
        }
    }

    /// Initialize voice agent using already-loaded models
    ///
    /// Use this when you've already loaded STT, LLM, and TTS models via the individual APIs:
    /// - `RunAnywhere.loadSTTModel(_:)`
    /// - `RunAnywhere.loadModel(_:)` (for LLM)
    /// - `RunAnywhere.loadTTSVoice(_:)`
    ///
    /// This will verify all components are loaded and mark the voice agent as ready.
    ///
    /// Example:
    /// ```swift
    /// // Load models individually (maybe from different views)
    /// try await RunAnywhere.loadSTTModel("sherpa-onnx-whisper-tiny.en")
    /// try await RunAnywhere.loadModel("lfm2-350m-q4_k_m")
    /// try await RunAnywhere.loadTTSVoice("vits-piper-en_GB-alba-medium")
    ///
    /// // Then initialize voice agent with those pre-loaded models
    /// try await RunAnywhere.initializeVoiceAgentWithLoadedModels()
    /// ```
    static func initializeVoiceAgentWithLoadedModels() async throws {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        try await ensureServicesReady()

        EventPublisher.shared.track(VoicePipelineEvent.pipelineStarted)

        do {
            try await serviceContainer.voiceAgentCapability.initializeWithLoadedModels()
            EventPublisher.shared.track(VoicePipelineEvent.pipelineCompleted(durationMs: 0))
        } catch {
            EventPublisher.shared.track(VoicePipelineEvent.pipelineFailed(error: SDKError.from(error, category: .voiceAgent)))
            throw error
        }
    }

    /// Check if voice agent is ready (all components initialized via initializeVoiceAgent)
    static var isVoiceAgentReady: Bool {
        get async {
            await serviceContainer.voiceAgentCapability.isReady
        }
    }

    // MARK: - Voice Processing

    /// Process a complete voice turn: audio → transcription → LLM response → synthesized speech
    static func processVoiceTurn(_ audioData: Data) async throws -> VoiceAgentResult {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        do {
            // Voice agent capability handles all event tracking internally
            let result = try await serviceContainer.voiceAgentCapability.processVoiceTurn(audioData)
            return result
        } catch {
            EventPublisher.shared.track(VoicePipelineEvent.pipelineFailed(error: SDKError.from(error, category: .voiceAgent)))
            throw error
        }
    }

    // MARK: - Individual Operations

    /// Transcribe audio (voice agent must be initialized)
    static func voiceAgentTranscribe(_ audioData: Data) async throws -> String {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }
        return try await serviceContainer.voiceAgentCapability.transcribe(audioData)
    }

    /// Generate LLM response (voice agent must be initialized)
    static func voiceAgentGenerateResponse(_ prompt: String) async throws -> String {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }
        return try await serviceContainer.voiceAgentCapability.generateResponse(prompt)
    }

    /// Synthesize speech (voice agent must be initialized)
    static func voiceAgentSynthesizeSpeech(_ text: String) async throws -> Data {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }
        return try await serviceContainer.voiceAgentCapability.synthesizeSpeech(text)
    }

    // MARK: - Cleanup

    /// Cleanup voice agent resources
    static func cleanupVoiceAgent() async {
        await serviceContainer.voiceAgentCapability.cleanup()
    }
}
