//
//  SessionMetadata.swift
//  RunAnywhere SDK
//
//  Session metadata for analytics tracking
//

import Foundation

// MARK: - Session Management

/// Metadata for analytics sessions
/// Used to group related analytics events together
public struct SessionMetadata: Sendable {
    /// Unique session identifier
    public let id: String

    /// Optional model ID associated with the session
    public let modelId: String?

    /// Session type for categorization
    public let type: String

    /// When the session started
    public let startTime: Date

    /// Additional session properties
    public let properties: [String: String]

    public init(
        id: String = UUID().uuidString,
        modelId: String? = nil,
        type: String = "default",
        startTime: Date = Date(),
        properties: [String: String] = [:]
    ) {
        self.id = id
        self.modelId = modelId
        self.type = type
        self.startTime = startTime
        self.properties = properties
    }
}

// MARK: - Session State

/// Session state tracking
public enum SessionState: String, Sendable {
    case active
    case paused
    case ended
}

/// Complete session information
public struct AnalyticsSession: Sendable {
    public let metadata: SessionMetadata
    public var state: SessionState
    public var endTime: Date?
    public var eventCount: Int

    public init(
        metadata: SessionMetadata,
        state: SessionState = .active,
        endTime: Date? = nil,
        eventCount: Int = 0
    ) {
        self.metadata = metadata
        self.state = state
        self.endTime = endTime
        self.eventCount = eventCount
    }

    public var duration: TimeInterval? {
        guard let endTime = endTime else { return nil }
        return endTime.timeIntervalSince(metadata.startTime)
    }
}
