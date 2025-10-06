import Foundation

// Import component configurations
import struct RunAnywhere.VADConfiguration
import struct RunAnywhere.STTConfiguration
import struct RunAnywhere.LLMConfiguration
import struct RunAnywhere.TTSConfiguration

// Import supporting types
import struct RunAnywhere.SpeakerInfo
import struct RunAnywhere.VoiceAgentResult

/// Unified configuration for all voice capabilities
public struct VoiceConfiguration {

    // MARK: - Component Configurations

    /// Voice Activity Detection configuration
    public let vad: VADConfiguration

    /// Speech-to-Text configuration
    public let stt: STTConfiguration

    /// Language Model configuration
    public let llm: LLMConfiguration

    /// Text-to-Speech configuration
    public let tts: TTSConfiguration

    /// Audio pipeline state management configuration
    public let pipeline: AudioPipelineStateManager.Configuration

    // MARK: - Feature Flags

    /// Enable speaker diarization
    public let enableSpeakerDiarization: Bool

    /// Enable streaming responses
    public let enableStreaming: Bool

    /// Enable TTS feedback prevention
    public let enableFeedbackPrevention: Bool

    /// Enable voice analytics
    public let enableAnalytics: Bool

    // MARK: - Quality Settings

    /// Audio quality settings
    public let audioQuality: AudioQuality

    /// Processing timeout settings
    public let timeouts: TimeoutConfiguration

    // MARK: - Initialization

    public init(
        vad: VADConfiguration = VADConfiguration(),
        stt: STTConfiguration = STTConfiguration(),
        llm: LLMConfiguration = LLMConfiguration(),
        tts: TTSConfiguration = TTSConfiguration(),
        pipeline: AudioPipelineStateManager.Configuration = AudioPipelineStateManager.Configuration(),
        enableSpeakerDiarization: Bool = false,
        enableStreaming: Bool = true,
        enableFeedbackPrevention: Bool = true,
        enableAnalytics: Bool = true,
        audioQuality: AudioQuality = .standard,
        timeouts: TimeoutConfiguration = TimeoutConfiguration()
    ) {
        self.vad = vad
        self.stt = stt
        self.llm = llm
        self.tts = tts
        self.pipeline = pipeline
        self.enableSpeakerDiarization = enableSpeakerDiarization
        self.enableStreaming = enableStreaming
        self.enableFeedbackPrevention = enableFeedbackPrevention
        self.enableAnalytics = enableAnalytics
        self.audioQuality = audioQuality
        self.timeouts = timeouts
    }

    // MARK: - Preset Configurations

    /// Default voice configuration optimized for general use
    public static let `default` = VoiceConfiguration()

    /// High-quality configuration for production use
    public static let highQuality = VoiceConfiguration(
        vad: VADConfiguration(energyThreshold: 0.005),
        stt: STTConfiguration(language: "en", enablePunctuation: true),
        llm: LLMConfiguration(temperature: 0.3, maxTokens: 150),
        tts: TTSConfiguration(voice: "alloy", speakingRate: 1.0),
        pipeline: AudioPipelineStateManager.Configuration(cooldownDuration: 1.0),
        enableSpeakerDiarization: true,
        enableStreaming: true,
        enableFeedbackPrevention: true,
        enableAnalytics: true,
        audioQuality: .high,
        timeouts: TimeoutConfiguration(stt: 30.0, llm: 60.0, tts: 30.0)
    )

    /// Fast configuration optimized for low latency
    public static let fast = VoiceConfiguration(
        vad: VADConfiguration(energyThreshold: 0.01),
        stt: STTConfiguration(language: "en", enablePunctuation: false),
        llm: LLMConfiguration(temperature: 0.1, maxTokens: 50),
        tts: TTSConfiguration(voice: "system", speakingRate: 1.2),
        pipeline: AudioPipelineStateManager.Configuration(cooldownDuration: 0.5),
        enableSpeakerDiarization: false,
        enableStreaming: true,
        enableFeedbackPrevention: true,
        enableAnalytics: false,
        audioQuality: .standard,
        timeouts: TimeoutConfiguration(stt: 15.0, llm: 30.0, tts: 15.0)
    )

