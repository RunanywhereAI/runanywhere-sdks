import AVFoundation
import Foundation
import os

/// Audio capture utility for voice applications
///
/// Provides a simple way to capture audio from the microphone and stream it
/// as `VoiceAudioChunk` objects for processing by the voice pipeline.
///
/// **Example usage:**
/// ```swift
/// let audioCapture = AudioCapture()
/// let audioStream = audioCapture.startContinuousCapture()
///
/// // Feed audio to voice pipeline
/// for try await event in pipeline.process(audioStream: audioStream) {
///     // Handle pipeline events
/// }
///
/// // Stop when done
/// audioCapture.stopContinuousCapture()
/// ```
///
/// **Audio Configuration:**
/// - Sample rate: 16kHz mono
/// - Format: Float32 PCM
/// - Chunk size: 100ms (1600 samples)
/// - Echo cancellation: Enabled via `.duckOthers` option
///
/// **Note:** This class only handles microphone capture. All AI processing
/// (VAD, STT, LLM, TTS) happens in the `ModularVoicePipeline`.
public class AudioCapture: NSObject {
    private let logger = SDKLogger(category: "AudioCapture")

    // Audio stream
    private var streamContinuation: AsyncStream<VoiceAudioChunk>.Continuation?
    private var sequenceNumber: Int = 0
    private var audioBuffer: [Float] = []
    private var isRecording = false

    // Audio engine for actual microphone capture
    private var audioEngine: AVAudioEngine?
    private let minBufferSize = 1600 // 0.1 seconds at 16kHz

    /// Whether audio is currently being captured
    public var isCurrentlyRecording: Bool { isRecording }

    public override init() {
        super.init()
        logger.info("AudioCapture initialized")
    }

    /// Start continuous audio capture
    ///
    /// Returns an async stream of audio chunks that can be processed by the voice pipeline.
    /// The stream will continue until `stopContinuousCapture()` is called.
    ///
    /// - Returns: AsyncStream of VoiceAudioChunk objects
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
    ///
    /// Stops the audio engine and finishes the audio stream.
    public func stopContinuousCapture() {
        stopAudioEngine()
        streamContinuation?.finish()
        streamContinuation = nil
        audioBuffer = []
        isRecording = false
        logger.info("Continuous audio capture stopped")
    }

    // MARK: - Audio Engine Methods

    private func startAudioEngine() throws {
        #if os(iOS) || os(tvOS) || os(watchOS)
        // Configure audio session for voice assistant (recording + playback)
        let audioSession = AVAudioSession.sharedInstance()

        // Use .duckOthers and .defaultToSpeaker for voice assistant to prevent feedback loop
        // - .duckOthers: Enables echo cancellation to prevent mic from capturing TTS output
        // - .defaultToSpeaker: Routes audio to speaker for better voice assistant UX
        // - .voiceChat mode: Provides additional acoustic echo cancellation
        try audioSession.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetooth, .duckOthers, .defaultToSpeaker]
        )
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
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
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
                guard let convertedBuffer = AVAudioPCMBuffer(
                    pcmFormat: outputFormat,
                    frameCapacity: AVAudioFrameCount(capacity)
                ) else {
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

            // Convert buffer to float array and stream
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
        }
    }

    // MARK: - Permission Handling

    /// Request microphone permission
    ///
    /// On iOS/tvOS/watchOS, this will prompt the user for microphone access.
    /// On macOS, permission is handled automatically when the microphone is accessed.
    ///
    /// - Returns: `true` if permission is granted, `false` otherwise
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
}

/// Errors that can occur during audio capture
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
