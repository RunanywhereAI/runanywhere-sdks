//
//  HybridAudioCapture.swift
//  RunAnywhereCore (React Native)
//
//  In-SDK microphone capture for STT features.
//  Port of the Swift SDK source of truth:
//  sdk/runanywhere-swift/Sources/RunAnywhere/Features/STT/Services/AudioCaptureManager.swift
//  (AVAudioEngine input tap 4096 → AVAudioConverter → 16kHz mono Int16 chunks),
//  minus the macOS-only device-selection sections.
//

@preconcurrency import AVFoundation
import Foundation
import NitroModules
import os

/// Errors raised by `HybridAudioCapture`. Mirrors the Swift SDK's
/// `AudioCaptureError` enum.
enum AudioCaptureError: LocalizedError {
    case permissionDenied
    case formatConversionFailed
    case engineStartFailed
    case noInputDevice

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission denied"
        case .formatConversionFailed:
            return "Failed to convert audio format"
        case .engineStartFailed:
            return "Failed to start audio engine"
        case .noInputDevice:
            return "No audio input device available"
        }
    }
}

class HybridAudioCapture: HybridAudioCaptureSpec {
    private let logger = SDKLogger(category: "AudioCapture")

    private struct CaptureState {
        var engine: AVAudioEngine?
        var inputNode: AVAudioInputNode?
        var isRecording = false
        var audioLevel: Double = 0.0
    }

    private let state = OSAllocatedUnfairLock(initialState: CaptureState())

    /// Canonical Whisper/Sherpa input sample rate
    /// (RAC_STT_DEFAULT_SAMPLE_RATE in commons).
    private let targetSampleRate: Double = 16000

    // MARK: - Properties

    var isRecording: Bool {
        state.withLock { $0.isRecording }
    }

    var audioLevel: Double {
        state.withLock { $0.audioLevel }
    }

    // MARK: - Methods

    /// Request microphone permission (iOS 17+ AVAudioApplication API,
    /// matching the Swift SDK's iOS 17 path).
    func requestPermission() throws -> Promise<Bool> {
        return Promise.async {
            await AVAudioApplication.requestRecordPermission()
        }
    }

    func startRecording(onAudioData: @escaping (_ chunk: ArrayBuffer) -> Void) throws -> Promise<Void> {
        return Promise.async { [weak self] in
            guard let self else { return }
            try await self.start(onAudioData: onAudioData)
        }
    }

    /// Activates a full-duplex `.playAndRecord` session WITHOUT starting the
    /// audio engine. The voice-agent driver calls this before `startRecording`
    /// so capture and playback share one session for the whole turn-taking loop
    /// (mic stays live while the TTS reply plays). Mirrors the iOS Swift
    /// voice-agent driver's `configureVoiceAudioSession()`.
    func activateAudioSession() throws -> Promise<Void> {
        return Promise.async { [weak self] in
            try await Self.configureFullDuplexSession()
            self?.logger.info("Full-duplex audio session activated (voice agent)")
        }
    }

