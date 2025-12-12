//
//  SpeakerDiarizationSegment.swift
//  RunAnywhere SDK
//
//  Time-stamped speaker segment
//

import Foundation

// MARK: - Speaker Segment

/// A time-stamped segment of speech from a speaker
public struct SpeakerDiarizationSegment: Sendable {

    /// ID of the speaker for this segment
    public let speakerId: String

    /// Start time of the segment (seconds)
    public let startTime: TimeInterval

    /// End time of the segment (seconds)
    public let endTime: TimeInterval

    /// Confidence score for speaker identification
    public let confidence: Float

    // MARK: - Computed Properties

    /// Duration of the segment
    public var duration: TimeInterval {
        endTime - startTime
    }

    // MARK: - Initialization

    public init(
        speakerId: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        confidence: Float
    ) {
        self.speakerId = speakerId
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
    }
}
