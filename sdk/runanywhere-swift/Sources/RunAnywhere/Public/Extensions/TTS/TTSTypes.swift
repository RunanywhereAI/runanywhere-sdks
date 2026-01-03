//
//  TTSTypes.swift
//  RunAnywhere SDK
//
//  Public types for Text-to-Speech synthesis.
//  These are thin wrappers over C++ types in rac_tts_types.h
//

import CRACommons
import Foundation

// MARK: - TTS Configuration

/// Configuration for TTS component
public struct TTSConfiguration: ComponentConfiguration, Sendable {

    // MARK: - ComponentConfiguration

    /// Component type
    public var componentType: SDKComponent { .tts }

    /// Model ID (voice identifier for TTS)
    public let modelId: String?

    /// Preferred framework (uses default extension implementation)
    public var preferredFramework: InferenceFramework? { nil }

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

    // MARK: - Validation

    public func validate() throws {
        guard speakingRate >= 0.5 && speakingRate <= 2.0 else {
            throw SDKError.tts(.invalidSpeakingRate, "Invalid speaking rate: \(speakingRate). Must be between 0.5 and 2.0.")
        }
        guard pitch >= 0.5 && pitch <= 2.0 else {
            throw SDKError.tts(.invalidPitch, "Invalid pitch: \(pitch). Must be between 0.5 and 2.0.")
        }
        guard volume >= 0.0 && volume <= 1.0 else {
            throw SDKError.tts(.invalidVolume, "Invalid volume: \(volume). Must be between 0.0 and 1.0.")
        }
    }
}

// MARK: - TTSConfiguration Builder

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

// MARK: - TTS Options

/// Options for text-to-speech synthesis
public struct TTSOptions: Sendable {

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

// MARK: - TTS Output

/// Output from Text-to-Speech synthesis
public struct TTSOutput: ComponentOutput, Sendable {

    /// Synthesized audio data
    public let audioData: Data

    /// Audio format of the output
    public let format: AudioFormat

    /// Duration of the audio in seconds
    public let duration: TimeInterval

    /// Phoneme timestamps if available
    public let phonemeTimestamps: [TTSPhonemeTimestamp]?

    /// Processing metadata
    public let metadata: TTSSynthesisMetadata

    /// Timestamp (required by ComponentOutput)
    public let timestamp: Date

    public init(
        audioData: Data,
        format: AudioFormat,
        duration: TimeInterval,
        phonemeTimestamps: [TTSPhonemeTimestamp]? = nil,
        metadata: TTSSynthesisMetadata,
        timestamp: Date = Date()
    ) {
        self.audioData = audioData
        self.format = format
        self.duration = duration
        self.phonemeTimestamps = phonemeTimestamps
        self.metadata = metadata
        self.timestamp = timestamp
    }

    /// Audio size in bytes
    public var audioSizeBytes: Int {
        audioData.count
    }

    /// Whether the output has phoneme timing information
    public var hasPhonemeTimestamps: Bool {
        guard let timestamps = phonemeTimestamps else { return false }
        return !timestamps.isEmpty
    }

    // MARK: - C++ Bridge (rac_tts_output_t)

    /// Initialize from C++ rac_tts_output_t
    public init(from cOutput: rac_tts_output_t) {
        // Convert audio data
        let audioData: Data
        if cOutput.audio_size > 0, let dataPtr = cOutput.audio_data {
            audioData = Data(bytes: dataPtr, count: cOutput.audio_size)
        } else {
            audioData = Data()
        }

        // Convert audio format
        let format = AudioFormat(from: cOutput.format)

        // Convert phoneme timestamps
        var phonemeTimestamps: [TTSPhonemeTimestamp]?
        if cOutput.num_phoneme_timestamps > 0, let cPhonemes = cOutput.phoneme_timestamps {
            phonemeTimestamps = (0..<cOutput.num_phoneme_timestamps).compactMap { i in
                let cPhoneme = cPhonemes[Int(i)]
                guard let phoneme = cPhoneme.phoneme else { return nil }
                return TTSPhonemeTimestamp(
                    phoneme: String(cString: phoneme),
                    startTime: TimeInterval(cPhoneme.start_time_ms) / 1000.0,
                    endTime: TimeInterval(cPhoneme.end_time_ms) / 1000.0
                )
            }
        }

        // Convert metadata
        let metadata = TTSSynthesisMetadata(
            voice: cOutput.metadata.voice.map { String(cString: $0) } ?? "unknown",
            language: cOutput.metadata.language.map { String(cString: $0) } ?? "en-US",
            processingTime: TimeInterval(cOutput.metadata.processing_time_ms) / 1000.0,
            characterCount: Int(cOutput.metadata.character_count)
        )

        self.init(
            audioData: audioData,
            format: format,
            duration: TimeInterval(cOutput.duration_ms) / 1000.0,
            phonemeTimestamps: phonemeTimestamps,
            metadata: metadata,
            timestamp: Date(timeIntervalSince1970: TimeInterval(cOutput.timestamp_ms) / 1000.0)
        )
    }
}

// MARK: - Supporting Types

/// Synthesis metadata
public struct TTSSynthesisMetadata: Sendable {
    /// Voice used for synthesis
    public let voice: String

    /// Language used for synthesis
    public let language: String

    /// Processing time in seconds
    public let processingTime: TimeInterval

    /// Number of characters synthesized
    public let characterCount: Int

    /// Characters processed per second
    public var charactersPerSecond: Double {
        processingTime > 0 ? Double(characterCount) / processingTime : 0
    }

    public init(
        voice: String,
        language: String,
        processingTime: TimeInterval,
        characterCount: Int
    ) {
        self.voice = voice
        self.language = language
        self.processingTime = processingTime
        self.characterCount = characterCount
    }
}

/// Phoneme timestamp information
public struct TTSPhonemeTimestamp: Sendable {
    /// The phoneme
    public let phoneme: String

    /// Start time in seconds
    public let startTime: TimeInterval

    /// End time in seconds
    public let endTime: TimeInterval

    /// Duration of the phoneme
    public var duration: TimeInterval {
        endTime - startTime
    }

    public init(phoneme: String, startTime: TimeInterval, endTime: TimeInterval) {
        self.phoneme = phoneme
        self.startTime = startTime
        self.endTime = endTime
    }
}

// MARK: - Speak Result

/// Result from `speak()` - contains metadata only, no audio data.
public struct TTSSpeakResult: Sendable {

    /// Duration of the spoken audio in seconds
    public let duration: TimeInterval

    /// Audio format used
    public let format: AudioFormat

    /// Audio size in bytes (0 for system TTS which plays directly)
    public let audioSizeBytes: Int

    /// Synthesis metadata (voice, language, processing time, etc.)
    public let metadata: TTSSynthesisMetadata

    /// Timestamp when speech completed
    public let timestamp: Date

    public init(
        duration: TimeInterval,
        format: AudioFormat,
        audioSizeBytes: Int,
        metadata: TTSSynthesisMetadata,
        timestamp: Date = Date()
    ) {
        self.duration = duration
        self.format = format
        self.audioSizeBytes = audioSizeBytes
        self.metadata = metadata
        self.timestamp = timestamp
    }

    /// Create from TTSOutput (internal use)
    internal init(from output: TTSOutput) {
        self.duration = output.duration
        self.format = output.format
        self.audioSizeBytes = output.audioSizeBytes
        self.metadata = output.metadata
        self.timestamp = output.timestamp
    }
}
