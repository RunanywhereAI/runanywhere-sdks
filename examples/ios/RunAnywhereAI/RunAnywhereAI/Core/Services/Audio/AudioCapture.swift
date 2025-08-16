import AVFoundation
import Foundation
import os
import RunAnywhereSDK

public class AudioCapture: NSObject {
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "AudioCapture")
    private var audioEngine = AVAudioEngine()
    private var inputNode: AVAudioInputNode
    private var targetFormat: AVAudioFormat  // Format we want for WhisperKit
    private var recordingBuffer: [Float] = []
    private var isRecording = false
    private var converter: AVAudioConverter?

    // Properties for continuous capture
    private var continuationTask: Task<Void, Never>?
    private var streamContinuation: AsyncStream<VoiceAudioChunk>.Continuation?
    private var sequenceNumber: Int = 0

    public override init() {
        inputNode = audioEngine.inputNode
        // WhisperKit expects 16kHz mono audio
        targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!
        super.init()
        logger.info("AudioCapture initialized with target format: 16kHz, mono, Float32")
    }

    public func startRecording() async throws {
        logger.info("startRecording() called")
        guard !isRecording else {
            logger.debug("Already recording, returning")
            return
        }

        logger.info("Requesting microphone permission...")
        let hasPermission = await AudioCapture.requestMicrophonePermission()
        logger.info("Microphone permission: \(hasPermission)")
        guard hasPermission else {
            logger.error("Microphone permission denied")
            throw AudioCaptureError.microphonePermissionDenied
        }

        logger.debug("Clearing recording buffer")
        recordingBuffer.removeAll()

        // Configure audio session BEFORE accessing the audio engine
        logger.info("Configuring audio session...")
        try await configureAudioSession()
        logger.info("Audio session configured")

        // Prepare the audio engine after audio session is configured
        logger.info("Preparing audio engine...")
        audioEngine.prepare()
        logger.info("Audio engine prepared")

        // Now we can safely get the input format
        logger.info("Getting input format...")
        let inputFormat = inputNode.outputFormat(forBus: 0)
        logger.info("Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")

        // Ensure the format is valid
        guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
            logger.warning("Invalid format detected (sampleRate: \(inputFormat.sampleRate), channels: \(inputFormat.channelCount)), attempting reset...")

            // Reset the audio engine completely
            audioEngine.stop()
            audioEngine.reset()

            // Reconfigure audio session
            logger.info("Reconfiguring audio session after reset...")
            try await configureAudioSession()

            // Create new audio engine instance
            audioEngine = AVAudioEngine()
            inputNode = audioEngine.inputNode
            audioEngine.prepare()

            // Try again after reset
            let retryFormat = inputNode.outputFormat(forBus: 0)
            logger.warning("Retry format: \(retryFormat.sampleRate)Hz, \(retryFormat.channelCount) channels")
            guard retryFormat.sampleRate > 0 && retryFormat.channelCount > 0 else {
                logger.error("Invalid format after reset - Sample rate: \(retryFormat.sampleRate), Channels: \(retryFormat.channelCount)")
                throw AudioCaptureError.audioEngineError("Invalid input format after reset. Sample rate: \(retryFormat.sampleRate), Channels: \(retryFormat.channelCount)")
            }

            // Use the retry format if it's valid
            logger.info("Using retry format for recording")
            isRecording = true

            logger.info("Installing audio tap with retry format...")
            inputNode.installTap(
                onBus: 0,
                bufferSize: 1024,
                format: retryFormat
            ) { [weak self] buffer, _ in
                guard let self = self, self.isRecording else { return }
                self.processAudioBuffer(buffer)
            }

            logger.info("Starting audio engine...")
            try audioEngine.start()
            logger.info("Recording started (retry path)")
            return
        }

        // Set recording flag after validation but before installing tap
        isRecording = true

        logger.info("Installing audio tap...")
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: inputFormat  // Use the node's actual format
        ) { [weak self] buffer, _ in
            guard let self = self, self.isRecording else { return }
            self.processAudioBuffer(buffer)
        }

        logger.info("Starting audio engine...")
        try audioEngine.start()
        logger.info("Recording started successfully")
    }

    public func stopRecording() async throws -> Data {
        logger.info("stopRecording() called")
        guard isRecording else {
            logger.error("Not recording")
            throw AudioCaptureError.notRecording
        }

        isRecording = false
        logger.info("Stopping audio engine...")
        audioEngine.stop()
        inputNode.removeTap(onBus: 0)
        converter = nil  // Clean up converter

        logger.info("Deactivating audio session...")
        try await deactivateAudioSession()

        let data = convertBufferToData(recordingBuffer)
        logger.info("Recording stopped. Buffer size: \(self.recordingBuffer.count) samples, Data size: \(data.count) bytes")
        return data
    }

    public func recordAudio(duration: TimeInterval) async throws -> Data {
        try await startRecording()

        try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))

        return try await stopRecording()
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // If we need to convert the format
        if buffer.format != targetFormat {
            // Create converter if needed
            if converter == nil {
                logger.debug("Creating audio converter from \(buffer.format.sampleRate)Hz to \(self.targetFormat.sampleRate)Hz")
                converter = AVAudioConverter(from: buffer.format, to: targetFormat)
            }

            guard let converter = converter else { return }

            // Calculate output frame capacity
            let outputFrameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * (targetFormat.sampleRate / buffer.format.sampleRate)
            )

            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: outputFrameCapacity
            ) else { return }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if status == .haveData {
                appendBufferToRecording(convertedBuffer)
            }
        } else {
            // No conversion needed
            appendBufferToRecording(buffer)
        }
    }

    private func appendBufferToRecording(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else {
            logger.warning("No channel data in buffer")
            return
        }

        let channelDataValue = channelData.pointee
        let channelDataCount = Int(buffer.frameLength)

        let samples = Array(UnsafeBufferPointer(
            start: channelDataValue,
            count: channelDataCount
        ))

        recordingBuffer.append(contentsOf: samples)

        // Log periodically (every ~1 second)
        if recordingBuffer.count % 16000 == 0 {
            let duration = Double(recordingBuffer.count) / 16000.0
            logger.debug("Recording... Duration: \(String(format: "%.1f", duration))s")
        }
    }

    private func convertBufferToData(_ buffer: [Float]) -> Data {
        let data = buffer.withUnsafeBufferPointer { bufferPointer in
            Data(buffer: bufferPointer)
        }
        return data
    }

    private func configureAudioSession() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func deactivateAudioSession() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    public static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    public var isCurrentlyRecording: Bool {
        isRecording
    }

    public func getRecordingDuration() -> TimeInterval {
        Double(recordingBuffer.count) / 16000.0
    }

    // MARK: - Continuous Capture Methods

    /// Start continuous audio capture with streaming
    public func startContinuousCapture() -> AsyncStream<VoiceAudioChunk> {
        // Stop any existing capture
        stopContinuousCapture()

        // Reset sequence number
        sequenceNumber = 0

        return AsyncStream { continuation in
            self.streamContinuation = continuation

            Task {
                do {
                    // Configure audio session for real-time
                    try await self.configureAudioSession()

                    // Prepare the audio engine first
                    self.audioEngine.prepare()

                    // Get the actual hardware format after prepare
                    let inputFormat = self.inputNode.outputFormat(forBus: 0)

                    self.logger.info("Continuous capture format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")

                    // Ensure the format is valid
                    guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
                        self.logger.warning("Invalid format detected, attempting reset...")

                        // Reset the audio engine completely
                        self.audioEngine.stop()
                        self.audioEngine.reset()

                        // Reconfigure audio session
                        try await self.configureAudioSession()

                        // Create new audio engine instance
                        self.audioEngine = AVAudioEngine()
                        self.inputNode = self.audioEngine.inputNode
                        self.audioEngine.prepare()

                        // Try again after reset
                        let retryFormat = self.inputNode.outputFormat(forBus: 0)
                        self.logger.info("Retry format: \(retryFormat.sampleRate)Hz, \(retryFormat.channelCount) channels")

                        guard retryFormat.sampleRate > 0 && retryFormat.channelCount > 0 else {
                            self.logger.error("Invalid format after reset")
                            continuation.finish()
                            return
                        }

                        // Create converter with retry format
                        if retryFormat != self.targetFormat {
                            self.converter = AVAudioConverter(from: retryFormat, to: self.targetFormat)
                        }

                        // Install tap with retry format
                        self.inputNode.installTap(onBus: 0,
                                                 bufferSize: 512,
                                                 format: retryFormat) { [weak self] buffer, time in
                            guard let self = self else { return }

                            if let processedData = self.processBufferForStreaming(buffer, time: time) {
                                let chunk = VoiceAudioChunk(
                                    data: processedData,
                                    timestamp: Date().timeIntervalSince1970,
                                    sampleRate: Int(self.targetFormat.sampleRate),
                                    channels: Int(self.targetFormat.channelCount),
                                    sequenceNumber: self.sequenceNumber,
                                    isFinal: false
                                )
                                self.sequenceNumber += 1
                                continuation.yield(chunk)
                            }
                        }

                        // Start audio engine
                        try self.audioEngine.start()
                        self.logger.info("Continuous audio capture started (retry path)")
                        return  // IMPORTANT: Exit here after handling invalid format
                    }

                    // Valid format path - Create converter for format conversion if needed
                    if inputFormat != self.targetFormat {
                        self.converter = AVAudioConverter(from: inputFormat, to: self.targetFormat)
                    }

                    // Install tap with small buffer for low latency (512 samples ~11ms at 44.1kHz)
                    self.inputNode.installTap(onBus: 0,
                                             bufferSize: 512,
                                             format: inputFormat) { [weak self] buffer, time in
                        guard let self = self else { return }

                        // Process and resample the audio
                        if let processedData = self.processBufferForStreaming(buffer, time: time) {
                            // Create AudioChunk
                            let chunk = VoiceAudioChunk(
                                data: processedData,
                                timestamp: Date().timeIntervalSince1970,
                                sampleRate: Int(self.targetFormat.sampleRate),
                                channels: Int(self.targetFormat.channelCount),
                                sequenceNumber: self.sequenceNumber,
                                isFinal: false
                            )
                            self.sequenceNumber += 1

                            continuation.yield(chunk)
                        }
                    }

                    // Start audio engine after installing tap
                    try self.audioEngine.start()
                    self.logger.info("Continuous audio capture started")
                } catch {
                    self.logger.error("Failed to start continuous capture: \(error)")
                    continuation.finish()
                }
            }
        }
    }

    /// Stop continuous audio capture
    public func stopContinuousCapture() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        streamContinuation?.finish()
        streamContinuation = nil
        continuationTask?.cancel()
        continuationTask = nil
        converter = nil
        logger.info("Continuous audio capture stopped")
    }

    /// Process buffer for streaming (convert to 16kHz mono for WhisperKit)
    private func processBufferForStreaming(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) -> Data? {
        var targetBuffer: AVAudioPCMBuffer

        // Convert format if needed
        if buffer.format != targetFormat {
            guard let converter = converter else {
                logger.error("Converter not available")
                return nil
            }

            // Calculate output frame capacity
            let outputFrameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * (targetFormat.sampleRate / buffer.format.sampleRate)
            )

            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: outputFrameCapacity
            ) else {
                logger.error("Failed to create converted buffer")
                return nil
            }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            guard status == .haveData else {
                if let error = error {
                    logger.error("Conversion error: \(error)")
                }
                return nil
            }

            targetBuffer = convertedBuffer
        } else {
            targetBuffer = buffer
        }

        // Convert buffer to Data
        return bufferToData(targetBuffer)
    }

    /// Convert AVAudioPCMBuffer to Data
    private func bufferToData(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let channelData = buffer.floatChannelData else {
            logger.warning("No channel data in buffer")
            return nil
        }

        let channelDataValue = channelData.pointee
        let channelDataCount = Int(buffer.frameLength)

        let samples = Array(UnsafeBufferPointer(
            start: channelDataValue,
            count: channelDataCount
        ))

        return samples.withUnsafeBufferPointer { bufferPointer in
            Data(buffer: bufferPointer)
        }
    }
}

// Extension for Data to Float conversion (needed for WhisperKit)
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
