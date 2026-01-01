//
//  EventPublisher.swift
//  RunAnywhere SDK
//
//  Central event publishing system for the SDK.
//  Receives public events from C++ and broadcasts to Swift subscribers.
//

import Foundation

/// Central event publisher for the SDK.
///
/// Receives public events from the C++ event system and broadcasts them to Swift subscribers.
/// C++ is the source of truth for event routing - it determines which events reach Swift.
///
/// ## Architecture
///
/// Events flow: Swift/C++ → C++ rac_analytics_event_emit() → C++ routes based on destination
///   - TELEMETRY_ONLY/ALL → C++ analytics callback (telemetry backend)
///   - PUBLIC_ONLY/ALL → Swift publicEventCallback → EventPublisher.track() → subscribers
///
/// ## Usage
///
/// ```swift
/// // Subscribe to events
/// let subscriptionId = EventPublisher.shared.subscribe { event in
///     print("Event: \(event.type)")
/// }
///
/// // Unsubscribe when done
/// EventPublisher.shared.unsubscribe(subscriptionId)
/// ```
public final class EventPublisher: @unchecked Sendable {

    // MARK: - Singleton

    /// Shared instance
    public static let shared = EventPublisher()

    // MARK: - Private State

    private let lock = NSLock()
    private var subscribers: [UUID: (any SDKEvent) -> Void] = [:]
    private let logger = SDKLogger(category: "EventPublisher")

    private init() {}

    // MARK: - Event Reception (from C++ callback)

    /// Track an event.
    ///
    /// Called by the C++ public event callback when an event is routed to Swift.
    /// Notifies all registered subscribers.
    ///
    /// - Parameter event: The event to publish to subscribers
    public func track(_ event: any SDKEvent) {
        lock.lock()
        let subs = subscribers
        lock.unlock()

        // Notify all subscribers
        for (_, handler) in subs {
            handler(event)
        }
    }

    /// Alias for `track` for semantic clarity.
    public func publish(_ event: any SDKEvent) {
        track(event)
    }

    // MARK: - Subscribing

    /// Subscribe to all public events.
    ///
    /// Events are received from the C++ event system based on their destination.
    /// Only events marked as PUBLIC_ONLY or ALL will reach subscribers.
    ///
    /// - Parameter handler: Callback invoked for each event
    /// - Returns: Subscription ID for unsubscribing
    @discardableResult
    public func subscribe(handler: @escaping (any SDKEvent) -> Void) -> UUID {
        let id = UUID()
        lock.lock()
        subscribers[id] = handler
        lock.unlock()
        logger.debug("Added subscriber: \(id)")
        return id
    }

    /// Unsubscribe from events.
    ///
    /// - Parameter id: The subscription ID returned from `subscribe`
    public func unsubscribe(_ id: UUID) {
        lock.lock()
        subscribers.removeValue(forKey: id)
        lock.unlock()
        logger.debug("Removed subscriber: \(id)")
    }

    // MARK: - Subscriber Count

    /// Number of active subscribers
    public var subscriberCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return subscribers.count
    }

    // MARK: - Reset

    /// Reset the publisher, removing all subscribers.
    ///
    /// - Important: This should only be called by `RunAnywhere.reset()`.
    internal func reset() {
        lock.lock()
        subscribers.removeAll()
        lock.unlock()
        logger.info("EventPublisher reset")
    }
}
