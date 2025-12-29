//
//  RunAnywhere+VoiceAgent.swift
//  RunAnywhere SDK
//
//  Public API for Voice Agent operations (full voice pipeline).
//  Events are tracked via EventPublisher.
//
//  Architecture:
//  - Voice agent uses SHARED handles from the individual capabilities (STT, LLM, TTS)
//  - Models are loaded via loadSTT(), loadLLM(), loadTTS() (the individual capability APIs)
//  - Voice agent is purely an orchestrator for the full voice pipeline
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
    /// Models are loaded via the individual capability APIs (loadSTT, loadLLM, loadTTS).
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

        // Voice agent delegates to individual capabilities for model state
        async let sttLoaded = serviceContainer.voiceAgentCapability.isSTTLoaded
        async let sttModelId = serviceContainer.voiceAgentCapability.currentSTTModelId
        async let llmLoaded = serviceContainer.voiceAgentCapability.isLLMLoaded
        async let llmModelId = serviceContainer.voiceAgentCapability.currentLLMModelId
        async let ttsLoaded = serviceContainer.voiceAgentCapability.isTTSLoaded
        async let ttsVoiceId = serviceContainer.voiceAgentCapability.currentTTSVoiceId

        let (sttL, sttId, llmL, llmId, ttsL, ttsId) =
            await (sttLoaded, sttModelId, llmLoaded, llmModelId, ttsLoaded, ttsVoiceId)

        let sttState: ComponentLoadState
        if sttL, let modelId = sttId {
            sttState = .loaded(modelId: modelId)
        } else {
            sttState = .notLoaded
        }

        let llmState: ComponentLoadState
        if llmL, let modelId = llmId {
            llmState = .loaded(modelId: modelId)
        } else {
            llmState = .notLoaded
        }

        let ttsState: ComponentLoadState
        if ttsL, let modelId = ttsId {
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

    /// Initialize voice agent using already-loaded models from individual capabilities
    ///
    /// Use this after loading models via the individual capability APIs:
    ///
    /// Example:
    /// ```swift
    /// // Load models via individual capability APIs
    /// try await RunAnywhere.loadSTT("sherpa-onnx-whisper-tiny.en")
    /// try await RunAnywhere.loadLLM("lfm2-350m-q4_k_m")
    /// try await RunAnywhere.loadTTS("vits-piper-en_GB-alba-medium")
    ///
    /// // Then initialize voice agent (it will use the shared handles)
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

    /// Check if voice agent is ready (all components initialized)
    static var isVoiceAgentReady: Bool {
        get async {
            await serviceContainer.voiceAgentCapability.isReady
        }
    }

    // MARK: - Voice Processing

    /// Process a complete voice turn: audio -> transcription -> LLM response -> synthesized speech
    static func processVoiceTurn(_ audioData: Data) async throws -> VoiceAgentResult {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        do {
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
