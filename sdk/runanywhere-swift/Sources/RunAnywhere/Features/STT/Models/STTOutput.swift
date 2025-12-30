//
//  STTOutput.swift
//  RunAnywhere SDK
//
//  Output model from Speech-to-Text
//
//  🟢 BRIDGE: Thin wrapper over C++ rac_stt_output_t
//  C++ Source: include/rac/features/stt/rac_stt_types.h
//

import CRACommons
import Foundation

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
    /// - Parameter cOutput: The C++ output struct
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
