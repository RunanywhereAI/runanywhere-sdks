//
//  TTSEventType.swift
//  RunAnywhere SDK
//
//  TTS event type enumeration
//

import Foundation

/// TTS event types
public enum TTSEventType: String {
    case synthesisStarted = "tts_synthesis_started"
    case synthesisCompleted = "tts_synthesis_completed"
    case synthesisChunk = "tts_synthesis_chunk"
    case modelLoaded = "tts_model_loaded"
    case modelLoadFailed = "tts_model_load_failed"
    case error = "tts_error"
}
