//
//  VoiceAgentMicDriver.swift
//  RunAnywhere SDK
//
//  Audio ingress for the voice agent. The C ABI owns no microphone access;
//  the platform SDK captures raw mic frames and pushes them continuously into
//  the C core via rac_voice_agent_feed_audio_proto. The core performs energy-
//  based utterance segmentation and runs the STT -> LLM -> TTS turn pipeline
//  itself, returning the synthesized reply inline for playback. This driver is
//  therefore a thin capture -> feed -> play loop with NO SDK-side VAD.
//
//  Playout runs CONCURRENTLY with the feed loop. It used to be awaited inline,
//  which stopped the feed for the whole of a reply and then dropped everything
//  captured during it — so speaking over the agent could not be heard at all and
//  the only way to take the turn back was the on-screen control. The core
//  already decides whether an onset inside the audible window is a real
//  interruption or the agent hearing itself (see the echo estimate in
//  voice_agent_feed_abi.cpp); this layer's job is only to keep the frames
//  flowing and to stop the speaker when the core says the user has the turn.
//

import AVFoundation
import CRACommons
import Foundation
import os

/// Captures mic audio and feeds raw frames to the in-core voice agent.
///
/// Mirrors Kotlin `VoiceAgentMicDriver.kt`. Segmentation/endpointing lives in
/// the C core (`rac_voice_agent_feed_audio_proto`); frames captured while a
/// turn is processing are dropped by the bounded queue.
final class VoiceAgentMicDriver: @unchecked Sendable {
    private let handle: CppBridge.VoiceAgentHandle
    private let capture = AudioCaptureManager()
    private let playback = AudioPlaybackManager()
    private let logger = SDKLogger(category: "VoiceAgentMic")

    /// Reports `.speaking` when a reply becomes audible and `.listening` when it
    /// stops. The core emits `PLAYING_TTS` *before* synthesis and hands the WAV
    /// back for this driver to play, so its pipeline states describe intent, not
    /// sound. Only this layer knows when audio is actually leaving the speaker,
    /// so only this layer can say "speaking" truthfully — and the interrupt
    /// affordance a UI mounts on that state is then reachable exactly while
    /// there is something to interrupt.
    private let onPlaybackPhase: @Sendable (AgentState) -> Void

    private let chunkLock = OSAllocatedUnfairLock<[Data]>(initialState: [])

    /// The reply currently coming out of the speaker, held so it can be cut off
    /// from outside the feed loop — which is the whole point of not awaiting it
    /// inline any more.
    /// The live playout task plus the generation that owns it.
    ///
    /// The generation is what makes a stale task harmless. Both tasks share one
    /// `AudioPlaybackManager` and one phase callback, so without it a retiring
    /// task could stop the player its successor had just started, and report
    /// `.listening` over its successor's `.speaking` — leaving the panel idle
    /// while the reply was audible.
    private struct PlayoutState {
        var task: Task<Void, Never>?
        var generation: UInt64 = 0
    }

    private let playoutLock = OSAllocatedUnfairLock<PlayoutState>(initialState: PlayoutState())

    init(
        handle: CppBridge.VoiceAgentHandle,
        onPlaybackPhase: @escaping @Sendable (AgentState) -> Void = { _ in }
    ) {
        self.handle = handle
        self.onPlaybackPhase = onPlaybackPhase
    }

    /// Runs until the calling task is cancelled.
    func run() async throws {
        guard await capture.requestPermission() else {
            throw SDKException(
                code: .permissionDenied,
                message: "Microphone permission denied",
                category: .component
            )
        }

        // The voice agent owns a single full-duplex session for the whole turn-
        // taking loop. Capture and playback must NOT reconfigure or deactivate it:
        // a `.record` override silences the reply and disables voice-processing
        // AGC on the mic signal, and a playback deactivate tears down the live
        // capture engine mid-session.
        try await configureVoiceAudioSession()
        playback.managesAudioSession = false

        // Register teardown BEFORE startRecording: configureVoiceAudioSession has
        // already activated the shared .playAndRecord session, so if capture start
        // throws (mic contended / engine fails) this defer still deactivates it —
        // otherwise the activated session leaks and other apps stay ducked.
        defer {
            capture.stopRecording(deactivateSession: true)
            // Cancelling the playout task is what restores the `.listening`
            // phase for a subscriber; `playback.stop()` alone would leave a UI
            // latched on "Speaking" over a silent speaker.
            cancelPlayout()
            chunkLock.withLock { $0.removeAll() }
            logger.info("Voice-agent mic capture stopped")
        }

        try await capture.startRecording(configureSession: false) { [weak self] chunk in
            self?.enqueueChunk(chunk)
        }
        logger.info("Voice-agent mic capture started")

        try await feedLoop()
    }

