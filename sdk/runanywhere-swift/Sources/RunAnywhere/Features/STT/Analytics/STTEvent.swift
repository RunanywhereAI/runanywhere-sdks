//
//  STTEvent.swift
//  RunAnywhere SDK
//
//  All STT-related events in one place.
//  Each event declares its destination (public, analytics, or both).
//

import Foundation

// MARK: - STT Event

/// All STT (Speech-to-Text) related events.
///
/// Usage:
/// ```swift
/// EventPublisher.shared.track(STTEvent.transcriptionCompleted(...))
/// ```
public enum STTEvent: SDKEvent {

    // MARK: - Model Lifecycle

    case modelLoadStarted(modelId: String, modelSizeBytes: Int64 = 0, framework: InferenceFrameworkType = .unknown)
    case modelLoadCompleted(modelId: String, durationMs: Double, modelSizeBytes: Int64 = 0, framework: InferenceFrameworkType = .unknown)
    case modelLoadFailed(modelId: String, error: String, framework: InferenceFrameworkType = .unknown)
    case modelUnloaded(modelId: String)

    // MARK: - Transcription

    /// Transcription started event
    /// - Parameters:
    ///   - audioLengthMs: Duration of audio in milliseconds
    ///   - audioSizeBytes: Size of audio data in bytes
    ///   - isStreaming: Whether this is a streaming transcription
    ///   - sampleRate: Audio sample rate in Hz (default 16000)
    case transcriptionStarted(
        transcriptionId: String,
        modelId: String,
        audioLengthMs: Double,
        audioSizeBytes: Int,
        language: String,
        isStreaming: Bool = false,
        sampleRate: Int = 16000,
        framework: InferenceFrameworkType = .unknown
    )
    case partialTranscript(text: String, wordCount: Int)
    case finalTranscript(text: String, confidence: Float)

    /// Transcription completed event
    /// - Parameters:
    ///   - realTimeFactor: Processing time / audio length (< 1.0 means faster than real-time)
    case transcriptionCompleted(
        transcriptionId: String,
        modelId: String,
        text: String,
        confidence: Float,
        durationMs: Double,
        audioLengthMs: Double,
        audioSizeBytes: Int,
        wordCount: Int,
        realTimeFactor: Double,
        language: String,
        isStreaming: Bool = false,
        sampleRate: Int = 16000,
        framework: InferenceFrameworkType = .unknown
    )
    case transcriptionFailed(transcriptionId: String, modelId: String, error: String)

    // MARK: - Detection (Analytics Only)

    case languageDetected(language: String, confidence: Float)

    // MARK: - SDKEvent Conformance

    public var type: String {
        switch self {
        case .modelLoadStarted: return "stt_model_load_started"
        case .modelLoadCompleted: return "stt_model_load_completed"
        case .modelLoadFailed: return "stt_model_load_failed"
        case .modelUnloaded: return "stt_model_unloaded"
        case .transcriptionStarted: return "stt_transcription_started"
        case .partialTranscript: return "stt_partial_transcript"
        case .finalTranscript: return "stt_final_transcript"
        case .transcriptionCompleted: return "stt_transcription_completed"
        case .transcriptionFailed: return "stt_transcription_failed"
        case .languageDetected: return "stt_language_detected"
        }
    }

    public var category: EventCategory { .stt }

    public var destination: EventDestination {
        switch self {
        // Analytics only - internal metrics / streaming chunks (too chatty for public API)
        case .languageDetected, .partialTranscript, .finalTranscript:
            return .analyticsOnly
        // Both - app developers need these
        default:
            return .all
        }
    }

    public var properties: [String: String] {
        switch self {
        case .modelLoadStarted(let modelId, let modelSizeBytes, let framework):
            var props = [
                "model_id": modelId,
                "framework": framework.rawValue
            ]
            if modelSizeBytes > 0 {
                props["model_size_bytes"] = String(modelSizeBytes)
            }
            return props

        case .modelLoadCompleted(let modelId, let durationMs, let modelSizeBytes, let framework):
            var props = [
                "model_id": modelId,
                "duration_ms": String(format: "%.1f", durationMs),
                "framework": framework.rawValue
            ]
            if modelSizeBytes > 0 {
                props["model_size_bytes"] = String(modelSizeBytes)
            }
            return props

        case .modelLoadFailed(let modelId, let error, let framework):
            return [
                "model_id": modelId,
                "error": error,
                "framework": framework.rawValue
            ]

        case .modelUnloaded(let modelId):
            return ["model_id": modelId]

        case .transcriptionStarted(let id, let modelId, let audioLengthMs, let audioSizeBytes, let language, let isStreaming, let sampleRate, let framework):
            return [
                "transcription_id": id,
                "model_id": modelId,
                "audio_length_ms": String(format: "%.1f", audioLengthMs),
                "audio_size_bytes": String(audioSizeBytes),
                "language": language,
                "is_streaming": String(isStreaming),
                "sample_rate": String(sampleRate),
                "framework": framework.rawValue
            ]

        case .partialTranscript(let text, let wordCount):
            return [
                "text_length": String(text.count),
                "word_count": String(wordCount)
            ]

        case .finalTranscript(let text, let confidence):
            return [
                "text_length": String(text.count),
                "confidence": String(format: "%.3f", confidence)
            ]

        case .transcriptionCompleted(
            let id,
            let modelId,
            let text,
            let confidence,
            let durationMs,
            let audioLengthMs,
            let audioSizeBytes,
            let wordCount,
            let realTimeFactor,
            let language,
            let isStreaming,
            let sampleRate,
            let framework
        ):
            return [
                "transcription_id": id,
                "model_id": modelId,
                "text_length": String(text.count),
                "confidence": String(format: "%.3f", confidence),
                "duration_ms": String(format: "%.1f", durationMs),
                "audio_length_ms": String(format: "%.1f", audioLengthMs),
                "audio_size_bytes": String(audioSizeBytes),
                "word_count": String(wordCount),
                "real_time_factor": String(format: "%.3f", realTimeFactor),
                "language": language,
                "is_streaming": String(isStreaming),
                "sample_rate": String(sampleRate),
                "success": "true",
                "framework": framework.rawValue
            ]

        case .transcriptionFailed(let id, let modelId, let error):
            return [
                "transcription_id": id,
                "model_id": modelId,
                "error": error,
                "success": "false"
            ]

        case .languageDetected(let language, let confidence):
            return [
                "language": language,
                "confidence": String(format: "%.3f", confidence)
            ]
        }
    }
}
