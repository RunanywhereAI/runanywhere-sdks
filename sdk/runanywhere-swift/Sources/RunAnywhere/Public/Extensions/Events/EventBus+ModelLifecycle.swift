//
//  EventBus+ModelLifecycle.swift
//  RunAnywhere SDK
//
//  Typed model-lifecycle stream over the raw SDK event bus.
//
//  Native commons signals "model loaded/unloaded" on THREE different proto
//  channels depending on the path that performed the work:
//    1. component-lifecycle events (EVENT_CATEGORY_COMPONENT,
//       `event.componentLifecycle.currentState`) — the `loadModel` path,
//    2. model events (`event.model.kind` load/unload completed),
//    3. LLM generation events (`event.generation.kind` modelLoaded/Unloaded).
//
//  Which channel fires when is an SDK-internal detail. Consumers should not
//  need to know it — before this helper every app ViewModel hand-decoded all
//  three with an identical switch. `EventBus.modelLifecycle` folds them into
//  one typed stream; `modelLoaded` / `modelUnloaded` are pre-filtered views.
//

import Combine

// MARK: - Typed change

/// One model load/unload transition, decoded from the raw event bus.
public struct RAModelLifecycleChange: Sendable {
    public enum Kind: Sendable {
        case loaded
        case unloaded
    }

    /// Whether the model finished loading or was unloaded.
    public let kind: Kind

    /// Registry id of the affected model. May be empty when the native
    /// channel did not carry one (rare; treat as "current model").
    public let modelID: String

    /// SDK component slot the change applies to (.llm, .stt, .tts, ...).
    public let component: RASDKComponent

    /// The underlying raw event, for consumers that need extra payload
    /// fields (progress, framework, error, ...).
    public let event: RASDKEvent
}

// MARK: - EventBus typed publishers

public extension EventBus {

    /// Unified model load/unload stream across all native signal channels.
    ///
    /// ```swift
    /// RunAnywhere.events.modelLifecycle
    ///     .filter { $0.component == .llm }
    ///     .receive(on: DispatchQueue.main)
    ///     .sink { change in ... }
    /// ```
    var modelLifecycle: AnyPublisher<RAModelLifecycleChange, Never> {
        events
            .compactMap(EventBus.modelLifecycleChange(from:))
            .eraseToAnyPublisher()
    }

    /// `modelLifecycle` filtered to load completions.
    var modelLoaded: AnyPublisher<RAModelLifecycleChange, Never> {
        modelLifecycle
            .filter { $0.kind == .loaded }
            .eraseToAnyPublisher()
    }

    /// `modelLifecycle` filtered to unloads.
    var modelUnloaded: AnyPublisher<RAModelLifecycleChange, Never> {
        modelLifecycle
            .filter { $0.kind == .unloaded }
            .eraseToAnyPublisher()
    }

    /// Decode a raw SDK event into a lifecycle change, or nil when the event
    /// is not a load/unload transition. Exposed so non-Combine consumers can
    /// reuse the exact same channel mapping.
    static func modelLifecycleChange(from event: RASDKEvent) -> RAModelLifecycleChange? {
        // Channel 1: component-lifecycle (the canonical loadModel path).
        if event.category == .component {
            let lifecycle = event.componentLifecycle
            switch lifecycle.currentState {
            case .ready:
                return RAModelLifecycleChange(
                    kind: .loaded,
                    modelID: lifecycle.modelID,
                    component: lifecycle.component,
                    event: event
                )
            case .notLoaded, .unloading, .shutdown, .deleting:
                return RAModelLifecycleChange(
                    kind: .unloaded,
                    modelID: lifecycle.modelID,
                    component: lifecycle.component,
                    event: event
                )
            default:
                return nil
            }
        }

        // Channels 2 + 3: model events and LLM generation events.
        let modelID = event.model.modelID.isEmpty
            ? event.generation.modelID
            : event.model.modelID

        switch (event.model.kind, event.generation.kind) {
        case (.loadCompleted, _), (_, .modelLoaded):
            return RAModelLifecycleChange(
                kind: .loaded,
                modelID: modelID,
                component: event.component,
                event: event
            )
        case (.unloadCompleted, _), (_, .modelUnloaded):
            return RAModelLifecycleChange(
                kind: .unloaded,
                modelID: modelID,
                component: event.component,
                event: event
            )
        default:
            return nil
        }
    }
}
