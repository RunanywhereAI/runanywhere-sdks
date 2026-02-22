//
//  AudioCaptureManager.swift
//  RunAnywhere SDK
//
//  Shared audio capture utility for STT features.
//  Can be used with any STT backend (ONNX, etc.)
//

import AVFoundation
import CRACommons
import Foundation

/// Manages audio capture from microphone for STT services.
///
/// This is a shared utility that works with any STT backend (ONNX, etc.).
/// It captures audio at 16kHz mono Int16 format, which is the standard input format
/// for speech recognition models like Whisper.
///
/// - Works on: iOS, tvOS, and macOS using AVAudioEngine
/// - NOT supported on: watchOS (AVAudioEngine inputNode tap doesn't work reliably)
///
/// ## Usage
/// ```swift
/// let capture = AudioCaptureManager()
/// let granted = await capture.requestPermission()
/// if granted {
///     try capture.startRecording { audioData in
///         // Feed audioData to your STT service
///     }
/// }
/// ```
public class AudioCaptureManager: ObservableObject {
    private let logger = SDKLogger(category: "AudioCapture")

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?

    @Published public var isRecording = false
    @Published public var audioLevel: Float = 0.0

    private let targetSampleRate = Double(RAC_STT_DEFAULT_SAMPLE_RATE)

    public init() {
        logger.info("AudioCaptureManager initialized")
    }

    /// Request microphone permission
    public func requestPermission() async -> Bool {
        #if os(iOS)
        // Use modern AVAudioApplication API for iOS 17+
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            // Fallback to deprecated API for older iOS versions
            return await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
        #elseif os(tvOS)
        // tvOS doesn't have AVAudioApplication, use legacy API
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        #elseif os(macOS)
        // On macOS, use AVCaptureDevice for permission request
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
        #endif
    }

    /// Start recording audio from microphone
    /// - Note: Not supported on watchOS due to AVAudioEngine limitations
    public func startRecording(onAudioData: @escaping (Data) -> Void) throws {
        guard !isRecording else {
            logger.warning("Already recording")
            return
        }

        #if os(iOS) || os(tvOS)
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement)
        try audioSession.setActive(true)
        #endif

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        #if os(macOS)
        // On macOS there is no AVAudioSession. Preparing the engine before
        // reading the input node format establishes the audio-unit graph
        // connections and avoids kAudioUnitErr_NoConnection (-10877).
        engine.prepare()
        #endif

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

            if let audioData = self.bufferToData(buffer: convertedBuffer) {
                DispatchQueue.main.async {
                    onAudioData(audioData)
                }
            }
        }

        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw error
        }

        self.audioEngine = engine
        self.inputNode = inputNode

        DispatchQueue.main.async {
            self.isRecording = true
        }

        logger.info("Recording started")
    }

    /// Activates the AVAudioSession without starting the audio engine.
    /// Call this to keep the app alive in the background (with UIBackgroundModes: audio)
    /// before the user is ready to record. Follow with `startRecording` when recording begins.
    public func activateAudioSession() throws {
        #if os(iOS) || os(tvOS)
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement)
        try audioSession.setActive(true)
        logger.info("Audio session activated (keepalive)")
        #endif
    }

    /// Deactivates the AVAudioSession. Call this when the session is fully ended.
    public func deactivateAudioSession() {
        #if os(iOS) || os(tvOS)
        try? AVAudioSession.sharedInstance().setActive(false)
        logger.info("Audio session deactivated")
        #endif
    }

    /// Stop recording.
    /// - Parameter deactivateSession: When `true` (default) the AVAudioSession is also
    ///   deactivated. Pass `false` to keep the session alive for subsequent recordings
    ///   (e.g. between listening segments in a flow session).
    public func stopRecording(deactivateSession: Bool = true) {
        guard isRecording else { return }

        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()

        audioEngine = nil
        inputNode = nil

        #if os(iOS) || os(tvOS)
        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(false)
        }
        #endif

        DispatchQueue.main.async {
            self.isRecording = false
            self.audioLevel = 0.0
        }

        logger.info("Recording stopped (deactivateSession=\(deactivateSession))")
    }

    // MARK: - Private Helpers

    /// Converts a PCM buffer to the target format. Internal for unit testing.
    internal func convert(
        buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        // The input block returns .endOfStream after providing one buffer.
        // On macOS the converter stays in that "finished" state across calls,
        // producing empty output for every subsequent buffer. Resetting before
        // each conversion clears the state so the next buffer is processed.
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

        let channelDataPointer = channelData.pointee
        let frames = Int(buffer.frameLength)

        // Calculate RMS (root mean square) for audio level
        var sum: Float = 0.0
        for i in 0..<frames {
            let sample = channelDataPointer[i]
            sum += sample * sample
        }

        let rms = sqrt(sum / Float(frames))
        let dbLevel = 20 * log10(rms + 0.0001) // Add small value to avoid log(0)

        // Normalize to 0-1 range (-60dB to 0dB)
        let normalizedLevel = max(0, min(1, (dbLevel + 60) / 60))

        DispatchQueue.main.async {
            self.audioLevel = normalizedLevel
        }
    }

    deinit {
        stopRecording()
    }
}

// MARK: - Errors

public enum AudioCaptureError: LocalizedError {
    case permissionDenied
    case formatConversionFailed
    case engineStartFailed
    case noInputDevice

    public var errorDescription: String? {
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