    /// Privacy-focused configuration with minimal data collection
    public static let privacy = VoiceConfiguration(
        vad: VADConfiguration(energyThreshold: 0.01),
        stt: STTConfiguration(language: "en", enablePunctuation: true),
        llm: LLMConfiguration(temperature: 0.3, maxTokens: 100),
        tts: TTSConfiguration(voice: "system"),
        pipeline: AudioPipelineStateManager.Configuration(),
        enableSpeakerDiarization: false,
        enableStreaming: false,
        enableFeedbackPrevention: true,
        enableAnalytics: false,
        audioQuality: .standard,
        timeouts: TimeoutConfiguration()
    )
}

// MARK: - Supporting Types

/// Audio quality levels
public enum AudioQuality {
    case low
    case standard
    case high
    case lossless

    /// Sample rate for the quality level
    public var sampleRate: Int {
        switch self {
        case .low: return 8000
        case .standard: return 16000
        case .high: return 44100
        case .lossless: return 48000
        }
    }

    /// Bit depth for the quality level
    public var bitDepth: Int {
        switch self {
        case .low: return 8
        case .standard: return 16
        case .high: return 16
        case .lossless: return 24
        }
    }
}

/// Timeout configuration for various operations
public struct TimeoutConfiguration {
    /// Speech-to-text processing timeout (seconds)
    public let stt: TimeInterval

    /// Language model generation timeout (seconds)
    public let llm: TimeInterval

    /// Text-to-speech synthesis timeout (seconds)
    public let tts: TimeInterval

    /// Overall pipeline timeout (seconds)
    public let pipeline: TimeInterval

    public init(
        stt: TimeInterval = 30.0,
        llm: TimeInterval = 60.0,
        tts: TimeInterval = 30.0,
        pipeline: TimeInterval = 180.0
    ) {
        self.stt = stt
        self.llm = llm
        self.tts = tts
        self.pipeline = pipeline
    }
}

// MARK: - Configuration Validation

public extension VoiceConfiguration {
    /// Validate the configuration for consistency and compatibility
    func validate() throws {
        // Validate timeout values
        guard timeouts.stt > 0, timeouts.llm > 0, timeouts.tts > 0, timeouts.pipeline > 0 else {
            throw SDKError.invalidConfiguration("Timeout values must be positive")
        }

        // Validate pipeline timeout is sufficient for component timeouts
        let totalComponentTime = timeouts.stt + timeouts.llm + timeouts.tts
        guard timeouts.pipeline >= totalComponentTime else {
            throw SDKError.invalidConfiguration("Pipeline timeout must be at least the sum of component timeouts")
        }

        // Validate cooldown duration
        guard pipeline.cooldownDuration >= 0 else {
            throw SDKError.invalidConfiguration("Cooldown duration must be non-negative")
        }

        // Validate VAD threshold
        guard vad.energyThreshold >= 0 && vad.energyThreshold <= 1.0 else {
            throw SDKError.invalidConfiguration("VAD energy threshold must be between 0 and 1")
        }

        // Validate LLM parameters
        guard llm.temperature >= 0 && llm.temperature <= 2.0 else {
            throw SDKError.invalidConfiguration("LLM temperature must be between 0 and 2")
        }

        guard llm.maxTokens > 0 else {
            throw SDKError.invalidConfiguration("LLM max tokens must be positive")
        }

        // Validate TTS parameters
        guard tts.speakingRate > 0 && tts.speakingRate <= 3.0 else {
            throw SDKError.invalidConfiguration("TTS speaking rate must be between 0 and 3")
        }
    }
}

// MARK: - Builder Pattern

/// Builder for creating voice configurations with fluent API
public final class VoiceConfigurationBuilder {
    private var configuration = VoiceConfiguration()

    public init() {}

    // MARK: - Component Configuration

    public func vad(_ config: VADConfiguration) -> VoiceConfigurationBuilder {
        configuration = configuration.with(vad: config)
        return self
    }

    public func stt(_ config: STTConfiguration) -> VoiceConfigurationBuilder {
        configuration = configuration.with(stt: config)
        return self
    }

    public func llm(_ config: LLMConfiguration) -> VoiceConfigurationBuilder {
        configuration = configuration.with(llm: config)
        return self
    }

    public func tts(_ config: TTSConfiguration) -> VoiceConfigurationBuilder {
        configuration = configuration.with(tts: config)
        return self
    }

    // MARK: - Feature Flags

