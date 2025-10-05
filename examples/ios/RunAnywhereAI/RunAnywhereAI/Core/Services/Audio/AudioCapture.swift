import AVFoundation
import Foundation
import os
import RunAnywhere

/// Simplified Audio Capture that provides audio stream for processing
/// VAD is handled externally by VoiceSessionManager
public class AudioCapture: NSObject {
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "AudioCapture")

    // Audio stream
    private var streamContinuation: AsyncStream<VoiceAudioChunk>.Continuation?
    private var sequenceNumber: Int = 0
    private var audioBuffer: [Float] = []
    private var isRecording = false

    // Audio engine for actual microphone capture
    private var audioEngine: AVAudioEngine?
    private let minBufferSize = 1600 // 0.1 seconds at 16kHz

    // Properties for compatibility
    public var isCurrentlyRecording: Bool { isRecording }

    public override init() {
        super.init()
        logger.info("AudioCapture initialized - VAD handled by VoiceSessionManager")
    }

    /// Start continuous audio capture - provides raw audio stream
    /// VAD processing is handled by the VoiceSessionManager
    public func startContinuousCapture() -> AsyncStream<VoiceAudioChunk> {
        stopContinuousCapture()
        sequenceNumber = 0
        audioBuffer = []

        return AsyncStream { continuation in
            self.streamContinuation = continuation

            Task {
                // Request microphone permission first
                let hasPermission = await AudioCapture.requestMicrophonePermission()
                guard hasPermission else {
                    self.logger.error("Microphone permission denied")
                    continuation.finish()
                    return
                }

                // Start actual audio capture from microphone
                do {
                    try self.startAudioEngine()
                    self.isRecording = true
                    self.logger.info("Started continuous audio capture with audio engine")
                } catch {
                    self.logger.error("Failed to start audio engine: \(error)")
                    continuation.finish()
                }
            }
        }
    }

    /// Stop continuous audio capture
    public func stopContinuousCapture() {
        stopAudioEngine()
        streamContinuation?.finish()
        streamContinuation = nil
        audioBuffer = []
        isRecording = false
        logger.info("Continuous audio capture stopped")
    }

    /// Called by external VAD detector to provide audio data
    public func receiveAudioData(_ audioData: Data) {
        guard isRecording else { return }

        // Convert Data to Float samples
        let samples = audioData.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }

        audioBuffer.append(contentsOf: samples)

        // Send chunk if buffer is large enough (~1 second)
        if audioBuffer.count >= 16000 {
            sendAudioChunk()
        }
    }

    private func sendAudioChunk() {
        guard !audioBuffer.isEmpty else { return }

        let chunk = VoiceAudioChunk(
            samples: audioBuffer,
            timestamp: Date().timeIntervalSince1970,
            sampleRate: 16000,
            channels: 1,
            sequenceNumber: sequenceNumber,
            isFinal: false
        )

        sequenceNumber += 1
        streamContinuation?.yield(chunk)

        // logger.debug("Sent audio chunk #\(self.sequenceNumber): \(self.audioBuffer.count) samples")
        audioBuffer = []
    }

    // MARK: - Legacy Methods (for compatibility)

    public func startRecording() async throws {
        // Legacy method - simplified for compatibility
        isRecording = true
        logger.info("Started recording (legacy mode)")
    }

    public func stopRecording() async throws -> Data {
        isRecording = false

        // Return accumulated buffer as Data
        let data = audioBuffer.withUnsafeBufferPointer { bufferPointer in
            Data(buffer: bufferPointer)
        }
        audioBuffer = []

        logger.info("Stopped recording, returned \(data.count) bytes")
        return data
    }

    public func recordAudio(duration: TimeInterval) async throws -> Data {
        try await startRecording()
        try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        return try await stopRecording()
    }

    public func getRecordingDuration() -> TimeInterval {
        Double(audioBuffer.count) / 16000.0
    }

    public static func requestMicrophonePermission() async -> Bool {
        #if os(iOS) || os(tvOS) || os(watchOS)
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        #else
        // On macOS, microphone permission is handled differently
        return true // macOS will prompt when actually using the microphone
        #endif
    }

    // MARK: - Audio Engine Methods

    private func startAudioEngine() throws {
        #if os(iOS) || os(tvOS) || os(watchOS)
        // Configure audio session for both recording and playback
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .mixWithOthers])
        try audioSession.setActive(true)
        #endif

        // Create and configure audio engine
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            throw AudioCaptureError.audioEngineError("Failed to create audio engine")
        }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Create format for 16kHz mono audio
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                              sampleRate: 16000,
                                              channels: 1,
                                              interleaved: false) else {
            throw AudioCaptureError.audioEngineError("Failed to create audio format")
        }

        // Create converter if needed
        let needsConversion = inputFormat.sampleRate != outputFormat.sampleRate ||
                            inputFormat.channelCount != outputFormat.channelCount

        var converter: AVAudioConverter?
        if needsConversion {
            converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        }

        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            var processedBuffer = buffer

            // Convert to 16kHz mono if needed
            if let converter = converter {
                let capacity = outputFormat.sampleRate * Double(buffer.frameLength) / inputFormat.sampleRate
                guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat,
                                                            frameCapacity: AVAudioFrameCount(capacity)) else {
                    return
                }

                var error: NSError?
                let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }

                converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
                if error == nil {
                    processedBuffer = convertedBuffer
                }
            }

            // Convert buffer to float array
            self.processAudioBuffer(processedBuffer)
        }

        // Start the engine
        try audioEngine.start()
        logger.info("Audio engine started - capturing at 16kHz mono")
    }

    private func stopAudioEngine() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        #if os(iOS) || os(tvOS) || os(watchOS)
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            logger.error("Failed to deactivate audio session: \(error)")
        }
        #endif
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let frameLength = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))

        audioBuffer.append(contentsOf: samples)

        // Send chunks of audio data (100ms chunks = 1600 samples at 16kHz)
        while audioBuffer.count >= minBufferSize {
            let chunkSamples = Array(audioBuffer.prefix(minBufferSize))
            audioBuffer.removeFirst(minBufferSize)

            let chunk = VoiceAudioChunk(
                samples: chunkSamples,
                timestamp: Date().timeIntervalSince1970,
                sampleRate: 16000,
                channels: 1,
                sequenceNumber: sequenceNumber,
                isFinal: false
            )

            sequenceNumber += 1
            streamContinuation?.yield(chunk)

            // logger.debug("Sent audio chunk #\(self.sequenceNumber): \(chunkSamples.count) samples")
        }
    }
}

// Extension for Data to Float conversion
extension Data {
    func toFloatArray() -> [Float] {
        return self.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
    }
}

public enum AudioCaptureError: LocalizedError {
    case microphonePermissionDenied
    case notRecording
    case audioEngineError(String)

    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission was denied. Please enable microphone access in Settings."
        case .notRecording:
            return "No active recording to stop."
        case .audioEngineError(let message):
            return "Audio engine error: \(message)"
        }
    }
}
