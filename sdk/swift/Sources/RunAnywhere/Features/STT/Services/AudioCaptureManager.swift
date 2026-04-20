// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Microphone audio capture for STT sessions. Ports the capability surface
// from legacy `sdk/runanywhere-swift/Sources/RunAnywhere/Features/STT/
// Services/AudioCaptureManager.swift`, adapted to feed `ra_stt_feed_audio`
// (or any `(Float[]) -> Void` callback the host supplies) instead of
// routing through the legacy `CppBridge+STT.feedAudio`.
//
// Platform support: iOS, tvOS, macOS. watchOS skipped — AVAudioEngine
// inputNode tap is unreliable there.

#if canImport(AVFoundation)
import AVFoundation
#endif
import Foundation
import CRACommonsCore

/// Captures mic audio at 16 kHz mono and pushes Float[] chunks to a
/// user-supplied callback. Defaults match Whisper's input format.
@MainActor
public final class AudioCaptureManager: ObservableObject {

    public struct Configuration: Sendable {
        public var targetSampleRate: Double
        public var bufferSize: UInt32
        public init(targetSampleRate: Double = 16_000, bufferSize: UInt32 = 4_096) {
            self.targetSampleRate = targetSampleRate
            self.bufferSize = bufferSize
        }
    }

    public enum Error: Swift.Error, LocalizedError {
        case permissionDenied
        case formatConversionFailed
        case engineStartFailed(message: String)
        case noInputDevice
        case unsupportedPlatform

        public var errorDescription: String? {
            switch self {
            case .permissionDenied:         return "Microphone permission denied"
            case .formatConversionFailed:   return "Failed to convert audio format"
            case .engineStartFailed(let m): return "Failed to start audio engine: \(m)"
            case .noInputDevice:            return "No audio input device available"
            case .unsupportedPlatform:      return "Audio capture not supported on this platform"
            }
        }
    }

#if canImport(AVFoundation) && !os(watchOS)
    @Published public private(set) var isRecording = false
    @Published public private(set) var audioLevel: Float = 0
    private let configuration: Configuration
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    /// Request mic permission.
    public func requestPermission() async -> Bool {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        }
        return await withCheckedContinuation { c in
            AVAudioSession.sharedInstance().requestRecordPermission { c.resume(returning: $0) }
        }
        #elseif os(tvOS)
        return await withCheckedContinuation { c in
            AVAudioSession.sharedInstance().requestRecordPermission { c.resume(returning: $0) }
        }
        #elseif os(macOS)
        return await withCheckedContinuation { c in
            AVCaptureDevice.requestAccess(for: .audio) { c.resume(returning: $0) }
        }
        #else
        return false
        #endif
    }

    /// Start recording, delivering each converted buffer as raw `Data`.
    /// Main-branch sample UIs consume `Data` directly; this wraps the
    /// `[Float]` overload and converts float32 samples to a byte buffer.
    public func startRecording(
        onAudio: @escaping @Sendable (Data) -> Void
    ) async throws {
        try await startRecording { (samples: [Float]) in
            let bytes = samples.withUnsafeBufferPointer { ptr -> Data in
                Data(bytes: ptr.baseAddress!, count: ptr.count * MemoryLayout<Float>.size)
            }
            onAudio(bytes)
        }
    }

    /// Start recording. The callback fires on a background queue with each
    /// converted buffer as `[Float]` samples.
    public func startRecording(
        onAudio: @escaping @Sendable ([Float]) -> Void
    ) async throws {
        guard !isRecording else { return }

        #if os(iOS) || os(tvOS)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Swift.Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.record, mode: .measurement)
                    try session.setActive(true)
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
        #endif

        let engine = AVAudioEngine()
        let node = engine.inputNode
        let inputFormat = node.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw Error.noInputDevice
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: configuration.targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw Error.formatConversionFailed
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw Error.formatConversionFailed
        }

        node.installTap(
            onBus: 0,
            bufferSize: configuration.bufferSize,
            format: inputFormat
        ) { [weak self] buffer, _ in
            guard let self = self else { return }
            guard let out = self.convert(buffer: buffer, converter: converter,
                                           target: targetFormat) else { return }
            let samples = self.bufferToFloatArray(buffer: out)
            Task { @MainActor in self.updateLevel(samples: samples) }
            onAudio(samples)
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Swift.Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do { try engine.start(); cont.resume() }
                catch {
                    node.removeTap(onBus: 0)
                    cont.resume(throwing: Error.engineStartFailed(message: error.localizedDescription))
                }
            }
        }

        self.audioEngine = engine
        self.inputNode = node
        self.isRecording = true
    }

    /// Stop recording. `deactivateSession` controls AVAudioSession teardown.
    public func stopRecording(deactivateSession: Bool = true) {
        guard isRecording else { return }
        let engine = audioEngine
        let node = inputNode
        audioEngine = nil
        inputNode = nil
        DispatchQueue.global(qos: .userInitiated).async {
            node?.removeTap(onBus: 0)
            engine?.stop()
        }
        #if os(iOS) || os(tvOS)
        if deactivateSession {
            Task.detached(priority: .utility) {
                try? AVAudioSession.sharedInstance().setActive(
                    false, options: .notifyOthersOnDeactivation)
            }
        }
        #endif
        isRecording = false
        audioLevel = 0
    }

    // MARK: - Internals

    private func convert(
        buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        target: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        converter.reset()
        let capacity = AVAudioFrameCount(
            ceil(Double(buffer.frameLength) * (target.sampleRate / buffer.format.sampleRate)))
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity)
        else { return nil }
        var err: NSError?
        var provided = false
        let input: AVAudioConverterInputBlock = { _, status in
            if provided { status.pointee = .noDataNow; return nil }
            provided = true; status.pointee = .haveData; return buffer
        }
        converter.convert(to: out, error: &err, withInputFrom: input)
        return err == nil ? out : nil
    }

    private func bufferToFloatArray(buffer: AVAudioPCMBuffer) -> [Float] {
        guard let ptr = buffer.floatChannelData?.pointee else { return [] }
        return Array(UnsafeBufferPointer(start: ptr, count: Int(buffer.frameLength)))
    }

    private func updateLevel(samples: [Float]) {
        guard !samples.isEmpty else { return }
        var sum: Float = 0
        for s in samples { sum += s * s }
        let rms = (sum / Float(samples.count)).squareRoot()
        let db = 20 * log10f(rms + 0.0001)
        audioLevel = max(0, min(1, (db + 60) / 60))
    }

    deinit {
        // MainActor-isolated; stopRecording() calls MainActor APIs.
        // We can't hop to MainActor in deinit; rely on host to stop explicitly.
    }

#else  // watchOS / non-AVFoundation
    public init(configuration: Configuration = .init()) {}
    public func requestPermission() async -> Bool { false }
    public func startRecording(onAudio: @escaping @Sendable ([Float]) -> Void) async throws {
        throw Error.unsupportedPlatform
    }
    public func stopRecording(deactivateSession: Bool = true) {}
    public var isRecording: Bool { false }
    public var audioLevel: Float { 0 }
#endif
}
