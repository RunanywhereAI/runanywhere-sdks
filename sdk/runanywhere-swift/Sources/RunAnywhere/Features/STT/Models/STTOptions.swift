//
//  STTOptions.swift
//  RunAnywhere SDK
//
//  Options for speech-to-text transcription
//
//  🟢 BRIDGE: Thin wrapper over C++ rac_stt_options_t
//  C++ Source: include/rac/features/stt/rac_stt_types.h
//

import CRACommons
import Foundation

// MARK: - STT Options

/// Options for speech-to-text transcription
public struct STTOptions: Sendable {
    /// Language code for transcription (e.g., "en", "es", "fr")
    public let language: String

    /// Whether to auto-detect the spoken language
    public let detectLanguage: Bool

    /// Enable automatic punctuation in transcription
    public let enablePunctuation: Bool

    /// Enable speaker diarization (identify different speakers)
    public let enableDiarization: Bool

    /// Maximum number of speakers to identify (requires enableDiarization)
    public let maxSpeakers: Int?

    /// Enable word-level timestamps
    public let enableTimestamps: Bool

    /// Custom vocabulary words to improve recognition
    public let vocabularyFilter: [String]

    /// Audio format of input data
    public let audioFormat: AudioFormat

    /// Sample rate of input audio (default: 16000 Hz for STT models)
    public let sampleRate: Int

    /// Preferred framework for transcription (ONNX, etc.)
    public let preferredFramework: InferenceFramework?

    public init(
        language: String = "en",
        detectLanguage: Bool = false,
        enablePunctuation: Bool = true,
        enableDiarization: Bool = false,
        maxSpeakers: Int? = nil,
        enableTimestamps: Bool = true,
        vocabularyFilter: [String] = [],
        audioFormat: AudioFormat = .pcm,
        sampleRate: Int = Int(RAC_STT_DEFAULT_SAMPLE_RATE),
        preferredFramework: InferenceFramework? = nil
    ) {
        self.language = language
        self.detectLanguage = detectLanguage
        self.enablePunctuation = enablePunctuation
        self.enableDiarization = enableDiarization
        self.maxSpeakers = maxSpeakers
        self.enableTimestamps = enableTimestamps
        self.vocabularyFilter = vocabularyFilter
        self.audioFormat = audioFormat
        self.sampleRate = sampleRate
        self.preferredFramework = preferredFramework
    }

    /// Create options with default settings for a specific language
    public static func `default`(language: String = "en") -> STTOptions {
        STTOptions(language: language)
    }

    // MARK: - C++ Bridge (rac_stt_options_t)

    /// Execute a closure with the C++ equivalent options struct
    /// - Parameter body: Closure that receives pointer to rac_stt_options_t
    /// - Returns: The result of the closure
    public func withCOptions<T>(_ body: (UnsafePointer<rac_stt_options_t>) throws -> T) rethrows -> T {
        var cOptions = rac_stt_options_t()
        cOptions.detect_language = detectLanguage ? RAC_TRUE : RAC_FALSE
        cOptions.enable_punctuation = enablePunctuation ? RAC_TRUE : RAC_FALSE
        cOptions.enable_diarization = enableDiarization ? RAC_TRUE : RAC_FALSE
        cOptions.max_speakers = Int32(maxSpeakers ?? 0)
        cOptions.enable_timestamps = enableTimestamps ? RAC_TRUE : RAC_FALSE
        cOptions.audio_format = audioFormat.toCFormat()
        cOptions.sample_rate = Int32(sampleRate)

        return try language.withCString { langPtr in
            cOptions.language = langPtr
            return try body(&cOptions)
        }
    }
}
