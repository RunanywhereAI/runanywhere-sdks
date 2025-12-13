// swiftlint:disable file_length
//
//  STTComponent.swift
//  RunAnywhere SDK
//
//  Speech-to-Text component following the clean architecture
//

@preconcurrency import AVFoundation
import Foundation

// MARK: - STT Component

/// Speech-to-Text component following the clean architecture
public final class STTComponent: BaseComponent<any STTService>, @unchecked Sendable { // swiftlint:disable:this type_body_length

    // MARK: - Properties

    public override static var componentType: SDKComponent { .stt }

    private let sttConfiguration: STTConfiguration
    private var isModelLoaded = false
    private var modelPath: String?
    private var providerName: String = "Unknown"  // Store the provider name for telemetry
    private let logger = SDKLogger(category: "STTComponent")

    // MARK: - Initialization

    public init(configuration: STTConfiguration) {
        self.sttConfiguration = configuration
        super.init(configuration: configuration)
    }

    // MARK: - Service Creation

    public override func createService() async throws -> any STTService {
        let modelId = sttConfiguration.modelId ?? "unknown"
        let modelName = modelId

        // Check if we already have a cached service via the lifecycle tracker
        if let cachedService = await ModelLifecycleTracker.shared.sttService(for: modelId) {
            logger.info("Reusing cached STT service for model: \(modelId)")
            isModelLoaded = true
            return cachedService
        }

        // Notify lifecycle manager
        await MainActor.run {
            ModelLifecycleTracker.shared.modelWillLoad(
                modelId: modelId,
                modelName: modelName,
                framework: .whisperKit,
                modality: .stt
            )
        }

        // Try to get a registered STT provider from central registry
        let provider = await MainActor.run {
            ModuleRegistry.shared.sttProvider(for: sttConfiguration.modelId)
        }

        guard let provider = provider else {
            await MainActor.run {
                ModelLifecycleTracker.shared.modelLoadFailed(
                    modelId: modelId,
                    modality: .stt,
                    error: "No STT service provider registered"
                )
            }
            throw RunAnywhereError.componentNotInitialized(
                "No STT service provider registered. Please register WhisperKitServiceProvider.register()"
            )
        }

        modelPath = modelId

        do {
            // Create service through provider
            let sttService = try await provider.createSTTService(configuration: sttConfiguration)

            // Store provider name for telemetry
            self.providerName = provider.name

            // Service is already initialized by the provider
            isModelLoaded = true

            // Store service in lifecycle tracker for reuse
            await MainActor.run {
                ModelLifecycleTracker.shared.modelDidLoad(
                    modelId: modelId,
                    modelName: modelName,
                    framework: .whisperKit,
                    modality: .stt,
                    sttService: sttService
                )
            }

            return sttService
        } catch {
            await MainActor.run {
                ModelLifecycleTracker.shared.modelLoadFailed(
                    modelId: modelId,
                    modality: .stt,
                    error: error.localizedDescription
                )
            }
            throw error
        }
    }

    public override func performCleanup() async throws {
        await service?.cleanup()
        isModelLoaded = false
        modelPath = nil
    }

    // MARK: - Capabilities

    /// Whether the underlying service supports live/streaming transcription
    /// If false, `liveTranscribe` will internally fall back to batch processing
    public var supportsStreaming: Bool {
        service?.supportsStreaming ?? false
    }

    /// Get the recommended transcription mode based on service capabilities
    public var recommendedMode: STTMode {
        supportsStreaming ? .live : .batch
    }

    // MARK: - Batch Transcription API

    /// Transcribe audio data in batch mode
    /// - Parameters:
    ///   - audioData: Raw audio data (Int16 PCM)
    ///   - options: Transcription options (language, punctuation, etc.)
    /// - Returns: Transcription output with text, confidence, and metadata
    public func transcribe(_ audioData: Data, options: STTOptions = .default()) async throws -> STTOutput {
        try ensureReady()

        let input = STTInput(
            audioData: audioData,
            format: options.audioFormat,
            language: options.language,
            options: options
        )
        return try await process(input)
    }

    /// Transcribe audio data with simple parameters (convenience method)
    public func transcribe(_ audioData: Data, format: AudioFormat = .wav, language: String? = nil) async throws -> STTOutput {
        try ensureReady()

        let input = STTInput(
            audioData: audioData,
            format: format,
            language: language
        )
        return try await process(input)
    }

    /// Transcribe audio buffer
    public func transcribe(_ audioBuffer: AVAudioPCMBuffer, language: String? = nil) async throws -> STTOutput {
        try ensureReady()

        let input = STTInput(
            audioBuffer: audioBuffer,
            format: .pcm,
            language: language
        )
        return try await process(input)
    }

