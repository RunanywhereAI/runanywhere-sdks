import Foundation
import RunAnywhereSDK
import AVFoundation
import WhisperKit
import os

/// WhisperKit implementation of VoiceService
public class WhisperKitService: VoiceService {
    private let logger = Logger(subsystem: "com.runanywhere.whisperkit", category: "WhisperKitService")

    // MARK: - Properties

    private var currentModelPath: String?
    private var isInitialized: Bool = false
    private var whisperKit: WhisperKit?

    // Properties for streaming
    private var streamingTask: Task<Void, Error>?
    private var audioAccumulator = Data()
    private let minAudioLength = 8000  // 500ms at 16kHz
    private let contextOverlap = 1600   // 100ms overlap for context

    // MARK: - VoiceService Implementation

    public func initialize(modelPath: String?) async throws {
        logger.info("Starting initialization...")
        logger.debug("Model path requested: \(modelPath ?? "default", privacy: .public)")

        // Skip initialization if already initialized with the same model
        if isInitialized && whisperKit != nil && currentModelPath == (modelPath ?? "whisper-base") {
            logger.info("✅ WhisperKit already initialized with model: \(self.currentModelPath ?? "unknown", privacy: .public)")
            return
        }

        // Map model ID to WhisperKit model name
        let whisperKitModelName = mapModelIdToWhisperKitName(modelPath ?? "whisper-base")
        logger.info("Creating WhisperKit instance with model: \(whisperKitModelName)")

        // Try multiple approaches to find and load models
        do {
            // Approach 1: Check for models in the app bundle
            if let bundleModelPath = Bundle.main.path(forResource: whisperKitModelName, ofType: nil) {
                logger.info("📦 Found model in app bundle: \(bundleModelPath)")
                whisperKit = try await WhisperKit(
                    modelFolder: bundleModelPath,
                    verbose: true,
                    logLevel: .info,
                    prewarm: true,
                    load: true,
                    download: false  // Disable downloading
                )
                logger.info("✅ WhisperKit initialized with bundled model")
                currentModelPath = modelPath ?? "whisper-base"
                isInitialized = true
                return
            }

            // Approach 2: Check Documents directory for downloaded models
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            let possiblePaths = [
                documentsPath?.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml/\(whisperKitModelName)"),
                documentsPath?.appendingPathComponent("WhisperKit/\(whisperKitModelName)"),
                documentsPath?.appendingPathComponent("RunAnywhere/Models/WhisperKit/\(whisperKitModelName)"),
                documentsPath?.appendingPathComponent("\(whisperKitModelName)")
            ]

            for possiblePath in possiblePaths {
                if let path = possiblePath, FileManager.default.fileExists(atPath: path.path) {
                    logger.info("📁 Found local model at: \(path.path)")
                    do {
                        whisperKit = try await WhisperKit(
                            modelFolder: path.path,
                            verbose: true,
                            logLevel: .info,
                            prewarm: true,
                            load: true,
                            download: false  // Disable downloading
                        )
                        logger.info("✅ WhisperKit initialized with local model")
                        currentModelPath = modelPath ?? "whisper-base"
                        isInitialized = true
                        return
                    } catch {
                        logger.warning("⚠️ Failed to load model from \(path.path): \(error)")
                        continue
                    }
                }
            }

            // Approach 3: Try to initialize without downloading (will use any cached models)
            logger.info("🔍 Attempting to initialize with any cached models...")
            do {
                whisperKit = try await WhisperKit(
                    model: whisperKitModelName,
                    verbose: true,
                    logLevel: .info,
                    prewarm: false,  // Don't prewarm to avoid network calls
                    load: false,     // Don't auto-load to avoid network calls
                    download: false  // Explicitly disable downloading
                )

                // Try to load models manually
                try await whisperKit?.loadModels()
                logger.info("✅ WhisperKit initialized with cached model")
                currentModelPath = modelPath ?? "whisper-base"
                isInitialized = true
                return
            } catch {
                logger.warning("⚠️ No cached models available: \(error)")
            }

            // If all approaches fail, mark as initialized for offline fallback
            logger.info("📱 No local WhisperKit models found - using offline fallback mode")
            isInitialized = true
            currentModelPath = modelPath ?? "whisper-base"
            // whisperKit remains nil, which will trigger fallback in transcribe method

        } catch {
            logger.error("❌ Failed to initialize WhisperKit: \(error, privacy: .public)")
            logger.error("Error details: \(error.localizedDescription, privacy: .public)")
            // Mark as initialized for offline fallback
            isInitialized = true
            currentModelPath = modelPath ?? "whisper-base"
            logger.info("📱 Continuing in offline fallback mode")
        }
    }

