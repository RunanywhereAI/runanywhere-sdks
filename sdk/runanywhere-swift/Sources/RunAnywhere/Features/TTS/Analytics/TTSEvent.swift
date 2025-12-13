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

    case modelLoadStarted(voiceId: String, framework: InferenceFrameworkType = .unknown)
    case modelLoadCompleted(voiceId: String, durationMs: Double, framework: InferenceFrameworkType = .unknown)
    case modelLoadFailed(voiceId: String, error: String, framework: InferenceFrameworkType = .unknown)
    case modelUnloaded(voiceId: String)

    // MARK: - Synthesis

    case synthesisStarted(synthesisId: String, voiceId: String, text: String, framework: InferenceFrameworkType = .unknown)
    case synthesisChunk(synthesisId: String, chunkSize: Int)
    case synthesisCompleted(
        synthesisId: String,
        voiceId: String,
        characterCount: Int,
        audioSizeBytes: Int,
        durationMs: Double,
        framework: InferenceFrameworkType = .unknown
    )
    case synthesisFailed(synthesisId: String, error: String)

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
        case .modelLoadStarted(let voiceId, let framework):
            return [
                "voice_id": voiceId,
                "framework": framework.rawValue
            ]

        case .modelLoadCompleted(let voiceId, let durationMs, let framework):
            return [
                "voice_id": voiceId,
                "duration_ms": String(format: "%.1f", durationMs),
                "framework": framework.rawValue
            ]

        case .modelLoadFailed(let voiceId, let error, let framework):
            return [
                "voice_id": voiceId,
                "error": error,
                "framework": framework.rawValue
            ]

        case .modelUnloaded(let voiceId):
            return ["voice_id": voiceId]

        case .synthesisStarted(let id, let voiceId, let text, let framework):
            return [
                "synthesis_id": id,
                "voice_id": voiceId,
                "character_count": String(text.count),
                "framework": framework.rawValue
            ]

        case .synthesisChunk(let id, let chunkSize):
            return [
                "synthesis_id": id,
                "chunk_size": String(chunkSize)
            ]

        case .synthesisCompleted(let id, let voiceId, let charCount, let audioSize, let durationMs, let framework):
            let charsPerSecond = durationMs > 0 ? Double(charCount) / (durationMs / 1000.0) : 0
            return [
                "synthesis_id": id,
                "voice_id": voiceId,
                "character_count": String(charCount),
                "audio_size_bytes": String(audioSize),
                "duration_ms": String(format: "%.1f", durationMs),
                "chars_per_second": String(format: "%.2f", charsPerSecond),
                "framework": framework.rawValue
            ]

        case .synthesisFailed(let id, let error):
            return ["synthesis_id": id, "error": error]
        }
    }
}
