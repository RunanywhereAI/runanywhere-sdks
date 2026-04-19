//
//  STTTypes.swift
//  RunAnywhere SDK
//
//  Public types for Speech-to-Text transcription.
//  These are thin wrappers over C++ types in rac_stt_types.h
//

import CRACommons
import Foundation

// MARK: - STT Configuration

/// Configuration for STT component
public struct STTConfiguration: ComponentConfiguration, Sendable {
    /// Component type
    public var componentType: SDKComponent { .stt }

    /// Model ID
    public let modelId: String?

    // Model parameters
    public let language: String
    public let sampleRate: Int
    public let enablePunctuation: Bool
    public let enableDiarization: Bool
    public let vocabularyList: [String]
    public let maxAlternatives: Int
    public let enableTimestamps: Bool

    public init(
        modelId: String? = nil,
        language: String = "en-US",
        sampleRate: Int = Int(RAC_STT_DEFAULT_SAMPLE_RATE),
        enablePunctuation: Bool = true,
        enableDiarization: Bool = false,
        vocabularyList: [String] = [],
        maxAlternatives: Int = 1,
        enableTimestamps: Bool = true
    ) {
        self.modelId = modelId
        self.language = language
        self.sampleRate = sampleRate
        self.enablePunctuation = enablePunctuation
        self.enableDiarization = enableDiarization
        self.vocabularyList = vocabularyList
        self.maxAlternatives = maxAlternatives
        self.enableTimestamps = enableTimestamps
    }

    public func validate() throws {
        guard sampleRate > 0 && sampleRate <= 48000 else {
            throw SDKError.general(.validationFailed, "Sample rate must be between 1 and 48000 Hz")
        }
        guard maxAlternatives > 0 && maxAlternatives <= 10 else {
            throw SDKError.general(.validationFailed, "Max alternatives must be between 1 and 10")
        }
    }
}

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

// MARK: - STT Output

/// Output from Speech-to-Text (conforms to ComponentOutput protocol)
public struct STTOutput: ComponentOutput {
    /// Transcribed text
    public let text: String

    /// Confidence score (0.0 to 1.0)
    public let confidence: Float

    /// Word-level timestamps if available
    public let wordTimestamps: [WordTimestamp]?

    /// Detected language if auto-detected
    public let detectedLanguage: String?

    /// Alternative transcriptions if available
    public let alternatives: [TranscriptionAlternative]?

    /// Processing metadata
    public let metadata: TranscriptionMetadata

    /// Timestamp (required by ComponentOutput)
    public let timestamp: Date

    public init(
        text: String,
        confidence: Float,
        wordTimestamps: [WordTimestamp]? = nil,
        detectedLanguage: String? = nil,
        alternatives: [TranscriptionAlternative]? = nil,
        metadata: TranscriptionMetadata,
        timestamp: Date = Date()
    ) {
        self.text = text
        self.confidence = confidence
        self.wordTimestamps = wordTimestamps
        self.detectedLanguage = detectedLanguage
        self.alternatives = alternatives
        self.metadata = metadata
        self.timestamp = timestamp
    }

    // MARK: - C++ Bridge (rac_stt_output_t)

    /// Initialize from C++ rac_stt_output_t
    public init(from cOutput: rac_stt_output_t) {
        // Convert word timestamps
        var wordTimestamps: [WordTimestamp]?
        if cOutput.num_word_timestamps > 0, let cWords = cOutput.word_timestamps {
            wordTimestamps = (0..<cOutput.num_word_timestamps).compactMap { i in
                let cWord = cWords[Int(i)]
                guard let text = cWord.text else { return nil }
                return WordTimestamp(
                    word: String(cString: text),
                    startTime: TimeInterval(cWord.start_ms) / 1000.0,
                    endTime: TimeInterval(cWord.end_ms) / 1000.0,
                    confidence: cWord.confidence
                )
            }
        }

        // Convert alternatives
        var alternatives: [TranscriptionAlternative]?
        if cOutput.num_alternatives > 0, let cAlts = cOutput.alternatives {
            alternatives = (0..<cOutput.num_alternatives).compactMap { i in
                let cAlt = cAlts[Int(i)]
                guard let text = cAlt.text else { return nil }
                return TranscriptionAlternative(
                    text: String(cString: text),
                    confidence: cAlt.confidence
                )
            }
        }

        // Convert metadata
        let metadata = TranscriptionMetadata(
            modelId: cOutput.metadata.model_id.map { String(cString: $0) } ?? "unknown",
            processingTime: TimeInterval(cOutput.metadata.processing_time_ms) / 1000.0,
            audioLength: TimeInterval(cOutput.metadata.audio_length_ms) / 1000.0
        )

        self.init(
            text: cOutput.text.map { String(cString: $0) } ?? "",
            confidence: cOutput.confidence,
            wordTimestamps: wordTimestamps,
            detectedLanguage: cOutput.detected_language.map { String(cString: $0) },
            alternatives: alternatives,
            metadata: metadata,
            timestamp: Date(timeIntervalSince1970: TimeInterval(cOutput.timestamp_ms) / 1000.0)
        )
    }
}

// MARK: - Supporting Types

/// Transcription metadata
public struct TranscriptionMetadata: Sendable {
    public let modelId: String
    public let processingTime: TimeInterval
    public let audioLength: TimeInterval
    public let realTimeFactor: Double // Processing time / audio length

    public init(
        modelId: String,
        processingTime: TimeInterval,
        audioLength: TimeInterval
    ) {
        self.modelId = modelId
        self.processingTime = processingTime
        self.audioLength = audioLength
        self.realTimeFactor = audioLength > 0 ? processingTime / audioLength : 0
    }
}

/// Word timestamp information
public struct WordTimestamp: Sendable {
    public let word: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let confidence: Float

    public init(word: String, startTime: TimeInterval, endTime: TimeInterval, confidence: Float) {
        self.word = word
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
    }
}

/// Alternative transcription
public struct TranscriptionAlternative: Sendable {
    public let text: String
    public let confidence: Float

    public init(text: String, confidence: Float) {
        self.text = text
        self.confidence = confidence
    }
}

// MARK: - STT Transcription Result

/// Transcription result from service
public struct STTTranscriptionResult: Sendable {
    public let transcript: String
    public let confidence: Float?
    public let timestamps: [TimestampInfo]?
    public let language: String?
    public let alternatives: [AlternativeTranscription]?

    public init(
        transcript: String,
        confidence: Float? = nil,
        timestamps: [TimestampInfo]? = nil,
        language: String? = nil,
        alternatives: [AlternativeTranscription]? = nil
    ) {
        self.transcript = transcript
        self.confidence = confidence
        self.timestamps = timestamps
        self.language = language
        self.alternatives = alternatives
    }

    // MARK: - Nested Types

    public struct TimestampInfo: Sendable {
        public let word: String
        public let startTime: TimeInterval
        public let endTime: TimeInterval
        public let confidence: Float?

        public init(word: String, startTime: TimeInterval, endTime: TimeInterval, confidence: Float? = nil) {
            self.word = word
            self.startTime = startTime
            self.endTime = endTime
            self.confidence = confidence
        }
    }

    public struct AlternativeTranscription: Sendable {
        public let transcript: String
        public let confidence: Float

        public init(transcript: String, confidence: Float) {
            self.transcript = transcript
            self.confidence = confidence
        }
    }
}
