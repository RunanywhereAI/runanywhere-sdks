//
//  TTSConfiguration.swift
//  RunAnywhere SDK
//
//  Configuration for Text-to-Speech operations
//

import Foundation

/// Configuration for TTS component
///
/// Conforms to ComponentConfiguration and ComponentInitParameters protocols
/// for integration with the SDK's component system.
public struct TTSConfiguration: ComponentConfiguration, ComponentInitParameters, Sendable {

    // MARK: - ComponentInitParameters

    /// Component type
    public var componentType: SDKComponent { .tts }

    /// Model ID (voice identifier for TTS)
    public let modelId: String?

    // MARK: - TTS-Specific Properties

    /// Voice identifier to use for synthesis
    public let voice: String

    /// Language for synthesis (BCP-47 format, e.g., "en-US")
    public let language: String

    /// Speaking rate (0.5 to 2.0, 1.0 is normal)
    public let speakingRate: Float

    /// Speech pitch (0.5 to 2.0, 1.0 is normal)
    public let pitch: Float

    /// Speech volume (0.0 to 1.0)
    public let volume: Float

    /// Audio format for output
    public let audioFormat: AudioFormat

    /// Whether to use neural/premium voice if available
    public let useNeuralVoice: Bool

    /// Whether to enable SSML markup support
    public let enableSSML: Bool

    // MARK: - Initialization

    /// Initialize TTS configuration with default values
    public init(
        voice: String = "com.apple.ttsbundle.siri_female_en-US_compact",
        language: String = "en-US",
        speakingRate: Float = 1.0,
        pitch: Float = 1.0,
        volume: Float = 1.0,
        audioFormat: AudioFormat = .pcm,
        useNeuralVoice: Bool = true,
        enableSSML: Bool = false
    ) {
        self.voice = voice
        self.language = language
        self.speakingRate = speakingRate
        self.pitch = pitch
        self.volume = volume
        self.audioFormat = audioFormat
        self.useNeuralVoice = useNeuralVoice
        self.enableSSML = enableSSML
        self.modelId = nil
    }

    // MARK: - ComponentConfiguration

    public func validate() throws {
        guard speakingRate >= 0.5 && speakingRate <= 2.0 else {
            throw TTSError.invalidSpeakingRate(value: speakingRate)
        }
        guard pitch >= 0.5 && pitch <= 2.0 else {
            throw TTSError.invalidPitch(value: pitch)
        }
        guard volume >= 0.0 && volume <= 1.0 else {
            throw TTSError.invalidVolume(value: volume)
        }
    }
}

// MARK: - Builder Pattern

extension TTSConfiguration {

    /// Create configuration with builder pattern
    public static func builder(voice: String = "com.apple.ttsbundle.siri_female_en-US_compact") -> Builder {
        Builder(voice: voice)
    }

    public class Builder {
        private var voice: String
        private var language: String = "en-US"
        private var speakingRate: Float = 1.0
        private var pitch: Float = 1.0
        private var volume: Float = 1.0
        private var audioFormat: AudioFormat = .pcm
        private var useNeuralVoice: Bool = true
        private var enableSSML: Bool = false

        init(voice: String) {
            self.voice = voice
        }

        public func voice(_ voice: String) -> Builder {
            self.voice = voice
            return self
        }

        public func language(_ language: String) -> Builder {
            self.language = language
            return self
        }

        public func speakingRate(_ rate: Float) -> Builder {
            self.speakingRate = rate
            return self
        }

        public func pitch(_ pitch: Float) -> Builder {
            self.pitch = pitch
            return self
        }

        public func volume(_ volume: Float) -> Builder {
            self.volume = volume
            return self
        }

        public func audioFormat(_ format: AudioFormat) -> Builder {
            self.audioFormat = format
            return self
        }

        public func useNeuralVoice(_ enabled: Bool) -> Builder {
            self.useNeuralVoice = enabled
            return self
        }

        public func enableSSML(_ enabled: Bool) -> Builder {
            self.enableSSML = enabled
            return self
        }

        public func build() -> TTSConfiguration {
            TTSConfiguration(
                voice: voice,
                language: language,
                speakingRate: speakingRate,
                pitch: pitch,
                volume: volume,
                audioFormat: audioFormat,
                useNeuralVoice: useNeuralVoice,
                enableSSML: enableSSML
            )
        }
    }
}
