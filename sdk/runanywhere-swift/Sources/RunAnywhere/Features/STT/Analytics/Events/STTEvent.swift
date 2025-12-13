//
//  STTEvent.swift
//  RunAnywhere SDK
//
//  STT-specific analytics event
//

import Foundation

// MARK: - STT Event

/// STT-specific analytics event
public struct STTEvent: AnalyticsEvent {
    public let id: String
    public let type: String
    public let timestamp: Date
    public let sessionId: String?
    public let eventData: any AnalyticsEventData

    public init(
        type: STTEventType,
        sessionId: String? = nil,
        eventData: any AnalyticsEventData
    ) {
        self.id = UUID().uuidString
        self.type = type.rawValue
        self.timestamp = Date()
        self.sessionId = sessionId
        self.eventData = eventData
    }
}
