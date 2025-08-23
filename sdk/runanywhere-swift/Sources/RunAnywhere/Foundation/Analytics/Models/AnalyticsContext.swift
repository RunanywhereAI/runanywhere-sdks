//
//  AnalyticsContext.swift
//  RunAnywhere SDK
//
//  Strongly typed context enum for analytics error tracking
//

import Foundation

/// Analytics error context types for strongly typed error tracking
public enum AnalyticsContext: String, CaseIterable {
    case transcription = "transcription"
    case pipelineProcessing = "pipeline_processing"
    case initialization = "initialization"
    case componentExecution = "component_execution"
    case modelLoading = "model_loading"
    case audioProcessing = "audio_processing"
    case textGeneration = "text_generation"
    case speakerDiarization = "speaker_diarization"
}
