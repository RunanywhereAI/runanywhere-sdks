//
//  TTSEvent.swift
//  RunAnywhere SDK
//
//  All TTS-related events in one place.
//  Each event declares its destination (public, analytics, or both).
//
//  Note: TTSEvent conforms to TelemetryEventProperties for strongly typed analytics.
//  This avoids string conversion/parsing and enables compile-time type checking.
//

import CRACommons
import Foundation

// MARK: - TTS Event

/// All TTS (Text-to-Speech) related events.
///
/// Usage:
/// ```swift
/// EventPublisher.shared.track(TTSEvent.synthesisCompleted(...))
/// ```
///
/// TTSEvent provides strongly typed properties via `telemetryProperties`.
/// This enables:
/// - Type safety at compile time
/// - No string parsing for analytics
/// - Validation guardrails
public enum TTSEvent: SDKEvent, TelemetryEventProperties {

    // MARK: - Model Lifecycle

    case modelLoadStarted(modelId: String, modelSizeBytes: Int64 = 0, framework: InferenceFramework = .unknown)
    case modelLoadCompleted(modelId: String, durationMs: Double, modelSizeBytes: Int64 = 0, framework: InferenceFramework = .unknown)
    case modelLoadFailed(modelId: String, error: SDKError, framework: InferenceFramework = .unknown)
    case modelUnloaded(modelId: String)

    // MARK: - Synthesis

    /// Synthesis started event
    /// - Parameters:
    ///   - characterCount: Number of characters in the text to synthesize
    ///   - sampleRate: Audio sample rate in Hz (default: RAC_TTS_DEFAULT_SAMPLE_RATE)
    case synthesisStarted(
        synthesisId: String,
        modelId: String,
        characterCount: Int,
        sampleRate: Int = Int(RAC_TTS_DEFAULT_SAMPLE_RATE),
        framework: InferenceFramework = .unknown
    )

    /// Streaming synthesis chunk generated
    case synthesisChunk(synthesisId: String, chunkSize: Int)

    /// Synthesis completed event
    /// - Parameters:
    ///   - audioDurationMs: Duration of generated audio in milliseconds
    ///   - audioSizeBytes: Size of generated audio in bytes
    ///   - processingDurationMs: Time taken to synthesize (processing time)
    ///   - charactersPerSecond: Synthesis speed (characters processed per second)
    ///   - sampleRate: Audio sample rate in Hz
    case synthesisCompleted(
        synthesisId: String,
        modelId: String,
        characterCount: Int,
        audioDurationMs: Double,
        audioSizeBytes: Int,
        processingDurationMs: Double,
        charactersPerSecond: Double,
        sampleRate: Int = Int(RAC_TTS_DEFAULT_SAMPLE_RATE),
        framework: InferenceFramework = .unknown
    )
    case synthesisFailed(synthesisId: String, modelId: String, error: SDKError)

    // MARK: - SDKEvent Conformance

    public var type: String {
        switch self {
        case .modelLoadStarted: return "tts_model_load_started"
        case .modelLoadCompleted: return "tts_model_load_completed"
        case .modelLoadFailed: return "tts_model_load_failed"
        case .modelUnloaded: return "tts_model_unloaded"
        case .synthesisStarted: return "tts_synthesis_started"
        case .synthesisChunk: return "tts_synthesis_chunk"
        case .synthesisCompleted: return "tts_synthesis_completed"
        case .synthesisFailed: return "tts_synthesis_failed"
        }
    }

    public var category: EventCategory { .tts }

    public var destination: EventDestination {
        switch self {
        case .synthesisChunk:
            // Chunk events are too chatty for public API
            return .analyticsOnly
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
                voice: modelId,
                modelSizeBytes: modelSizeBytes > 0 ? modelSizeBytes : nil
            )

        case .modelLoadCompleted(let modelId, let durationMs, let modelSizeBytes, let framework):
            return TelemetryProperties(
                modelId: modelId,
                framework: framework.rawValue,
                processingTimeMs: durationMs,
                success: true,
                voice: modelId,
                modelSizeBytes: modelSizeBytes > 0 ? modelSizeBytes : nil
            )

        case .modelLoadFailed(let modelId, let error, let framework):
            return TelemetryProperties(
                modelId: modelId,
                framework: framework.rawValue,
                success: false,
                errorMessage: error.message,
                errorCode: error.code.rawValue,
                voice: modelId
            )

        case .modelUnloaded(let modelId):
            return TelemetryProperties(
                modelId: modelId,
                voice: modelId
            )

        case .synthesisStarted(let id, let modelId, let characterCount, let sampleRate, let framework):
            return TelemetryProperties(
                modelId: modelId,
                framework: framework.rawValue,
                characterCount: characterCount,
                sampleRate: sampleRate,
                voice: modelId,
                synthesisId: id
            )

        case .synthesisChunk(let id, let chunkSize):
            return TelemetryProperties(
                audioSizeBytes: chunkSize,
                synthesisId: id
            )

        case .synthesisCompleted(
            let id,
            let modelId,
            let charCount,
            let audioDurationMs,
            let audioSize,
            let processingDurationMs,
            let charsPerSecond,
            let sampleRate,
            let framework
        ):
            return TelemetryProperties(
                modelId: modelId,
                framework: framework.rawValue,
                processingTimeMs: processingDurationMs,
                success: true,
                characterCount: charCount,
                charactersPerSecond: charsPerSecond,
                audioSizeBytes: audioSize,
                sampleRate: sampleRate,
                voice: modelId,
                outputDurationMs: audioDurationMs,
                synthesisId: id
            )

        case .synthesisFailed(let id, let modelId, let error):
            return TelemetryProperties(
                modelId: modelId,
                success: false,
                errorMessage: error.message,
                errorCode: error.code.rawValue,
                voice: modelId,
                synthesisId: id
            )
        }
    }
}
