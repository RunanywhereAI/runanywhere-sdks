//
//  STTCapability.swift
//  RunAnywhere SDK
//
//  Actor-based STT capability that owns model lifecycle and transcription.
//  Uses ManagedLifecycle for unified lifecycle + analytics handling.
//

@preconcurrency import AVFoundation
import Foundation

/// Actor-based STT capability that provides a simplified interface for speech-to-text.
/// Owns the model lifecycle and provides thread-safe access to transcription operations.
///
/// Uses `ManagedLifecycle` to handle model loading/unloading with automatic analytics tracking.
public actor STTCapability: ModelLoadableCapability {
    public typealias Configuration = STTConfiguration

    // MARK: - State

    /// Managed lifecycle with integrated event tracking
    private let managedLifecycle: ManagedLifecycle<STTService>

    /// Current configuration
    private var config: STTConfiguration?

    // MARK: - Dependencies

    private let logger = SDKLogger(category: "STTCapability")
    private let analyticsService: STTAnalyticsService

    // MARK: - Initialization

    public init(analyticsService: STTAnalyticsService = STTAnalyticsService()) {
        self.analyticsService = analyticsService
        self.managedLifecycle = ManagedLifecycle.forSTT()
    }

    // MARK: - Configuration (Capability Protocol)

    public func configure(_ config: STTConfiguration) {
        self.config = config
        Task { await managedLifecycle.configure(config) }
    }

    // MARK: - Model Lifecycle (ModelLoadableCapability Protocol)
    // All lifecycle operations are delegated to ManagedLifecycle which handles analytics automatically

    public var isModelLoaded: Bool {
        get async { await managedLifecycle.isLoaded }
    }

    public var currentModelId: String? {
        get async { await managedLifecycle.currentModelId }
    }

    /// Whether the service supports streaming transcription
    public var supportsStreaming: Bool {
        get async {
            guard let service = await managedLifecycle.currentService else { return false }
            return service.supportsStreaming
        }
    }

    public func loadModel(_ modelId: String) async throws {
        try await managedLifecycle.load(modelId)
    }

    public func unload() async throws {
        await managedLifecycle.unload()
    }

    public func cleanup() async {
        await managedLifecycle.reset()
    }

    // MARK: - Transcription

    /// Transcribe audio data
    /// - Parameters:
    ///   - audioData: Raw audio data
    ///   - options: Transcription options
    /// - Returns: Transcription output
    public func transcribe(
        _ audioData: Data,
        options: STTOptions = STTOptions()
    ) async throws -> STTOutput {
        let service = try await managedLifecycle.requireService()
        let modelId = await managedLifecycle.modelIdOrUnknown()

        logger.info("Transcribing audio with model: \(modelId)")

        // Merge options with config defaults
        let effectiveOptions = mergeOptions(options)

        // Calculate audio metrics
        let audioSizeBytes = audioData.count
        let audioLengthMs = estimateAudioLength(dataSize: audioSizeBytes) * 1000

        // Start transcription tracking
        let transcriptionId = await analyticsService.startTranscription(
            modelId: modelId,
            audioLengthMs: audioLengthMs,
            audioSizeBytes: audioSizeBytes,
            language: effectiveOptions.language,
            isStreaming: false,
            sampleRate: STTConstants.defaultSampleRate,
            framework: service.inferenceFramework
        )

        // Perform transcription
        let result: STTTranscriptionResult
        do {
            result = try await service.transcribe(audioData: audioData, options: effectiveOptions)
        } catch {
            logger.error("Transcription failed: \(error)")
            await analyticsService.trackTranscriptionFailed(
                transcriptionId: transcriptionId,
                errorMessage: error.localizedDescription
            )
            await managedLifecycle.trackOperationError(error, operation: "transcribe")
            throw SDKError.stt(.generationFailed, "Transcription failed: \(error.localizedDescription)", underlying: error)
        }

        // Complete transcription tracking
        await analyticsService.completeTranscription(
            transcriptionId: transcriptionId,
            text: result.transcript,
            confidence: result.confidence ?? STTConstants.defaultConfidence
        )

        let metrics = await analyticsService.getMetrics()
        let processingTime = metrics.lastEventTime.map { $0.timeIntervalSince(metrics.startTime) } ?? 0

        logger.info("Transcription completed in \(Int(processingTime * 1000))ms")

        // Convert to output
        return STTOutput(
            text: result.transcript,
            confidence: result.confidence ?? STTConstants.defaultConfidence,
            wordTimestamps: result.timestamps?.map { timestamp in
                WordTimestamp(
                    word: timestamp.word,
                    startTime: timestamp.startTime,
                    endTime: timestamp.endTime,
                    confidence: timestamp.confidence ?? STTConstants.defaultConfidence
                )
            },
            detectedLanguage: result.language,
            alternatives: result.alternatives?.map { alt in
                TranscriptionAlternative(text: alt.transcript, confidence: alt.confidence)
            },
            metadata: TranscriptionMetadata(
                modelId: modelId,
                processingTime: processingTime,
                audioLength: audioLengthMs / 1000
            )
        )
    }

    /// Transcribe audio buffer
    /// - Parameters:
    ///   - buffer: Audio buffer
    ///   - language: Optional language hint
    /// - Returns: Transcription output
    public func transcribe(
        _ buffer: AVAudioPCMBuffer,
        language: String? = nil
    ) async throws -> STTOutput {
        let audioData = convertBufferToData(buffer)
        let effectiveLanguage = language ?? config?.language ?? "en"
        let options = STTOptions(
            language: effectiveLanguage,
            audioFormat: .pcm
        )
        return try await transcribe(audioData, options: options)
    }

    /// Stream transcription for real-time processing
    /// - Parameters:
    ///   - audioStream: Async stream of audio data chunks
    ///   - options: Transcription options
    /// - Returns: Async stream of transcription text
    public func streamTranscribe<S: AsyncSequence>(
        _ audioStream: S,
        options: STTOptions = STTOptions()
    ) -> AsyncThrowingStream<String, Error> where S.Element == Data {
        AsyncThrowingStream { continuation in
            Task {
                guard let service = await self.managedLifecycle.currentService else {
                    continuation.finish(
                        throwing: SDKError.stt(.componentNotReady, "STT model not loaded")
                    )
                    return
                }

                let effectiveOptions = self.mergeOptions(options)
                let modelId = await self.managedLifecycle.modelIdOrUnknown()

                // Start transcription tracking (streaming mode - audio length unknown upfront)
                let transcriptionId = await self.analyticsService.startTranscription(
                    modelId: modelId,
                    audioLengthMs: 0,  // Unknown for streaming
                    audioSizeBytes: 0, // Unknown for streaming
                    language: effectiveOptions.language,
                    isStreaming: true,
                    sampleRate: STTConstants.defaultSampleRate,
                    framework: service.inferenceFramework
                )

                var lastPartialWordCount = 0

                do {
                    let result = try await service.streamTranscribe(
                        audioStream: audioStream,
                        options: effectiveOptions,
                        onPartial: { partial in
                            // Track streaming update
                            let wordCount = partial.split(separator: " ").count
                            if wordCount > lastPartialWordCount {
                                Task {
                                    await self.analyticsService.trackPartialTranscript(text: partial)
                                }
                                lastPartialWordCount = wordCount
                            }
                            continuation.yield(partial)
                        }
                    )

                    // Complete transcription tracking
                    await self.analyticsService.completeTranscription(
                        transcriptionId: transcriptionId,
                        text: result.transcript,
                        confidence: result.confidence ?? STTConstants.defaultConfidence
                    )

                    // Yield final result
                    continuation.yield(result.transcript)
                    continuation.finish()
                } catch {
                    await self.analyticsService.trackTranscriptionFailed(
                        transcriptionId: transcriptionId,
                        errorMessage: error.localizedDescription
                    )
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Analytics

    /// Get current STT analytics metrics
    public func getAnalyticsMetrics() async -> STTMetrics {
        await analyticsService.getMetrics()
    }

    // MARK: - Private Methods

    private func mergeOptions(_ options: STTOptions) -> STTOptions {
        guard let config = config else { return options }

        return STTOptions(
            language: options.language.isEmpty ? (config.language ?? "en") : options.language,
            detectLanguage: options.detectLanguage,
            enablePunctuation: options.enablePunctuation,
            enableDiarization: options.enableDiarization,
            maxSpeakers: options.maxSpeakers,
            enableTimestamps: options.enableTimestamps,
            vocabularyFilter: options.vocabularyFilter,
            audioFormat: options.audioFormat,
            preferredFramework: options.preferredFramework
        )
    }

    private func convertBufferToData(_ buffer: AVAudioPCMBuffer) -> Data {
        guard let channelData = buffer.floatChannelData else { return Data() }

        let channelDataValue = channelData.pointee
        let channelDataCount = Int(buffer.frameLength)

        let samples = Array(UnsafeBufferPointer<Float>(
            start: channelDataValue,
            count: channelDataCount
        ))

        return samples.withUnsafeBufferPointer { bufferPointer in
            Data(buffer: bufferPointer)
        }
    }

    private func estimateAudioLength(dataSize: Int, sampleRate: Int = STTConstants.defaultSampleRate) -> TimeInterval {
        let bytesPerSample = 2 // 16-bit PCM
        let samples = dataSize / bytesPerSample
        return TimeInterval(samples) / TimeInterval(sampleRate)
    }
}
