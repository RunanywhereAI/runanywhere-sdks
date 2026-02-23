//
//  WhisperKitSTTService.swift
//  WhisperKitRuntime Module
//
//  Actor wrapping WhisperKit for model loading and transcription.
//  Called from C++ via callbacks registered in WhisperKitSTT.swift.
//

import Accelerate
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
public actor WhisperKitSTTService {
    public static let shared = WhisperKitSTTService()

    private let logger = SDKLogger(category: "WhisperKitSTTService")

    /// Peak amplitude target for normalization. Audio with peaks below
    /// `normalizationThreshold` is scaled so its peak reaches this level.
    /// 0.9 leaves headroom to avoid clipping.
    private let normalizationTarget: Float = 0.9

    /// Audio quieter than this peak amplitude is considered too quiet and
    /// will be normalized. The `.measurement` audio session mode disables
    /// AGC, so normal-volume speech often arrives at ~0.03-0.05 peak.
    private let normalizationThreshold: Float = 0.1

    private var whisperKit: WhisperKit?
    public private(set) var currentModelId: String?

    public var isModelLoaded: Bool {
        whisperKit != nil
    }

    // MARK: - Model Loading

    public func loadModel(modelId: String, modelFolder: String) async throws {
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

        var floatSamples = convertInt16PCMToFloat(audioData)

        // Normalize quiet audio so Whisper's mel spectrogram has enough energy.
        // The AudioCaptureManager uses .measurement mode which disables AGC,
        // causing normal-volume speech to arrive at ~0.03-0.05 peak amplitude.
        let peakAmplitude = peakAbs(floatSamples)
        if peakAmplitude > 0 && peakAmplitude < normalizationThreshold {
            let gain = normalizationTarget / peakAmplitude
            applyGain(&floatSamples, gain: gain)
            let before = String(format: "%.4f", peakAmplitude)
            let after = String(format: "%.4f", peakAmplitude * gain)
            let factor = String(format: "%.1f", gain)
            logger.info("Normalized audio: peak \(before) → \(after) (gain \(factor)x)")
        }

        let audioDurationSec = Double(floatSamples.count) / 16000.0
        logger.info("Transcribing \(String(format: "%.2f", audioDurationSec))s audio, peak=\(String(format: "%.4f", peakAmplitude))")

        var decodeOptions = DecodingOptions()
        decodeOptions.language = options.language

        let results = try await kit.transcribe(
            audioArray: floatSamples,
            decodeOptions: decodeOptions
        )

        let processingTimeSec = Date().timeIntervalSince(startTime)

        let transcribedText = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        let detectedLanguage = results.first?.language

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

        let confidence: Float = {
            let segments = results.flatMap(\.segments)
            guard !segments.isEmpty else { return 0.0 }
            let avgNoSpeechProb = segments.map(\.noSpeechProb).reduce(0, +) / Float(segments.count)
            return 1.0 - avgNoSpeechProb
        }()

        let metadata = TranscriptionMetadata(
            modelId: modelId,
            processingTime: processingTimeSec,
            audioLength: audioDurationSec
        )

        logger.info("Transcription complete (\(String(format: "%.2f", processingTimeSec))s): '\(transcribedText.prefix(80))'")

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

    private func convertInt16PCMToFloat(_ data: Data) -> [Float] {
        let sampleCount = data.count / MemoryLayout<Int16>.size
        return data.withUnsafeBytes { rawBuffer in
            let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
            return (0..<sampleCount).map { Float(int16Buffer[$0]) / 32768.0 }
        }
    }

    /// Peak absolute amplitude using Accelerate (O(n) vectorized).
    private func peakAbs(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var result: Float = 0
        vDSP_maxmgv(samples, 1, &result, vDSP_Length(samples.count))
        return result
    }

    /// In-place gain using Accelerate (O(n) vectorized).
    private func applyGain(_ samples: inout [Float], gain: Float) {
        var gainValue = gain
        vDSP_vsmul(samples, 1, &gainValue, &samples, 1, vDSP_Length(samples.count))
    }
}
