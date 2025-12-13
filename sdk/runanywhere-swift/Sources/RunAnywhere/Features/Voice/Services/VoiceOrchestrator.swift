import Foundation

// MARK: - Voice Orchestrator

/// Orchestrator for voice operations handling component lifecycle and result conversion
/// Centralizes voice pipeline logic to reduce duplication in public API
public final class VoiceOrchestrator {

    private let logger = SDKLogger(category: "VoiceOrchestrator")

    // MARK: - Initialization

    public init() {}

    // MARK: - STT Operations

    /// Transcribe audio data using an STT component
    /// - Parameters:
    ///   - audio: Audio data to transcribe
    ///   - modelId: Model identifier to use
    ///   - options: Transcription options
    /// - Returns: STTResult compatible with public API
    public func transcribe(
        audio: Data,
        modelId: String = "whisper-base",
        options: STTOptions = STTOptions()
    ) async throws -> STTResult {
        logger.info("Starting transcription with model: \(modelId)")

        // Create and initialize STT component
        let sttConfig = STTConfiguration(
            modelId: modelId,
            language: options.language,
            enablePunctuation: options.enablePunctuation,
            enableDiarization: options.enableDiarization
        )

        let sttComponent = await STTComponent(configuration: sttConfig)
        try await sttComponent.initialize()

        defer {
            // Cleanup in background
            Task {
                try? await sttComponent.cleanup()
            }
        }

        // Transcribe audio
        let result = try await sttComponent.transcribe(audio, format: options.audioFormat)

        // Convert STTOutput to STTResult
        return convertToSTTResult(result)
    }

    // MARK: - Voice Pipeline Operations

    /// Process a voice turn through the full STT → LLM → TTS pipeline
    /// - Parameters:
    ///   - audio: Audio data to process
    ///   - sttModelId: STT model to use
    ///   - llmModelId: LLM model to use
    ///   - ttsVoice: TTS voice to use
    /// - Returns: Synthesized audio response
    public func processVoiceTurn(
        audio: Data,
        sttModelId: String = "whisper-base",
        llmModelId: String = "llama-3.2-1b",
        ttsVoice: String = "alloy"
    ) async throws -> VoiceTurnResult {
        logger.info("Processing voice turn: STT(\(sttModelId)) → LLM(\(llmModelId)) → TTS(\(ttsVoice))")

        // Create all components
        let sttComponent = await STTComponent(configuration: STTConfiguration(modelId: sttModelId))
        let llmComponent = await LLMComponent(configuration: LLMConfiguration(modelId: llmModelId))
        let ttsComponent = await TTSComponent(configuration: TTSConfiguration(voice: ttsVoice))

        // Initialize all components
        try await sttComponent.initialize()
        try await llmComponent.initialize()
        try await ttsComponent.initialize()

        defer {
            // Cleanup in background
            Task {
                try? await sttComponent.cleanup()
                try? await llmComponent.cleanup()
                try? await ttsComponent.cleanup()
            }
        }

        // 1. Transcribe audio
        let transcript = try await sttComponent.transcribe(audio)
        logger.debug("Transcription: \(transcript.text)")

        // 2. Generate response
        let response = try await llmComponent.generate(prompt: transcript.text)
        logger.debug("Response: \(response.text)")

        // 3. Synthesize speech
        let audioResponse = try await ttsComponent.synthesize(response.text)

        return VoiceTurnResult(
            transcription: transcript.text,
            response: response.text,
            audioData: audioResponse.audioData
        )
    }

    /// Create and initialize components for a voice conversation
    /// - Parameters:
    ///   - sttModelId: STT model to use
    ///   - llmModelId: LLM model to use
    ///   - ttsVoice: TTS voice to use
    /// - Returns: Initialized VoiceConversationComponents
    public func initializeConversationComponents(
        sttModelId: String = "whisper-base",
        llmModelId: String = "llama-3.2-1b",
        ttsVoice: String = "alloy"
    ) async throws -> VoiceConversationComponents {
        logger.info("Initializing conversation components")

        let sttComponent = await STTComponent(configuration: STTConfiguration(modelId: sttModelId))
        let llmComponent = await LLMComponent(configuration: LLMConfiguration(modelId: llmModelId))
        let ttsComponent = await TTSComponent(configuration: TTSConfiguration(voice: ttsVoice))

        try await sttComponent.initialize()
        try await llmComponent.initialize()
        try await ttsComponent.initialize()

        return VoiceConversationComponents(
            stt: sttComponent,
            llm: llmComponent,
            tts: ttsComponent
        )
    }

    // MARK: - Result Conversion

    /// Convert STTOutput to STTResult for public API compatibility
    public func convertToSTTResult(_ output: STTOutput) -> STTResult {
        STTResult(
            text: output.text,
            segments: output.wordTimestamps?.map { timestamp in
                STTSegment(
                    text: timestamp.word,
                    startTime: timestamp.startTime,
                    endTime: timestamp.endTime,
                    confidence: timestamp.confidence
                )
            } ?? [],
            language: output.detectedLanguage,
            confidence: output.confidence,
            duration: output.metadata.audioLength,
            alternatives: output.alternatives?.map { alt in
                STTAlternative(
                    text: alt.text,
                    confidence: alt.confidence
                )
            } ?? []
        )
    }
}

// MARK: - Voice Turn Result

/// Result of a voice turn operation
public struct VoiceTurnResult: Sendable {
    /// The transcribed text from audio input
    public let transcription: String

    /// The generated text response
    public let response: String

    /// The synthesized audio data
    public let audioData: Data

    public init(transcription: String, response: String, audioData: Data) {
        self.transcription = transcription
        self.response = response
        self.audioData = audioData
    }
}

// MARK: - Voice Conversation Components

/// Container for initialized voice conversation components
public struct VoiceConversationComponents: @unchecked Sendable {
    /// Speech-to-text component
    public let stt: STTComponent

    /// Large language model component
    public let llm: LLMComponent

    /// Text-to-speech component
    public let tts: TTSComponent

    public init(stt: STTComponent, llm: LLMComponent, tts: TTSComponent) {
        self.stt = stt
        self.llm = llm
        self.tts = tts
    }

    /// Cleanup all components
    public func cleanup() async throws {
        try await stt.cleanup()
        try await llm.cleanup()
        try await tts.cleanup()
    }
}
