//
//  ResourceTypes.swift
//  RunAnywhere SDK
//
//  Resource types for capabilities.
//  Lifecycle events are tracked directly via EventPublisher in ManagedLifecycle.
//

import Foundation

// MARK: - Resource Types

/// Types of resources that can be loaded by capabilities
public enum CapabilityResourceType: String, Codable, Sendable {
    case llmModel = "llm_model"
    case sttModel = "stt_model"
    case ttsVoice = "tts_voice"
    case vadModel = "vad_model"
    case diarizationModel = "diarization_model"
}
