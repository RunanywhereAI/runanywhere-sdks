//
//  TTSEvent.swift
//  RunAnywhere SDK
//
//  All TTS-related events in one place.
//  Each event declares its destination (public, analytics, or both).
//
//  Note: TTSEvent conforms to TypedEventProperties for strongly typed analytics.
//  This avoids string conversion/parsing and enables compile-time type checking.
//

import Foundation

// MARK: - TTS Event

/// All TTS (Text-to-Speech) related events.
///
/// Usage:
/// ```swift
/// EventPublisher.shared.track(TTSEvent.synthesisCompleted(...))
/// ```
///
/// TTSEvent provides strongly typed properties via `typedProperties`.
/// This enables:
/// - Type safety at compile time
/// - No string parsing for analytics
/// - Validation guardrails
public enum TTSEvent: SDKEvent, TypedEventProperties {

    // MARK: - Model Lifecycle

    case modelLoadStarted(modelId: String, modelSizeBytes: Int64 = 0, framework: InferenceFramework = .unknown)
    case modelLoadCompleted(modelId: String, durationMs: Double, modelSizeBytes: Int64 = 0, framework: InferenceFramework = .unknown)
    case modelLoadFailed(modelId: String, error: SDKError, framework: InferenceFramework = .unknown)
    case modelUnloaded(modelId: String)

    // MARK: - Synthesis

    /// Synthesis started event
    /// - Parameters:
    ///   - characterCount: Number of characters in the text to synthesize
    ///   - sampleRate: Audio sample rate in Hz (default: TTSConstants.defaultSampleRate)
    case synthesisStarted(
        synthesisId: String,
        modelId: String,
        characterCount: Int,
        sampleRate: Int = TTSConstants.defaultSampleRate,
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
        sampleRate: Int = TTSConstants.defaultSampleRate,
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
                "framework": framework.rawValue
            ].merging(error.telemetryProperties) { _, new in new }

        case .modelUnloaded(let modelId):
            return ["model_id": modelId]

        case .synthesisStarted(let id, let modelId, let characterCount, let sampleRate, let framework):
            return [
                "synthesis_id": id,
                "model_id": modelId,
                "character_count": String(characterCount),
                "sample_rate": String(sampleRate),
                "framework": framework.rawValue
            ]

        case .synthesisChunk(let id, let chunkSize):
            return [
                "synthesis_id": id,
                "chunk_size": String(chunkSize)
            ]

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
            return [
                "synthesis_id": id,
                "model_id": modelId,
                "character_count": String(charCount),
                "audio_duration_ms": String(format: "%.1f", audioDurationMs),
                "audio_size_bytes": String(audioSize),
                "processing_duration_ms": String(format: "%.1f", processingDurationMs),
                "chars_per_second": String(format: "%.2f", charsPerSecond),
                "sample_rate": String(sampleRate),
                "success": "true",
                "framework": framework.rawValue
            ]

        case .synthesisFailed(let id, let modelId, let error):
            return [
                "synthesis_id": id,
                "model_id": modelId,
                "success": "false"
            ].merging(error.telemetryProperties) { _, new in new }
        }
    }

    // MARK: - TypedEventProperties Conformance

    /// Strongly typed event properties - no string conversion needed.
    /// These values are used directly by TelemetryEventPayload.
    public var typedProperties: EventProperties {
        switch self {
        case .modelLoadStarted(let modelId, let modelSizeBytes, let framework):
            return EventProperties(
                modelId: modelId,
                framework: framework.rawValue,
                voice: modelId,
                modelSizeBytes: modelSizeBytes > 0 ? modelSizeBytes : nil
            )

        case .modelLoadCompleted(let modelId, let durationMs, let modelSizeBytes, let framework):
            return EventProperties(
                modelId: modelId,
                framework: framework.rawValue,
                processingTimeMs: durationMs,
                success: true,
                voice: modelId,
                modelSizeBytes: modelSizeBytes > 0 ? modelSizeBytes : nil
            )

        case .modelLoadFailed(let modelId, let error, let framework):
            return EventProperties(
                modelId: modelId,
                framework: framework.rawValue,
                success: false,
                errorMessage: error.message,
                errorCode: error.code.rawValue,
                voice: modelId
            )

        case .modelUnloaded(let modelId):
            return EventProperties(
                modelId: modelId,
                voice: modelId
            )

        case .synthesisStarted(let id, let modelId, let characterCount, let sampleRate, let framework):
            return EventProperties(
                modelId: modelId,
                framework: framework.rawValue,
                characterCount: characterCount,
                sampleRate: sampleRate,
                voice: modelId,
                synthesisId: id
            )

        case .synthesisChunk(let id, let chunkSize):
            return EventProperties(
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
            return EventProperties(
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
            return EventProperties(
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
