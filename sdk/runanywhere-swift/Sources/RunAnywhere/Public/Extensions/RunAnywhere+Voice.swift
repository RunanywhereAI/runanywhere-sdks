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
        events.publish(SDKVoiceEvent.transcriptionStarted)

        do {
            // Find appropriate voice service
            guard let voiceService = await RunAnywhere.serviceContainer.voiceCapabilityService.findVoiceService(for: modelId) else {
                throw STTError.noVoiceServiceAvailable
            }

            // Initialize the service
            try await voiceService.initialize(modelPath: modelId)

            // Transcribe audio
            let result = try await voiceService.transcribe(audio: audio, options: options)

            events.publish(SDKVoiceEvent.transcriptionFinal(text: result.text))
            return result
        } catch {
            events.publish(SDKVoiceEvent.pipelineError(error))
            throw error
        }
    }

    /// Create a modular voice pipeline with event tracking
    /// - Parameters:
    ///   - vadParams: VAD initialization parameters
    ///   - sttParams: STT initialization parameters
    ///   - llmParams: LLM initialization parameters
    ///   - ttsParams: TTS initialization parameters
    /// - Returns: Configured voice pipeline
    static func createVoicePipeline(
        vadParams: VADInitParameters? = nil,
        sttParams: STTInitParameters? = nil,
        llmParams: LLMInitParameters? = nil,
        ttsParams: TTSInitParameters? = nil
    ) -> VoicePipelineManager {
        Task {
            events.publish(SDKVoiceEvent.pipelineStarted)
        }

        return RunAnywhere.serviceContainer.voiceCapabilityService.createPipeline(
            vadParams: vadParams,
            sttParams: sttParams,
            llmParams: llmParams,
            ttsParams: ttsParams
        )
    }

    /// Create a voice pipeline with ModularPipelineConfig
    /// - Parameters:
    ///   - config: Modular pipeline configuration
    ///   - speakerDiarization: Optional speaker diarization service
    /// - Returns: Configured voice pipeline
    static func createVoicePipeline(
        config: ModularPipelineConfig,
        speakerDiarization: SpeakerDiarizationService? = nil
    ) -> VoicePipelineManager {
        Task {
            events.publish(SDKVoiceEvent.pipelineStarted)
        }

        // Create pipeline using config parameters
        return VoicePipelineManager(
            config: config,
            vadService: nil,
            voiceService: nil,
            llmService: nil,
            ttsService: nil,
            speakerDiarization: speakerDiarization
        )
    }

    /// Process voice input through the complete pipeline with real-time events
    /// - Parameters:
    ///   - audioStream: Stream of audio chunks
    ///   - vadParams: VAD initialization parameters
    ///   - sttParams: STT initialization parameters
    ///   - llmParams: LLM initialization parameters
    ///   - ttsParams: TTS initialization parameters
    /// - Returns: Stream of voice events
    static func processVoice(
        audioStream: AsyncStream<VoiceAudioChunk>,
        vadParams: VADInitParameters? = nil,
        sttParams: STTInitParameters? = nil,
        llmParams: LLMInitParameters? = nil,
        ttsParams: TTSInitParameters? = nil
    ) -> AsyncThrowingStream<SDKVoiceEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                events.publish(SDKVoiceEvent.pipelineStarted)

                do {
                    // Create pipeline and process voice stream
                    let pipeline = RunAnywhere.serviceContainer.voiceCapabilityService.createPipeline(
                        vadParams: vadParams,
                        sttParams: sttParams,
                        llmParams: llmParams,
                        ttsParams: ttsParams
                    )
                    let eventStream = pipeline.process(audioStream: audioStream)

                    for try await event in eventStream {
                        // Convert and publish SDK events
                        if let sdkEvent = convertToSDKEvent(event) {
                            events.publish(sdkEvent)
                        }
                        // Forward to caller
                        continuation.yield(event)
                    }

                    events.publish(SDKVoiceEvent.pipelineCompleted)
                    continuation.finish()
                } catch {
                    events.publish(SDKVoiceEvent.pipelineError(error))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Find voice service for a specific model
    /// - Parameter modelId: The model identifier
    /// - Returns: Voice service if available
    static func findVoiceService(for modelId: String) async -> STTService? {
        return await RunAnywhere.serviceContainer.voiceCapabilityService.findVoiceService(for: modelId)
    }

    /// Find text-to-speech service
    /// - Returns: TTS service if available
    static func findTTSService() async -> TextToSpeechService? {
        return await RunAnywhere.serviceContainer.voiceCapabilityService.findTTSService()
    }

    // MARK: - Private Helper

    private static func convertToSDKEvent(_ event: ModularPipelineEvent) -> SDKVoiceEvent? {
        switch event {
        case .vadSpeechStart:
            return .vadDetected
        case .vadSpeechEnd:
            return .vadEnded
        case .sttPartialTranscript(let text):
            return .transcriptionPartial(text: text)
        case .sttFinalTranscript(let text):
            return .transcriptionFinal(text: text)
        case .llmThinking:
            return .llmProcessing
        case .llmFinalResponse(let text):
            return .responseGenerated(text: text)
        case .ttsStarted:
            return .synthesisStarted
        case .ttsComplete:
            return .synthesisCompleted
        case .ttsAudioChunk(let chunk):
            // Convert audio chunk to Data
            let data = chunk.samples.withUnsafeBytes { Data($0) }
            return .audioGenerated(data: data)
        default:
            return nil
        }
    }
}
