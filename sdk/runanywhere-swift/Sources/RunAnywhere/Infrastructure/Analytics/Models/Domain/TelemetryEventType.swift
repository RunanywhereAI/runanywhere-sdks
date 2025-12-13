//
//  TelemetryEventType.swift
//  RunAnywhere SDK
//
//  Telemetry event types
//

import Foundation

/// Standard telemetry event types
public enum TelemetryEventType: String, Codable {
    // MARK: - Model Events
    case modelLoaded = "model_loaded"
    case modelLoadFailed = "model_load_failed"
    case modelUnloaded = "model_unloaded"

    // MARK: - LLM Generation Events
    case generationStarted = "generation_started"
    case generationCompleted = "generation_completed"
    case generationFailed = "generation_failed"

    // MARK: - STT (Speech-to-Text) Events
    case sttModelLoaded = "stt_model_loaded"
    case sttModelLoadFailed = "stt_model_load_failed"
    case sttTranscriptionStarted = "stt_transcription_started"
    case sttTranscriptionCompleted = "stt_transcription_completed"
    case sttTranscriptionFailed = "stt_transcription_failed"
    case sttStreamingUpdate = "stt_streaming_update"

    // MARK: - TTS (Text-to-Speech) Events
    case ttsModelLoaded = "tts_model_loaded"
    case ttsModelLoadFailed = "tts_model_load_failed"
    case ttsSynthesisStarted = "tts_synthesis_started"
    case ttsSynthesisCompleted = "tts_synthesis_completed"
    case ttsSynthesisFailed = "tts_synthesis_failed"

    // MARK: - Speaker Diarization Events
    case speakerDiarizationStarted = "speaker_diarization_started"
    case speakerDiarizationCompleted = "speaker_diarization_completed"
    case speakerDiarizationFailed = "speaker_diarization_failed"

    // MARK: - System Events
    case error = "error"
    case performance = "performance"
    case memory = "memory"
    case custom = "custom"
}