    /// Deactivates the AVAudioSession.
    func deactivateAudioSession() throws {
        Task.detached(priority: .utility) {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        logger.info("Audio session deactivated")
    }

    /// Stop recording.
    /// Mirrors Swift `AudioCaptureManager.stopRecording(deactivateSession:)`:
    /// capture references and nil out immediately so the logical state is
    /// "stopped", then tear down audio hardware on a background thread
    /// (removeTap()/engine.stop() perform synchronous Mach IPC to
    /// mediaserverd that can block the calling thread for 400-500ms).
    func stopRecording(deactivateSession: Bool) throws {
        let (engine, node): (AVAudioEngine?, AVAudioInputNode?) = state.withLock { current in
            guard current.isRecording else { return (nil, nil) }
            let captured = (current.engine, current.inputNode)
            current.engine = nil
            current.inputNode = nil
            current.isRecording = false
            current.audioLevel = 0.0
            return captured
        }
        guard engine != nil || node != nil else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            node?.removeTap(onBus: 0)
            engine?.stop()
        }

        if deactivateSession {
            Task.detached(priority: .utility) {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }

        logger.info("Recording stopped (deactivateSession=\(deactivateSession))")
    }

    // MARK: - Private Implementation

    private static func configureAndActivateSession() async throws {
        // Configure the audio session on a background thread — setActive()
        // performs IPC to mediaserverd which can block for 100-300ms.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let audioSession = AVAudioSession.sharedInstance()
                    // Preserve a full-duplex session if the voice agent already
                    // configured one (activateAudioSession → .playAndRecord):
                    // switching back to .record would silence the TTS reply and
                    // disable the simultaneous playback the agent needs. STT capture
                    // (no prior activate) falls through to the unprocessed
                    // .record/.measurement path that gives Whisper the cleanest signal.
                    if audioSession.category != .playAndRecord {
                        try audioSession.setCategory(.record, mode: .measurement)
                    }
                    try audioSession.setActive(true)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Configures a full-duplex `.playAndRecord` session for the voice agent so
    /// the mic stays live while TTS replies play. `.default` (not `.measurement`)
    /// keeps input processing on so speech sits at a usable level for energy
    /// endpointing; the speaker override routes replies to the loud speaker rather
    /// than the receiver. Mirrors the iOS Swift voice-agent session config.
    private static func configureFullDuplexSession() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(
                        .playAndRecord,
                        mode: .default,
                        options: [.defaultToSpeaker, .allowBluetooth]
                    )
                    try session.setActive(true)
                    // `.defaultToSpeaker` alone can fall back to the receiver under
                    // `.playAndRecord`; force the loud speaker route.
                    try? session.overrideOutputAudioPort(.speaker)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func start(onAudioData: @escaping (_ chunk: ArrayBuffer) -> Void) async throws {
        guard !isRecording else {
            logger.warning("Already recording")
            return
        }

        try await Self.configureAndActivateSession()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            logger.error("No valid audio input device (sampleRate=\(inputFormat.sampleRate), channels=\(inputFormat.channelCount))")
            throw AudioCaptureError.noInputDevice
        }

        logger.info("Input format: \(inputFormat.sampleRate) Hz, \(inputFormat.channelCount) channels")

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioCaptureError.formatConversionFailed
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioCaptureError.formatConversionFailed
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            self.updateAudioLevel(buffer: buffer)

            guard let convertedBuffer = self.convert(buffer: buffer, using: converter, to: outputFormat) else {
                return
            }

            if let audioData = self.bufferToData(buffer: convertedBuffer), !audioData.isEmpty {
                do {
                    // Owning copy — Nitro marshals it to the JS thread.
                    let chunk = try ArrayBuffer.copy(data: audioData)
                    onAudioData(chunk)
                } catch {
                    self.logger.error("Failed to wrap audio chunk: \(error.localizedDescription)")
                }
            }
        }

        // Start the engine on a background thread — AVAudioEngine.start()
        // performs synchronous IPC to mediaserverd.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try engine.start()
                    continuation.resume()
                } catch {
                    inputNode.removeTap(onBus: 0)
                    continuation.resume(throwing: error)
                }
            }
        }

        state.withLock { current in
            current.engine = engine
            current.inputNode = inputNode
            current.isRecording = true
        }

        logger.info("Recording started")
    }

    // MARK: - Private Helpers (Swift SDK parity)

    private func convert(
        buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        // The input block returns .haveData once then .noDataNow; resetting
        // before each conversion clears the converter's "finished" state.
        converter.reset()

        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * (format.sampleRate / buffer.format.sampleRate)))

        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: capacity
        ) else {
            return nil
        }

        var error: NSError?
        var hasProvidedData = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if hasProvidedData {
                outStatus.pointee = .noDataNow
                return nil
            }
            hasProvidedData = true
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            logger.error("Conversion error: \(error.localizedDescription)")
            return nil
        }

        return convertedBuffer
    }

    private func bufferToData(buffer: AVAudioPCMBuffer) -> Data? {
        guard let channelData = buffer.int16ChannelData else {
            return nil
        }

        let channelDataPointer = channelData.pointee
        let dataSize = Int(buffer.frameLength * buffer.format.streamDescription.pointee.mBytesPerFrame)

        return Data(bytes: channelDataPointer, count: dataSize)
    }

    private func updateAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }

        // RMS→dB level computation. The Swift SDK delegates this to commons
        // (rac_audio_compute_level_db), but this pod has no `CRACommons`
        // Swift module map (RACommons.xcframework ships only the C ABI for
        // the C++ bridges), so the identical math is inlined here:
        // level_db = 20 * log10(rms), then normalized -60dB..0dB → 0..1.
        let samples = channelData.pointee
        var sumSquares: Double = 0
        for index in 0..<frames {
            let sample = Double(samples[index])
            sumSquares += sample * sample
        }
        let rms = (sumSquares / Double(frames)).squareRoot()
        let dbLevel: Double = rms > 0 ? 20.0 * log10(rms) : -100.0

        // Normalize to 0-1 range (-60dB to 0dB) — Swift SDK parity.
        let normalizedLevel = max(0.0, min(1.0, (dbLevel + 60.0) / 60.0))

        state.withLock { $0.audioLevel = normalizedLevel }
    }

    deinit {
        try? stopRecording(deactivateSession: true)
    }
}
