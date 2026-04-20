// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Public SDK event protocol + Combine bridge. The concrete record type
// produced by `EventBus.eventStream` is `SDKEventRecord` (see
// Infrastructure/Events/EventBus.swift). Sample apps treat events as
// `any SDKEvent` with a `.type` + `.properties` view; both forms are
// supported.

import Combine
import Foundation
import CRACommonsCore

/// Protocol-shape event for sample-app consumption. Matches the
/// main-branch SDKEvent protocol.
public protocol SDKEvent: Sendable {
    var category:    EventCategory    { get }
    var type:        String           { get }
    var properties:  [String: String] { get }
    var name:        String           { get }
    var timestampMs: Int64            { get }
}

extension SDKEventRecord: SDKEvent {
    /// Legacy `event.type` is the event name.
    public var type: String { name }

    /// Flat `[String: String]` view of the event's payload JSON. Arrays
    /// and nested objects are skipped; numeric + boolean leaves are
    /// stringified.
    public var properties: [String: String] {
        guard let json = payloadJSON,
              let data = json.data(using: .utf8),
              let raw  = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        var out: [String: String] = [:]
        for (k, v) in raw {
            switch v {
            case let s as String:   out[k] = s
            case let n as NSNumber: out[k] = n.stringValue
            case let b as Bool:     out[k] = b ? "true" : "false"
            default: continue
            }
        }
        return out
    }
}

// MARK: - Combine bridge: EventBus.events

@MainActor
extension EventBus {
    /// Single shared Combine subject that republishes every AsyncStream
    /// event. `ensurePumpRunning()` starts the forwarder on first access.
    private static let eventSubject = PassthroughSubject<SDKEventRecord, Never>()
    private static var pumpTask: Task<Void, Never>?

    private static func ensurePumpRunning() {
        guard pumpTask == nil else { return }
        pumpTask = Task { @MainActor in
            for await event in EventBus.shared.eventStream {
                eventSubject.send(event)
            }
        }
    }

    /// Combine publisher of every emitted `SDKEvent`. Sample apps use
    /// `RunAnywhere.events.events.receive(on:).sink { ... }`.
    public var events: AnyPublisher<any SDKEvent, Never> {
        EventBus.ensurePumpRunning()
        return EventBus.eventSubject
            .map { (evt: SDKEventRecord) -> any SDKEvent in evt }
            .eraseToAnyPublisher()
    }
}
