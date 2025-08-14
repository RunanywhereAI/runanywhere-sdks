import Foundation
import RunAnywhereSDK
import AVFoundation
#if canImport(WhisperKit)
import WhisperKit
#endif

/// WhisperKit implementation of VoiceService
public class WhisperKitService: VoiceService {

    // MARK: - Properties

    private var currentModelPath: String?
    private var isInitialized: Bool = false

    #if canImport(WhisperKit)
    private var whisperKit: WhisperKit?
    #endif

    // MARK: - VoiceService Implementation

    public func initialize(modelPath: String?) async throws {
        #if canImport(WhisperKit)
        do {
            whisperKit = try await WhisperKit(
                computeOptions: WhisperKit.getComputeOptions(),
                audioProcessor: AudioProcessor(),
                logLevel: .info
            )
            currentModelPath = modelPath ?? "openai/whisper-base"
            isInitialized = true
            print("WhisperKitService initialized with actual WhisperKit model: \(currentModelPath ?? "default")")
        } catch {
            print("Failed to initialize WhisperKit: \(error)")
            throw VoiceError.transcriptionFailed(error)
        }
        #else
        // Fallback to simulated initialization when WhisperKit is not available
        currentModelPath = modelPath ?? "whisper-base"
        isInitialized = true
        print("WhisperKitService initialized with simulated model: \(currentModelPath ?? "default")")
        #endif
    }

    public func transcribe(
        audio: Data,
        options: TranscriptionOptions
    ) async throws -> TranscriptionResult {
        guard isInitialized else {
            throw VoiceError.serviceNotInitialized
        }

        #if canImport(WhisperKit)
        guard let whisperKit = whisperKit else {
            throw VoiceError.serviceNotInitialized
        }

        do {
            // Convert Data to audio samples for WhisperKit
            let audioSamples = convertDataToFloatArray(audio)

            // Perform transcription using WhisperKit
            let transcriptionResult = try await whisperKit.transcribe(
                audioArray: audioSamples
            )

            // Extract the transcribed text
            let transcribedText = transcriptionResult.first?.text ?? ""

            // Return the result
            return TranscriptionResult(
                text: transcribedText,
                language: transcriptionResult.first?.language ?? options.language.rawValue,
                confidence: 0.95, // WhisperKit doesn't provide confidence scores directly
                duration: Double(audioSamples.count) / 16000.0 // Based on 16kHz sample rate
            )
        } catch {
            throw VoiceError.transcriptionFailed(error)
        }
        #else
        // Fallback to simulated transcription when WhisperKit is not available
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        return TranscriptionResult(
            text: "This is a simulated transcription. WhisperKit not available.",
            language: options.language.rawValue,
            confidence: 0.95,
            duration: Double(audio.count) / 32000.0 // Estimate based on 16kHz mono audio
        )
        #endif
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
        #if canImport(WhisperKit)
        whisperKit = nil
        #endif
    }

    // MARK: - Initialization

    public init() {
        // No initialization needed for basic service
    }

    // MARK: - Helper Methods

    private func convertDataToFloatArray(_ data: Data) -> [Float] {
        let floatCount = data.count / MemoryLayout<Float>.size
        var floatArray = [Float](repeating: 0, count: floatCount)
        _ = data.withUnsafeBytes { bytes in
            floatArray.withUnsafeMutableBufferPointer { buffer in
                bytes.copyBytes(to: buffer)
            }
        }
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
