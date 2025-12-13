//
//  SpeakerDiarizationProfile.swift
//  RunAnywhere SDK
//
//  Speaker profile with statistics
//

import Foundation

// MARK: - Speaker Profile

/// Profile of a speaker with statistics
public struct SpeakerDiarizationProfile: Sendable {

    /// Unique identifier for the speaker
    public let id: String

    /// Speaker embedding vector
    public let embedding: [Float]?

    /// Total speaking time across all segments
    public let totalSpeakingTime: TimeInterval

    /// Number of segments for this speaker
    public let segmentCount: Int

    /// Optional display name
    public let name: String?

    // MARK: - Initialization

    public init(
        id: String,
        embedding: [Float]? = nil,
        totalSpeakingTime: TimeInterval,
        segmentCount: Int,
        name: String? = nil
    ) {
        self.id = id
        self.embedding = embedding
        self.totalSpeakingTime = totalSpeakingTime
        self.segmentCount = segmentCount
        self.name = name
    }
}