    /// Cut the agent off mid-utterance.
    ///
    /// - Parameter discardPendingInput: `true` for the on-screen interrupt
    ///   control, where the frames buffered behind the tap are the tail of the
    ///   agent's own playout and belong to nobody. `false` for a voice barge-in,
    ///   where those frames are the first syllables of the user's sentence —
    ///   dropping them would clip the very turn that caused the interrupt.
    func stopPlayback(discardPendingInput: Bool) {
        cancelPlayout()
        if discardPendingInput {
            discardPendingChunks()
        }
    }

    // MARK: - Audio session

    private func configureVoiceAudioSession() async throws {
        #if os(iOS) || os(tvOS)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let session = AVAudioSession.sharedInstance()
                    // `.default`, not `.voiceChat`. The agent is full-duplex (see
                    // the file header), so this is NOT "we don't need echo
                    // cancellation" — it is a measured trade. `.voiceChat` forces
                    // the telephony I/O path, which attenuates speaker output to
                    // call levels (quiet replies) and runs an AGC that suppresses
                    // the mic after a long playout, breaking endpointing on every
                    // turn after the first; both were observed, and a pipeline that
                    // stops hearing anything after turn one is worse than one that
                    // occasionally misses an interruption.
                    //
                    // What pays for that choice is the core's echo estimate
                    // (voice_agent_feed_abi.cpp): with no canceller, a voice over
                    // the reply has to arrive ~8 dB above what the loudspeaker puts
                    // into this same microphone.
                    //
                    // An earlier version of this comment cited a simulator run over
                    // a 0 dB-coupled loopback as evidence that this worked. It is
                    // not evidence of anything: a loopback returns the agent's own
                    // voice to the microphone at full level and returns nothing
                    // else, so it exercises neither the coupling a room has nor the
                    // advantage a nearby talker has. Replaying real recordings made
                    // over an actual speaker -> room -> microphone path through the
                    // same decision showed it firing on NONE of six interruptions,
                    // including ones 24 dB louder than the agent, because the echo
                    // estimate was a running maximum that absorbed the interrupting
                    // voice itself. That is fixed in the core, where the estimate is
                    // now predicted from the reply's own waveform; on the same
                    // recordings it fires from about 6 dB of advantage upwards and
                    // still never on the agent alone.
                    try session.setCategory(
                        .playAndRecord,
                        mode: .default,
                        options: [.defaultToSpeaker, .allowBluetooth]
                    )
                    try session.setActive(true)
                    // Force the loud speaker route; `.defaultToSpeaker` alone can fall
                    // back to the receiver under `.playAndRecord`.
                    try session.overrideOutputAudioPort(.speaker)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        #endif
    }

    // MARK: - Chunk queue

    private func enqueueChunk(_ chunk: Data) {
        chunkLock.withLock { queue in
            queue.append(chunk)
            if queue.count > MicConstants.channelCapacity {
                queue.removeFirst(queue.count - MicConstants.channelCapacity)
            }
        }
    }

    private func drainChunks() -> [Data] {
        chunkLock.withLock { queue in
            let drained = queue
            queue.removeAll()
            return drained
        }
    }

    private func discardPendingChunks() {
        chunkLock.withLock { $0.removeAll() }
    }

    // MARK: - Feed loop