    public func enableSpeakerDiarization(_ enabled: Bool = true) -> VoiceConfigurationBuilder {
        configuration = configuration.with(enableSpeakerDiarization: enabled)
        return self
    }

    public func enableStreaming(_ enabled: Bool = true) -> VoiceConfigurationBuilder {
        configuration = configuration.with(enableStreaming: enabled)
        return self
    }

    public func audioQuality(_ quality: AudioQuality) -> VoiceConfigurationBuilder {
        configuration = configuration.with(audioQuality: quality)
        return self
    }

    // MARK: - Build

    public func build() throws -> VoiceConfiguration {
        try configuration.validate()
        return configuration
    }
}

// MARK: - Copy-on-Write Methods

extension VoiceConfiguration {
    func with(vad: VADConfiguration) -> VoiceConfiguration {
        return VoiceConfiguration(
            vad: vad, stt: self.stt, llm: self.llm, tts: self.tts, pipeline: self.pipeline,
            enableSpeakerDiarization: self.enableSpeakerDiarization, enableStreaming: self.enableStreaming,
            enableFeedbackPrevention: self.enableFeedbackPrevention, enableAnalytics: self.enableAnalytics,
            audioQuality: self.audioQuality, timeouts: self.timeouts
        )
    }

    func with(stt: STTConfiguration) -> VoiceConfiguration {
        return VoiceConfiguration(
            vad: self.vad, stt: stt, llm: self.llm, tts: self.tts, pipeline: self.pipeline,
            enableSpeakerDiarization: self.enableSpeakerDiarization, enableStreaming: self.enableStreaming,
            enableFeedbackPrevention: self.enableFeedbackPrevention, enableAnalytics: self.enableAnalytics,
            audioQuality: self.audioQuality, timeouts: self.timeouts
        )
    }

    func with(llm: LLMConfiguration) -> VoiceConfiguration {
        return VoiceConfiguration(
            vad: self.vad, stt: self.stt, llm: llm, tts: self.tts, pipeline: self.pipeline,
            enableSpeakerDiarization: self.enableSpeakerDiarization, enableStreaming: self.enableStreaming,
            enableFeedbackPrevention: self.enableFeedbackPrevention, enableAnalytics: self.enableAnalytics,
            audioQuality: self.audioQuality, timeouts: self.timeouts
        )
    }

    func with(tts: TTSConfiguration) -> VoiceConfiguration {
        return VoiceConfiguration(
            vad: self.vad, stt: self.stt, llm: self.llm, tts: tts, pipeline: self.pipeline,
            enableSpeakerDiarization: self.enableSpeakerDiarization, enableStreaming: self.enableStreaming,
            enableFeedbackPrevention: self.enableFeedbackPrevention, enableAnalytics: self.enableAnalytics,
            audioQuality: self.audioQuality, timeouts: self.timeouts
        )
    }

    func with(enableSpeakerDiarization: Bool) -> VoiceConfiguration {
        return VoiceConfiguration(
            vad: self.vad, stt: self.stt, llm: self.llm, tts: self.tts, pipeline: self.pipeline,
            enableSpeakerDiarization: enableSpeakerDiarization, enableStreaming: self.enableStreaming,
            enableFeedbackPrevention: self.enableFeedbackPrevention, enableAnalytics: self.enableAnalytics,
            audioQuality: self.audioQuality, timeouts: self.timeouts
        )
    }

    func with(enableStreaming: Bool) -> VoiceConfiguration {
        return VoiceConfiguration(
            vad: self.vad, stt: self.stt, llm: self.llm, tts: self.tts, pipeline: self.pipeline,
            enableSpeakerDiarization: self.enableSpeakerDiarization, enableStreaming: enableStreaming,
            enableFeedbackPrevention: self.enableFeedbackPrevention, enableAnalytics: self.enableAnalytics,
            audioQuality: self.audioQuality, timeouts: self.timeouts
        )
    }

    func with(audioQuality: AudioQuality) -> VoiceConfiguration {
        return VoiceConfiguration(
            vad: self.vad, stt: self.stt, llm: self.llm, tts: self.tts, pipeline: self.pipeline,
            enableSpeakerDiarization: self.enableSpeakerDiarization, enableStreaming: self.enableStreaming,
            enableFeedbackPrevention: self.enableFeedbackPrevention, enableAnalytics: self.enableAnalytics,
            audioQuality: audioQuality, timeouts: self.timeouts
        )
    }
}
