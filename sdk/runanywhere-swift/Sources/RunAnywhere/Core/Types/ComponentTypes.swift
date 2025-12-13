//
//  ComponentTypes.swift
//  RunAnywhere SDK
//
//  Core type definitions for component models
//

import Foundation

// MARK: - Component Protocols

/// Protocol for component configuration and initialization
///
/// All component configurations (LLM, STT, TTS, VAD, etc.) conform to this protocol.
/// Provides common properties needed for model selection and framework preference.
public protocol ComponentConfiguration: Sendable {
    /// Model identifier (optional - uses default if not specified)
    var modelId: String? { get }

    /// Preferred inference framework for this component (optional)
    var preferredFramework: InferenceFramework? { get }

    /// Validates the configuration
    func validate() throws
}

// Default implementation for preferredFramework (most configs don't need it)
extension ComponentConfiguration {
    public var preferredFramework: InferenceFramework? { nil }
}

/// Protocol for component input data
public protocol ComponentInput: Sendable {}

/// Protocol for component output data
public protocol ComponentOutput: Sendable {
    var timestamp: Date { get }
}

// MARK: - SDK Component Enum

/// SDK component types for identification
public enum SDKComponent: String, CaseIterable, Sendable {
    case llm
    case stt
    case tts
    case vad
    case speakerDiarization
    case voice
    case embedding

    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .llm: return "LLM"
        case .stt: return "Speech-to-Text"
        case .tts: return "Text-to-Speech"
        case .vad: return "Voice Activity Detection"
        case .speakerDiarization: return "Speaker Diarization"
        case .voice: return "Voice Agent"
        case .embedding: return "Embedding"
        }
    }
}
