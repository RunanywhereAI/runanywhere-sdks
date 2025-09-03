import Foundation

// MARK: - Voice Extensions (Component-Based)

public extension RunAnywhere {

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
            // Create and initialize STT component
            let sttConfig = STTConfiguration(
                modelId: modelId,
                language: options.language,
                enablePunctuation: options.enablePunctuation,
                enableDiarization: options.enableDiarization
            )

            let sttComponent = await STTComponent(configuration: sttConfig)
            try await sttComponent.initialize()

            // Transcribe audio
            let result = try await sttComponent.transcribe(audio, format: options.audioFormat)

            // Convert STTOutput to STTResult for compatibility
            let sttResult = STTResult(
                text: result.text,
                segments: result.wordTimestamps?.map { timestamp in
                    STTSegment(
                        text: timestamp.word,
                        startTime: timestamp.startTime,
                        endTime: timestamp.endTime,
                        confidence: timestamp.confidence
                    )
                } ?? [],
                language: result.detectedLanguage,
                confidence: result.confidence,
                duration: result.metadata.audioLength,
                alternatives: result.alternatives?.map { alt in
                    STTAlternative(
                        text: alt.text,
                        confidence: alt.confidence
                    )
                } ?? []
            )

            events.publish(SDKVoiceEvent.transcriptionFinal(text: result.text))

            // Cleanup
            try await sttComponent.cleanup()

            return sttResult
        } catch {
            events.publish(SDKVoiceEvent.pipelineError(error))
            throw error
        }
    }

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
                    // Create components (these are @MainActor so need await)
                    let sttComponent = await STTComponent(configuration: STTConfiguration(modelId: sttModelId))
                    let llmComponent = await LLMComponent(configuration: LLMConfiguration(modelId: llmModelId))
                    let ttsComponent = await TTSComponent(configuration: TTSConfiguration(voice: ttsVoice))

                    // Initialize all components
                    try await sttComponent.initialize()
                    try await llmComponent.initialize()
                    try await ttsComponent.initialize()

                    continuation.yield(.initialized)

                    // Components are ready for use
                    // The actual conversation loop would be implemented here

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
        // Create components (these are @MainActor so need await)
        let sttComponent = await STTComponent(configuration: STTConfiguration(modelId: sttModelId))
        let llmComponent = await LLMComponent(configuration: LLMConfiguration(modelId: llmModelId))
        let ttsComponent = await TTSComponent(configuration: TTSConfiguration(voice: ttsVoice))

        // Initialize all components
        try await sttComponent.initialize()
        try await llmComponent.initialize()
        try await ttsComponent.initialize()

        // Process through pipeline
        // 1. Transcribe audio
        let transcript = try await sttComponent.transcribe(audio)
        events.publish(SDKVoiceEvent.transcriptionFinal(text: transcript.text))

        // 2. Generate response
        let response = try await llmComponent.generate(prompt: transcript.text)
        events.publish(SDKVoiceEvent.responseGenerated(text: response.text))

        // 3. Synthesize speech
        let audioResponse = try await ttsComponent.synthesize(response.text)
        events.publish(SDKVoiceEvent.audioGenerated(data: audioResponse.audioData))

        // Cleanup
        try await sttComponent.cleanup()
        try await llmComponent.cleanup()
        try await ttsComponent.cleanup()

        return audioResponse.audioData
    }
}

// MARK: - Voice Conversation Events

public enum VoiceConversationEvent {
    case initialized
    case transcribing
    case transcribed(String)
    case generating
    case generated(String)
    case synthesizing
    case synthesized(Data)
    case error(Error)
}
