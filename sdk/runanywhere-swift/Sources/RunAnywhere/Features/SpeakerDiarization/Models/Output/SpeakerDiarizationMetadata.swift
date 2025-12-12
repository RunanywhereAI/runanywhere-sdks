//
//  SpeakerDiarizationMetadata.swift
//  RunAnywhere SDK
//
//  Metadata about diarization processing
//

import Foundation

// MARK: - Diarization Metadata

/// Metadata about the diarization processing
public struct SpeakerDiarizationMetadata: Sendable {

    /// Time taken to process the audio
    public let processingTime: TimeInterval

    /// Length of the audio processed
    public let audioLength: TimeInterval

    /// Number of speakers detected
    public let speakerCount: Int

    /// Method used for diarization ("energy", "ml", "hybrid")
    public let method: String

    // MARK: - Initialization

    public init(
        processingTime: TimeInterval,
        audioLength: TimeInterval,
        speakerCount: Int,
        method: String
    ) {
        self.processingTime = processingTime
        self.audioLength = audioLength
        self.speakerCount = speakerCount
        self.method = method
    }
}