    /// Transcribe with VAD context
    public func transcribeWithVAD(_ audioData: Data, format: AudioFormat = .wav, vadOutput: VADOutput) async throws -> STTOutput {
        try ensureReady()

        let input = STTInput(
            audioData: audioData,
            format: format,
            vadOutput: vadOutput
        )
        return try await process(input)
    }

    // MARK: - Live/Streaming Transcription API

    /// Live transcription with real-time partial results
    /// - Parameters:
    ///   - audioStream: Async sequence of audio data chunks
    ///   - options: Transcription options
    /// - Returns: Async stream of transcription text (partial and final results)
    /// - Note: If the service doesn't support streaming, this will collect all audio
    ///         and return a single result when the stream completes
    public func liveTranscribe<S: AsyncSequence>(
        _ audioStream: S,
        options: STTOptions = .default()
    ) -> AsyncThrowingStream<String, Error> where S.Element == Data {
        return streamTranscribe(audioStream, language: options.language)
    }

    /// Process STT input
    public func process(_ input: STTInput) async throws -> STTOutput { // swiftlint:disable:this function_body_length
        try ensureReady()

        guard let sttService = service else {
            throw RunAnywhereError.componentNotReady("STT service not available")
        }

        // Validate input
        try input.validate()

        // Create options from input or use defaults
        let options = input.options ?? STTOptions(
            language: input.language ?? sttConfiguration.language,
            detectLanguage: input.language == nil,
            enablePunctuation: sttConfiguration.enablePunctuation,
            enableDiarization: sttConfiguration.enableDiarization,
            maxSpeakers: nil,
            enableTimestamps: sttConfiguration.enableTimestamps,
            vocabularyFilter: sttConfiguration.vocabularyList,
            audioFormat: input.format,
            preferredFramework: nil  // Use default provider selection
        )

        // Note: preferredFramework in STTOptions can be used in createService() for provider selection
        // Currently, the service is already created during component initialization
        // Future enhancement: Support dynamic provider switching based on preferredFramework

        // Get audio data
        let audioData: Data
        if !input.audioData.isEmpty {
            audioData = input.audioData
        } else if let buffer = input.audioBuffer {
            audioData = convertBufferToData(buffer)
        } else {
            throw RunAnywhereError.validationFailed("No audio data provided")
        }

        // Track processing time
        let startTime = Date()

        // Calculate audio length for telemetry
        let audioLength = estimateAudioLength(dataSize: audioData.count, format: input.format, sampleRate: sttConfiguration.sampleRate)
        let modelId = sttConfiguration.modelId ?? "unknown"
        let frameworkName = self.providerName

        // Perform transcription with error telemetry
        let result: STTTranscriptionResult
        do {
            result = try await sttService.transcribe(audioData: audioData, options: options)
        } catch {
            // Submit failure telemetry
            let processingTime = Date().timeIntervalSince(startTime)
            Task.detached(priority: .background) {
                let deviceInfo = TelemetryDeviceInfo.current
                let eventData = STTTranscriptionTelemetryData(
                    modelId: modelId,
                    modelName: modelId,
                    framework: frameworkName,
                    device: deviceInfo.device,
                    osVersion: deviceInfo.osVersion,
                    platform: deviceInfo.platform,
                    sdkVersion: SDKConstants.version,
                    processingTimeMs: processingTime * 1000,
                    success: false,
                    errorMessage: error.localizedDescription,
                    audioDurationMs: audioLength * 1000,
                    realTimeFactor: nil,
                    wordCount: nil,
                    confidence: nil,
                    language: nil,
                    isStreaming: false
                )
                let event = STTEvent(type: .transcriptionCompleted, eventData: eventData)
                await AnalyticsQueueManager.shared.enqueue(event)
            }
            throw error
        }

        let processingTime = Date().timeIntervalSince(startTime)

        // Convert to strongly typed output
        let wordTimestamps = result.timestamps?.map { timestamp in
            WordTimestamp(
                word: timestamp.word,
                startTime: timestamp.startTime,
                endTime: timestamp.endTime,
                confidence: timestamp.confidence ?? 0.9
            )
        }

        let alternatives = result.alternatives?.map { alt in
            TranscriptionAlternative(
                text: alt.transcript,
                confidence: alt.confidence
            )
        }

        let metadata = TranscriptionMetadata(
            modelId: modelId,
            processingTime: processingTime,
            audioLength: audioLength
        )

        let output = STTOutput(
            text: result.transcript,
            confidence: result.confidence ?? 0.9,
            wordTimestamps: wordTimestamps,
            detectedLanguage: result.language,
            alternatives: alternatives,
            metadata: metadata
        )

        // Submit success telemetry for batch transcription
        let wordCount = result.transcript.split(separator: " ").count
        let realTimeFactor = audioLength > 0 ? processingTime / audioLength : 0
        Task.detached(priority: .background) {
            let deviceInfo = TelemetryDeviceInfo.current
            let eventData = STTTranscriptionTelemetryData(
                modelId: modelId,
                modelName: modelId,
                framework: frameworkName,
                device: deviceInfo.device,
                osVersion: deviceInfo.osVersion,
                platform: deviceInfo.platform,
                sdkVersion: SDKConstants.version,
                processingTimeMs: processingTime * 1000,
                success: true,
                audioDurationMs: audioLength * 1000,
                realTimeFactor: realTimeFactor,
                wordCount: wordCount,
                confidence: result.confidence.map { Double($0) },
                language: result.language,
                isStreaming: false
            )
            let event = STTEvent(type: .transcriptionCompleted, eventData: eventData)
            await AnalyticsQueueManager.shared.enqueue(event)
        }

        return output
    }

