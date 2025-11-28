import Foundation
import AVFoundation
import RunAnywhere

/// Manages audio capture from microphone for STT
public class AudioCaptureManager: ObservableObject {
    private let logger = SDKLogger(category: "AudioCapture")

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?

    @Published public var isRecording = false
    @Published public var audioLevel: Float = 0.0

    private let targetSampleRate: Double = 16000.0 // Whisper requirement

    public init() {
        logger.info("AudioCaptureManager initialized")
    }

    /// Request microphone permission
    public func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Start recording audio from microphone
    public func startRecording(onAudioData: @escaping (Data) -> Void) throws {
        guard !isRecording else {
            logger.warning("Already recording")
            return
        }

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement)
        try audioSession.setActive(true)

        // Create audio engine
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        // Get input format
        let inputFormat = inputNode.outputFormat(forBus: 0)
        logger.info("Input format: \(inputFormat.sampleRate) Hz, \(inputFormat.channelCount) channels")

        // Create converter format (16kHz, mono, int16)
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioCaptureError.formatConversionFailed
        }

        // Create audio converter
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioCaptureError.formatConversionFailed
        }

        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
            guard let self = self else { return }

            // Update audio level for visualization
            self.updateAudioLevel(buffer: buffer)

            // Convert to target format
            guard let convertedBuffer = self.convert(buffer: buffer, using: converter, to: outputFormat) else {
                return
            }

            // Convert to Data (int16 PCM)
            if let audioData = self.bufferToData(buffer: convertedBuffer) {
                DispatchQueue.main.async {
                    onAudioData(audioData)
                }
            }
        }

        // Start engine
        try engine.start()

        self.audioEngine = engine
        self.inputNode = inputNode

        DispatchQueue.main.async {
            self.isRecording = true
        }

        logger.info("Recording started")
    }

    /// Stop recording
    public func stopRecording() {
        guard isRecording else { return }

        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()

        audioEngine = nil
        inputNode = nil

        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false)

        DispatchQueue.main.async {
            self.isRecording = false
            self.audioLevel = 0.0
        }

        logger.info("Recording stopped")
    }

    // MARK: - Private Helpers

    private func convert(
        buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * (format.sampleRate / buffer.format.sampleRate))

        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: capacity
        ) else {
            return nil
        }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
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

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission denied"
        case .formatConversionFailed:
            return "Failed to convert audio format"
        case .engineStartFailed:
            return "Failed to start audio engine"
        }
    }
}
