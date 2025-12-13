//
//  STTCapability.swift
//  RunAnywhere SDK
//
//  Actor-based STT capability that owns model lifecycle and transcription
//

@preconcurrency import AVFoundation
import Foundation

/// Actor-based STT capability that provides a simplified interface for speech-to-text
/// Owns the model lifecycle and provides thread-safe access to transcription operations
public actor STTCapability: ModelLoadableCapability {
    public typealias Configuration = STTConfiguration
    public typealias Service = STTService

    // MARK: - State

    /// Unified model lifecycle manager
    private let lifecycle: ModelLifecycleManager<STTService>

    /// Current configuration
    private var config: STTConfiguration?

    // MARK: - Dependencies

    private let logger = SDKLogger(category: "STTCapability")
    private let analyticsService: STTAnalyticsService

    // MARK: - Initialization

    public init(analyticsService: STTAnalyticsService = STTAnalyticsService()) {
        self.lifecycle = ModelLifecycleManager.forSTT()
        self.analyticsService = analyticsService
    }

    // MARK: - Configuration (Capability Protocol)

    public func configure(_ config: STTConfiguration) {
        self.config = config
        Task { await lifecycle.configure(config) }
    }

    // MARK: - Model Lifecycle (ModelLoadableCapability Protocol)

    public var isModelLoaded: Bool {
        get async { await lifecycle.isLoaded }
    }

    public var currentModelId: String? {
        get async { await lifecycle.currentResourceId }
    }

    /// Whether the service supports streaming transcription
    public var supportsStreaming: Bool {
        get async {
            guard let service = await lifecycle.currentService else { return false }
            return service.supportsStreaming
        }
    }

    public func loadModel(_ modelId: String) async throws {
        let startTime = Date()

        do {
            try await lifecycle.load(modelId)
            let loadTime = Date().timeIntervalSince(startTime)
            await analyticsService.trackModelLoading(
                modelId: modelId,
                loadTime: loadTime,
                success: true
            )
        } catch {
            let loadTime = Date().timeIntervalSince(startTime)
            await analyticsService.trackModelLoading(
                modelId: modelId,
                loadTime: loadTime,
                success: false
            )
            throw error
        }
    }

    public func unload() async throws {
        await lifecycle.unload()
    }

    public func cleanup() async {
        await lifecycle.reset()
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
        let service = try await lifecycle.requireService()
        let modelId = await lifecycle.currentResourceId ?? "unknown"

        logger.info("Transcribing audio with model: \(modelId)")

        // Merge options with config defaults
        let effectiveOptions = mergeOptions(options)

        // Estimate audio length
        let audioLengthMs = estimateAudioLength(dataSize: audioData.count) * 1000

        // Start transcription tracking
        let transcriptionId = await analyticsService.startTranscription(
            audioLengthMs: audioLengthMs,
            language: effectiveOptions.language
        )

        let startTime = Date()

        // Perform transcription
        let result: STTTranscriptionResult
        do {
            result = try await service.transcribe(audioData: audioData, options: effectiveOptions)
        } catch {
            logger.error("Transcription failed: \(error)")
            let processingTimeMs = Date().timeIntervalSince(startTime) * 1000
            await analyticsService.trackTranscriptionFailed(
                transcriptionId: transcriptionId,
                audioLengthMs: audioLengthMs,
                processingTimeMs: processingTimeMs,
                errorMessage: error.localizedDescription
            )
            throw CapabilityError.operationFailed("Transcription", error)
        }

        // Complete transcription tracking
        await analyticsService.completeTranscription(
            transcriptionId: transcriptionId,
            text: result.transcript,
            confidence: result.confidence ?? 0.9
        )

        let metrics = await analyticsService.getMetrics()
        let processingTime = metrics.lastEventTime.map { $0.timeIntervalSince(metrics.startTime) } ?? 0

        logger.info("Transcription completed in \(Int(processingTime * 1000))ms")

        // Convert to output
        return STTOutput(
            text: result.transcript,
            confidence: result.confidence ?? 0.9,
            wordTimestamps: result.timestamps?.map { timestamp in
                WordTimestamp(
                    word: timestamp.word,
                    startTime: timestamp.startTime,
                    endTime: timestamp.endTime,
                    confidence: timestamp.confidence ?? 0.9
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
                guard let service = await self.lifecycle.currentService else {
                    continuation.finish(
                        throwing: CapabilityError.resourceNotLoaded("STT model")
                    )
                    return
                }

                let modelId = await self.lifecycle.currentResourceId ?? "unknown"
                let effectiveOptions = self.mergeOptions(options)

                // Start transcription tracking
                let transcriptionId = await self.analyticsService.startTranscription(
                    audioLengthMs: 0, // Unknown for streaming
                    language: effectiveOptions.language
                )

                let startTime = Date()
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
                        confidence: result.confidence ?? 0.9
                    )

                    // Yield final result
                    continuation.yield(result.transcript)
                    continuation.finish()
                } catch {
                    let processingTimeMs = Date().timeIntervalSince(startTime) * 1000
                    await self.analyticsService.trackTranscriptionFailed(
                        transcriptionId: transcriptionId,
                        audioLengthMs: 0,
                        processingTimeMs: processingTimeMs,
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

    private func estimateAudioLength(dataSize: Int, sampleRate: Int = 16000) -> TimeInterval {
        let bytesPerSample = 2 // 16-bit PCM
        let samples = dataSize / bytesPerSample
        return TimeInterval(samples) / TimeInterval(sampleRate)
    }
}
