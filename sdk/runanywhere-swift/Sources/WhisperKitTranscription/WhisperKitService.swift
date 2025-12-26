import Foundation
import RunAnywhere
import WhisperKit

/// WhisperKit implementation of STTService
public class WhisperKitService: STTService {
    private let logger = SDKLogger(category: "WhisperKitService")

    // MARK: - Framework Identification

    /// WhisperKit uses the WhisperKit inference framework (built on Core ML)
    public let inferenceFramework: InferenceFramework = .whisperKit

    // MARK: - Properties

    private var currentModelPath: String?
    private var isInitialized: Bool = false
    private var whisperKit: WhisperKit?
    private let garbledDetector = WhisperKitGarbledOutputDetector()
    private let streamProcessor = WhisperKitStreamProcessor()

    // Protocol requirements
    public var isReady: Bool { isInitialized && whisperKit != nil }
    public var currentModel: String? { currentModelPath }

    // MARK: - VoiceService Implementation

    public func initialize(modelPath: String?) async throws {
        logger.info("Starting initialization...")
        logger.debug("Model path requested: \(modelPath ?? "default")")

        // Skip initialization if already initialized with the same model
        if isInitialized && whisperKit != nil && currentModelPath == (modelPath ?? "whisper-base") {
            logger.info("✅ WhisperKit already initialized with model: \(self.currentModelPath ?? "unknown")")
            return
        }

        do {
            // Try to initialize WhisperKit with specific model
            let whisperKitModelName = mapModelIdToWhisperKitName(modelPath ?? "whisper-base")
            logger.info("Creating WhisperKit instance with model: \(whisperKitModelName)")

            // Initialize WhisperKit with specific model using WhisperKitConfig
            logger.info("🔧 Attempting WhisperKit initialization with model: \(whisperKitModelName)")

            // First try with just model name
            do {
                let config = WhisperKitConfig(
                    model: whisperKitModelName,
                    verbose: true,
                    logLevel: .info,
                    prewarm: true
                )
                whisperKit = try await WhisperKit(config)
                logger.info("✅ WhisperKit initialized successfully with model: \(whisperKitModelName)")
            } catch {
                logger.warning("⚠️ Failed to initialize with specific model, trying with base model")
                // Fallback to base model
                let fallbackConfig = WhisperKitConfig(
                    model: "openai_whisper-base",
                    verbose: true,
                    logLevel: .info,
                    prewarm: true
                )
                whisperKit = try await WhisperKit(fallbackConfig)
                logger.info("✅ WhisperKit initialized with fallback base model")
            }

            currentModelPath = modelPath ?? "whisper-base"
            isInitialized = true
            logger.info("✅ Successfully initialized WhisperKit")
            logger.debug("isInitialized: \(self.isInitialized)")
        } catch {
            logger.error("❌ Failed to initialize WhisperKit: \(error)")
            logger.error("Error details: \(error.localizedDescription)")
            throw STTError.transcriptionFailed(error)
        }
    }

    public func transcribe(
        audioData: Data,
        options: STTOptions
    ) async throws -> STTTranscriptionResult {
        // Convert Data to Float array
        let audioSamples = audioData.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
        let result = try await transcribeInternal(samples: audioSamples, options: options)
        // Convert STTResult to STTTranscriptionResult
        return STTTranscriptionResult(
            transcript: result.text,
            confidence: result.confidence,
            timestamps: nil,
            language: result.language,
            alternatives: nil
        )
    }

