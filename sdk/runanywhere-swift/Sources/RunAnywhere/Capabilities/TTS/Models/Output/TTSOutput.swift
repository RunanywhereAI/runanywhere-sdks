//
//  TTSOutput.swift
//  RunAnywhere SDK
//
//  Output model for Text-to-Speech operations
//

import Foundation

/// Output from Text-to-Speech synthesis
///
/// Conforms to ComponentOutput protocol for integration with the SDK's component system.
public struct TTSOutput: ComponentOutput, Sendable {

    // MARK: - Properties

    /// Synthesized audio data
    public let audioData: Data

    /// Audio format of the output
    public let format: AudioFormat

    /// Duration of the audio in seconds
    public let duration: TimeInterval

    /// Phoneme timestamps if available
    public let phonemeTimestamps: [TTSPhonemeTimestamp]?

    /// Processing metadata
    public let metadata: TTSSynthesisMetadata

    /// Timestamp (required by ComponentOutput)
    public let timestamp: Date

    // MARK: - Initialization

    public init(
        audioData: Data,
        format: AudioFormat,
        duration: TimeInterval,
        phonemeTimestamps: [TTSPhonemeTimestamp]? = nil,
        metadata: TTSSynthesisMetadata,
        timestamp: Date = Date()
    ) {
        self.audioData = audioData
        self.format = format
        self.duration = duration
        self.phonemeTimestamps = phonemeTimestamps
        self.metadata = metadata
        self.timestamp = timestamp
    }

    // MARK: - Computed Properties

    /// Audio size in bytes
    public var audioSizeBytes: Int {
        audioData.count
    }

    /// Whether the output has phoneme timing information
    public var hasPhonemeTimestamps: Bool {
        phonemeTimestamps != nil && !phonemeTimestamps!.isEmpty
    }
}

// MARK: - Supporting Types

/// Synthesis metadata
public struct TTSSynthesisMetadata: Sendable {
    /// Voice used for synthesis
    public let voice: String

    /// Language used for synthesis
    public let language: String

    /// Processing time in seconds
    public let processingTime: TimeInterval

    /// Number of characters synthesized
    public let characterCount: Int

    /// Characters processed per second
    public var charactersPerSecond: Double {
        processingTime > 0 ? Double(characterCount) / processingTime : 0
    }

    public init(
        voice: String,
        language: String,
        processingTime: TimeInterval,
        characterCount: Int
    ) {
        self.voice = voice
        self.language = language
        self.processingTime = processingTime
        self.characterCount = characterCount
    }
}

/// Phoneme timestamp information
public struct TTSPhonemeTimestamp: Sendable {
    /// The phoneme
    public let phoneme: String

    /// Start time in seconds
    public let startTime: TimeInterval

    /// End time in seconds
    public let endTime: TimeInterval

    /// Duration of the phoneme
    public var duration: TimeInterval {
        endTime - startTime
    }

    public init(phoneme: String, startTime: TimeInterval, endTime: TimeInterval) {
        self.phoneme = phoneme
        self.startTime = startTime
        self.endTime = endTime
    }
}
