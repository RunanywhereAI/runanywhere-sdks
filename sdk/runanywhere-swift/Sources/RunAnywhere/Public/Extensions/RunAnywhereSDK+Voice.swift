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

    /// Find appropriate voice service for model
    func findVoiceService(for modelId: String) -> VoiceService? {
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

    /// Find appropriate TTS service
    func findTTSService() -> TextToSpeechService {
        // For now, always use system TTS
        return SystemTextToSpeechService()
    }

    /// Find appropriate generation service
    func findGenerationService() -> GenerationService {
        return serviceContainer.generationService
    }

    /// Find appropriate LLM service for a model
    func findLLMService(for modelId: String? = nil) -> LLMService? {
        // Try to find a model info for this modelId
        if let modelId = modelId,
           let model = try? serviceContainer.modelRegistry.getModel(by: modelId) {
            // Find adapter that can handle this model
            if let unifiedAdapter = serviceContainer.adapterRegistry.findBestAdapter(for: model),
               unifiedAdapter.supportedModalities.contains(FrameworkModality.textToText) {
                // Create an LLM service from the unified adapter
                if let llmService = unifiedAdapter.createService(for: FrameworkModality.textToText) as? LLMService {
                    return llmService
                }
            }
        }

        // Fallback: Find any framework that supports text generation
        let textFrameworks = serviceContainer.adapterRegistry.getFrameworks(for: FrameworkModality.textToText)
        if let firstTextFramework = textFrameworks.first,
           let adapter = serviceContainer.adapterRegistry.getAdapter(for: firstTextFramework) {
            if let llmService = adapter.createService(for: FrameworkModality.textToText) as? LLMService {
                return llmService
            }
        }

        return nil
    }

}
