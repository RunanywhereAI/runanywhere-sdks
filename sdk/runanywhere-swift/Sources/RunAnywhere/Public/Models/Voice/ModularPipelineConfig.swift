import Foundation

/// Configuration for modular voice pipeline with flexible component selection
public struct ModularPipelineConfig {
    /// Which components to include in the pipeline
    public let components: Set<VoiceComponent>

    /// VAD configuration (if VAD component is included)
    public let vad: VADConfig?

    /// STT configuration (if STT component is included)
    public let stt: VoiceSTTConfig?

    /// LLM configuration (if LLM component is included)
    public let llm: VoiceLLMConfig?

    /// TTS configuration (if TTS component is included)
    public let tts: VoiceTTSConfig?

    /// Whether to enable streaming for all components
    public let streamingEnabled: Bool

    public init(
        components: Set<VoiceComponent>,
        vad: VADConfig? = nil,
        stt: VoiceSTTConfig? = nil,
        llm: VoiceLLMConfig? = nil,
        tts: VoiceTTSConfig? = nil,
        streamingEnabled: Bool = true
    ) {
        self.components = components
        self.vad = vad
        self.stt = stt
        self.llm = llm
        self.tts = tts
        self.streamingEnabled = streamingEnabled
    }

    // MARK: - Convenience Builders

    /// Just transcription (STT only)
    public static func transcriptionOnly(model: String = "whisper-base", language: String = "en") -> ModularPipelineConfig {
        return ModularPipelineConfig(
            components: [.stt],
            stt: VoiceSTTConfig(modelId: model, language: language, streamingEnabled: true)
        )
    }

    /// Transcription with VAD (VAD -> STT)
    public static func transcriptionWithVAD(
        sttModel: String = "whisper-base",
        vadThreshold: Float = 0.02
    ) -> ModularPipelineConfig {
        return ModularPipelineConfig(
            components: [.vad, .stt],
            vad: VADConfig(energyThreshold: vadThreshold),
            stt: VoiceSTTConfig(modelId: sttModel, streamingEnabled: true)
        )
    }

    /// Conversational without TTS (VAD -> STT -> LLM)
    public static func conversationalNoTTS(
        sttModel: String = "whisper-base",
        llmModel: String? = nil
    ) -> ModularPipelineConfig {
        return ModularPipelineConfig(
            components: [.vad, .stt, .llm],
            vad: VADConfig(),
            stt: VoiceSTTConfig(modelId: sttModel, streamingEnabled: true),
            llm: VoiceLLMConfig(modelId: llmModel)
        )
    }

    /// Full conversational pipeline (VAD -> STT -> LLM -> TTS)
    public static func fullPipeline(
        sttModel: String = "whisper-base",
        llmModel: String? = nil,
        ttsVoice: String = "system"
    ) -> ModularPipelineConfig {
        return ModularPipelineConfig(
            components: [.vad, .stt, .llm, .tts],
            vad: VADConfig(),
            stt: VoiceSTTConfig(modelId: sttModel, streamingEnabled: true),
            llm: VoiceLLMConfig(modelId: llmModel),
            tts: VoiceTTSConfig(voice: ttsVoice)
        )
    }
}
