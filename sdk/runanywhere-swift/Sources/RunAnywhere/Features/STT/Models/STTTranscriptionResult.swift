//
//  STTTranscriptionResult.swift
//  RunAnywhere SDK
//
//  Transcription result from STT service
//

import Foundation

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
