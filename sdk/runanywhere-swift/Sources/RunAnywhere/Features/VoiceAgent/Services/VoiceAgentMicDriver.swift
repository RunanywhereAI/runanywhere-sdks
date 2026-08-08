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
            playback.stop()
            chunkLock.withLock { $0.removeAll() }
            logger.info("Voice-agent mic capture stopped")
        }

        try await capture.startRecording(configureSession: false) { [weak self] chunk in
            self?.enqueueChunk(chunk)
        }
        logger.info("Voice-agent mic capture started")

        try await feedLoop()
    }

    /// Cut the agent off mid-utterance: stop playout and drop the frames that
    /// were captured while it was speaking.
    func stopPlayback() {
        playback.stop()
        discardPendingChunks()
    }

    // MARK: - Audio session

    private func configureVoiceAudioSession() async throws {
        #if os(iOS) || os(tvOS)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let session = AVAudioSession.sharedInstance()
                    // `.default` (not `.voiceChat`): the agent is half-duplex — the
                    // mic is gated while TTS plays, so we don't need voice-processing
                    // echo cancellation. `.voiceChat` forces the telephony I/O path,
                    // which attenuates speaker output to call levels (quiet replies)
                    // and runs an AGC that suppresses the mic after a long playout,
                    // breaking endpointing on every turn after the first.
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
    /// feed call for the duration of a turn when an utterance closes and
    /// returns the synthesized reply inline; we play it and drop any backlog
    /// captured during the turn so the device's own playout is not re-fed.
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
                    await playReply(reply)
                    discardPendingChunks()
                }
            }
        }
    }

    /// Play one reply, bracketing it with the phase the UI renders.
    ///
    /// The `.listening` report is in a `defer` so an interrupted or failed
    /// playout still ends the speaking state — a panel that latches on
    /// "Speaking" over a silent speaker is the exact contradiction this
    /// signal exists to prevent. Mirrors Kotlin `playReply`.
    private func playReply(_ wav: Data) async {
        onPlaybackPhase(.speaking)
        defer { onPlaybackPhase(.listening) }
        do {
            try await playback.play(wav)
        } catch is CancellationError {
            // Session teardown; `defer` has already restored the listening phase.
        } catch {
            // Barge-in lands here too: the user took the turn back mid-utterance,
            // which is the ordinary outcome of the interrupt control rather than
            // a fault, so it is not logged as an error.
            logger.info("Agent reply playout ended early: \(error.localizedDescription)")
        }
    }
}

private enum MicConstants {
    static let sampleRateHz = RADefaults.AudioCapture.micSampleRateHz
    static let channelCapacity = RADefaults.AudioCapture.micChannelCapacity
}
