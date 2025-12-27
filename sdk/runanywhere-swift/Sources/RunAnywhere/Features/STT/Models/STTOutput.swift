//
//  STTOutput.swift
//  RunAnywhere SDK
//
//  Output model from Speech-to-Text
//

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
