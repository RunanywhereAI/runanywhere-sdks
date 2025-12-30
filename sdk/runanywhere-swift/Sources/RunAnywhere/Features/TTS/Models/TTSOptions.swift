//
//  TTSOptions.swift
//  RunAnywhere SDK
//
//  Options for text-to-speech synthesis operations
//
//  🟢 BRIDGE: Thin wrapper over C++ rac_tts_options_t
//  C++ Source: include/rac/features/tts/rac_tts_types.h
//

import CRACommons
import Foundation

/// Options for text-to-speech synthesis
///
/// These options can be passed to individual synthesis calls to override
/// the default configuration settings.
public struct TTSOptions: Sendable {

    // MARK: - Properties

    /// Voice to use for synthesis (nil uses default)
    public let voice: String?

    /// Language for synthesis (BCP-47 format, e.g., "en-US")
    public let language: String

    /// Speech rate (0.0 to 2.0, 1.0 is normal)
    public let rate: Float

    /// Speech pitch (0.0 to 2.0, 1.0 is normal)
    public let pitch: Float

    /// Speech volume (0.0 to 1.0)
    public let volume: Float

    /// Audio format for output
    public let audioFormat: AudioFormat

    /// Sample rate for output audio in Hz
    public let sampleRate: Int

    /// Whether to use SSML markup
    public let useSSML: Bool

    // MARK: - Initialization

    public init(
        voice: String? = nil,
        language: String = "en-US",
        rate: Float = 1.0,
        pitch: Float = 1.0,
        volume: Float = 1.0,
        audioFormat: AudioFormat = .pcm,
        sampleRate: Int = Int(RAC_TTS_DEFAULT_SAMPLE_RATE),
        useSSML: Bool = false
    ) {
        self.voice = voice
        self.language = language
        self.rate = rate
        self.pitch = pitch
        self.volume = volume
        self.audioFormat = audioFormat
        self.sampleRate = sampleRate
        self.useSSML = useSSML
    }

    // MARK: - Factory Methods

    /// Create options from TTSConfiguration
    public static func from(configuration: TTSConfiguration) -> TTSOptions {
        TTSOptions(
            voice: configuration.voice,
            language: configuration.language,
            rate: configuration.speakingRate,
            pitch: configuration.pitch,
            volume: configuration.volume,
            audioFormat: configuration.audioFormat,
            sampleRate: configuration.audioFormat == .pcm ? Int(RAC_TTS_DEFAULT_SAMPLE_RATE) : Int(RAC_TTS_CD_QUALITY_SAMPLE_RATE),
            useSSML: configuration.enableSSML
        )
    }

    /// Default options
    public static var `default`: TTSOptions {
        TTSOptions()
    }

    // MARK: - C++ Bridge (rac_tts_options_t)

    /// Execute a closure with the C++ equivalent options struct
    /// - Parameter body: Closure that receives pointer to rac_tts_options_t
    /// - Returns: The result of the closure
    public func withCOptions<T>(_ body: (UnsafePointer<rac_tts_options_t>) throws -> T) rethrows -> T {
        var cOptions = rac_tts_options_t()
        cOptions.rate = rate
        cOptions.pitch = pitch
        cOptions.volume = volume
        cOptions.audio_format = audioFormat.toCFormat()
        cOptions.sample_rate = Int32(sampleRate)
        cOptions.use_ssml = useSSML ? RAC_TRUE : RAC_FALSE

        return try language.withCString { langPtr in
            cOptions.language = langPtr

            if let voice = voice {
                return try voice.withCString { voicePtr in
                    cOptions.voice = voicePtr
                    return try body(&cOptions)
                }
            } else {
                cOptions.voice = nil
                return try body(&cOptions)
            }
        }
    }
}
