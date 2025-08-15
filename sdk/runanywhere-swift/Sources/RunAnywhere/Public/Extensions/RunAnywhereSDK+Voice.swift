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
        options: TranscriptionOptions = TranscriptionOptions()
    ) async throws -> TranscriptionResult {
        try await ensureInitialized()

        // Find appropriate voice service
        guard let voiceService = findVoiceService(for: modelId) else {
            // No adapter available, return placeholder
            return TranscriptionResult(
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

        // Cleanup
        await voiceService.cleanup()

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

    /// Process voice query (transcribe and generate response)
    /// - Parameters:
    ///   - audio: Audio data to transcribe
    ///   - voiceModelId: Voice model for transcription
    ///   - llmModelId: LLM model for response generation (uses current if nil)
    /// - Returns: Voice response with input and output text
    func processVoiceQuery(
        audio: Data,
        voiceModelId: String = "whisper-base",
        llmModelId: String? = nil
    ) async throws -> VoiceResponse {
        try await ensureInitialized()

        // Transcribe audio to text
        let transcription = try await transcribe(
            audio: audio,
            modelId: voiceModelId
        )

        // Generate response using existing generation service
        let textResponse = try await generate(
            prompt: transcription.text,
            options: GenerationOptions()
        )

        return VoiceResponse(
            inputText: transcription.text,
            outputText: textResponse.text
        )
    }
}

/// Response from voice processing
public struct VoiceResponse {
    /// The transcribed input text
    public let inputText: String

    /// The generated output text
    public let outputText: String

    public init(inputText: String, outputText: String) {
        self.inputText = inputText
        self.outputText = outputText
    }
}