    /// Drains captured frames and feeds them to the core. The core blocks the
    /// feed call for the duration of a turn when an utterance closes and returns
    /// the synthesized reply inline; playout is started concurrently and the
    /// loop goes straight back to feeding, so a voice arriving over the reply
    /// reaches the core while there is still something to interrupt. The core
    /// drops the backlog captured while it was computing the turn, so the
    /// device's own playout is never re-segmented as a user turn.
    private func feedLoop() async throws {
        while !Task.isCancelled {
            let chunks = drainChunks()
            if chunks.isEmpty {
                try await Task.sleep(nanoseconds: 20_000_000)
                continue
            }

            for chunk in chunks {
                if Task.isCancelled { return }

                let (status, result) = try CppBridge.VoiceAgent.feedAudioProto(
                    handle: handle.rawValue,
                    audio: chunk,
                    sampleRate: Int32(MicConstants.sampleRateHz),
                    channels: 1,
                    encoding: .pcmS16Le,
                    isFinal: false
                )

                if status == RAC_ERROR_NOT_INITIALIZED {
                    throw SDKException(
                        code: .notInitialized,
                        message: "Voice agent is no longer initialized",
                        category: .component
                    )
                }
                if status != RAC_SUCCESS {
                    logger.warning("Voice feed failed: rc=\(status)")
                    continue
                }

                // A non-empty reply means the core closed an utterance and ran a
                // full turn this call. `synthesizedAudio` is self-describing WAV.
                if let reply = result?.synthesizedAudio, !reply.isEmpty {
                    logger.info("Playing agent reply (\(reply.count) WAV bytes)")
                    // The feed call blocked for the whole turn, so this queue now
                    // holds whatever the microphone heard while the reply was
                    // being computed. Those frames predate playout: they are not
                    // part of the turn that just closed and they are not the user
                    // talking over a reply that had not started. Feeding them
                    // would seed the core's echo estimate from pre-playout quiet
                    // and let the reply's own onset clear the bar it set — the
                    // agent interrupting itself. The core drops its own partial
                    // frame the same way; this drops the driver's.
                    discardPendingChunks()
                    startPlayout(reply)
                }
            }
        }
    }

    // MARK: - Playout

    /// Begin one reply without blocking the feed loop, bracketing it with the
    /// phase the UI renders.
    ///
    /// The `.listening` report is in a `defer` so an interrupted or failed
    /// playout still ends the speaking state — a panel that latches on
    /// "Speaking" over a silent speaker is the exact contradiction this signal
    /// exists to prevent.
    private func startPlayout(_ wav: Data) {
        // Claim a generation, take custody of the outgoing task, and install the
        // new one — all under one lock, so two rapid replies cannot both believe
        // they are current.
        //
        // The new task used to be created (and so allowed to start playing)
        // before the stale one was cancelled. Cancelling the stale task runs its
        // `play(_:)` cancellation handler, which stops the shared player — the one
        // the new reply had just started. The reply went silent while the panel
        // said Speaking. The feed loop deliberately keeps running during playout,
        // so that overlap is reachable, not theoretical.
        playoutLock.withLock { state in
            state.generation += 1
            let generation = state.generation
            let previous = state.task
            previous?.cancel()
            state.task = Task { [weak self] in
                guard let self else { return }
                // Let the cancelled playout finish its teardown before this one
                // touches the player. Awaiting the task — not just cancelling it —
                // is what orders the stale `stop()` before the new `play()`.
                await previous?.value
                guard self.isCurrentPlayout(generation) else { return }
                self.onPlaybackPhase(.speaking)
                // Only the current generation may hand the UI back to `.listening`;
                // a task retired mid-playout would otherwise contradict its
                // successor.
                defer {
                    if self.isCurrentPlayout(generation) { self.onPlaybackPhase(.listening) }
                }
                do {
                    try await self.playback.play(wav)
                } catch is CancellationError {
                    // Session teardown or barge-in; `defer` restored the phase.
                } catch {
                    // A cut-off playout lands here too — the ordinary outcome of the
                    // interrupt control or of the user talking over the reply, not a
                    // fault, so it is not logged as an error.
                    self.logger.info("Agent reply playout ended early: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Whether `generation` is still the playout the driver considers live.
    private func isCurrentPlayout(_ generation: UInt64) -> Bool {
        !Task.isCancelled && playoutLock.withLock { $0.generation == generation }
    }

    /// Stop whatever is playing and let the playout task report `.listening`.
    private func cancelPlayout() {
        // Bumping the generation retires the live task's right to report a phase,
        // so a playout cancelled here cannot publish `.listening` on top of
        // whatever the caller does next.
        let task = playoutLock.withLock { state -> Task<Void, Never>? in
            let live = state.task
            state.task = nil
            state.generation += 1
            return live
        }
        task?.cancel()
        // `play(_:)`'s cancellation handler stops the player, but a task that has
        // not started yet has no handler installed; stopping directly makes the
        // silence immediate either way.
        playback.stop()
    }
}

private enum MicConstants {
    static let sampleRateHz = RADefaults.AudioCapture.micSampleRateHz
    static let channelCapacity = RADefaults.AudioCapture.micChannelCapacity
}
