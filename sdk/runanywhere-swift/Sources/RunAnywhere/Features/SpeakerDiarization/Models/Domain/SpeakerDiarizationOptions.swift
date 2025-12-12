//
//  SpeakerDiarizationOptions.swift
//  RunAnywhere SDK
//
//  Runtime options for Speaker Diarization operations
//

import Foundation

// MARK: - Speaker Diarization Options

/// Runtime options for speaker diarization operations
public struct SpeakerDiarizationOptions: Sendable {

    /// Maximum number of speakers to detect
    public let maxSpeakers: Int

    /// Minimum speech duration to consider (seconds)
    public let minSpeechDuration: TimeInterval

    /// Threshold for detecting speaker changes (0.0-1.0)
    public let speakerChangeThreshold: Float

    // MARK: - Initialization

    public init(
        maxSpeakers: Int = 10,
        minSpeechDuration: TimeInterval = 0.5,
        speakerChangeThreshold: Float = 0.7
    ) {
        self.maxSpeakers = maxSpeakers
        self.minSpeechDuration = minSpeechDuration
        self.speakerChangeThreshold = speakerChangeThreshold
    }
}
