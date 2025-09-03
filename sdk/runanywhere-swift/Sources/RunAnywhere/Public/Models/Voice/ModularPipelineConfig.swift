import Foundation

/// Configuration for the modular voice pipeline
/// This bridges between the old pipeline system and new component system
public struct ModularPipelineConfig: Sendable {
    public let components: Set<VoiceComponent>

    // Component parameters (using the new init parameters)
    public let vad: VADInitParameters?
    public let stt: STTInitParameters?
    public let llm: LLMInitParameters?
    public let tts: TTSInitParameters?

    // Pipeline settings
    public let enableSpeakerDiarization: Bool
    public let continuousMode: Bool

    public init(
        components: Set<VoiceComponent> = [.vad, .stt, .llm, .tts],
        vad: VADInitParameters? = nil,
        stt: STTInitParameters? = nil,
        llm: LLMInitParameters? = nil,
        tts: TTSInitParameters? = nil,
        enableSpeakerDiarization: Bool = false,
        continuousMode: Bool = false
    ) {
        self.components = components
        self.vad = vad
        self.stt = stt
        self.llm = llm
        self.tts = tts
        self.enableSpeakerDiarization = enableSpeakerDiarization
        self.continuousMode = continuousMode
    }

    /// Create from VoiceAgentInitParameters
    public init(from agentParams: VoiceAgentInitParameters) {
        self.components = [.vad, .stt, .llm, .tts]
        self.vad = agentParams.vadParameters
        self.stt = agentParams.sttParameters
        self.llm = agentParams.llmParameters
        self.tts = agentParams.ttsParameters
        self.enableSpeakerDiarization = false
        self.continuousMode = false
    }
}

/// Bridge types for backward compatibility
public typealias VADConfig = VADInitParameters
public typealias VoiceSTTConfig = STTInitParameters
public typealias VoiceLLMConfig = LLMInitParameters
public typealias VoiceTTSConfig = TTSInitParameters
