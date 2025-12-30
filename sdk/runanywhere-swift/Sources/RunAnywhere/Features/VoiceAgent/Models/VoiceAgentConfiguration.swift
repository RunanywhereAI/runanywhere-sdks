//
//  VoiceAgentConfiguration.swift
//  RunAnywhere SDK
//
//  Configuration for VoiceAgent capability
//
//  🟢 BRIDGE: Thin wrapper over C++ rac_voice_agent_config_t
//  C++ Source: include/rac/features/voice_agent/rac_voice_agent.h
//

import CRACommons
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

    // MARK: - C++ Bridge (rac_voice_agent_config_t)

    /// Execute a closure with the C++ equivalent config struct
    /// - Parameter body: Closure that receives pointer to rac_voice_agent_config_t
    /// - Returns: The result of the closure
    public func withCConfig<T>(_ body: (UnsafePointer<rac_voice_agent_config_t>) throws -> T) rethrows -> T {
        var cConfig = rac_voice_agent_config_t()

        // VAD config
        cConfig.vad_config.sample_rate = Int32(vadConfig.sampleRate)
        cConfig.vad_config.frame_length = vadConfig.frameLength
        cConfig.vad_config.energy_threshold = vadConfig.energyThreshold

        // TTS voice is always set
        return try ttsConfig.voice.withCString { ttsPtr in
            cConfig.tts_config.voice = ttsPtr

            // Handle optional model IDs for STT and LLM
            if let sttModelId = sttConfig.modelId {
                return try sttModelId.withCString { sttPtr in
                    cConfig.stt_config.model_id = sttPtr

                    if let llmModelId = llmConfig.modelId {
                        return try llmModelId.withCString { llmPtr in
                            cConfig.llm_config.model_id = llmPtr
                            return try body(&cConfig)
                        }
                    } else {
                        cConfig.llm_config.model_id = nil
                        return try body(&cConfig)
                    }
                }
            } else {
                cConfig.stt_config.model_id = nil

                if let llmModelId = llmConfig.modelId {
                    return try llmModelId.withCString { llmPtr in
                        cConfig.llm_config.model_id = llmPtr
                        return try body(&cConfig)
                    }
                } else {
                    cConfig.llm_config.model_id = nil
                    return try body(&cConfig)
                }
            }
        }
    }
}
