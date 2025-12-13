//
//  EventPublisher.swift
//  RunAnywhere SDK
//
//  Simple event router. Call track(event) and it handles the rest.
//

import Foundation

// MARK: - Event Publisher

/// Simple event router for the SDK.
///
/// Just call `track(event)` - the router decides where to send it
/// based on the event's `destination` property.
///
/// Usage:
/// ```swift
/// EventPublisher.shared.track(LLMEvent.generationCompleted(...))
/// ```
public final class EventPublisher: @unchecked Sendable {

    // MARK: - Singleton

    public static let shared = EventPublisher()

    // MARK: - Dependencies

    private let eventBus: EventBus
    private var analyticsQueue: AnalyticsQueueManager?

    // MARK: - Initialization

    private init(eventBus: EventBus = .shared) {
        self.eventBus = eventBus
    }

    /// Initialize with analytics queue (call during SDK startup)
    public func initialize(analyticsQueue: AnalyticsQueueManager) {
        self.analyticsQueue = analyticsQueue
    }

    // MARK: - Track

    /// Track an event. Routes automatically based on event.destination.
    public func track(_ event: any SDKEvent) {
        let destination = event.destination

        // Route to EventBus (public)
        if destination != .analyticsOnly {
            eventBus.publish(event)
        }

        // Route to Analytics (telemetry)
        if destination != .publicOnly {
            Task {
                await analyticsQueue?.enqueue(event)
            }
        }
    }

    /// Track an event asynchronously (for use in async contexts)
    public func trackAsync(_ event: any SDKEvent) async {
        let destination = event.destination

        // Route to EventBus (public)
        if destination != .analyticsOnly {
            eventBus.publish(event)
        }

        // Route to Analytics (telemetry)
        if destination != .publicOnly {
            await analyticsQueue?.enqueue(event)
        }
    }
}
