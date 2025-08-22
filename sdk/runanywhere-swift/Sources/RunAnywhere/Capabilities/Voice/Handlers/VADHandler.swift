import Foundation
import os

/// Handles Voice Activity Detection processing in the voice pipeline
public class VADHandler {
    private let logger = SDKLogger(category: "VADHandler")

    // State management
    private var isSpeechActive = false
    private var speechStartTime: Date?
    private var lastSpeechTime: Date?
    private var floatBuffer: [Float] = []

    // Configuration
    private let minSpeechDuration: TimeInterval = 1.0

    public init() {}

    /// Reset handler state
    public func reset() {
        isSpeechActive = false
        speechStartTime = nil
        lastSpeechTime = nil
        floatBuffer = []
    }

    /// Process audio chunk through VAD
    /// - Parameters:
    ///   - chunk: Audio chunk to process
    ///   - vad: VAD service to use
    ///   - segmentationStrategy: Strategy for audio segmentation
    ///   - continuation: Event stream continuation
    /// - Returns: Audio samples to process if ready, nil otherwise
    public func processAudioChunk(
        _ chunk: VoiceAudioChunk,
        vad: VADService,
        segmentationStrategy: AudioSegmentationStrategy,
        continuation: AsyncThrowingStream<ModularPipelineEvent, Error>.Continuation
    ) -> [Float]? {

        let floatArray = chunk.samples

        // Process audio through VAD and check result
        let hasVoice = vad.processAudioData(floatArray)

        // Handle speech state transitions
        let wasSpeaking = isSpeechActive

        // Check if speech state changed
        if hasVoice && !wasSpeaking {
            // Speech just started
            handleSpeechStart(continuation: continuation)
        }

        // Always buffer audio when speech is active
        if isSpeechActive {
            bufferAudioDuringSpeech(samples: floatArray)

            // Update last speech time if voice detected
            if hasVoice {
                lastSpeechTime = Date()
            }
        }

        // Check if we should process based on segmentation strategy
        if isSpeechActive && !floatBuffer.isEmpty {
            if shouldProcessSegment(strategy: segmentationStrategy) {
                // Process the audio
                return finalizeSegment(
                    segmentationStrategy: segmentationStrategy,
                    continuation: continuation
                )
            }
        }

        return nil
    }

    /// Process audio without VAD (buffering mode)
    /// - Parameters:
    ///   - chunk: Audio chunk to buffer
    /// - Returns: Audio samples to process if buffer is full, nil otherwise
    public func processWithoutVAD(_ chunk: VoiceAudioChunk) -> [Float]? {
        floatBuffer.append(contentsOf: chunk.samples)

        // Process periodically (~2 seconds at 16kHz)
        if floatBuffer.count > 32000 {
            let floatsToProcess = floatBuffer
            floatBuffer = []
            return floatsToProcess
        }

        return nil
    }

    /// Get any remaining buffered audio
    public func getRemainingBuffer() -> [Float]? {
        guard !floatBuffer.isEmpty else { return nil }
        let remaining = floatBuffer
        floatBuffer = []
        return remaining
    }

    // MARK: - Private Methods

    private func handleSpeechStart(continuation: AsyncThrowingStream<ModularPipelineEvent, Error>.Continuation) {
        isSpeechActive = true
        speechStartTime = Date()
        lastSpeechTime = Date()
        floatBuffer = []  // Clear float buffer
        continuation.yield(.vadSpeechStart)
        logger.info("Speech started, beginning to buffer audio")
    }

    private func bufferAudioDuringSpeech(samples: [Float]) {
        floatBuffer.append(contentsOf: samples)
    }

    private func shouldProcessSegment(strategy: AudioSegmentationStrategy) -> Bool {
        let speechDuration = Date().timeIntervalSince(speechStartTime ?? Date())
        let silenceDuration = Date().timeIntervalSince(lastSpeechTime ?? Date())

        // Ask segmentation strategy if we should process
        return strategy.shouldProcessAudio(
            audioBuffer: floatBuffer,
            sampleRate: 16000,
            silenceDuration: silenceDuration,
            speechDuration: speechDuration
        )
    }

    private func finalizeSegment(
        segmentationStrategy: AudioSegmentationStrategy,
        continuation: AsyncThrowingStream<ModularPipelineEvent, Error>.Continuation
    ) -> [Float] {
        let speechDuration = Date().timeIntervalSince(speechStartTime ?? Date())
        let silenceDuration = Date().timeIntervalSince(lastSpeechTime ?? Date())

        isSpeechActive = false
        continuation.yield(.vadSpeechEnd)
        logger.info("Speech segment complete after \(speechDuration)s (silence: \(silenceDuration)s), processing \(floatBuffer.count) samples")

        let floatsToProcess = floatBuffer
        floatBuffer = []

        // Reset segmentation strategy
        segmentationStrategy.reset()

        return floatsToProcess
    }
}
