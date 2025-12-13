//
//  SpeakerDiarizationInput.swift
//  RunAnywhere SDK
//
//  Input model for Speaker Diarization operations
//

import Foundation

// MARK: - Speaker Diarization Input

/// Input for Speaker Diarization (conforms to ComponentInput protocol)
public struct SpeakerDiarizationInput: ComponentInput, Sendable {

    /// Audio data to diarize
    public let audioData: Data

    /// Audio format
    public let format: AudioFormat

    /// Optional transcription for labeled output
    public let transcription: STTOutput?

    /// Expected number of speakers (if known)
    public let expectedSpeakers: Int?

    /// Custom options for this operation
    public let options: SpeakerDiarizationOptions?

    // MARK: - Initialization

    public init(
        audioData: Data,
        format: AudioFormat = .wav,
        transcription: STTOutput? = nil,
        expectedSpeakers: Int? = nil,
        options: SpeakerDiarizationOptions? = nil
    ) {
        self.audioData = audioData
        self.format = format
        self.transcription = transcription
        self.expectedSpeakers = expectedSpeakers
        self.options = options
    }

    // MARK: - ComponentInput

    public func validate() throws {
        guard !audioData.isEmpty else {
            throw SpeakerDiarizationError.invalidConfiguration(reason: "Audio data cannot be empty")
        }
    }
}
