import Foundation

// MARK: - Voice Extensions (Event-Based)

public extension RunAnywhere {

    /// Transcribe audio to text with comprehensive event reporting
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
        await events.publish(SDKVoiceEvent.transcriptionStarted)

        do {
            // Find appropriate voice service
            guard let voiceService = RunAnywhere.serviceContainer.voiceCapabilityService.findVoiceService(for: modelId) else {
                throw STTError.noVoiceServiceAvailable
            }

            // Initialize the service
            try await voiceService.initialize(modelPath: modelId)

            // Transcribe audio
            let result = try await voiceService.transcribe(audio: audio, options: options)

            await events.publish(SDKVoiceEvent.transcriptionFinal(text: result.text))
            return result
        } catch {
            await events.publish(SDKVoiceEvent.pipelineError(error))
            throw error
        }
    }

    /// Create a modular voice pipeline with event tracking
    /// - Parameters:
    ///   - config: Pipeline configuration
    ///   - speakerDiarization: Optional speaker diarization service
    ///   - segmentationStrategy: Optional audio segmentation strategy
    /// - Returns: Configured voice pipeline
    static func createVoicePipeline(
        config: ModularPipelineConfig,
        speakerDiarization: SpeakerDiarizationService? = nil,
        segmentationStrategy: AudioSegmentationStrategy? = nil
    ) -> VoicePipelineManager {
        Task {
            await events.publish(SDKVoiceEvent.pipelineCreated(config: config))
        }

        return RunAnywhere.serviceContainer.voiceCapabilityService.createPipeline(config: config)
    }

    /// Process voice input through the complete pipeline with real-time events
    /// - Parameters:
    ///   - audioStream: Stream of audio chunks
    ///   - config: Pipeline configuration
    /// - Returns: Stream of pipeline events
    static func processVoice(
        audioStream: AsyncStream<VoiceAudioChunk>,
        config: ModularPipelineConfig
    ) -> AsyncThrowingStream<ModularPipelineEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await events.publish(SDKVoiceEvent.pipelineStarted(config: config))

                do {
                    // Create pipeline and process voice stream
                    let pipeline = RunAnywhere.serviceContainer.voiceCapabilityService.createPipeline(config: config)
                    let eventStream = pipeline.process(audioStream: audioStream)

                    for try await event in eventStream {
                        // Publish to event bus for transparency
                        await events.publish(SDKVoiceEvent.pipelineEvent(event))

                        // Forward to caller
                        continuation.yield(event)
                    }

                    await events.publish(SDKVoiceEvent.pipelineCompleted)
                    continuation.finish()
                } catch {
                    await events.publish(SDKVoiceEvent.pipelineError(error))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Find voice service for a specific model
    /// - Parameter modelId: The model identifier
    /// - Returns: Voice service if available
    static func findVoiceService(for modelId: String) -> STTService? {
        return RunAnywhere.serviceContainer.voiceCapabilityService.findVoiceService(for: modelId)
    }

    /// Find text-to-speech service
    /// - Returns: TTS service if available
    static func findTTSService() -> TextToSpeechService? {
        return RunAnywhere.serviceContainer.voiceCapabilityService.findTTSService()
    }
}
