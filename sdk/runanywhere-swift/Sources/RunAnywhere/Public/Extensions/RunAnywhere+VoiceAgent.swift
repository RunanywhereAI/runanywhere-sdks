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

    /// Check if voice agent is ready
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
