//
//  RunAnywhere+VoiceAgent.swift
//  RunAnywhere SDK
//
//  Public API for Voice Agent operations (full voice pipeline)
//

import Foundation

// MARK: - Voice Agent Operations

public extension RunAnywhere {

    // MARK: - Initialization

    /// Initialize the voice agent with configuration
    /// - Parameter config: Voice agent configuration
    static func initializeVoiceAgent(_ config: VoiceAgentConfiguration) async throws {
        guard isSDKInitialized else {
            throw RunAnywhereError.notInitialized
        }

        try await ensureDeviceRegistered()

        events.publishAsync(SDKVoiceEvent.pipelineStarted)

        do {
            try await serviceContainer.voiceAgentCapability.initialize(config)
            events.publishAsync(SDKVoiceEvent.pipelineCompleted)
        } catch {
            events.publishAsync(SDKVoiceEvent.pipelineError(error))
            throw error
        }
    }

    /// Initialize voice agent with individual model IDs
    /// - Parameters:
    ///   - sttModelId: STT model identifier
    ///   - llmModelId: LLM model identifier
    ///   - ttsVoice: TTS voice identifier
    static func initializeVoiceAgent(
        sttModelId: String,
        llmModelId: String,
        ttsVoice: String = "com.apple.ttsbundle.siri_female_en-US_compact"
    ) async throws {
        guard isSDKInitialized else {
            throw RunAnywhereError.notInitialized
        }

        try await ensureDeviceRegistered()

        events.publishAsync(SDKVoiceEvent.pipelineStarted)

        do {
            try await serviceContainer.voiceAgentCapability.initialize(
                sttModelId: sttModelId,
                llmModelId: llmModelId,
                ttsVoice: ttsVoice
            )
            events.publishAsync(SDKVoiceEvent.pipelineCompleted)
        } catch {
            events.publishAsync(SDKVoiceEvent.pipelineError(error))
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
    /// - Parameter audioData: Audio data from user
    /// - Returns: Voice agent result with all outputs
    static func processVoiceTurn(_ audioData: Data) async throws -> VoiceAgentResult {
        guard isSDKInitialized else {
            throw RunAnywhereError.notInitialized
        }

        do {
            let result = try await serviceContainer.voiceAgentCapability.processVoiceTurn(audioData)

            // Publish events (using optional fields from VoiceAgentResult)
            if let transcription = result.transcription {
                events.publishAsync(SDKVoiceEvent.transcriptionFinal(text: transcription))
            }
            if let response = result.response {
                events.publishAsync(SDKVoiceEvent.responseGenerated(text: response))
            }
            if let audioData = result.synthesizedAudio {
                events.publishAsync(SDKVoiceEvent.audioGenerated(data: audioData))
            }

            return result
        } catch {
            events.publishAsync(SDKVoiceEvent.pipelineError(error))
            throw error
        }
    }

    /// Process audio stream for continuous conversation
    /// - Parameter audioStream: Async stream of audio data chunks
    /// - Returns: Async stream of voice agent events
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
    /// - Parameter audioData: Audio data to transcribe
    /// - Returns: Transcribed text
    static func voiceAgentTranscribe(_ audioData: Data) async throws -> String {
        guard isSDKInitialized else {
            throw RunAnywhereError.notInitialized
        }

        let text = try await serviceContainer.voiceAgentCapability.transcribe(audioData)
        events.publishAsync(SDKVoiceEvent.transcriptionFinal(text: text))
        return text
    }

    /// Generate LLM response (voice agent must be initialized)
    /// - Parameter prompt: Input prompt
    /// - Returns: Generated response
    static func voiceAgentGenerateResponse(_ prompt: String) async throws -> String {
        guard isSDKInitialized else {
            throw RunAnywhereError.notInitialized
        }

        let response = try await serviceContainer.voiceAgentCapability.generateResponse(prompt)
        events.publishAsync(SDKVoiceEvent.responseGenerated(text: response))
        return response
    }

    /// Synthesize speech (voice agent must be initialized)
    /// - Parameter text: Text to synthesize
    /// - Returns: Synthesized audio data
    static func voiceAgentSynthesizeSpeech(_ text: String) async throws -> Data {
        guard isSDKInitialized else {
            throw RunAnywhereError.notInitialized
        }

        let audioData = try await serviceContainer.voiceAgentCapability.synthesizeSpeech(text)
        events.publishAsync(SDKVoiceEvent.audioGenerated(data: audioData))
        return audioData
    }

    // MARK: - Cleanup

    /// Cleanup voice agent resources
    static func cleanupVoiceAgent() async {
        await serviceContainer.voiceAgentCapability.cleanup()
    }
}
