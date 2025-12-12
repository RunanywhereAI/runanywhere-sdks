//
//  SpeakerDiarizationOutput.swift
//  RunAnywhere SDK
//
//  Output from Speaker Diarization operations
//

import Foundation

// MARK: - Speaker Diarization Output

/// Output from Speaker Diarization (conforms to ComponentOutput protocol)
public struct SpeakerDiarizationOutput: ComponentOutput, Sendable {

    /// Speaker segments with timing information
    public let segments: [SpeakerDiarizationSegment]

    /// Speaker profiles with statistics
    public let speakers: [SpeakerDiarizationProfile]

    /// Labeled transcription (if STT output was provided)
    public let labeledTranscription: SpeakerDiarizationLabeledTranscription?

    /// Processing metadata
    public let metadata: SpeakerDiarizationMetadata

    /// Timestamp (required by ComponentOutput)
    public let timestamp: Date

    // MARK: - Initialization

    public init(
        segments: [SpeakerDiarizationSegment],
        speakers: [SpeakerDiarizationProfile],
        labeledTranscription: SpeakerDiarizationLabeledTranscription? = nil,
        metadata: SpeakerDiarizationMetadata,
        timestamp: Date = Date()
    ) {
        self.segments = segments
        self.speakers = speakers
        self.labeledTranscription = labeledTranscription
        self.metadata = metadata
        self.timestamp = timestamp
    }
}
