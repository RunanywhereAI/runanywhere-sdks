// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Source-compat overlay for the iOS sample app. These symbols existed on
// the main branch and are referenced verbatim by the sample's view models;
// they're re-shaped here as thin adapters over the v2 API so the sample
// builds without any UI/UX change.

import Combine
import Foundation
import CRACommonsCore

// MARK: - SDKEvent protocol

/// Legacy protocol-based SDKEvent. The sample's LLMViewModel+Events etc.
/// treat events as `any SDKEvent` with `.category`, `.type`, `.properties`.
/// The v2 struct `SDKEvent` is renamed to `SDKEventStruct` and a matching
/// typealias protocol is offered here.
public protocol SDKEventProtocol: Sendable {
    var category:   EventCategory { get }
    var type:       String { get }
    var properties: [String: String] { get }
    var name:       String { get }
    var timestampMs: Int64 { get }
}

extension SDKEvent: SDKEventProtocol {
    /// Legacy `event.type` — mirrors the event name.
    public var type: String { name }

    /// Best-effort parse of `payloadJSON` into `[String: String]`. Non-
    /// string leaf values are stringified. Arrays / nested objects are
    /// dropped — sample apps read flat key-value maps.
    public var properties: [String: String] {
        guard let json = payloadJSON,
              let data = json.data(using: .utf8),
              let raw  = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        var out: [String: String] = [:]
        for (k, v) in raw {
            switch v {
            case let s as String:  out[k] = s
            case let n as NSNumber: out[k] = n.stringValue
            case let b as Bool:    out[k] = b ? "true" : "false"
            default: continue
            }
        }
        return out
    }
}

/// Sample-app protocol name alias. `handleSDKEvent(_ event: any SDKEvent)`
/// resolves against the `SDKEventProtocol` typealias below.
public typealias SDKEventLegacyProtocol = SDKEventProtocol

// MARK: - EventBus.events as Combine publisher

/// The sample uses `.receive(on:).sink {...}` which expects a Combine
/// Publisher. Expose a passthrough subject on EventBus that mirrors the
/// AsyncStream and republishes on a Combine-friendly path.
@MainActor
extension EventBus {
    // Single shared Combine subject that republishes every AsyncStream
    // event. `ensurePumpRunning()` starts the forwarder the first time
    // someone touches `eventsPublisher`.
    private static let eventSubject = PassthroughSubject<SDKEvent, Never>()
    private static var pumpTask: Task<Void, Never>?

    /// Legacy Combine-facing events. Sample apps write
    /// `RunAnywhere.events.events.receive(on:).sink { ... }`.
    public var eventsPublisher: AnyPublisher<any SDKEventProtocol, Never> {
        EventBus.ensurePumpRunning()
        return EventBus.eventSubject
            .map { (evt: SDKEvent) -> any SDKEventProtocol in evt }
            .eraseToAnyPublisher()
    }

    private static func ensurePumpRunning() {
        guard pumpTask == nil else { return }
        pumpTask = Task { @MainActor in
            for await event in EventBus.shared.eventStream {
                eventSubject.send(event)
            }
        }
    }
}

/// Legacy spelling: `RunAnywhere.events.events`.
///
/// `RunAnywhere.events` is already `EventBus.shared` (see EventBus.swift).
/// The sample then writes `.events` on it to get a Combine publisher.
/// We can't rename the existing `events: AsyncStream` getter without
/// breaking callers, so expose the Combine publisher as `events` via a
/// nested proxy: `RunAnywhere.events.events` forwards to the publisher.
public extension EventBus {
    /// Legacy Combine publisher access. `RunAnywhere.events.events.sink {}`
    /// resolves via the MainActor-isolated `eventsPublisher` below; we
    /// don't need a second property — `events` shadows the AsyncStream
    /// getter with the Combine publisher at `SampleAppCompat.swift`'s
    /// extension level.
    @MainActor
    var events: AnyPublisher<any SDKEventProtocol, Never> {
        eventsPublisher
    }
}

// MARK: - RunAnywhere.* top-level aliases

@MainActor
public extension RunAnywhere {

    // --- Voice agent -----------------------------------------------------

    /// Legacy handle returned from startVoiceSession. Wraps the new
    /// `VoiceSession` and re-exposes `.events` as an AsyncStream.
    final class VoiceSessionHandle: @unchecked Sendable {
        public let session: VoiceSession
        public let events: AsyncStream<VoiceSessionEvent>
        private let continuation: AsyncStream<VoiceSessionEvent>.Continuation

        init(session: VoiceSession) {
            self.session = session
            var cont: AsyncStream<VoiceSessionEvent>.Continuation!
            self.events = AsyncStream { c in cont = c }
            self.continuation = cont
        }

        public func stop() { continuation.finish() }
    }

