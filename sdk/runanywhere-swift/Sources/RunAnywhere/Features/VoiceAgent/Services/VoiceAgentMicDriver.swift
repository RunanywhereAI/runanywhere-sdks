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

    private let chunkLock = OSAllocatedUnfairLock<[Data]>(initialState: [])

    init(handle: CppBridge.VoiceAgentHandle) {
        self.handle = handle
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
        try await capture.startRecording(configureSession: false) { [weak self] chunk in
            self?.enqueueChunk(chunk)
        }
        logger.info("Voice-agent mic capture started")

        defer {
            capture.stopRecording(deactivateSession: true)
            playback.stop()
            chunkLock.withLock { $0.removeAll() }
            logger.info("Voice-agent mic capture stopped")
        }

        try await feedLoop()
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
                    sampleRateHz: Int32(MicConstants.sampleRateHz),
                    channels: 1,
                    encoding: Int32(RAAudioEncoding.pcmS16Le.rawValue),
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
                    try await playback.play(reply)
                    discardPendingChunks()
                }
            }
        }
    }
}

private enum MicConstants {
    static let sampleRateHz = 16_000
    static let channelCapacity = 128
}
