//
//  VoiceSession.swift
//  RunAnywhere SDK
//
//  A live voice agent. The session owns its prerequisites: it downloads and
//  loads the models it was handed, ensures a VAD is resident, and wires the
//  pipeline. Subscribing to `events` never opens the microphone — `start()` is
//  the only thing that does.
//

import Foundation
import os

/// A running voice agent that listens, thinks, and speaks.
public final class VoiceSession: @unchecked Sendable {

    private struct State {
        var micTask: Task<Void, Never>?
        var driver: VoiceAgentMicDriver?
        var isClosed = false
        /// Subscribers of `events`, so the driver's playout phase can be merged
        /// into the same stream the core's events arrive on.
        var subscribers: [UUID: AsyncThrowingStream<VoiceEvent, Error>.Continuation] = [:]
    }

    private let handle: CppBridge.VoiceAgentHandle
    private let adapter: VoiceAgentStreamAdapter
    private let ttsOptions: RATTSOptions
    private let state = OSAllocatedUnfairLock<State>(initialState: State())
    private let logger = SDKLogger(category: "RunAnywhere.VoiceSession")

    internal init(
        handle: CppBridge.VoiceAgentHandle,
        ttsOptions: RATTSOptions
    ) {
        self.handle = handle
        self.adapter = VoiceAgentStreamAdapter(handle: handle.rawValue)
        self.ttsOptions = ttsOptions
    }

    /// Turn-by-turn activity from the pipeline.
    ///
    /// Iterating this does not start audio capture.
    ///
    /// Carries two merged sources: the core's own voice events, and the
    /// `.speaking`/`.listening` phase the mic driver reports around real
    /// playout. The core cannot supply the latter — it emits `PLAYING_TTS`
    /// before synthesis and hands the audio back for the platform to play — so
    /// without the merge a subscriber is told the agent is speaking while the
    /// speaker is silent, and is never told when it stops.
    public var events: AsyncThrowingStream<VoiceEvent, Error> {
        // `adapter.stream()` is what installs the native proto callback, and it
        // has to run before this getter returns. It used to be called inside the
        // pump `Task` below, which only *scheduled* the installation: a caller
        // that reads `session.events` and then immediately calls `start()` could
        // open the microphone and run an entire turn before the callback
        // existed, and every event of that turn — transcript, reply, agent
        // state — was dropped on the floor. Playback survived regardless,
        // because the mic driver plays the audio the feed call returns inline,
        // so the panel sat dead while the product talked out loud. Attaching
        // here makes the subscription a fact by the time `events` is handed back.
        let protoStream = adapter.stream()

        return AsyncThrowingStream { continuation in
            let id = UUID()
            state.withLock { $0.subscribers[id] = continuation }

            let task = Task {
                for await proto in protoStream {
                    if Task.isCancelled { break }
                    if let event = VoiceEvent.from(proto: proto) {
                        continuation.yield(event)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable [state] _ in
                state.withLock { $0.subscribers[id] = nil }
                task.cancel()
            }
        }
    }

    /// Fan one locally-observed event out to every `events` subscriber.
    private func publish(_ event: VoiceEvent) {
        let continuations = state.withLock { Array($0.subscribers.values) }
        for continuation in continuations { continuation.yield(event) }
    }

    /// Open the microphone and begin the turn-taking loop.
    ///
    /// - Throws: `SDKException` when the session is closed or the microphone is
    ///   unavailable.
    public func start() throws {
        try state.withLock { locked in
            guard !locked.isClosed else {
                throw SDKException(
                    code: .invalidState,
                    message: "Voice session is closed",
                    category: .component
                )
            }
            guard locked.micTask == nil else { return }

            let driver = VoiceAgentMicDriver(handle: handle) { [weak self] phase in
                self?.publish(.agentStateChanged(phase))
            }
            locked.driver = driver
            locked.micTask = Task { [logger] in
                do {
                    try await driver.run()
                } catch is CancellationError {
                    // Expected when the caller stops the session.
                } catch {
                    logger.error("Voice-agent mic driver stopped: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Speak `text` now, outside the turn loop.
    ///
    /// - Throws: `SDKException` when no TTS voice is loaded or synthesis fails.
    @discardableResult
    public func say(_ text: String) async throws -> SpeechHandle {
        try await RunAnywhere.speakAndTrack(text: text, options: ttsOptions)
    }

    /// Stop the agent mid-utterance and await settlement of playback and any
    /// in-flight response before returning.
    public func interrupt() async {
        let driver = state.withLock { $0.driver }
        driver?.stopPlayback()
        if let handle = RunAnywhere.activeSpeechHandleSnapshot() {
            await handle.interrupt()
        } else {
            await RunAnywhere.stopSpeech()
        }
    }

    /// Stop capture, tear down the pipeline, and release native resources.
    public func close() async {
        let torn = state.withLock { locked -> (Task<Void, Never>?, Bool) in
            guard !locked.isClosed else { return (nil, false) }
            locked.isClosed = true
            let task = locked.micTask
            locked.micTask = nil
            locked.driver = nil
            return (task, true)
        }
        guard torn.1 else { return }
        torn.0?.cancel()
        await torn.0?.value
        await CppBridge.VoiceAgent.shared.cleanup()
    }
}
