//
//  TTSEvent.swift
//  RunAnywhere SDK
//
//  All TTS-related events in one place.
//  Each event declares its destination (public, analytics, or both).
//

import Foundation

// MARK: - TTS Event

/// All TTS (Text-to-Speech) related events.
///
/// Usage:
/// ```swift
/// EventPublisher.shared.track(TTSEvent.synthesisCompleted(...))
/// ```
public enum TTSEvent: SDKEvent {

    // MARK: - Model Lifecycle

    case modelLoadStarted(voiceId: String, modelSizeBytes: Int64 = 0, framework: InferenceFrameworkType = .unknown)
    case modelLoadCompleted(voiceId: String, durationMs: Double, modelSizeBytes: Int64 = 0, framework: InferenceFrameworkType = .unknown)
    case modelLoadFailed(voiceId: String, error: String, framework: InferenceFrameworkType = .unknown)
    case modelUnloaded(voiceId: String)

    // MARK: - Synthesis

    /// Synthesis started event
    /// - Parameters:
    ///   - characterCount: Number of characters in the text to synthesize
    ///   - sampleRate: Audio sample rate in Hz (default 22050 for most TTS)
    case synthesisStarted(
        synthesisId: String,
        voiceId: String,
        characterCount: Int,
        sampleRate: Int = 22050,
        framework: InferenceFrameworkType = .unknown
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
        voiceId: String,
        characterCount: Int,
        audioDurationMs: Double,
        audioSizeBytes: Int,
        processingDurationMs: Double,
        charactersPerSecond: Double,
        sampleRate: Int = 22050,
        framework: InferenceFrameworkType = .unknown
    )
    case synthesisFailed(synthesisId: String, voiceId: String, error: String)

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
        case .modelLoadStarted(let voiceId, let modelSizeBytes, let framework):
            var props = [
                "voice_id": voiceId,
                "framework": framework.rawValue
            ]
            if modelSizeBytes > 0 {
                props["model_size_bytes"] = String(modelSizeBytes)
            }
            return props

        case .modelLoadCompleted(let voiceId, let durationMs, let modelSizeBytes, let framework):
            var props = [
                "voice_id": voiceId,
                "duration_ms": String(format: "%.1f", durationMs),
                "framework": framework.rawValue
            ]
            if modelSizeBytes > 0 {
                props["model_size_bytes"] = String(modelSizeBytes)
            }
            return props

        case .modelLoadFailed(let voiceId, let error, let framework):
            return [
                "voice_id": voiceId,
                "error": error,
                "framework": framework.rawValue
            ]

        case .modelUnloaded(let voiceId):
            return ["voice_id": voiceId]

        case .synthesisStarted(let id, let voiceId, let characterCount, let sampleRate, let framework):
            return [
                "synthesis_id": id,
                "voice_id": voiceId,
                "model_id": voiceId,  // Alias for consistency with backend
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
            let voiceId,
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
                "voice_id": voiceId,
                "model_id": voiceId,  // Alias for consistency with backend
                "character_count": String(charCount),
                "audio_duration_ms": String(format: "%.1f", audioDurationMs),
                "audio_size_bytes": String(audioSize),
                "processing_duration_ms": String(format: "%.1f", processingDurationMs),
                "chars_per_second": String(format: "%.2f", charsPerSecond),
                "sample_rate": String(sampleRate),
                "success": "true",
                "framework": framework.rawValue
            ]

        case .synthesisFailed(let id, let voiceId, let error):
            return [
                "synthesis_id": id,
                "voice_id": voiceId,
                "model_id": voiceId,  // Alias for consistency with backend
                "error": error,
                "success": "false"
            ]
        }
    }
}