    /// Internal transcription with Float samples
    private func transcribeInternal(
        samples: [Float],
        options: STTOptions
    ) async throws -> STTResult {
        logger.info("transcribe() called with \(samples.count) samples")
        logger.debug("Options - Language: \(options.language)")

        guard isInitialized, self.whisperKit != nil else {
            logger.error("❌ Service not initialized!")
            throw STTError.serviceNotInitialized
        }

        guard !samples.isEmpty else {
            logger.error("❌ No audio samples to transcribe!")
            throw STTError.audioFormatNotSupported
        }

        let duration = Double(samples.count) / 16000.0
        logger.info("Audio: \(samples.count) samples, \(String(format: "%.2f", duration))s")

        // Simple audio validation
        let maxAmplitude = samples.map { abs($0) }.max() ?? 0
        let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))

        logger.info("Audio stats: max=\(String(format: "%.4f", maxAmplitude)), rms=\(String(format: "%.4f", rms))")

        if samples.allSatisfy({ $0 == 0 }) {
            logger.warning("All samples are zero - returning empty result")
            return STTResult(
                text: "",
                language: options.language,
                confidence: 0.0,
                duration: duration
            )
        }

        // For short audio, don't pad with zeros - WhisperKit handles it better
        var processedSamples = samples

        // Only pad if extremely short (less than 1.0 second)
        // WhisperKit performs much better with at least 1 second of audio
        let minRequiredSamples = 16000 // 1.0 seconds minimum
        if samples.count < minRequiredSamples {
            logger.info("📏 Audio too short (\(samples.count) samples), padding to \(minRequiredSamples)")
            // Pad with very low noise instead of zeros to avoid silence detection
            let noise = (0..<(minRequiredSamples - samples.count)).map { _ in Float.random(in: -0.0001...0.0001) }
            processedSamples = samples + noise
        } else {
            logger.info("📏 Processing \(samples.count) samples without padding")
        }

        return try await transcribeWithSamples(processedSamples, options: options, originalDuration: duration)
    }

    private func transcribeWithSamples(
        _ audioSamples: [Float],
        options: STTOptions,
        originalDuration: Double
    ) async throws -> STTResult {
        guard let whisperKit = whisperKit else {
            throw STTError.serviceNotInitialized
        }

        logger.info("Starting WhisperKit transcription with \(audioSamples.count) samples...")

        let decodingOptions = createDecodingOptions(for: audioSamples, options: options)
        let transcriptionResults = try await performTranscription(
            whisperKit: whisperKit,
            audioSamples: audioSamples,
            decodingOptions: decodingOptions
        )

        let transcribedText = extractAndValidateText(from: transcriptionResults, audioSamples: audioSamples)
        return createResult(text: transcribedText, from: transcriptionResults, options: options, duration: originalDuration)
    }

    private func createDecodingOptions(for audioSamples: [Float], options: STTOptions) -> DecodingOptions {
        let audioLengthSeconds = Float(audioSamples.count) / 16000.0
        let adaptiveNoSpeechThreshold: Float = audioLengthSeconds < 2.0 ? 0.3 : 0.4

        return DecodingOptions(
            task: .transcribe,
            language: "en",
            temperature: 0.0,
            temperatureFallbackCount: 1,
            sampleLength: 224,
            usePrefillPrompt: false,
            detectLanguage: false,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            compressionRatioThreshold: 1.8,
            logProbThreshold: -1.0,
            noSpeechThreshold: adaptiveNoSpeechThreshold
        )
    }

    private func performTranscription(
        whisperKit: WhisperKit,
        audioSamples: [Float],
        decodingOptions: DecodingOptions
    ) async throws -> [TranscriptionResult] {
        logger.info("🚀 Calling WhisperKit.transcribe() with \(audioSamples.count) samples...")
        let results = try await whisperKit.transcribe(audioArray: audioSamples, decodeOptions: decodingOptions)
        logger.info("✅ WhisperKit.transcribe() completed with \(results.count) results")
        return results
    }

    private func extractAndValidateText(from results: [TranscriptionResult], audioSamples: [Float]) -> String {
        var text = ""
        if let firstResult = results.first {
            text = firstResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
            text = cleanSpecialTokens(from: text)
        }

        if garbledDetector.isGarbled(text) {
            logger.warning("⚠️ Detected garbled output, rejecting transcription")
            return ""
        }

        logTranscriptionResult(text: text, results: results, audioSamples: audioSamples)
        return text
    }

    private func cleanSpecialTokens(from text: String) -> String {
        text.replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .replacingOccurrences(of: ">>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func logTranscriptionResult(text: String, results: [TranscriptionResult], audioSamples: [Float]) {
        if !text.isEmpty {
            logger.info("✅ Transcribed: '\(text)'")
        } else if results.isEmpty {
            logger.warning("⚠️ No transcription results returned")
        } else {
            logger.warning("⚠️ Empty or invalid transcription")
            let rms = sqrt(audioSamples.reduce(0) { $0 + $1 * $1 } / Float(audioSamples.count))
            logger.info("  Audio: \(Double(audioSamples.count) / 16000.0)s, RMS: \(String(format: "%.4f", rms))")
        }
    }

    private func createResult(
        text: String,
        from results: [TranscriptionResult],
        options: STTOptions,
        duration: Double
    ) -> STTResult {
        let result = STTResult(
            text: text,
            language: results.first?.language ?? options.language,
            confidence: text.isEmpty ? 0.0 : 0.95,
            duration: duration
        )
        logger.info("✅ Returning result with text: '\(result.text)'")
        return result
    }


    public func cleanup() async {
        isInitialized = false
        currentModelPath = nil
        whisperKit = nil
    }

    // MARK: - Initialization

    public init() {
        logger.info("Service instance created")
        // No initialization needed for basic service
    }

    // MARK: - Helper Methods

    private func mapModelIdToWhisperKitName(_ modelId: String) -> String {
        // Map common model IDs to WhisperKit model names
        switch modelId.lowercased() {
        case "whisper-tiny", "tiny":
            return "openai_whisper-tiny"
        case "whisper-base", "base":
            return "openai_whisper-base"
        case "whisper-small", "small":
            return "openai_whisper-small"
        case "whisper-medium", "medium":
            return "openai_whisper-medium"
        case "whisper-large", "large":
            return "openai_whisper-large-v3"
        default:
            // Default to base if not recognized
            logger.warning("Unknown model ID: \(modelId), defaulting to whisper-base")
            return "openai_whisper-base"
        }
    }

    // MARK: - Streaming Support

    /// Support for streaming transcription
    public var supportsStreaming: Bool {
        true
    }

    /// Stream transcription for real-time processing (protocol requirement)
    /// Delegates to transcribeStream for actual implementation
    public func streamTranscribe<S: AsyncSequence>(
        audioStream: S,
        options: STTOptions,
        onPartial: @escaping (String) -> Void
    ) async throws -> STTTranscriptionResult where S.Element == Data {
        logger.info("streamTranscribe called, delegating to transcribeStream")

        var finalTranscript = ""
        var finalConfidence: Float = 0.0
        var finalLanguage: String?

        // Convert generic AsyncSequence to AsyncStream<VoiceAudioChunk>
        let voiceChunkStream = AsyncStream<VoiceAudioChunk> { continuation in
            Task {
                do {
                    for try await audioData in audioStream {
                        // Convert Data to Float samples then to VoiceAudioChunk
                        let samples = audioData.withUnsafeBytes { buffer in
                            Array(buffer.bindMemory(to: Float.self))
                        }
                        let chunk = VoiceAudioChunk(
                            samples: samples,
                            timestamp: Date().timeIntervalSince1970
                        )
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }
        }

        // Process stream and collect results
        do {
            for try await segment in transcribeStream(audioStream: voiceChunkStream, options: options) {
                onPartial(segment.text)
                finalTranscript = segment.text
                // Language comes from options, not from segment
                finalLanguage = options.language
                finalConfidence = segment.confidence
            }

            return STTTranscriptionResult(
                transcript: finalTranscript,
                confidence: finalConfidence,
                timestamps: nil,
                language: finalLanguage,
                alternatives: nil
            )
        } catch {
            logger.error("Stream transcription failed: \(error)")
            throw error
        }
    }

    public func transcribeStream(
        audioStream: AsyncStream<VoiceAudioChunk>,
        options: STTOptions
    ) -> AsyncThrowingStream<STTSegment, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Ensure WhisperKit is loaded
                    let whisperKit = try await ensureWhisperKitLoaded()

                    // Process stream using dedicated processor
                    try await streamProcessor.processStream(
                        whisperKit: whisperKit,
                        audioStream: audioStream,
                        options: options,
                        continuation: continuation
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func ensureWhisperKitLoaded() async throws -> WhisperKit {
        if let whisperKit = self.whisperKit {
            return whisperKit
        }

        if isInitialized {
            throw STTError.serviceNotInitialized
        }

        try await initialize(modelPath: nil)

        guard let whisperKit = self.whisperKit else {
            throw STTError.serviceNotInitialized
        }

        return whisperKit
    }

}
