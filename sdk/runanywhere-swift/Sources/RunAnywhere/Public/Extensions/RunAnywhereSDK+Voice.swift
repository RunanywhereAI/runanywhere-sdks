import Foundation

// MARK: - Voice Extensions
public extension RunAnywhereSDK {

    /// Register a voice framework adapter
    func registerVoiceFrameworkAdapter(_ adapter: VoiceFrameworkAdapter) {
        // This will be connected to internal registry through ServiceContainer
        // For now, store in a simple way
        voiceAdapters[adapter.framework] = adapter
    }

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

        // Find appropriate voice adapter
        guard let adapter = findVoiceAdapter(for: modelId) else {
            // No adapter available, return placeholder
            return TranscriptionResult(
                text: "No voice adapter registered. Please register WhisperKitAdapter.",
                language: options.language.rawValue,
                confidence: 0.0,
                duration: 0.0
            )
        }

        // Create voice service
        let voiceService = adapter.createService()

        // Initialize the service
        try await voiceService.initialize(modelPath: modelId)

        // Transcribe audio
        let result = try await voiceService.transcribe(audio: audio, options: options)

        // Cleanup
        await voiceService.cleanup()

        return result
    }

    /// Find appropriate voice adapter for model
    private func findVoiceAdapter(for modelId: String) -> VoiceFrameworkAdapter? {
        // For MVP, just return first available voice adapter
        return voiceAdapters.values.first
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
