import Foundation

// MARK: - Supporting Types

/// Delegate for forwarding voice conversation events
private class VoiceConversationDelegate: ModularPipelineDelegate {
    private let continuation: AsyncThrowingStream<SDKVoiceEvent, Error>.Continuation

    init(continuation: AsyncThrowingStream<SDKVoiceEvent, Error>.Continuation) {
        self.continuation = continuation
    }

    func pipelineDidGenerateEvent(_ event: SDKVoiceEvent) {
        continuation.yield(event)
    }
}

// MARK: - Voice Extensions (Unified Architecture)

public extension RunAnywhere {

    /// Transcribe audio to text using the unified voice processor
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
        guard RunAnywhere.isSDKInitialized else {
            throw SDKError.notInitialized
        }

        EventBus.shared.publish(SDKVoiceEvent.transcriptionStarted)

        do {
            // Create STT configuration
            let sttConfig = STTConfiguration(
                modelId: modelId,
                language: options.language,
                enablePunctuation: options.enablePunctuation,
                enableDiarization: options.enableDiarization
            )

            // Use unified component creation pattern
            let sttComponent = await STTComponent(configuration: sttConfig)
            try await sttComponent.initialize()

            let result = try await sttComponent.transcribe(audio)

            // Create result for compatibility
            let sttResult = STTResult(
                text: result.text,
                segments: [],
                language: options.language,
                confidence: result.confidence,
                duration: 0.0,
                alternatives: []
            )

            try await sttComponent.cleanup()
            return sttResult

        } catch {
            EventBus.shared.publish(SDKVoiceEvent.pipelineError(error))
            throw error
        }
    }

    /// Create a voice conversation using unified voice configuration
    /// - Parameters:
    ///   - config: Voice configuration (uses default if not provided)
    /// - Returns: AsyncThrowingStream of voice events
    static func createVoiceConversation(
        config: VoiceConfiguration = .default
    ) -> AsyncThrowingStream<SDKVoiceEvent, Error> {
        guard RunAnywhere.isSDKInitialized else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: SDKError.notInitialized)
            }
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Use the unified voice pipeline service
                    let pipeline = try await createVoicePipeline(config: config)

                    EventBus.shared.publish(SDKVoiceEvent.conversationInitialized)

                    // Set up event forwarding from the pipeline
                    pipeline.delegate = VoiceConversationDelegate(continuation: continuation)

                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Create a voice conversation with simple parameters (convenience method)
    /// - Parameters:
    ///   - sttModelId: STT model to use
    ///   - llmModelId: LLM model to use
    ///   - ttsVoice: TTS voice to use
    /// - Returns: AsyncThrowingStream of voice events
    static func createVoiceConversation(
        sttModelId: String = "whisper-base",
        llmModelId: String = "llama-3.2-1b",
        ttsVoice: String = "alloy"
    ) -> AsyncThrowingStream<SDKVoiceEvent, Error> {
        // Create configuration from simple parameters
        do {
            let config = try VoiceConfigurationBuilder()
                .stt(STTConfiguration(modelId: sttModelId))
                .llm(LLMConfiguration(modelId: llmModelId))
                .tts(TTSConfiguration(voice: ttsVoice))
                .build()

            return createVoiceConversation(config: config)
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }
    }

    /// Process audio through the voice pipeline
    /// - Parameters:
    ///   - audio: Audio data to process
    ///   - config: Voice configuration to use
    /// - Returns: The pipeline result with processed audio
    static func processVoiceTurn(
        audio: Data,
        config: VoiceConfiguration = .default
    ) async throws -> VoicePipelineResult {
        guard RunAnywhere.isSDKInitialized else {
            throw SDKError.notInitialized
        }

        EventBus.shared.publish(SDKVoiceEvent.pipelineStarted)

        do {
            // Use the unified voice pipeline service
            let pipeline = try await createVoicePipeline(config: config)

            // Initialize the pipeline
            _ = pipeline.initializeComponents()

            // Convert audio data to audio chunk stream
            let audioChunk = VoiceAudioChunk(
                samples: audio.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) },
                timestamp: Date().timeIntervalSince1970,
                sampleRate: 16000,
                channels: 1,
                sequenceNumber: 0,
                isFinal: true
            )

            let audioStream = AsyncStream<VoiceAudioChunk> { continuation in
                continuation.yield(audioChunk)
                continuation.finish()
            }

            // Process through pipeline and collect result
            var transcription: STTResult?
            var llmResponse: String?
            var audioOutput: Data?

            for try await event in pipeline.process(audioStream: audioStream) {
                switch event {
                case .transcriptionFinal(let text):
                    transcription = STTResult(text: text, segments: [], language: "en", confidence: 1.0, duration: 0, alternatives: [])
                case .llmFinalResponse(let text):
                    llmResponse = text
                case .audioGenerated(let data):
                    audioOutput = data
                case .pipelineCompleted:
                    break
                default:
                    continue
                }
            }

            let result = VoicePipelineResult(
                transcription: transcription ?? STTResult(text: "", segments: [], language: "en", confidence: 0, duration: 0, alternatives: []),
                llmResponse: llmResponse ?? "",
                audioOutput: audioOutput
            )

            EventBus.shared.publish(SDKVoiceEvent.pipelineCompleted)

            return result

        } catch {
            EventBus.shared.publish(SDKVoiceEvent.pipelineError(error))
            throw error
        }
    }

    /// Process audio through the voice pipeline with simple parameters (convenience method)
    /// - Parameters:
    ///   - audio: Audio data to process
    ///   - sttModelId: STT model to use
    ///   - llmModelId: LLM model to use
    ///   - ttsVoice: TTS voice to use
    /// - Returns: The final audio response data
    static func processVoiceTurn(
        audio: Data,
        sttModelId: String = "whisper-base",
        llmModelId: String = "llama-3.2-1b",
        ttsVoice: String = "alloy"
    ) async throws -> Data {
        // Create configuration from simple parameters
        let config = try VoiceConfigurationBuilder()
            .stt(STTConfiguration(modelId: sttModelId))
            .llm(LLMConfiguration(modelId: llmModelId))
            .tts(TTSConfiguration(voice: ttsVoice))
            .build()

        let result = try await processVoiceTurn(audio: audio, config: config)
        return result.audioOutput ?? Data()
    }
}
