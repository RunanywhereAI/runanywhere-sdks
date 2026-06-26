//
//  HybridAudioPlayback.swift
//  RunAnywhereCore (React Native)
//
//  In-SDK audio playback for TTS features.
//  Port of the Swift SDK source of truth:
//  sdk/runanywhere-swift/Sources/RunAnywhere/Features/TTS/Services/AudioPlaybackManager.swift
//  (AVAudioPlayer over in-memory WAV data; resolve-on-finish via delegate;
//  pause/resume; interruption handling — pause on begin, auto-resume on
//  .shouldResume; session .playback + .duckOthers; deactivate with
//  .notifyOthersOnDeactivation), minus the macOS-only sections.
//

// AVAudioPlayer/AVAudioSession come from AVFoundation submodules.
import AVFoundation
import Foundation
import NitroModules
import os

/// Errors raised by `HybridAudioPlayback`. Mirrors the Swift SDK's
/// `AudioPlaybackError` enum.
enum AudioPlaybackError: LocalizedError {
    case emptyAudioData
    case playbackFailed
    case playbackInterrupted
    case invalidAudioFormat

    var errorDescription: String? {
        switch self {
        case .emptyAudioData:
            return "Audio data is empty"
        case .playbackFailed:
            return "Failed to start audio playback"
        case .playbackInterrupted:
            return "Audio playback was interrupted"
        case .invalidAudioFormat:
            return "Invalid audio format"
        }
    }
}

class HybridAudioPlayback: HybridAudioPlaybackSpec {
    private let logger = SDKLogger(category: "AudioPlayback")

    private struct State {
        var audioPlayer: AVAudioPlayer?
        var playbackContinuation: CheckedContinuation<Void, Error>?
        /// Whether THIS playback configured/activated the session (TTS-only
        /// screen). When the voice agent owns a shared `.playAndRecord` session
        /// this stays false so cleanup does not deactivate it mid-capture.
        var ownsSession = false
    }

    /// The mutable playback state lives behind a single unfair lock so the
    /// play-time write and the delegate-callback read+clear never race
    /// (Swift SDK parity: OSAllocatedUnfairLock<State>).
    private let lock = OSAllocatedUnfairLock(initialState: State())

    /// AVAudioPlayerDelegate requires NSObjectProtocol; the Nitro spec base is
    /// already a class, so delegate callbacks are received by this proxy and
    /// forwarded back to the hybrid.
    private lazy var delegateProxy = PlaybackDelegateProxy(owner: self)

    // MARK: - Properties

    var isPlaying: Bool {
        lock.withLock { $0.audioPlayer?.isPlaying ?? false }
    }

    var currentTime: Double {
        lock.withLock { $0.audioPlayer?.currentTime ?? 0.0 }
    }

    var duration: Double {
        lock.withLock { $0.audioPlayer?.duration ?? 0.0 }
    }

    // MARK: - Methods

    /// Play in-memory WAV data. Resolves when playback finishes, rejects on
    /// failure/interruption (delegate-driven — no JS polling).
    func play(wavData: ArrayBuffer) throws -> Promise<Void> {
        // Copy synchronously — the JS-owned buffer is only valid during this call.
        let audioData = wavData.toData(copyIfNeeded: true)
        return Promise.async { [weak self] in
            guard let self else { return }
            guard !audioData.isEmpty else {
                throw AudioPlaybackError.emptyAudioData
            }
            try await self.playAwaitingCompletion {
                try AVAudioPlayer(data: audioData)
            }
        }
    }

    /// Play an audio file from disk. Resolves when playback finishes.
    func playFile(path: String) throws -> Promise<Void> {
        return Promise.async { [weak self] in
            guard let self else { return }
            try await self.playAwaitingCompletion {
                try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            }
        }
    }

    /// Stop current playback. An in-flight `play()` promise rejects with
    /// `playbackInterrupted` (Swift SDK parity: cleanup(success: false)).
    func stop() throws {
        let player = lock.withLock { $0.audioPlayer }
        guard let player else { return }

        player.stop()
        cleanupPlayback(success: false)
        logger.info("Playback stopped by user")
    }

    /// Pause current playback (Swift SDK AudioPlaybackManager.swift:113-117).
    func pause() throws {
        guard isPlaying else { return }
        lock.withLock { $0.audioPlayer }?.pause()
        logger.info("Playback paused")
    }

    /// Resume paused playback (Swift SDK AudioPlaybackManager.swift:120-124).
    func resume() throws {
        guard let player = lock.withLock({ $0.audioPlayer }), !player.isPlaying else { return }
        player.play()
        logger.info("Playback resumed")
    }

    // MARK: - Private Implementation

