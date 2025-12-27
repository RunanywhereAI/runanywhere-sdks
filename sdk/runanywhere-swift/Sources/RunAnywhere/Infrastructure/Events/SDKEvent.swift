//
//  SDKEvent.swift
//  RunAnywhere SDK
//
//  Single unified event protocol for the entire SDK.
//  Events declare their destination and the router handles the rest.
//

import Foundation

// MARK: - Event Destination

/// Where an event should be routed
public enum EventDestination: Sendable {
    /// Only to public EventBus (app developers)
    case publicOnly
    /// Only to analytics/telemetry (backend)
    case analyticsOnly
    /// Both destinations (default)
    case all
}

// MARK: - Event Category

/// Event categories for filtering/grouping
public enum EventCategory: String, Sendable {
    case sdk
    case model
    case llm
    case stt
    case tts
    case voice
    case storage
    case device
    case network
    case error
}

// MARK: - SDK Event Protocol

/// Single protocol for ALL SDK events.
///
/// Every event in the SDK conforms to this protocol. The `destination` property
/// tells the router where to send the event:
/// - `.all` (default) → EventBus + Analytics
/// - `.publicOnly` → EventBus only
/// - `.analyticsOnly` → Analytics only
///
/// Usage:
/// ```swift
/// EventPublisher.shared.track(LLMEvent.generationCompleted(...))
/// ```
public protocol SDKEvent: Sendable {
    /// Unique identifier for this event instance
    var id: String { get }

    /// Event type string (used for analytics categorization)
    var type: String { get }

    /// Category for filtering/routing
    var category: EventCategory { get }

    /// When the event occurred
    var timestamp: Date { get }

    /// Optional session ID for grouping related events
    var sessionId: String? { get }

    /// Where to route this event
    var destination: EventDestination { get }

    /// Event properties as key-value pairs (for analytics serialization)
    var properties: [String: String] { get }
}

// MARK: - Default Implementations

extension SDKEvent {
    public var id: String { UUID().uuidString }
    public var timestamp: Date { Date() }
    public var sessionId: String? { nil }
    public var destination: EventDestination { .all }
}
