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
        /// Watches the core's own event stream for a barge-in. Owned by the
        /// session rather than by a caller's `events` subscription: stopping the
        /// speaker when the user takes the turn is the session's job and has to
        /// happen whether or not anybody is rendering events.
        var bargeInTask: Task<Void, Never>?
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

            // Speaking over the agent: the core decides whether an onset inside
            // the audible window is a real interruption or the microphone hearing
            // the loudspeaker, and says so with INTERRUPT_REASON_USER_BARGE_IN.
            // Only this layer can stop the speaker, so this subscription is the
            // other half of that handshake — without it the core's decision has
            // no effect and the agent talks over the user to the end of its
            // sentence.
            let protoStream = adapter.stream()
            locked.bargeInTask = Task { [weak self, logger] in
                for await proto in protoStream {
                    if Task.isCancelled { break }
                    guard case .interrupted(let interrupted) = proto.payload,
                          interrupted.reason == .userBargeIn else { continue }
                    logger.info("User barge-in: stopping playout, turn handed back")
                    let driver = self?.state.withLock { $0.driver }
                    driver?.stopPlayback(discardPendingInput: false)
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
        // The control was pressed, so whatever is queued behind it is the tail of
        // the agent's own playout rather than the user's next sentence.
        driver?.stopPlayback(discardPendingInput: true)
        if let handle = RunAnywhere.activeSpeechHandleSnapshot() {
            await handle.interrupt()
        } else {
            await RunAnywhere.stopSpeech()
        }
    }

    /// Stop capture, tear down the pipeline, and release native resources.
    public func close() async {
        let torn = state.withLock { locked -> (Task<Void, Never>?, Task<Void, Never>?, Bool) in
            guard !locked.isClosed else { return (nil, nil, false) }
            locked.isClosed = true
            let mic = locked.micTask
            let bargeIn = locked.bargeInTask
            locked.micTask = nil
            locked.bargeInTask = nil
            locked.driver = nil
            return (mic, bargeIn, true)
        }
        guard torn.2 else { return }
        torn.1?.cancel()
        torn.0?.cancel()
        // Both tasks are awaited, not just the mic: `cancel()` is cooperative, and
        // the barge-in task holds a subscription on the adapter's event stream.
        // Leaving the loop is what fires the stream's `onTermination`, which
        // deregisters the native proto callback and quiesces it. Returning before
        // that has happened lets the deregistration land after
        // `rac_voice_agent_cleanup` has already torn the pipeline down.
        await torn.1?.value
        await torn.0?.value
        await CppBridge.VoiceAgent.shared.cleanup()
    }
}
