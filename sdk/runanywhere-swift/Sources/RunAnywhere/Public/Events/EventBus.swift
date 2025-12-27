//
//  EventBus.swift
//  RunAnywhere SDK
//
//  Simple pub/sub for SDK events.
//

import Combine
import Foundation

// MARK: - Event Bus

/// Central event bus for SDK-wide event distribution.
///
/// Subscribe to events by category or to all events:
/// ```swift
/// // Subscribe to all events
/// EventBus.shared.events
///     .sink { event in print(event.type) }
///
/// // Subscribe to specific category
/// EventBus.shared.events(for: .llm)
///     .sink { event in print(event.type) }
/// ```
public final class EventBus: @unchecked Sendable {

    // MARK: - Singleton

    public static let shared = EventBus()

    // MARK: - Publishers

    private let subject = PassthroughSubject<any SDKEvent, Never>()

    /// All events publisher
    public var events: AnyPublisher<any SDKEvent, Never> {
        subject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Publishing

    /// Publish an event to all subscribers
    public func publish(_ event: any SDKEvent) {
        subject.send(event)
    }

    // MARK: - Filtered Subscriptions

    /// Get events for a specific category
    public func events(for category: EventCategory) -> AnyPublisher<any SDKEvent, Never> {
        subject
            .filter { $0.category == category }
            .eraseToAnyPublisher()
    }

    /// Subscribe to events with a closure
    public func on(_ handler: @escaping (any SDKEvent) -> Void) -> AnyCancellable {
        subject.sink { event in
            handler(event)
        }
    }

    /// Subscribe to events of a specific category
    public func on(
        _ category: EventCategory,
        handler: @escaping (any SDKEvent) -> Void
    ) -> AnyCancellable {
        events(for: category).sink { event in
            handler(event)
        }
    }
}
