//
//  SDKEvent.swift
//  RunAnywhere SDK
//
//  Minimal event protocol for SDK events.
//  All event logic and definitions are in C++ (rac_analytics_events.h).
//  This Swift protocol only provides the interface for bridged events.
//

import Foundation

// MARK: - Event Destination

/// Where an event should be routed (mirrors C++ rac_event_destination_t)
public enum EventDestination: Sendable {
    /// Only to public EventBus (app developers)
    case publicOnly
    /// Only to analytics/telemetry (backend)
    case analyticsOnly
    /// Both destinations (default)
    case all
}

// MARK: - Event Category

/// Event categories for filtering/grouping (mirrors C++ categories)
public enum EventCategory: String, Sendable {
    case sdk
    case model
    case llm
    case stt
    case tts
    case voice
    case rag
    case storage
    case device
    case network
    case error
}

// MARK: - SDK Event Protocol

/// Minimal protocol for SDK events.
///
/// Events originate from C++ and are bridged to Swift via EventBridge.
/// App developers can subscribe to events via EventPublisher or EventBus.
public protocol SDKEvent: Sendable {
    /// Unique identifier for this event instance
    var id: String { get }

    /// Event type string (from C++ event types)
    var type: String { get }

    /// Category for filtering/routing
    var category: EventCategory { get }

    /// When the event occurred
    var timestamp: Date { get }

    /// Optional session ID for grouping related events
    var sessionId: String? { get }

    /// Where to route this event
    var destination: EventDestination { get }

    /// Event properties as key-value pairs
    var properties: [String: String] { get }
}

// MARK: - Default Implementations

extension SDKEvent {
    public var id: String { UUID().uuidString }
    public var timestamp: Date { Date() }
    public var sessionId: String? { nil }
    public var destination: EventDestination { .all }
}
