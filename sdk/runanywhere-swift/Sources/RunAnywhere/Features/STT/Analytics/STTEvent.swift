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

    case modelLoadStarted(modelId: String, framework: InferenceFrameworkType = .unknown)
    case modelLoadCompleted(modelId: String, durationMs: Double, framework: InferenceFrameworkType = .unknown)
    case modelLoadFailed(modelId: String, error: String, framework: InferenceFrameworkType = .unknown)
    case modelUnloaded(modelId: String)

    // MARK: - Transcription

    case transcriptionStarted(transcriptionId: String, audioLengthMs: Double, language: String, framework: InferenceFrameworkType = .unknown)
    case partialTranscript(text: String, wordCount: Int)
    case finalTranscript(text: String, confidence: Float)
    case transcriptionCompleted(
        transcriptionId: String,
        text: String,
        confidence: Float,
        durationMs: Double,
        audioLengthMs: Double,
        wordCount: Int,
        framework: InferenceFrameworkType = .unknown
    )
    case transcriptionFailed(transcriptionId: String, error: String)

    // MARK: - Detection (Analytics Only)

    case languageDetected(language: String, confidence: Float)
    case speakerDetected(speakerId: String)
    case speakerChanged(fromSpeaker: String?, toSpeaker: String)

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
        case .speakerDetected: return "stt_speaker_detected"
        case .speakerChanged: return "stt_speaker_changed"
        }
    }

    public var category: EventCategory { .stt }

    public var destination: EventDestination {
        switch self {
        // Analytics only - internal metrics
        case .languageDetected, .speakerDetected, .speakerChanged:
            return .analyticsOnly
        // Both - app developers need these
        default:
            return .all
        }
    }

    public var properties: [String: String] {
        switch self {
        case .modelLoadStarted(let modelId, let framework):
            return [
                "model_id": modelId,
                "framework": framework.rawValue
            ]

        case .modelLoadCompleted(let modelId, let durationMs, let framework):
            return [
                "model_id": modelId,
                "duration_ms": String(format: "%.1f", durationMs),
                "framework": framework.rawValue
            ]

        case .modelLoadFailed(let modelId, let error, let framework):
            return [
                "model_id": modelId,
                "error": error,
                "framework": framework.rawValue
            ]

        case .modelUnloaded(let modelId):
            return ["model_id": modelId]

        case .transcriptionStarted(let id, let audioLengthMs, let language, let framework):
            return [
                "transcription_id": id,
                "audio_length_ms": String(format: "%.1f", audioLengthMs),
                "language": language,
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

        case .transcriptionCompleted(let id, let text, let confidence, let durationMs, let audioLengthMs, let wordCount, let framework):
            let rtf = audioLengthMs > 0 ? durationMs / audioLengthMs : 0
            return [
                "transcription_id": id,
                "text_length": String(text.count),
                "confidence": String(format: "%.3f", confidence),
                "duration_ms": String(format: "%.1f", durationMs),
                "audio_length_ms": String(format: "%.1f", audioLengthMs),
                "word_count": String(wordCount),
                "real_time_factor": String(format: "%.3f", rtf),
                "framework": framework.rawValue
            ]

        case .transcriptionFailed(let id, let error):
            return ["transcription_id": id, "error": error]

        case .languageDetected(let language, let confidence):
            return [
                "language": language,
                "confidence": String(format: "%.3f", confidence)
            ]

        case .speakerDetected(let speakerId):
            return ["speaker_id": speakerId]

        case .speakerChanged(let fromSpeaker, let toSpeaker):
            var props = ["to_speaker": toSpeaker]
            if let from = fromSpeaker {
                props["from_speaker"] = from
            }
            return props
        }
    }
}