    public func transcribe(
        audio: Data,
        options: VoiceTranscriptionOptions
    ) async throws -> VoiceTranscriptionResult {
        // Convert Data to Float array
        let audioSamples = audio.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
        return try await transcribe(samples: audioSamples, options: options)
    }

    /// Direct transcription with Float samples
    public func transcribe(
        samples: [Float],
        options: VoiceTranscriptionOptions
    ) async throws -> VoiceTranscriptionResult {
        logger.info("transcribe() called with \(samples.count) samples")
        logger.debug("Options - Language: \(options.language.rawValue, privacy: .public), Task: \(String(describing: options.task), privacy: .public)")

        guard isInitialized else {
            logger.error("❌ Service not initialized!")
            throw VoiceError.serviceNotInitialized
        }

        // If whisperKit is nil, we're in offline fallback mode
        if whisperKit == nil {
            logger.info("📱 WhisperKit not available - using fallback")
            let duration = Double(samples.count) / 16000.0

            // Analyze audio to determine if speech was detected
            let maxAmplitude = samples.map { abs($0) }.max() ?? 0
            let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))

            // If we have significant audio, return empty transcription to continue pipeline
            // The LLM can still respond to user even without transcription
            if maxAmplitude > 0.01 || rms > 0.005 {
                logger.info("🎤 Audio detected but transcription unavailable")
                return VoiceTranscriptionResult(
                    text: "",  // Empty text, let LLM handle the response
                    language: options.language.rawValue,
                    confidence: 0.0,
                    duration: duration
                )
            } else {
                // No significant audio
                return VoiceTranscriptionResult(
                    text: "",
                    language: options.language.rawValue,
                    confidence: 0.0,
                    duration: duration
                )
            }
        }

        guard !samples.isEmpty else {
            logger.error("❌ No audio samples to transcribe!")
            throw VoiceError.unsupportedAudioFormat
        }

        let duration = Double(samples.count) / 16000.0
        logger.info("Audio: \(samples.count) samples, \(String(format: "%.2f", duration))s")

        // Simple audio validation
        let maxAmplitude = samples.map { abs($0) }.max() ?? 0
        let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))

        logger.info("Audio stats: max=\(String(format: "%.4f", maxAmplitude)), rms=\(String(format: "%.4f", rms))")

        if samples.allSatisfy({ $0 == 0 }) {
            logger.warning("All samples are zero - returning empty result")
            return VoiceTranscriptionResult(
                text: "",
                language: options.language.rawValue,
                confidence: 0.0,
                duration: duration
            )
        }

        // For short audio, don't pad with zeros - WhisperKit handles it better
        var processedSamples = samples

        // Only pad if extremely short (less than 0.5 seconds)
        let minRequiredSamples = 8000 // 0.5 seconds minimum
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
        options: VoiceTranscriptionOptions,
        originalDuration: Double
    ) async throws -> VoiceTranscriptionResult {
        guard let whisperKit = whisperKit else {
            // In offline fallback mode, return empty transcription
            logger.info("📱 WhisperKit not available for transcription")
            return VoiceTranscriptionResult(
                text: "",  // Empty transcription when WhisperKit unavailable
                language: options.language.rawValue,
                confidence: 0.0,
                duration: originalDuration
            )
        }

        logger.info("Starting WhisperKit transcription with \(audioSamples.count) samples...")

        // Use conservative decoding options to prevent garbled output
        // Adjust noSpeechThreshold based on audio length
        let noSpeechThresh: Float = audioSamples.count < 32000 ? 0.3 : 0.6  // Lower for short audio

        let decodingOptions = DecodingOptions(
            task: .transcribe,
            language: "en",  // Force English to avoid language detection issues
            temperature: 0.0,  // Start conservative
            temperatureFallbackCount: 1,  // Minimal fallbacks to prevent garbled output
            sampleLength: 224,  // Standard length
            usePrefillPrompt: false,  // Disable prefill to reduce special tokens
            detectLanguage: false,  // Force English instead of auto-detect
            skipSpecialTokens: true,  // Skip special tokens for cleaner output
            withoutTimestamps: true,  // Remove timestamps for cleaner text
            compressionRatioThreshold: 2.4,  // Stricter compression ratio
            logProbThreshold: -1.0,  // More conservative log probability
            noSpeechThreshold: noSpeechThresh  // Adaptive threshold based on audio length
        )

        logger.info("Using decoding options:")
        logger.info("  Task: \(decodingOptions.task)")
        logger.info("  Language: \(decodingOptions.language ?? "auto-detect")")
        logger.info("  Temperature: \(decodingOptions.temperature)")
        logger.info("  TemperatureFallbackCount: \(decodingOptions.temperatureFallbackCount)")
        logger.info("  SampleLength: \(decodingOptions.sampleLength)")
        logger.info("  DetectLanguage: \(decodingOptions.detectLanguage)")

        logger.info("🚀 Calling WhisperKit.transcribe() with \(audioSamples.count) samples...")
        let transcriptionResults = try await whisperKit.transcribe(
            audioArray: audioSamples,
            decodeOptions: decodingOptions
        )
        logger.info("✅ WhisperKit.transcribe() completed")
        logger.info("📊 Results count: \(transcriptionResults.count)")

        // Log WhisperKit version and capabilities if available
        logger.info("🔍 WhisperKit instance details:")
        logger.info("  Type: \(type(of: whisperKit))")
        // Skip fetching available models in offline mode to avoid network errors
        logger.info("  Running in offline mode - skipping model fetch")

        // Extract and validate the transcribed text
        var transcribedText = transcriptionResults.first?.text ?? ""

        // Validate result to reject garbled output
        if isGarbledOutput(transcribedText) {
            logger.warning("⚠️ Detected garbled output: '\(transcribedText.prefix(50))...'")
            transcribedText = "" // Treat as empty/failed transcription
        }

        // Log very detailed results for debugging
        if transcriptionResults.isEmpty {
            logger.error("❌ WhisperKit returned empty results array!")
        } else {
            for (resultIndex, result) in transcriptionResults.enumerated() {
                logger.info("Result \(resultIndex):")
                logger.info("  Text: '\(result.text)'")
                logger.info("  Language: \(result.language)")
                logger.info("  Segments count: \(result.segments.count)")

                for (segmentIndex, segment) in result.segments.enumerated() {
                    logger.info("  Segment \(segmentIndex):")
                    logger.info("    Text: '\(segment.text)'")
                    logger.info("    Start: \(segment.start), End: \(segment.end)")
                    logger.info("    Tokens: \(segment.tokens)")
                }

                if result.text.isEmpty {
                    logger.warning("⚠️ Result \(resultIndex) has empty text!")
                }
            }
        }

        logger.info("Final transcribed text: '\(transcribedText)'")

        // If transcription is empty or garbled, provide diagnostic information
        if transcribedText.isEmpty {
            let maxAmplitude = audioSamples.map { abs($0) }.max() ?? 0
            let avgAmplitude = audioSamples.map { abs($0) }.reduce(0, +) / Float(audioSamples.count)
            let rms = sqrt(audioSamples.reduce(0) { $0 + $1 * $1 } / Float(audioSamples.count))

            logger.warning("⚠️ WhisperKit transcription was empty or rejected")
            logger.info("  Audio duration: \(Double(audioSamples.count) / 16000.0) seconds")
            logger.info("  Audio amplitude: max=\(maxAmplitude), avg=\(avgAmplitude), rms=\(rms)")
            logger.info("  Audio samples: \(audioSamples.count)")
            logger.info("  Results array: \(transcriptionResults.count) items")

            // No fallback to prevent garbled output - return empty result
            logger.info("📝 Returning empty result to prevent garbled output")
        }

        // Return the result (even if empty)
        let result = VoiceTranscriptionResult(
            text: transcribedText,
            language: transcriptionResults.first?.language ?? options.language.rawValue,
            confidence: transcribedText.isEmpty ? 0.0 : 0.95,
            duration: originalDuration
        )
        logger.info("✅ Returning result with text: '\(result.text)'")
        return result
    }

    public var isReady: Bool {
        return isInitialized
    }

    public var currentModel: String? {
        return currentModelPath
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
        return true
    }

    /// Transcribe audio stream in real-time
    public func transcribeStream(
        audioStream: AsyncStream<VoiceAudioChunk>,
        options: VoiceTranscriptionOptions
    ) -> AsyncThrowingStream<VoiceTranscriptionSegment, Error> {
        AsyncThrowingStream { continuation in
            self.streamingTask = Task {
                do {
                    // For offline fallback mode, return empty segments
                    if self.whisperKit == nil && self.isInitialized {
                        // We're in offline fallback mode
                        self.logger.info("📱 WhisperKit unavailable for streaming transcription")

                        // Return empty segment to continue pipeline
                        let emptySegment = VoiceTranscriptionSegment(
                            text: "",
                            startTime: Date().timeIntervalSince1970,
                            endTime: Date().timeIntervalSince1970 + 0.1,
                            confidence: 0.0,
                            language: options.language.rawValue
                        )
                        continuation.yield(emptySegment)
                        continuation.finish()
                        return
                    }

                    // Ensure WhisperKit is loaded
                    guard let whisperKit = self.whisperKit else {
                        if !self.isInitialized {
                            // Not initialized, try to initialize with default model
                            try await self.initialize(modelPath: nil)
                        }
                        // If still nil, we're in offline fallback mode
                        if self.whisperKit == nil {
                            self.logger.info("📱 WhisperKit unavailable - returning empty transcription")
                            let emptySegment = VoiceTranscriptionSegment(
                                text: "",
                                startTime: Date().timeIntervalSince1970,
                                endTime: Date().timeIntervalSince1970 + 0.1,
                                confidence: 0.0,
                                language: options.language.rawValue
                            )
                            continuation.yield(emptySegment)
                            continuation.finish()
                            return
                        }
                        return
                    }

                    // Process audio stream
                    var audioBuffer = Data()
                    var lastTranscript = ""

                    for await chunk in audioStream {
                        audioBuffer.append(chunk.data)

                        // Process when we have enough audio (500ms)
                        if audioBuffer.count >= minAudioLength {
                            // Convert to float array for WhisperKit
                            let floatArray = audioBuffer.withUnsafeBytes { buffer in
                                Array(buffer.bindMemory(to: Float.self))
                            }

                            // Transcribe using WhisperKit with shorter settings for streaming
                            let decodingOptions = DecodingOptions(
                                task: options.task == .translate ? .translate : .transcribe,
                                language: options.language.rawValue,
                                temperature: 0.0,
                                temperatureFallbackCount: 0,
                                sampleLength: 224,  // Shorter for streaming
                                usePrefillPrompt: false,
                                detectLanguage: false,
                                skipSpecialTokens: true,
                                withoutTimestamps: false
                            )

                            let results = try await whisperKit.transcribe(
                                audioArray: floatArray,
                                decodeOptions: decodingOptions
                            )

                            // Get the transcribed text
                            if let result = results.first {
                                let newText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

                                // Only yield if there's new content
                                if !newText.isEmpty && newText != lastTranscript {
                                    let segment = VoiceTranscriptionSegment(
                                        text: newText,
                                        startTime: chunk.timestamp - 0.5,
                                        endTime: chunk.timestamp,
                                        confidence: 0.95,
                                        language: options.language.rawValue
                                    )
                                    continuation.yield(segment)
                                    lastTranscript = newText
                                }
                            }

                            // Keep last 100ms for context continuity
                            audioBuffer = Data(audioBuffer.suffix(contextOverlap))
                        }
                    }

                    // Process any remaining audio
                    if audioBuffer.count > 0 {
                        // Final transcription with remaining audio
                        let floatArray = audioBuffer.withUnsafeBytes { buffer in
                            Array(buffer.bindMemory(to: Float.self))
                        }

                        let decodingOptions = DecodingOptions(
                            task: options.task == .translate ? .translate : .transcribe,
                            language: options.language.rawValue,
                            temperature: 0.0,
                            temperatureFallbackCount: 0,
                            sampleLength: 224,
                            usePrefillPrompt: false,
                            detectLanguage: false,
                            skipSpecialTokens: true,
                            withoutTimestamps: false
                        )

                        let results = try await whisperKit.transcribe(
                            audioArray: floatArray,
                            decodeOptions: decodingOptions
                        )

                        if let result = results.first {
                            let segment = VoiceTranscriptionSegment(
                                text: result.text,
                                startTime: Date().timeIntervalSince1970 - 0.1,
                                endTime: Date().timeIntervalSince1970,
                                confidence: 0.95,
                                language: options.language.rawValue
                            )
                            continuation.yield(segment)
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Detect garbled or nonsensical WhisperKit output
    private func isGarbledOutput(_ text: String) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Empty text is not garbled, just empty
        guard !trimmedText.isEmpty else { return false }

        // Check for common garbled patterns
        let garbledPatterns = [
            // Repetitive characters
            "^[\\(\\)\\-\\.\\s]+$",  // Only parentheses, dashes, dots, spaces
            "^[\\-]{10,}",          // Many consecutive dashes
            "^[\\(]{5,}",           // Many consecutive opening parentheses
            "^[\\)]{5,}",           // Many consecutive closing parentheses
            "^[\\.,]{5,}",          // Many consecutive dots/commas
            // Special token patterns
            "^\\s*\\[.*\\]\\s*$",   // Text wrapped in brackets
            "^\\s*<.*>\\s*$",       // Text wrapped in angle brackets
        ]

        for pattern in garbledPatterns {
            if trimmedText.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }

        // Check character composition - if more than 70% is punctuation, likely garbled
        let punctuationCount = trimmedText.filter { $0.isPunctuation }.count
        let totalCount = trimmedText.count
        if totalCount > 5 && Double(punctuationCount) / Double(totalCount) > 0.7 {
            return true
        }

        // Check for excessive repetition of the same character
        let charCounts = Dictionary(trimmedText.map { ($0, 1) }, uniquingKeysWith: +)
        for (_, count) in charCounts {
            if count > max(10, trimmedText.count / 2) {
                return true
            }
        }

        return false
    }
}
