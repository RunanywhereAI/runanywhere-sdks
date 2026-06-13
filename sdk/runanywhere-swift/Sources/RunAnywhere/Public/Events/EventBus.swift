//
//  EventBus.swift
//  RunAnywhere SDK
//
//  Combine publisher over canonical SDK proto events.
//

import Combine
import os

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

    private let nativeSubscriptionId = OSAllocatedUnfairLock<UInt64>(initialState: 0)

    // MARK: - Initialization

    private init() {}

    // No `deinit`: `shared` is the only allocation site and it lives for the
    // process lifetime. The native subscription is owned by the explicit
    // `start()` / `stop()` lifecycle below.

    // MARK: - Native subscription lifecycle

    /// Start the native SDK event subscription. Idempotent: calling twice is a
    /// no-op. Invoked by `CppBridge.initialize` after the C++ commons core is
    /// brought up so native lifecycle/model/error events flow into `events`.
    ///
    /// Subscribing before `start()` is safe, but events emitted before the
    /// native subscription is wired are not delivered.
    public func start() {
        nativeSubscriptionId.withLock { id in
            guard id == 0 else { return }
            id = CppBridge.Events.subscribeSDKEvents { [weak self] event in
                self?.subject.send(event)
            }
        }
    }

    /// Stop the native SDK event subscription. Idempotent: calling twice is a
    /// no-op. Invoked during shutdown before the C++ commons core is torn down
    /// so the unsubscribe call still has a working native ABI surface.
    public func stop() {
        nativeSubscriptionId.withLock { id in
            guard id != 0 else { return }
            CppBridge.Events.unsubscribeSDKEvents(id)
            id = 0
        }
    }

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

    /// Extract a specific payload type from the proto envelope stream for
    /// internal convenience streams.
    private func eventsOfPayload<Payload>(
        _ selector: @escaping (RASDKEvent) -> Payload?
    ) -> AnyPublisher<Payload, Never> {
        subject
            .compactMap(selector)
            .eraseToAnyPublisher()
    }

    /// Stream of `RAVoiceEvent` payloads (voice-agent pipeline events).
    public var voiceEventPayloads: AnyPublisher<RAVoiceEvent, Never> {
        eventsOfPayload { envelope in
            guard case .voicePipeline(let payload)? = envelope.event else { return nil }
            return payload
        }
    }

    /// Stream of `RADownloadEvent` payloads (model download progress / lifecycle).
    public var downloadEventPayloads: AnyPublisher<RADownloadEvent, Never> {
        eventsOfPayload { envelope in
            guard case .download(let payload)? = envelope.event else { return nil }
            return payload
        }
    }

    /// Stream of `RAComponentLifecycleEvent` payloads.
    public var componentLifecycleEventPayloads: AnyPublisher<RAComponentLifecycleEvent, Never> {
        eventsOfPayload { envelope in
            guard case .componentLifecycle(let payload)? = envelope.event else { return nil }
            return payload
        }
    }

    /// Stream of `RAModelRegistryEvent` payloads.
    public var modelRegistryEventPayloads: AnyPublisher<RAModelRegistryEvent, Never> {
        eventsOfPayload { envelope in
            guard case .modelRegistry(let payload)? = envelope.event else { return nil }
            return payload
        }
    }

    // MARK: - Convenience Methods

    /// Get LLM events.
    public var llmEvents: AnyPublisher<RASDKEvent, Never> {
        events(for: .llm)
    }

    /// Get STT events.
    public var sttEvents: AnyPublisher<RASDKEvent, Never> {
        events(for: .stt)
    }

    /// Get TTS events.
    public var ttsEvents: AnyPublisher<RASDKEvent, Never> {
        events(for: .tts)
    }

    /// Get model events.
    public var modelEvents: AnyPublisher<RASDKEvent, Never> {
        events(for: .model)
    }

    /// Get error events.
    public var errorEvents: AnyPublisher<RASDKEvent, Never> {
        events(for: .error)
    }

    /// Get SDK lifecycle events.
    public var sdkEvents: AnyPublisher<RASDKEvent, Never> {
        events(for: .sdk)
    }

    /// Get RAG events.
    public var ragEvents: AnyPublisher<RASDKEvent, Never> {
        events(for: .rag)
    }

    // MARK: - Closure Subscriptions

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
