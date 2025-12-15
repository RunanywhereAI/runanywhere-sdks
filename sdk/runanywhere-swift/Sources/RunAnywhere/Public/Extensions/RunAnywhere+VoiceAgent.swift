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

        let sttState: ComponentLoadState = sttIsLoaded && sttId != nil
            ? .loaded(modelId: sttId!)
            : .notLoaded

        let llmState: ComponentLoadState = llmIsLoaded && llmId != nil
            ? .loaded(modelId: llmId!)
            : .notLoaded

        let ttsState: ComponentLoadState = ttsIsLoaded && ttsId != nil
            ? .loaded(modelId: ttsId!)
            : .notLoaded

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
            throw RunAnywhereError.notInitialized
        }

        try await ensureDeviceRegistered()

        EventPublisher.shared.track(VoicePipelineEvent.pipelineStarted)

        do {
            try await serviceContainer.voiceAgentCapability.initialize(config)
            EventPublisher.shared.track(VoicePipelineEvent.pipelineCompleted(durationMs: 0))
        } catch {
            EventPublisher.shared.track(VoicePipelineEvent.pipelineFailed(error: error.localizedDescription))
            throw error
        }
    }

    /// Initialize voice agent with individual model IDs
    static func initializeVoiceAgent(
        sttModelId: String,
        llmModelId: String,
        ttsVoice: String = "com.apple.ttsbundle.siri_female_en-US_compact"
    ) async throws {
        guard isSDKInitialized else {
            throw RunAnywhereError.notInitialized
        }

        try await ensureDeviceRegistered()

        EventPublisher.shared.track(VoicePipelineEvent.pipelineStarted)

        do {
            try await serviceContainer.voiceAgentCapability.initialize(
                sttModelId: sttModelId,
                llmModelId: llmModelId,
                ttsVoice: ttsVoice
            )
            EventPublisher.shared.track(VoicePipelineEvent.pipelineCompleted(durationMs: 0))
        } catch {
            EventPublisher.shared.track(VoicePipelineEvent.pipelineFailed(error: error.localizedDescription))
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
            throw RunAnywhereError.notInitialized
        }

        do {
            // Voice agent capability handles all event tracking internally
            let result = try await serviceContainer.voiceAgentCapability.processVoiceTurn(audioData)
            return result
        } catch {
            EventPublisher.shared.track(VoicePipelineEvent.pipelineFailed(error: error.localizedDescription))
            throw error
        }
    }

    /// Process audio stream for continuous conversation
    static func processVoiceStream(_ audioStream: AsyncStream<Data>) async -> AsyncThrowingStream<VoiceAgentEvent, Error> {
        guard isSDKInitialized else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: RunAnywhereError.notInitialized)
            }
        }

        return await serviceContainer.voiceAgentCapability.processStream(audioStream)
    }

    // MARK: - Individual Operations

    /// Transcribe audio (voice agent must be initialized)
    static func voiceAgentTranscribe(_ audioData: Data) async throws -> String {
        guard isSDKInitialized else {
            throw RunAnywhereError.notInitialized
        }
        return try await serviceContainer.voiceAgentCapability.transcribe(audioData)
    }

    /// Generate LLM response (voice agent must be initialized)
    static func voiceAgentGenerateResponse(_ prompt: String) async throws -> String {
        guard isSDKInitialized else {
            throw RunAnywhereError.notInitialized
        }
        return try await serviceContainer.voiceAgentCapability.generateResponse(prompt)
    }

    /// Synthesize speech (voice agent must be initialized)
    static func voiceAgentSynthesizeSpeech(_ text: String) async throws -> Data {
        guard isSDKInitialized else {
            throw RunAnywhereError.notInitialized
        }
        return try await serviceContainer.voiceAgentCapability.synthesizeSpeech(text)
    }

    // MARK: - Cleanup

    /// Cleanup voice agent resources
    static func cleanupVoiceAgent() async {
        await serviceContainer.voiceAgentCapability.cleanup()
    }
}
