import Foundation
import RunAnywhereSDK
import AVFoundation
import WhisperKit
import os

/// WhisperKit implementation of VoiceService
public class WhisperKitService: VoiceService {
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "WhisperKitService")

    // MARK: - Properties

    private var currentModelPath: String?
    private var isInitialized: Bool = false
    private var whisperKit: WhisperKit?

    // MARK: - VoiceService Implementation

    public func initialize(modelPath: String?) async throws {
        logger.info("Starting initialization...")
        logger.debug("Model path requested: \(modelPath ?? "default", privacy: .public)")

        do {
            // Initialize WhisperKit with default settings
            // Using WhisperKit's default initialization
            logger.info("Creating WhisperKit instance...")
            whisperKit = try await WhisperKit()
            currentModelPath = modelPath ?? "openai/whisper-base"
            isInitialized = true
            logger.info("✅ Successfully initialized with model: \(self.currentModelPath ?? "default", privacy: .public)")
            logger.debug("isInitialized: \(self.isInitialized)")
        } catch {
            logger.error("❌ Failed to initialize WhisperKit: \(error, privacy: .public)")
            logger.error("Error details: \(error.localizedDescription, privacy: .public)")
            throw VoiceError.transcriptionFailed(error)
        }
    }

    public func transcribe(
        audio: Data,
        options: VoiceTranscriptionOptions
    ) async throws -> VoiceTranscriptionResult {
        logger.info("transcribe() called")
        logger.debug("Audio data size: \(audio.count) bytes")
        logger.debug("Options - Language: \(options.language.rawValue, privacy: .public), Task: \(String(describing: options.task), privacy: .public)")

        guard isInitialized, let whisperKit = whisperKit else {
            logger.error("❌ Service not initialized!")
            logger.error("isInitialized: \(self.isInitialized), whisperKit: \(self.whisperKit != nil)")
            throw VoiceError.serviceNotInitialized
        }

        do {
            // Convert Data to audio samples for WhisperKit
            logger.info("Converting audio data to float array...")
            let audioSamples = convertDataToFloatArray(audio)
            logger.debug("Converted to \(audioSamples.count) samples")
            logger.debug("Duration: \(Double(audioSamples.count) / 16000.0) seconds")

            // Perform transcription using WhisperKit
            logger.info("Starting WhisperKit transcription...")
            let transcriptionResults = try await whisperKit.transcribe(
                audioArray: audioSamples
            )
            logger.info("Transcription completed")
            logger.debug("Results count: \(transcriptionResults.count)")

            // Extract the transcribed text
            let transcribedText = transcriptionResults.first?.text ?? ""
            logger.info("Transcribed text: '\(transcribedText, privacy: .public)'")

            // Return the result
            let result = VoiceTranscriptionResult(
                text: transcribedText,
                language: transcriptionResults.first?.language ?? options.language.rawValue,
                confidence: 0.95, // WhisperKit doesn't provide confidence scores directly
                duration: Double(audioSamples.count) / 16000.0 // Based on 16kHz sample rate
            )
            logger.info("✅ Returning result with text: '\(result.text, privacy: .public)'")
            return result
        } catch {
            logger.error("❌ Transcription failed: \(error, privacy: .public)")
            logger.error("Error details: \(error.localizedDescription, privacy: .public)")
            throw VoiceError.transcriptionFailed(error)
        }
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

    private func convertDataToFloatArray(_ data: Data) -> [Float] {
        logger.debug("Converting \(data.count) bytes to float array...")
        let floatCount = data.count / MemoryLayout<Float>.size
        var floatArray = [Float](repeating: 0, count: floatCount)
        _ = data.withUnsafeBytes { bytes in
            floatArray.withUnsafeMutableBufferPointer { buffer in
                bytes.copyBytes(to: buffer)
            }
        }
        logger.debug("Converted to \(floatArray.count) float values")
        return floatArray
    }
}

// MARK: - Voice Error

public enum VoiceError: LocalizedError {
    case serviceNotInitialized
    case modelNotFound(String)
    case transcriptionFailed(Error)
    case insufficientMemory
    case unsupportedAudioFormat

    public var errorDescription: String? {
        switch self {
        case .serviceNotInitialized:
            return "Voice service is not initialized"
        case .modelNotFound(let model):
            return "Model not found: \(model)"
        case .transcriptionFailed(let error):
            return "Transcription failed: \(error.localizedDescription)"
        case .insufficientMemory:
            return "Insufficient memory for voice processing"
        case .unsupportedAudioFormat:
            return "Unsupported audio format"
        }
    }
}
