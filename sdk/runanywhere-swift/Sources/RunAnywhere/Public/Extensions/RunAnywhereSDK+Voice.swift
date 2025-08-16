import Foundation

// MARK: - Voice Extensions
public extension RunAnywhereSDK {

    /// Transcribe audio to text
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
            // No adapter available, return placeholder
            return VoiceTranscriptionResult(
                text: "No voice adapter registered. Please register a UnifiedFrameworkAdapter with voice support.",
                language: options.language.rawValue,
                confidence: 0.0,
                duration: 0.0
            )
        }

        // Initialize the service
        try await voiceService.initialize(modelPath: modelId)

        // Transcribe audio
        let result = try await voiceService.transcribe(audio: audio, options: options)

        // Don't cleanup - keep service cached for reuse
        // await voiceService.cleanup()

        return result
    }

    /// Find appropriate voice service for model
    private func findVoiceService(for modelId: String) -> VoiceService? {
        // Try to find a model info for this modelId
        if let model = try? serviceContainer.modelRegistry.getModel(by: modelId) {
            // Find adapter that can handle this model
            if let unifiedAdapter = serviceContainer.adapterRegistry.findBestAdapter(for: model),
               unifiedAdapter.supportedModalities.contains(FrameworkModality.voiceToText) {
                // Create a voice service from the unified adapter
                if let voiceService = unifiedAdapter.createService(for: FrameworkModality.voiceToText) as? VoiceService {
                    return voiceService
                }
            }
        }

        // Fallback: Find any framework that supports voice-to-text
        let voiceFrameworks = serviceContainer.adapterRegistry.getFrameworks(for: FrameworkModality.voiceToText)
        if let firstVoiceFramework = voiceFrameworks.first,
           let adapter = serviceContainer.adapterRegistry.getAdapter(for: firstVoiceFramework) {
            if let voiceService = adapter.createService(for: FrameworkModality.voiceToText) as? VoiceService {
                return voiceService
            }
        }

        return nil
    }

    /// Process voice query with streaming events
    /// - Parameters:
    ///   - audio: Audio data to process
    ///   - config: Pipeline configuration
    /// - Returns: Stream of pipeline events
    func processVoiceStream(
        audio: Data,
        config: VoicePipelineConfig? = nil
    ) -> AsyncThrowingStream<VoicePipelineEvent, Error> {
        let orchestrator = serviceContainer.voiceOrchestrator
        return orchestrator.processVoicePipeline(
            audio: audio,
            config: config ?? VoicePipelineConfig.default
        )
    }

    /// Process voice query (transcribe and generate response)
    /// - Parameters:
    ///   - audio: Audio data to transcribe
    ///   - voiceModelId: Voice model for transcription
    ///   - llmModelId: LLM model for response generation (uses current if nil)
    ///   - ttsEnabled: Whether to enable text-to-speech
    /// - Returns: Complete pipeline result
    func processVoiceQuery(
        audio: Data,
        voiceModelId: String = "whisper-base",
        llmModelId: String? = nil,
        ttsEnabled: Bool = false,
        systemPrompt: String? = nil
    ) async throws -> VoicePipelineResult {
        try await ensureInitialized()

        let config = VoicePipelineConfig(
            sttModelId: voiceModelId,
            llmModelId: llmModelId,
            ttsEnabled: ttsEnabled,
            streamingEnabled: false,
            timeouts: VoicePipelineConfig.PipelineTimeouts(
                transcription: 30.0,
                llmGeneration: 60.0,  // Fixed: increased from default
                textToSpeech: 30.0
            ),
            systemPrompt: systemPrompt ?? "You are a helpful, friendly voice assistant. Respond naturally and conversationally, keeping responses concise and suitable for text-to-speech. Avoid URLs, code snippets, or complex formatting."
        )

        let orchestrator = serviceContainer.voiceOrchestrator
        return try await orchestrator.processVoiceQuery(
            audio: audio,
            config: config
        )
    }
}

// VoiceResponse is now replaced by VoicePipelineResult for better structure
