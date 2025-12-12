//
//  SpeakerDiarizationSpeakerInfo.swift
//  RunAnywhere SDK
//
//  Information about a detected speaker
//

import Foundation

// MARK: - Deprecated Typealias

/// Deprecated typealias for backward compatibility
@available(*, deprecated, renamed: "SpeakerDiarizationSpeakerInfo")
public typealias SpeakerInfo = SpeakerDiarizationSpeakerInfo

// MARK: - Speaker Info

/// Information about a detected speaker
public struct SpeakerDiarizationSpeakerInfo: Sendable {

    /// Unique identifier for the speaker
    public let id: String

    /// Optional display name for the speaker
    public var name: String?

    /// Confidence score for the speaker identification (0.0-1.0)
    public let confidence: Float?

    /// Speaker embedding vector (for comparison)
    public let embedding: [Float]?

    // MARK: - Initialization

    public init(
        id: String,
        name: String? = nil,
        confidence: Float? = nil,
        embedding: [Float]? = nil
    ) {
        self.id = id
        self.name = name
        self.confidence = confidence
        self.embedding = embedding
    }
}

// MARK: - Equatable

extension SpeakerDiarizationSpeakerInfo: Equatable {
    public static func == (lhs: SpeakerDiarizationSpeakerInfo, rhs: SpeakerDiarizationSpeakerInfo) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Hashable

extension SpeakerDiarizationSpeakerInfo: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
