//
//  SpeakerDiarizationLabeledTranscription.swift
//  RunAnywhere SDK
//
//  Transcription with speaker labels
//

import Foundation

// MARK: - Labeled Transcription

/// Transcription with speaker information
public struct SpeakerDiarizationLabeledTranscription: Sendable {

    /// Labeled segments of transcription
    public let segments: [LabeledSegment]

    // MARK: - Labeled Segment

    /// A segment of transcription labeled with speaker info
    public struct LabeledSegment: Sendable {

        /// ID of the speaker
        public let speakerId: String

        /// Transcribed text
        public let text: String

        /// Start time of the segment
        public let startTime: TimeInterval

        /// End time of the segment
        public let endTime: TimeInterval

        public init(
            speakerId: String,
            text: String,
            startTime: TimeInterval,
            endTime: TimeInterval
        ) {
            self.speakerId = speakerId
            self.text = text
            self.startTime = startTime
            self.endTime = endTime
        }
    }

    // MARK: - Initialization

    public init(segments: [LabeledSegment]) {
        self.segments = segments
    }

    // MARK: - Convenience

    /// Get full transcript as formatted text with speaker labels
    public var formattedTranscript: String {
        segments.map { "[\($0.speakerId)]: \($0.text)" }.joined(separator: "\n")
    }
}
