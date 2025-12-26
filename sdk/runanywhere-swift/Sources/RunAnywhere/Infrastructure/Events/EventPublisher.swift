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
    private var remoteDataSource: RemoteTelemetryDataSource?
    private let logger = SDKLogger(category: "EventPublisher")

    // MARK: - Initialization

    private init(eventBus: EventBus = .shared) {
        self.eventBus = eventBus
    }

    /// Initialize with remote data source (call during SDK startup)
    public func initialize(remoteDataSource: RemoteTelemetryDataSource) {
        self.remoteDataSource = remoteDataSource
    }

    // MARK: - Track

    /// Track an event. Routes automatically based on event.destination.
    public func track(_ event: any SDKEvent) {
        let destination = event.destination

        // Route to EventBus (public)
        if destination != .analyticsOnly {
            eventBus.publish(event)
        }

        // Route to Analytics (telemetry) - fire and forget
        if destination != .publicOnly {
            Task {
                await sendToRemote(event)
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

        // Route to Analytics (telemetry) - fire and forget
        if destination != .publicOnly {
            await sendToRemote(event)
        }
    }

    // MARK: - Private

    private func sendToRemote(_ event: any SDKEvent) async {
        guard let remoteDataSource = remoteDataSource else {
            // Not initialized yet - events before SDK init are dropped
            return
        }

        // Create payload directly from event (preserves category → modality)
        let payload: TelemetryEventPayload
        if let telemetryEvent = event as? (any TelemetryEventProperties) {
            payload = TelemetryEventPayload(from: event, telemetryProperties: telemetryEvent.telemetryProperties)
        } else {
            payload = TelemetryEventPayload(from: event)
        }

        // Fire and forget - backend handles failures
        do {
            try await remoteDataSource.sendPayloads([payload])
        } catch {
            // Log but don't fail - telemetry is non-critical
            logger.debug("Telemetry send failed (non-critical): \(error.localizedDescription)")
        }
    }
}
