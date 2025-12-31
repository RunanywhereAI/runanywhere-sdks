//
//  EventPublisher.swift
//  RunAnywhere SDK
//
//  Central event publishing system for the SDK.
//  Routes events to public subscribers and/or analytics based on destination.
//

import Foundation

/// Central event publisher for the SDK.
///
/// Receives events from SDK components and routes them to:
/// - Public subscribers (app developers via `subscribe`)
/// - Analytics/telemetry backend
///
/// ## Usage
///
/// ```swift
/// // Track an event
/// EventPublisher.shared.track(LLMEvent.generationStarted(...))
///
/// // Subscribe to events
/// EventPublisher.shared.subscribe { event in
///     print("Event: \(event.type)")
/// }
/// ```
public final class EventPublisher: @unchecked Sendable {

    // MARK: - Singleton

    /// Shared instance
    public static let shared = EventPublisher()

    // MARK: - Private State

    private let lock = NSLock()
    private var subscribers: [UUID: (any SDKEvent) -> Void] = [:]
    private var analyticsHandler: ((any SDKEvent) -> Void)?
    private let logger = SDKLogger(category: "EventPublisher")

    private init() {}

    // MARK: - Publishing

    /// Track an event.
    ///
    /// Routes the event based on its `destination` property.
    ///
    /// - Parameter event: The event to publish
    public func track(_ event: any SDKEvent) {
        lock.lock()
        let subs = subscribers
        let analytics = analyticsHandler
        lock.unlock()

        switch event.destination {
        case .publicOnly:
            notifySubscribers(event, subscribers: subs)

        case .analyticsOnly:
            analytics?(event)

        case .all:
            notifySubscribers(event, subscribers: subs)
            analytics?(event)
        }
    }

    /// Alias for `track` for semantic clarity.
    public func publish(_ event: any SDKEvent) {
        track(event)
    }

    // MARK: - Subscribing

    /// Subscribe to all public events.
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

    // MARK: - Analytics Integration

    /// Set the analytics handler.
    ///
    /// - Important: This should only be called by SDK initialization code.
    ///
    /// - Parameter handler: Handler for analytics events
    internal func setAnalyticsHandler(_ handler: @escaping (any SDKEvent) -> Void) {
        lock.lock()
        analyticsHandler = handler
        lock.unlock()
    }

    /// Initialize the event publisher for the given environment.
    ///
    /// - Important: This should only be called by SDK initialization code.
    ///
    /// - Parameter environment: The SDK environment
    internal func initialize(environment: SDKEnvironment) {
        let remoteDataSource = RemoteTelemetryDataSource(environment: environment)
        setAnalyticsHandler { event in
            Task {
                await remoteDataSource.sendEvent(event)
            }
        }
        logger.info("EventPublisher initialized with remote telemetry")
    }

    // MARK: - Reset

    /// Reset the publisher, removing all subscribers.
    ///
    /// - Important: This should only be called by `RunAnywhere.reset()`.
    internal func reset() {
        lock.lock()
        subscribers.removeAll()
        analyticsHandler = nil
        lock.unlock()
        logger.info("EventPublisher reset")
    }

    // MARK: - Private Helpers

    private func notifySubscribers(_ event: any SDKEvent, subscribers: [UUID: (any SDKEvent) -> Void]) {
        for (_, handler) in subscribers {
            handler(event)
        }
    }
}
