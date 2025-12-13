//
//  GenerationEventType.swift
//  RunAnywhere SDK
//
//  Generation event types
//

import Foundation

// MARK: - Generation Event Type

/// Generation event types
public enum GenerationEventType: String {
    case sessionStarted = "generation_session_started"
    case sessionEnded = "generation_session_ended"
    case generationStarted = "generation_started"
    case generationCompleted = "generation_completed"
    case firstTokenGenerated = "generation_first_token"
    case streamingUpdate = "generation_streaming_update"
    case error = "generation_error"
    case modelLoaded = "generation_model_loaded"
    case modelLoadFailed = "generation_model_load_failed"
    case modelUnloaded = "generation_model_unloaded"
}
