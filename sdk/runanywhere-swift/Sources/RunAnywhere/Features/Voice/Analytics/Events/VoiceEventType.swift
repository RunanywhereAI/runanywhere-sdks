//
//  VoiceEventType.swift
//  RunAnywhere SDK
//
//  Voice analytics event types
//

import Foundation

// MARK: - Voice Event Type

/// Voice event types
public enum VoiceEventType: String, Sendable, Codable {
    case pipelineCreated = "voice_pipeline_created"
    case pipelineStarted = "voice_pipeline_started"
    case pipelineCompleted = "voice_pipeline_completed"
    case pipelineFailed = "voice_pipeline_failed"
    case transcriptionStarted = "voice_transcription_started"
    case transcriptionCompleted = "voice_transcription_completed"
    case stageExecuted = "voice_stage_executed"
    case error = "voice_error"
}
