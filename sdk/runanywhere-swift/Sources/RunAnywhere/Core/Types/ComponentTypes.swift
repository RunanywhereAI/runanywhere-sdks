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

/// Protocol for component output data
public protocol ComponentOutput: Sendable {
    var timestamp: Date { get }
}

// MARK: - SDK Component Enum

/// SDK component types for identification.
///
/// This enum consolidates what was previously `CapabilityType` and provides
/// a unified type for all AI capabilities in the SDK.
///
/// ## Usage
///
/// ```swift
/// // Check what capabilities a module provides
/// let capabilities = MyModule.capabilities
/// if capabilities.contains(.llm) {
///     // Module provides LLM services
/// }
/// ```
public enum SDKComponent: String, CaseIterable, Codable, Sendable, Hashable {
    case llm = "LLM"
    case stt = "STT"
    case tts = "TTS"
    case vad = "VAD"
    case voice = "VOICE"
    case embedding = "EMBEDDING"
    case diffusion = "DIFFUSION"

    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .llm: return "Language Model"
        case .stt: return "Speech to Text"
        case .tts: return "Text to Speech"
        case .vad: return "Voice Activity Detection"
        case .voice: return "Voice Agent"
        case .embedding: return "Embedding"
        case .diffusion: return "Image Generation"
        }
    }

    /// Analytics key for the component (lowercase)
    public var analyticsKey: String {
        rawValue.lowercased()
    }
}
