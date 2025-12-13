//
//  STTEventType.swift
//  RunAnywhere SDK
//
//  STT event types for analytics
//

import Foundation

// MARK: - STT Event Type

/// STT event types
public enum STTEventType: String {
    case transcriptionStarted = "stt_transcription_started"
    case transcriptionCompleted = "stt_transcription_completed"
    case partialTranscript = "stt_partial_transcript"
    case finalTranscript = "stt_final_transcript"
    case speakerDetected = "stt_speaker_detected"
    case speakerChanged = "stt_speaker_changed"
    case languageDetected = "stt_language_detected"
    case modelLoaded = "stt_model_loaded"
    case modelLoadFailed = "stt_model_load_failed"
    case error = "stt_error"
}
