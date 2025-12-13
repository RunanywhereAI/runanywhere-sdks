import Foundation

// MARK: - Voice Extensions (Component-Based)

/// Extension for voice-related operations including STT, TTS, and voice pipelines
public extension RunAnywhere {

    // MARK: - Voice Pipelines

    /// Create a modular voice pipeline for the sample app
    /// This uses individual components in a modular way
    static func createVoicePipeline(config: ModularPipelineConfig) async throws -> ModularVoicePipeline {
        try await ModularVoicePipeline(config: config)
    }

    // MARK: - Speech-to-Text

    /// Transcribe audio to text using the new component architecture
    /// - Parameters:
    ///   - audio: Audio data to transcribe
    ///   - modelId: Model identifier to use (defaults to whisper model)
    ///   - options: Transcription options
    /// - Returns: Transcription result
    static func transcribe(
        audio: Data,
        modelId: String = "whisper-base",
        options: STTOptions = STTOptions()
    ) async throws -> STTResult {
        events.publish(SDKVoiceEvent.transcriptionStarted)

        do {
            let result = try await serviceContainer.voiceOrchestrator.transcribe(
                audio: audio,
                modelId: modelId,
                options: options
            )
            events.publish(SDKVoiceEvent.transcriptionFinal(text: result.text))
            return result
        } catch {
            events.publish(SDKVoiceEvent.pipelineError(error))
            throw error
        }
    }

    // MARK: - Voice Conversations

    /// Create a voice conversation using components
    /// - Parameters:
    ///   - sttModelId: STT model to use
    ///   - llmModelId: LLM model to use
    ///   - ttsVoice: TTS voice to use
    /// - Returns: AsyncThrowingStream of conversation events
    static func createVoiceConversation(
        sttModelId: String = "whisper-base",
        llmModelId: String = "llama-3.2-1b",
        ttsVoice: String = "alloy"
    ) -> AsyncThrowingStream<VoiceConversationEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    _ = try await serviceContainer.voiceOrchestrator.initializeConversationComponents(
                        sttModelId: sttModelId,
                        llmModelId: llmModelId,
                        ttsVoice: ttsVoice
                    )
                    continuation.yield(.initialized)
                    // Components are ready for use - conversation loop would be implemented here
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Process audio through the voice pipeline
    /// - Parameters:
    ///   - audio: Audio data to process
    ///   - sttModelId: STT model to use
    ///   - llmModelId: LLM model to use
    ///   - ttsVoice: TTS voice to use
    /// - Returns: The final audio response
    static func processVoiceTurn(
        audio: Data,
        sttModelId: String = "whisper-base",
        llmModelId: String = "llama-3.2-1b",
        ttsVoice: String = "alloy"
    ) async throws -> Data {
        let result = try await serviceContainer.voiceOrchestrator.processVoiceTurn(
            audio: audio,
            sttModelId: sttModelId,
            llmModelId: llmModelId,
            ttsVoice: ttsVoice
        )

        // Publish events
        events.publish(SDKVoiceEvent.transcriptionFinal(text: result.transcription))
        events.publish(SDKVoiceEvent.responseGenerated(text: result.response))
        events.publish(SDKVoiceEvent.audioGenerated(data: result.audioData))

        return result.audioData
    }
}
