//
//  STTResult.swift
//  RunAnywhere SDK
//
//  Result types from speech-to-text transcription
//

import Foundation

// MARK: - STT Result

/// Result from speech-to-text transcription
public struct STTResult: Sendable {
    public let text: String
    public let segments: [STTSegment]
    public let language: String?
    public let confidence: Float
    public let duration: TimeInterval
    public let alternatives: [STTAlternative]

    public init(
        text: String,
        segments: [STTSegment] = [],
        language: String? = nil,
        confidence: Float = 1.0,
        duration: TimeInterval = 0,
        alternatives: [STTAlternative] = []
    ) {
        self.text = text
        self.segments = segments
        self.language = language
        self.confidence = confidence
        self.duration = duration
        self.alternatives = alternatives
    }
}

// MARK: - STT Segment

/// A segment of transcribed text with timing
public struct STTSegment: Sendable {
    public let text: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let confidence: Float
    public let speaker: Int?

    public init(
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        confidence: Float = 1.0,
        speaker: Int? = nil
    ) {
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
        self.speaker = speaker
    }
}

// MARK: - STT Alternative

/// Alternative transcription result
public struct STTAlternative: Sendable {
    public let text: String
    public let confidence: Float

    public init(text: String, confidence: Float) {
        self.text = text
        self.confidence = confidence
    }
}
