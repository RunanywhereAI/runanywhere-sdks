//
//  STTOptions.swift
//  RunAnywhere SDK
//
//  Options for speech-to-text transcription
//

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

    /// Preferred framework for transcription (WhisperKit, ONNX, etc.)
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
        sampleRate: Int = 16000,
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
}
