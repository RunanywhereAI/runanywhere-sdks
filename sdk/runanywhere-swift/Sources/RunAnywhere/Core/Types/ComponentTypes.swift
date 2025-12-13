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

// MARK: - Component State

/// State of a component
public enum ComponentState: String, Sendable, CaseIterable {
    case notInitialized
    case initializing
    case ready
    case failed
    case cleaning

    /// Check if component is usable
    public var isUsable: Bool {
        self == .ready
    }
}

// MARK: - Component Status

/// Status of a component with optional error
public struct ComponentStatus: Sendable {
    public let component: SDKComponent
    public let state: ComponentState
    public let error: Error?

    public init(component: SDKComponent, state: ComponentState, error: Error? = nil) {
        self.component = component
        self.state = state
        self.error = error
    }
}

// MARK: - Initialization Result

/// Result of component initialization
public struct InitializationResult: Sendable {
    public let success: Bool
    public let components: [SDKComponent: ComponentState]
    public let errors: [SDKComponent: Error]

    public init(
        success: Bool,
        components: [SDKComponent: ComponentState] = [:],
        errors: [SDKComponent: Error] = [:]
    ) {
        self.success = success
        self.components = components
        self.errors = errors
    }

    /// Create a successful result
    public static func success(components: [SDKComponent]) -> InitializationResult {
        var states: [SDKComponent: ComponentState] = [:]
        for component in components {
            states[component] = .ready
        }
        return InitializationResult(success: true, components: states)
    }

    /// Create a failed result
    public static func failure(component: SDKComponent, error: Error) -> InitializationResult {
        return InitializationResult(
            success: false,
            components: [component: .failed],
            errors: [component: error]
        )
    }
}
