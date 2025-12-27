//
//  VoiceAgentConfiguration.swift
//  RunAnywhere SDK
//
//  Configuration for VoiceAgent capability
//

import Foundation

/// Configuration for the voice agent
/// Combines configurations from all composed capabilities (VAD, STT, LLM, TTS)
public struct VoiceAgentConfiguration: Sendable {
    /// VAD configuration
    public let vadConfig: VADConfiguration

    /// STT configuration
    public let sttConfig: STTConfiguration

    /// LLM configuration
    public let llmConfig: LLMConfiguration

    /// TTS configuration
    public let ttsConfig: TTSConfiguration

    /// Initialize with individual configurations
    public init(
        vadConfig: VADConfiguration = VADConfiguration(),
        sttConfig: STTConfiguration = STTConfiguration(),
        llmConfig: LLMConfiguration = LLMConfiguration(),
        ttsConfig: TTSConfiguration = TTSConfiguration()
    ) {
        self.vadConfig = vadConfig
        self.sttConfig = sttConfig
        self.llmConfig = llmConfig
        self.ttsConfig = ttsConfig
    }

    /// Create configuration with just model IDs
    public static func with(
        sttModelId: String,
        llmModelId: String,
        ttsVoice: String = "com.apple.ttsbundle.siri_female_en-US_compact"
    ) -> VoiceAgentConfiguration {
        VoiceAgentConfiguration(
            vadConfig: VADConfiguration(),
            sttConfig: STTConfiguration(modelId: sttModelId),
            llmConfig: LLMConfiguration(modelId: llmModelId),
            ttsConfig: TTSConfiguration(voice: ttsVoice)
        )
    }
}
