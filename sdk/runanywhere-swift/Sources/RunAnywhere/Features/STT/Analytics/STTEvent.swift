//
//  STTEvent.swift
//  RunAnywhere SDK
//
//  All STT-related events in one place.
//  Each event declares its destination (public, analytics, or both).
//
//  Note: STTEvent conforms to TelemetryEventProperties for strongly typed analytics.
//  This avoids string conversion/parsing and enables compile-time type checking.
//

import CRACommons
import Foundation

// MARK: - STT Event

/// All STT (Speech-to-Text) related events.
///
/// Usage:
/// ```swift
/// EventPublisher.shared.track(STTEvent.transcriptionCompleted(...))
/// ```
///
/// STTEvent provides strongly typed properties via `telemetryProperties`.
/// This enables:
/// - Type safety at compile time
/// - No string parsing for analytics
/// - Validation guardrails (e.g., confidence between 0-1)
public enum STTEvent: SDKEvent, TelemetryEventProperties {

    // MARK: - Model Lifecycle

    case modelLoadStarted(modelId: String, modelSizeBytes: Int64 = 0, framework: InferenceFramework = .unknown)
    case modelLoadCompleted(modelId: String, durationMs: Double, modelSizeBytes: Int64 = 0, framework: InferenceFramework = .unknown)
    case modelLoadFailed(modelId: String, error: SDKError, framework: InferenceFramework = .unknown)
    case modelUnloaded(modelId: String)

    // MARK: - Transcription

    /// Transcription started event
    /// - Parameters:
    ///   - audioLengthMs: Duration of audio in milliseconds
    ///   - audioSizeBytes: Size of audio data in bytes
    ///   - isStreaming: Whether this is a streaming transcription
    ///   - sampleRate: Audio sample rate in Hz (default: RAC_STT_DEFAULT_SAMPLE_RATE)
    case transcriptionStarted(
        transcriptionId: String,
        modelId: String,
        audioLengthMs: Double,
        audioSizeBytes: Int,
        language: String,
        isStreaming: Bool = false,
        sampleRate: Int = Int(RAC_STT_DEFAULT_SAMPLE_RATE),
        framework: InferenceFramework = .unknown
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
        sampleRate: Int = Int(RAC_STT_DEFAULT_SAMPLE_RATE),
        framework: InferenceFramework = .unknown
    )
    case transcriptionFailed(transcriptionId: String, modelId: String, error: SDKError)

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
        // Use derived properties from telemetryProperties for consistency
        // This eliminates duplicate property conversion logic
        telemetryProperties.toDictionary()
    }

    // MARK: - TelemetryEventProperties Conformance

    /// Strongly typed telemetry properties - no string conversion needed.
    /// These values are used directly by TelemetryEventPayload.
    public var telemetryProperties: TelemetryProperties {
        switch self {
        case .modelLoadStarted(let modelId, let modelSizeBytes, let framework):
            return TelemetryProperties(
                modelId: modelId,
                framework: framework.rawValue,
                modelSizeBytes: modelSizeBytes > 0 ? modelSizeBytes : nil
            )

        case .modelLoadCompleted(let modelId, let durationMs, let modelSizeBytes, let framework):
            return TelemetryProperties(
                modelId: modelId,
                framework: framework.rawValue,
                processingTimeMs: durationMs,
                success: true,
                modelSizeBytes: modelSizeBytes > 0 ? modelSizeBytes : nil
            )

        case .modelLoadFailed(let modelId, let error, let framework):
            return TelemetryProperties(
                modelId: modelId,
                framework: framework.rawValue,
                success: false,
                errorMessage: error.message,
                errorCode: error.code.rawValue
            )

        case .modelUnloaded(let modelId):
            return TelemetryProperties(modelId: modelId)

        case .transcriptionStarted(
            let id,
            let modelId,
            let audioLengthMs,
            let audioSizeBytes,
            let language,
            let isStreaming,
            let sampleRate,
            let framework
        ):
            return TelemetryProperties(
                modelId: modelId,
                framework: framework.rawValue,
                isStreaming: isStreaming,
                audioDurationMs: audioLengthMs,
                language: language,
                transcriptionId: id,
                audioSizeBytes: audioSizeBytes,
                sampleRate: sampleRate
            )

        case .partialTranscript(let text, let wordCount):
            return TelemetryProperties(
                wordCount: wordCount,
                characterCount: text.count
            )

        case .finalTranscript(let text, let confidence):
            return TelemetryProperties(
                confidence: Double(confidence),
                characterCount: text.count
            )

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
            return TelemetryProperties(
                modelId: modelId,
                framework: framework.rawValue,
                processingTimeMs: durationMs,
                success: true,
                isStreaming: isStreaming,
                audioDurationMs: audioLengthMs,
                realTimeFactor: realTimeFactor,
                wordCount: wordCount,
                confidence: Double(confidence),
                language: language,
                transcriptionId: id,
                characterCount: text.count,
                audioSizeBytes: audioSizeBytes,
                sampleRate: sampleRate
            )

        case .transcriptionFailed(let id, let modelId, let error):
            return TelemetryProperties(
                modelId: modelId,
                success: false,
                errorMessage: error.message,
                errorCode: error.code.rawValue,
                transcriptionId: id
            )

        case .languageDetected(let language, let confidence):
            return TelemetryProperties(
                confidence: Double(confidence),
                language: language
            )
        }
    }
}