    private func playAwaitingCompletion(makePlayer: @escaping () throws -> AVAudioPlayer) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try startPlayback(makePlayer: makePlayer, continuation: continuation)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func startPlayback(
        makePlayer: () throws -> AVAudioPlayer,
        continuation: CheckedContinuation<Void, Error>
    ) throws {
        // Stop any existing playback first.
        if lock.withLock({ $0.audioPlayer }) != nil {
            try? stop()
        }

        // Configure audio session for playback (.playback + .duckOthers).
        try configureAudioSession()

        // Create and configure audio player.
        let player = try makePlayer()
        player.delegate = delegateProxy
        player.prepareToPlay()

        guard player.play() else {
            deactivateAudioSession()
            throw AudioPlaybackError.playbackFailed
        }

        lock.withLock { current in
            current.audioPlayer = player
            current.playbackContinuation = continuation
        }

        logger.info("Playback started, duration: \(player.duration)s")
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        // The voice agent owns a full-duplex `.playAndRecord` session for the
        // whole turn-taking loop (mic capture stays live while the reply plays).
        // Forcing `.playback` here is output-only: it tears down the running
        // capture engine and trips cannotStartPlaying (OSStatus 561017449). When
        // such a session is already active, reuse it untouched and leave it alone
        // on cleanup. The TTS-only screen (no capture session) still gets a
        // dedicated `.playback` session.
        if session.category == .playAndRecord {
            // Reuse the voice agent's live session untouched, but force the loud
            // speaker route: under `.playAndRecord` the output can fall back to the
            // quiet receiver/earpiece, which presents as "no audio" even though
            // playback succeeded.
            try? session.overrideOutputAudioPort(.speaker)
            logger.info("[playback-v2] reusing active .playAndRecord session (speaker route, no setCategory)")
            lock.withLock { $0.ownsSession = false }
            return
        }
        logger.info("[playback-v2] configuring dedicated .playback session (category was \(session.category.rawValue))")
        try session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try session.setActive(true)
        lock.withLock { $0.ownsSession = true }
    }

    private func deactivateAudioSession() {
        let owns = lock.withLock { current -> Bool in
            let value = current.ownsSession
            current.ownsSession = false
            return value
        }
        guard owns else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    fileprivate func cleanupPlayback(success: Bool) {
        deactivateAudioSession()

        // Atomically take ownership of the one-shot continuation and clear
        // the player, then resume outside the lock.
        let continuation = lock.withLock { current -> CheckedContinuation<Void, Error>? in
            let taken = current.playbackContinuation
            current.playbackContinuation = nil
            current.audioPlayer = nil
            return taken
        }

        if let continuation {
            if success {
                continuation.resume()
            } else {
                continuation.resume(throwing: AudioPlaybackError.playbackInterrupted)
            }
        }
    }

    // MARK: - Delegate Forwarding (AVAudioPlayerDelegate parity)

    fileprivate func didFinishPlaying(successfully flag: Bool) {
        logger.info("Playback finished: \(flag ? "success" : "failed")")
        cleanupPlayback(success: flag)
    }

    fileprivate func decodeErrorDidOccur(_ error: Error?) {
        logger.error("Playback decode error: \(error?.localizedDescription ?? "unknown")")
        cleanupPlayback(success: false)
    }

    fileprivate func beginInterruption(player: AVAudioPlayer) {
        // Swift SDK AudioPlaybackManager.swift:239-244 — the system pauses
        // the player; `isPlaying` derives from the player so no extra state.
        logger.info("Playback interrupted")
        player.pause()
    }

    fileprivate func endInterruption(player: AVAudioPlayer, withOptions flags: Int) {
        // Swift SDK AudioPlaybackManager.swift:246-254 — auto-resume on
        // .shouldResume.
        logger.info("Playback interruption ended")
        if flags == AVAudioSession.InterruptionOptions.shouldResume.rawValue {
            player.play()
        }
    }

    deinit {
        try? stop()
    }
}

/// NSObject delegate proxy — receives AVAudioPlayerDelegate callbacks and
/// forwards them to the owning hybrid (which cannot subclass NSObject because
/// it already inherits the Nitro spec base class).
private final class PlaybackDelegateProxy: NSObject, AVAudioPlayerDelegate {
    private weak var owner: HybridAudioPlayback?

    init(owner: HybridAudioPlayback) {
        self.owner = owner
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        owner?.didFinishPlaying(successfully: flag)
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        owner?.decodeErrorDidOccur(error)
    }

    func audioPlayerBeginInterruption(_ player: AVAudioPlayer) {
        owner?.beginInterruption(player: player)
    }

    func audioPlayerEndInterruption(_ player: AVAudioPlayer, withOptions flags: Int) {
        owner?.endInterruption(player: player, withOptions: flags)
    }
}
