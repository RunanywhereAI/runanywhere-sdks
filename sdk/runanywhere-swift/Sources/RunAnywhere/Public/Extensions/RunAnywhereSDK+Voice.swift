import Foundation

// MARK: - Voice Extensions
public extension RunAnywhereSDK {

    /// Transcribe audio to text (one-shot transcription)
    /// - Parameters:
    ///   - audio: Audio data to transcribe
    ///   - modelId: Model identifier to use (defaults to whisper model)
    ///   - options: Transcription options
    /// - Returns: Transcription result
    func transcribe(
        audio: Data,
        modelId: String = "whisper-base",
        options: VoiceTranscriptionOptions = VoiceTranscriptionOptions()
    ) async throws -> VoiceTranscriptionResult {
        try await ensureInitialized()

        // Find appropriate voice service
        guard let voiceService = findVoiceService(for: modelId) else {
            throw VoiceError.noVoiceServiceAvailable
        }

        // Initialize the service
        try await voiceService.initialize(modelPath: modelId)

        // Transcribe audio
        let result = try await voiceService.transcribe(audio: audio, options: options)

        return result
    }

    // MARK: - Voice Pipeline API

    /// Create a modular voice pipeline with the specified configuration
    /// - Parameters:
    ///   - config: Pipeline configuration
    ///   - speakerDiarization: Optional speaker diarization service
    ///   - segmentationStrategy: Optional audio segmentation strategy
    /// - Returns: Configured voice pipeline
    public func createVoicePipeline(
        config: ModularPipelineConfig,
        speakerDiarization: SpeakerDiarizationProtocol? = nil,
        segmentationStrategy: AudioSegmentationStrategy? = nil
    ) -> VoicePipelineManager {
        // Delegate to voice capability service
        return serviceContainer.voiceCapabilityService.createPipeline(config: config)
    }

    /// Process voice input through the complete pipeline
    /// - Parameters:
    ///   - audioStream: Stream of audio chunks
    ///   - config: Pipeline configuration
    /// - Returns: Stream of pipeline events
    public func processVoice(
        audioStream: AsyncStream<VoiceAudioChunk>,
        config: ModularPipelineConfig
    ) -> AsyncThrowingStream<ModularPipelineEvent, Error> {
        // Delegate to voice capability service
        return serviceContainer.voiceCapabilityService.processVoice(
            audioStream: audioStream,
            config: config
        )
    }


    // MARK: - Service Discovery (Delegated to VoiceCapabilityService)

    /// Find appropriate voice service for model
    func findVoiceService(for modelId: String) -> VoiceService? {
        // Delegate to voice capability service
        return serviceContainer.voiceCapabilityService.findVoiceService(for: modelId)
    }

    /// Find appropriate TTS service
    func findTTSService() -> TextToSpeechService? {
        // Delegate to voice capability service
        return serviceContainer.voiceCapabilityService.findTTSService()
    }

}
