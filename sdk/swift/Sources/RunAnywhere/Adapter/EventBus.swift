// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// EventBus — observer surface over the C `ra_event_*` ABI. UI views
// subscribe to lifecycle/model/generation events emitted from the core.

import Foundation
import CRACommonsCore

public enum EventCategory: Sendable {
    case lifecycle, model, llm, stt, tts, vad, voiceAgent, download, telemetry, error, unknown

    var raw: ra_event_category_t {
        switch self {
        case .lifecycle:  return ra_event_category_t(RA_EVENT_CATEGORY_LIFECYCLE)
        case .model:      return ra_event_category_t(RA_EVENT_CATEGORY_MODEL)
        case .llm:        return ra_event_category_t(RA_EVENT_CATEGORY_LLM)
        case .stt:        return ra_event_category_t(RA_EVENT_CATEGORY_STT)
        case .tts:        return ra_event_category_t(RA_EVENT_CATEGORY_TTS)
        case .vad:        return ra_event_category_t(RA_EVENT_CATEGORY_VAD)
        case .voiceAgent: return ra_event_category_t(RA_EVENT_CATEGORY_VOICE_AGENT)
        case .download:   return ra_event_category_t(RA_EVENT_CATEGORY_DOWNLOAD)
        case .telemetry:  return ra_event_category_t(RA_EVENT_CATEGORY_TELEMETRY)
        case .error:      return ra_event_category_t(RA_EVENT_CATEGORY_ERROR)
        case .unknown:    return ra_event_category_t(RA_EVENT_CATEGORY_UNKNOWN)
        }
    }

    init(raw: ra_event_category_t) {
        switch raw {
        case ra_event_category_t(RA_EVENT_CATEGORY_LIFECYCLE):   self = .lifecycle
        case ra_event_category_t(RA_EVENT_CATEGORY_MODEL):       self = .model
        case ra_event_category_t(RA_EVENT_CATEGORY_LLM):         self = .llm
        case ra_event_category_t(RA_EVENT_CATEGORY_STT):         self = .stt
        case ra_event_category_t(RA_EVENT_CATEGORY_TTS):         self = .tts
        case ra_event_category_t(RA_EVENT_CATEGORY_VAD):         self = .vad
        case ra_event_category_t(RA_EVENT_CATEGORY_VOICE_AGENT): self = .voiceAgent
        case ra_event_category_t(RA_EVENT_CATEGORY_DOWNLOAD):    self = .download
        case ra_event_category_t(RA_EVENT_CATEGORY_TELEMETRY):   self = .telemetry
        case ra_event_category_t(RA_EVENT_CATEGORY_ERROR):       self = .error
        default:                                                  self = .unknown
        }
    }
}

public struct SDKEvent: Sendable {
    public let category: EventCategory
    public let name: String
    public let payloadJSON: String?
    public let timestampMs: Int64
}

public struct LifecycleEvent: Sendable {
    public let kind: String
    public init(kind: String) { self.kind = kind }
}

public struct ModelEvent: Sendable {
    public let kind: String
    public let modelId: String
    public init(kind: String, modelId: String) { self.kind = kind; self.modelId = modelId }
}

public struct LLMEvent: Sendable {
    public let kind: String
    public let modelId: String
    public init(kind: String, modelId: String) { self.kind = kind; self.modelId = modelId }
}

public struct STTEvent: Sendable {
    public let kind: String
    public init(kind: String) { self.kind = kind }
}

public struct TTSEvent: Sendable {
    public let kind: String
    public init(kind: String) { self.kind = kind }
}

@MainActor
public final class EventBus {
    public static let shared = EventBus()

    /// Async stream of every SDK event. Multiple subscribers each get an
    /// independent stream.
    ///
    /// Two property names are exposed for the same underlying firehose:
    ///
    /// - `eventStream`: this AsyncStream. Use from modern `for-await`
    ///   consumers.
    /// - `events` (see `SampleAppCompat.swift`): a Combine `AnyPublisher`
    ///   that republishes every emission. Use from Combine `.sink` /
    ///   `.receive(on:)` callers.
    public var eventStream: AsyncStream<SDKEvent> {
        AsyncStream { continuation in
            final class Ctx {
                let cont: AsyncStream<SDKEvent>.Continuation
                var subId: ra_event_subscription_id_t = -1
                init(_ c: AsyncStream<SDKEvent>.Continuation) { cont = c }
            }
            let ctx = Unmanaged.passRetained(Ctx(continuation))

            let cb: ra_event_callback_fn = { eventPtr, userData in
                guard let user = userData,
                      let evt = eventPtr?.pointee else { return }
                let ctx = Unmanaged<Ctx>.fromOpaque(user).takeUnretainedValue()
                let name = evt.name.flatMap { String(cString: $0) } ?? ""
                let payload = evt.payload_json.flatMap { String(cString: $0) }
                ctx.cont.yield(SDKEvent(
                    category: EventCategory(raw: evt.category),
                    name: name,
                    payloadJSON: payload,
                    timestampMs: evt.timestamp_ms))
            }

            let subId = ra_event_subscribe_all(cb, ctx.toOpaque())
            ctx.takeUnretainedValue().subId = subId

            continuation.onTermination = { _ in
                _ = ra_event_unsubscribe(subId)
                ctx.release()
            }
        }
    }

    public func emit(_ event: SDKEvent) {
        var raEvent = ra_event_t()
        raEvent.category = event.category.raw
        raEvent.timestamp_ms = event.timestampMs
        event.name.withCString { name in
            raEvent.name = name
            if let payload = event.payloadJSON {
                payload.withCString { p in
                    raEvent.payload_json = p
                    ra_event_publish(&raEvent)
                }
            } else {
                ra_event_publish(&raEvent)
            }
        }
    }
}

@MainActor
public extension RunAnywhere {
    static var events: EventBus { .shared }
}