    /// Stream transcription
    public func streamTranscribe<S: AsyncSequence>( // swiftlint:disable:this function_body_length
        _ audioStream: S,
        language: String? = nil
    ) -> AsyncThrowingStream<String, Error> where S.Element == Data {
        AsyncThrowingStream { continuation in
            Task {
                let startTime = Date()
                let modelId = self.sttConfiguration.modelId ?? "unknown"
                let frameworkName = self.providerName

                do {
                    try ensureReady()

                    guard let sttService = service else {
                        continuation.finish(throwing: RunAnywhereError.componentNotReady("STT service not available"))
                        return
                    }

                    let options = STTOptions(
                        language: language ?? sttConfiguration.language,
                        detectLanguage: language == nil,
                        enablePunctuation: sttConfiguration.enablePunctuation,
                        enableDiarization: sttConfiguration.enableDiarization,
                        enableTimestamps: false,
                        vocabularyFilter: sttConfiguration.vocabularyList,
                        audioFormat: .pcm
                    )

                    let result = try await sttService.streamTranscribe(
                        audioStream: audioStream,
                        options: options
                    ) { partial in
                        continuation.yield(partial)
                    }

                    // Yield final result
                    continuation.yield(result.transcript)

                    // Submit success telemetry for streaming transcription
                    let processingTime = Date().timeIntervalSince(startTime)
                    let wordCount = result.transcript.split(separator: " ").count
                    Task.detached(priority: .background) {
                        let deviceInfo = TelemetryDeviceInfo.current
                        let eventData = STTTranscriptionTelemetryData(
                            modelId: modelId,
                            modelName: modelId,
                            framework: frameworkName,
                            device: deviceInfo.device,
                            osVersion: deviceInfo.osVersion,
                            platform: deviceInfo.platform,
                            sdkVersion: SDKConstants.version,
                            processingTimeMs: processingTime * 1000,
                            success: true,
                            audioDurationMs: nil,  // Unknown for streaming
                            realTimeFactor: nil,
                            wordCount: wordCount,
                            confidence: result.confidence.map { Double($0) },
                            language: result.language,
                            isStreaming: true
                        )
                        let event = STTEvent(type: .transcriptionCompleted, eventData: eventData)
                        await AnalyticsQueueManager.shared.enqueue(event)
                    }

                    continuation.finish()
                } catch {
                    // Submit failure telemetry for streaming transcription
                    let processingTime = Date().timeIntervalSince(startTime)
                    Task.detached(priority: .background) {
                        let deviceInfo = TelemetryDeviceInfo.current
                        let eventData = STTTranscriptionTelemetryData(
                            modelId: modelId,
                            modelName: modelId,
                            framework: frameworkName,
                            device: deviceInfo.device,
                            osVersion: deviceInfo.osVersion,
                            platform: deviceInfo.platform,
                            sdkVersion: SDKConstants.version,
                            processingTimeMs: processingTime * 1000,
                            success: false,
                            errorMessage: error.localizedDescription,
                            audioDurationMs: nil,
                            realTimeFactor: nil,
                            wordCount: nil,
                            confidence: nil,
                            language: nil,
                            isStreaming: true
                        )
                        let event = STTEvent(type: .transcriptionCompleted, eventData: eventData)
                        await AnalyticsQueueManager.shared.enqueue(event)
                    }
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Get service for compatibility
    public func getService() -> (any STTService)? {
        return service
    }

    // MARK: - Private Helpers

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

    private func estimateAudioLength(dataSize: Int, format: AudioFormat, sampleRate: Int) -> TimeInterval {
        // Rough estimation based on format and sample rate
        let bytesPerSample: Int
        switch format {
        case .pcm, .wav:
            bytesPerSample = 2 // 16-bit PCM
        case .mp3:
            bytesPerSample = 1 // Compressed
        default:
            bytesPerSample = 2
        }

        let samples = dataSize / bytesPerSample
        return TimeInterval(samples) / TimeInterval(sampleRate)
    }
}