    /// Legacy config struct the sample populates. Translated to
    /// VoiceAgentConfig at startVoiceSession time.
    struct VoiceSessionConfig: Sendable {
        public var llmModelId:  String
        public var sttModelId:  String
        public var vadModelId:  String
        public var ttsModelId:  String
        public var systemPrompt: String

        public init(llmModelId: String = "qwen3-4b",
                    sttModelId: String = "whisper-base",
                    vadModelId: String = "silero-v5",
                    ttsModelId: String = "kokoro",
                    systemPrompt: String = "") {
            self.llmModelId = llmModelId
            self.sttModelId = sttModelId
            self.vadModelId = vadModelId
            self.ttsModelId = ttsModelId
            self.systemPrompt = systemPrompt
        }
    }

    static func startVoiceSession(config: VoiceSessionConfig) async throws
        -> VoiceSessionHandle
    {
        let agentConfig = VoiceAgentConfig(
            llm: config.llmModelId,
            stt: config.sttModelId,
            tts: config.ttsModelId,
            vad: config.vadModelId,
            systemPrompt: config.systemPrompt)
        let session = try await VoiceSession.create(from: .voiceAgent(agentConfig))
        return VoiceSessionHandle(session: session)
    }

    /// Legacy diagnostic helper — returns an empty map in v2 (status is
    /// reported via EventBus events, not a snapshot getter).
    static func getVoiceAgentComponentStates() async -> [String: String] {
        [:]
    }

    // --- Model queries ---------------------------------------------------

    /// True if any LLM session is currently loaded.
    static var isModelLoaded: Bool {
        SessionRegistry.currentLLM != nil
    }

    /// Current loaded LLM model id, or nil.
    static func getCurrentModelId() async -> String? {
        SessionRegistry.currentLLM?.modelId
    }
}

// MARK: - VoiceSessionEvent (legacy name)

/// Sample apps switch on `VoiceSessionEvent` (a nested enum in the
/// legacy VoiceSession). v2 uses `VoiceSession.Event`; this typealias
/// papers over the rename.
public typealias VoiceSessionEvent = VoiceSession.Event

// MARK: - RAGResult.totalTimeMs

public extension RAGResult {
    /// Wall-clock time for the query in ms. v2 doesn't currently measure
    /// it end-to-end; exposed as 0 so legacy logging that consumes this
    /// field compiles and doesn't crash. Real measurement is TBD.
    var totalTimeMs: Double { 0 }
}

// NOTE: `ragCreatePipeline`, `ragIngest`, `ragDestroyPipeline` are now
// `async throws` / `async` on `RunAnywhere` directly (see
// RAGSession.swift). No wrappers needed here.

// MARK: - VLMResult + legacy processImage/cancelVLMGeneration

/// Rich result returned by the legacy `RunAnywhere.processImage` overload
/// the sample's benchmark provider consumes. v2's modern
/// `VLMSession.process(...)` returns a plain `String`; this struct
/// wraps it with timing/token stats so legacy code compiles.
public struct VLMResult: Sendable {
    public let text: String
    public let totalTimeMs: Double
    public let tokensPerSecond: Double
    public let promptTokens: Int
    public let completionTokens: Int

    public init(text: String, totalTimeMs: Double,
                tokensPerSecond: Double,
                promptTokens: Int, completionTokens: Int) {
        self.text = text
        self.totalTimeMs = totalTimeMs
        self.tokensPerSecond = tokensPerSecond
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }
}

@MainActor
public extension RunAnywhere {
    /// Legacy overload used by the iOS sample benchmarks. Measures
    /// wall-clock time locally and approximates token counts from text
    /// length (~4 chars/token heuristic).
    static func processImage(
        _ image: VLMImage,
        prompt: String,
        maxTokens: Int = 256,
        temperature: Float = 0.0
    ) async throws -> VLMResult {
        let start = Date()
        let opts = VLMGenerationOptions(maxTokens: maxTokens, temperature: temperature)
        let text = try await Self.processImage(image, prompt: prompt, options: opts)
        let elapsed = Date().timeIntervalSince(start) * 1000
        let approxPromptTokens     = max(1, prompt.count / 4)
        let approxCompletionTokens = max(1, text.count  / 4)
        let tps = elapsed > 0
            ? Double(approxCompletionTokens) / (elapsed / 1000)
            : 0
        return VLMResult(
            text: text,
            totalTimeMs: elapsed,
            tokensPerSecond: tps,
            promptTokens: approxPromptTokens,
            completionTokens: approxCompletionTokens)
    }

    /// Legacy helper — cancels any in-flight VLM generation. v2 doesn't
    /// currently hold a per-process VLM session ref (each processImage
    /// call is self-contained); exposed as a no-op for source-compat.
    static func cancelVLMGeneration() async {}
}
