//
//  AnalyticsEvent.swift
//  RunAnywhere SDK
//
//  Protocol defining the structure for analytics events
//

import Foundation

// MARK: - Event System

/// Base protocol for all analytics events
/// All analytics events must conform to this protocol for consistent handling
public protocol AnalyticsEvent: Sendable {
    /// Unique identifier for the event
    var id: String { get }

    /// Event type string for categorization
    var type: String { get }

    /// Timestamp when the event occurred
    var timestamp: Date { get }

    /// Optional session ID to group related events
    var sessionId: String? { get }

    /// Structured event data payload
    var eventData: any AnalyticsEventData { get }
}
