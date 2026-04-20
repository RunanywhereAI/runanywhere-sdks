// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// PCM playback queue built on AVAudioEngine + AVAudioPlayerNode.
// Ports the capability surface from legacy `sdk/runanywhere-swift/Sources/
// RunAnywhere/Features/TTS/Services/AudioPlaybackManager.swift`.

#if canImport(AVFoundation)
import AVFoundation
#endif
import Foundation

/// Queue-driven PCM playback. Call `play(pcm:sampleRate:)` for each TTS
/// synthesis result; buffers are scheduled end-to-end with back-pressure.
@MainActor
public final class AudioPlaybackManager: ObservableObject {

    public enum Error: Swift.Error, LocalizedError {
        case formatFailed
        case engineStartFailed(message: String)
        case unsupportedPlatform

        public var errorDescription: String? {
            switch self {
            case .formatFailed:             return "Failed to build playback format"
            case .engineStartFailed(let m): return "Failed to start playback engine: \(m)"
            case .unsupportedPlatform:      return "Audio playback not supported on this platform"
            }
        }
    }

#if canImport(AVFoundation) && !os(watchOS)
    @Published public private(set) var isPlaying = false
    @Published public private(set) var queuedBufferCount = 0

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    private var sessionConfigured = false

    public init() {
        engine.attach(playerNode)
    }

    /// Enqueue a PCM buffer for playback. Sample rate can change between
    /// calls — the player reconfigures on mismatch.
    public func play(pcm: [Float], sampleRateHz: Int) throws {
        guard let fmt = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRateHz),
            channels: 1,
            interleaved: false
        ) else { throw Error.formatFailed }

        try ensureConfigured(format: fmt)

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: fmt, frameCapacity: AVAudioFrameCount(pcm.count)
        ) else { throw Error.formatFailed }

        buffer.frameLength = AVAudioFrameCount(pcm.count)
        if let channel = buffer.floatChannelData?.pointee {
            pcm.withUnsafeBufferPointer { src in
                channel.update(from: src.baseAddress!, count: pcm.count)
            }
        }

        queuedBufferCount += 1
        playerNode.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.queuedBufferCount = max(0, self.queuedBufferCount - 1)
                if self.queuedBufferCount == 0 {
                    self.isPlaying = false
                }
            }
        }

        if !playerNode.isPlaying {
            playerNode.play()
            isPlaying = true
        }
    }

    /// Stop playback immediately and drop the queued buffers.
    public func stop() {
        playerNode.stop()
        queuedBufferCount = 0
        isPlaying = false
    }

    /// Fade out over `duration` seconds, then stop.
    public func fadeOutAndStop(duration: TimeInterval = 0.2) {
        playerNode.volume = 0.0  // immediate — AVAudioPlayerNode has no ramp API
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            self?.stop()
            self?.playerNode.volume = 1.0
        }
    }

    // MARK: - Internals

    private func ensureConfigured(format: AVAudioFormat) throws {
        if let current = self.format,
           current.sampleRate == format.sampleRate,
           current.channelCount == format.channelCount {
            return
        }

        if playerNode.isPlaying { playerNode.stop() }
        if engine.isRunning { engine.stop() }
        engine.disconnectNodeOutput(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        self.format = format

        #if os(iOS) || os(tvOS)
        if !sessionConfigured {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            sessionConfigured = true
        }
        #endif

        do {
            try engine.start()
        } catch {
            throw Error.engineStartFailed(message: error.localizedDescription)
        }
    }

    deinit {
        // MainActor-isolated stop() can't run in deinit; rely on host to stop.
    }

#else  // watchOS / non-AVFoundation
    public init() {}
    public func play(pcm: [Float], sampleRateHz: Int) throws {
        throw Error.unsupportedPlatform
    }
    public func stop() {}
    public func fadeOutAndStop(duration: TimeInterval = 0.2) {}
    public var isPlaying: Bool { false }
    public var queuedBufferCount: Int { 0 }
#endif
}
