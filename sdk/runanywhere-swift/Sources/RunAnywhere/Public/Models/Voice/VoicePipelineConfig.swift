import Foundation

/// Configuration for voice pipeline processing
public struct VoicePipelineConfig {
    /// Model ID for speech-to-text
    public let sttModelId: String

    /// Model ID for LLM generation (nil uses current model)
    public let llmModelId: String?

    /// Whether to enable text-to-speech
    public let ttsEnabled: Bool

    /// TTS voice selection (nil uses default)
    public let ttsVoice: String?

    /// Whether to enable streaming events
    public let streamingEnabled: Bool

    /// Timeout configuration for each stage
    public let timeouts: PipelineTimeouts

    /// LLM generation options
    public let generationOptions: GenerationOptions

    /// System prompt for conversational context
    public let systemPrompt: String?

    public init(
        sttModelId: String = "whisper-base",
        llmModelId: String? = nil,
        ttsEnabled: Bool = false,
        ttsVoice: String? = nil,
        streamingEnabled: Bool = true,
        timeouts: PipelineTimeouts = PipelineTimeouts(),
        generationOptions: GenerationOptions? = nil,
        systemPrompt: String? = nil
    ) {
        self.sttModelId = sttModelId
        self.llmModelId = llmModelId
        self.ttsEnabled = ttsEnabled
        self.ttsVoice = ttsVoice
        self.streamingEnabled = streamingEnabled
        self.timeouts = timeouts
        self.systemPrompt = systemPrompt

        // If generation options provided, use them; otherwise create with system prompt
        if let providedOptions = generationOptions {
            self.generationOptions = providedOptions
        } else if let systemPrompt = systemPrompt {
            // Create default options with the provided system prompt
            self.generationOptions = GenerationOptions(
                maxTokens: 100,
                temperature: 0.7,
                systemPrompt: systemPrompt
            )
        } else {
            // Use default conversational options
            self.generationOptions = GenerationOptions(
                maxTokens: 100,
                temperature: 0.7
            )
        }
    }

    /// Default configuration for voice queries
    public static var `default`: VoicePipelineConfig {
        return VoicePipelineConfig(
            systemPrompt: "You are a helpful, friendly voice assistant. Respond naturally and conversationally, keeping responses concise and suitable for text-to-speech. Avoid URLs, code snippets, or complex formatting."
        )
    }

    /// Configuration for voice queries with custom system prompt
    public static func withSystemPrompt(_ prompt: String) -> VoicePipelineConfig {
        return VoicePipelineConfig(systemPrompt: prompt)
    }

    /// Timeout configuration for pipeline stages
    public struct PipelineTimeouts {
        /// Timeout for transcription (default: 30 seconds)
        public let transcription: TimeInterval

        /// Timeout for LLM generation (default: 60 seconds)
        public let llmGeneration: TimeInterval

        /// Timeout for text-to-speech (default: 30 seconds)
        public let textToSpeech: TimeInterval

        public init(
            transcription: TimeInterval = 30.0,
            llmGeneration: TimeInterval = 60.0,
            textToSpeech: TimeInterval = 30.0
        ) {
            self.transcription = transcription
            self.llmGeneration = llmGeneration
            self.textToSpeech = textToSpeech
        }
    }
}
