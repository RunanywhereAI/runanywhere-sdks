import Foundation

// MARK: - Type Alias

/// Type alias to help with type inference
public typealias PipelineEventStream = AsyncThrowingStream<ModularPipelineEvent, Error>

// MARK: - Modular Pipeline Configuration

/// Configuration for the modular voice pipeline
public struct ModularPipelineConfig {
    public let components: [SDKComponent]
    public let vadConfig: VADConfiguration?
    public let sttConfig: STTConfiguration?
    public let llmConfig: LLMConfiguration?
    public let ttsConfig: TTSConfiguration?

    public init(
        components: [SDKComponent],
        vadConfig: VADConfiguration? = nil,
        sttConfig: STTConfiguration? = nil,
        llmConfig: LLMConfiguration? = nil,
        ttsConfig: TTSConfiguration? = nil
    ) {
        self.components = components
        self.vadConfig = vadConfig
        self.sttConfig = sttConfig
        self.llmConfig = llmConfig
        self.ttsConfig = ttsConfig
    }

    /// Convenience initializer with simplified parameters
    public init(
        components: [SDKComponent],
        vad: VADConfig? = nil,
        stt: VoiceSTTConfig? = nil,
        llm: VoiceLLMConfig? = nil,
        tts: VoiceTTSConfig? = nil
    ) {
        self.components = components

        // Convert simplified configs to full configurations
        self.vadConfig = vad.map { VADConfiguration(energyThreshold: $0.energyThreshold) }
        self.sttConfig = stt.map { STTConfiguration(modelId: $0.modelId, language: $0.language) }
        self.llmConfig = llm.map {
            LLMConfiguration(
                modelId: $0.modelId,
                temperature: 0.3,  // Lower temperature for more consistent responses
                maxTokens: $0.maxTokens ?? 100,  // Use provided or default to 100
                systemPrompt: $0.systemPrompt,
                streamingEnabled: true  // Enable streaming for real-time feedback
            )
        }
        self.ttsConfig = tts.map { TTSConfiguration(voice: $0.voice) }
    }

    /// Create a configuration for transcription with VAD
    public static func transcriptionWithVAD(
        sttModel: String = "whisper-base",
        vadThreshold: Float = 0.01
    ) -> ModularPipelineConfig {
        return ModularPipelineConfig(
            components: [.vad, .stt],
            vad: VADConfig(energyThreshold: vadThreshold),
            stt: VoiceSTTConfig(modelId: sttModel, language: "en")
        )
    }
}

// MARK: - Simplified Configuration Types

/// Simplified VAD configuration
public struct VADConfig {
    public let energyThreshold: Float

    public init(energyThreshold: Float = 0.01) {
        self.energyThreshold = energyThreshold
    }
}

/// Simplified STT configuration for voice
public struct VoiceSTTConfig {
    public let modelId: String
    public let language: String

    public init(modelId: String = "whisper-base", language: String = "en") {
        self.modelId = modelId
        self.language = language
    }
}

/// Simplified LLM configuration for voice
public struct VoiceLLMConfig {
    public let modelId: String
    public let systemPrompt: String?
    public let maxTokens: Int?  // Optional - let model decide if not specified

    public init(modelId: String, systemPrompt: String? = nil, maxTokens: Int? = nil) {
        self.modelId = modelId
        self.systemPrompt = systemPrompt
        self.maxTokens = maxTokens
    }
}

/// Simplified TTS configuration for voice
public struct VoiceTTSConfig {
    public let voice: String

    public init(voice: String = "system") {
        self.voice = voice
    }
}
