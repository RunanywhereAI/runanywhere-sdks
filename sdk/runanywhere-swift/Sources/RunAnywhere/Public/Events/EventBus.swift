//
//  EventBus.swift
//  RunAnywhere SDK
//
//  Combine publisher over canonical SDK proto events.
//

import Combine

// MARK: - Event Bus

/// Central publisher for SDK-wide `RASDKEvent` distribution.
///
/// Subscribe to events by category or to all events:
/// ```swift
/// // Subscribe to all events
/// EventBus.shared.events
///     .sink { event in print(event.category) }
///
/// // Subscribe to specific category
/// EventBus.shared.events(for: .llm)
///     .sink { event in print(event.properties) }
/// ```
public final class EventBus: @unchecked Sendable {

    // MARK: - Singleton

    public static let shared = EventBus()

    // MARK: - Publishers

    private let subject = PassthroughSubject<RASDKEvent, Never>()

    /// All events publisher
    public var events: AnyPublisher<RASDKEvent, Never> {
        subject.eraseToAnyPublisher()
    }

    private var nativeSubscriptionId: UInt64 = 0

    // MARK: - Initialization

    private init() {
        nativeSubscriptionId = CppBridge.Events.subscribeSDKEvents { [weak self] event in
            self?.subject.send(event)
        }
    }

    // No `deinit`: `shared` is the only allocation site and it lives for the
    // process lifetime, so the previous unsubscribe-on-deinit path was dead
    // code. Native subscription cleanup, when required, runs through
    // `RunAnywhere.reset()` -> `CppBridge.shutdown()` instead.

    // MARK: - Publishing

    /// Publish an event to all subscribers
    public func publish(_ event: RASDKEvent) {
        if !CppBridge.Events.publishSDKEvent(event) {
            subject.send(event)
        }
    }

    // MARK: - Filtered Subscriptions

    /// Get events for a specific category
    public func events(for category: RAEventCategory) -> AnyPublisher<RASDKEvent, Never> {
        subject
            .filter { $0.category == category }
            .eraseToAnyPublisher()
    }

    /// Subscribe to events with a closure
    public func on(_ handler: @escaping (RASDKEvent) -> Void) -> AnyCancellable {
        subject.sink { event in
            handler(event)
        }
    }

    /// Subscribe to events of a specific category
    public func on(
        _ category: RAEventCategory,
        handler: @escaping (RASDKEvent) -> Void
    ) -> AnyCancellable {
        events(for: category).sink { event in
            handler(event)
        }
    }
}
