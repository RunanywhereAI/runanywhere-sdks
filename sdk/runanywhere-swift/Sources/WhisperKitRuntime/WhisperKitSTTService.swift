//
//  WhisperKitSTTService.swift
//  WhisperKitRuntime Module
//
//  Actor wrapping WhisperKit for model loading and transcription.
//  Conforms to SwiftSTTHandler so RunAnywhere core can route to it.
//

import CoreML
import Foundation
import RunAnywhere
import WhisperKit

// MARK: - WhisperKit STT Service

/// Actor managing WhisperKit model lifecycle and transcription.
///
/// Uses `.cpuAndNeuralEngine` compute units for all pipeline stages,
/// ensuring minimal CPU load and full Neural Engine utilization.
/// This makes it ideal for background STT on iOS.
public actor WhisperKitSTTService: SwiftSTTHandler {
    public static let shared = WhisperKitSTTService()

    private let logger = SDKLogger(category: "WhisperKitSTTService")

    private var whisperKit: WhisperKit?
    public private(set) var currentModelId: String?

    public var isModelLoaded: Bool {
        whisperKit != nil
    }

    // MARK: - Model Loading

    public func loadModel(modelId: String, modelFolder: String) async throws {
        // Unload existing model if one is loaded
        if whisperKit != nil {
            await unloadModel()
        }

        logger.info("Loading WhisperKit model '\(modelId)' from: \(modelFolder)")

        let computeOptions = ModelComputeOptions(
            melCompute: .cpuAndNeuralEngine,
            audioEncoderCompute: .cpuAndNeuralEngine,
            textDecoderCompute: .cpuAndNeuralEngine,
            prefillCompute: .cpuOnly
        )

        let config = WhisperKitConfig(
            modelFolder: modelFolder,
            computeOptions: computeOptions,
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: true,
            download: false
        )

        let kit = try await WhisperKit(config)

        self.whisperKit = kit
        self.currentModelId = modelId
        logger.info("WhisperKit model '\(modelId)' loaded successfully")
    }

    // MARK: - Transcription

    public func transcribe(_ audioData: Data, options: STTOptions) async throws -> STTOutput {
        guard let kit = whisperKit else {
            throw SDKError.stt(.notInitialized, "WhisperKit model not loaded")
        }

        let startTime = Date()
        let modelId = currentModelId ?? "unknown"

        // Convert Int16 PCM data to [Float] normalized to [-1.0, 1.0]
        let floatSamples = convertInt16PCMToFloat(audioData)

        // Build decode options from STTOptions
        var decodeOptions = DecodingOptions()
        decodeOptions.language = options.language

        // Transcribe
        let results = try await kit.transcribe(
            audioArray: floatSamples,
            decodeOptions: decodeOptions
        )

        let endTime = Date()
        let processingTimeSec = endTime.timeIntervalSince(startTime)
        let audioLengthSec = Double(floatSamples.count) / 16000.0

        // Extract text from results
        let transcribedText = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        let detectedLanguage = results.first?.language

        // Extract word timestamps if available
        let wordTimestamps: [WordTimestamp]? = results.first?.segments.flatMap { segment in
            (segment.words ?? []).map { word in
                WordTimestamp(
                    word: word.word,
                    startTime: Double(word.start),
                    endTime: Double(word.end),
                    confidence: word.probability
                )
            }
        }

        // Extract confidence from segments
        let confidence: Float = {
            let segments = results.flatMap(\.segments)
            guard !segments.isEmpty else { return 0.0 }
            // Use average no-speech probability inverted as a rough confidence
            let avgNoSpeechProb = segments.map(\.noSpeechProb).reduce(0, +) / Float(segments.count)
            return 1.0 - avgNoSpeechProb
        }()

        let metadata = TranscriptionMetadata(
            modelId: modelId,
            processingTime: processingTimeSec,
            audioLength: audioLengthSec
        )

        return STTOutput(
            text: transcribedText,
            confidence: confidence,
            wordTimestamps: wordTimestamps,
            detectedLanguage: detectedLanguage,
            alternatives: nil,
            metadata: metadata
        )
    }

    // MARK: - Unload

    public func unloadModel() async {
        let modelId = currentModelId ?? "unknown"
        whisperKit = nil
        currentModelId = nil
        logger.info("WhisperKit model '\(modelId)' unloaded")
    }

    // MARK: - Private Helpers

    /// Convert Int16 PCM audio data to Float array normalized to [-1.0, 1.0].
    /// Assumes 16kHz mono 16-bit PCM input (standard RunAnywhere audio format).
    private func convertInt16PCMToFloat(_ data: Data) -> [Float] {
        let sampleCount = data.count / MemoryLayout<Int16>.size
        return data.withUnsafeBytes { rawBuffer in
            let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
            return (0..<sampleCount).map { Float(int16Buffer[$0]) / 32768.0 }
        }
    }
}
