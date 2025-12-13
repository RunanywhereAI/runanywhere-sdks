//
//  ComponentTypes.swift
//  RunAnywhere SDK
//
//  Core type definitions for component models
//

import Foundation

// MARK: - Component Protocols

/// Protocol for component configuration
public protocol ComponentConfiguration: Sendable {
    var modelId: String? { get }
}

/// Protocol for component initialization parameters
public protocol ComponentInitParameters: Sendable {
    var modelId: String? { get }
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

// MARK: - Audio Format

/// Audio format options for audio processing
public enum AudioFormat: String, Sendable, CaseIterable {
    case pcm
    case wav
    case mp3
    case opus
    case aac
    case flac

    /// File extension for this format
    public var fileExtension: String {
        rawValue
    }

    /// MIME type for this format
    public var mimeType: String {
        switch self {
        case .pcm: return "audio/pcm"
        case .wav: return "audio/wav"
        case .mp3: return "audio/mpeg"
        case .opus: return "audio/opus"
        case .aac: return "audio/aac"
        case .flac: return "audio/flac"
        }
    }
}
