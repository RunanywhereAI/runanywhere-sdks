//
//  CapabilityType.swift
//  RunAnywhere SDK
//
//  Defines the types of AI capabilities that the SDK supports.
//  Each capability maps to a service protocol (LLMService, STTService, etc.)
//

import Foundation

/// Types of AI capabilities supported by the SDK.
///
/// Each capability type corresponds to a specific service protocol
/// and is used for service provider registration and discovery.
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
public enum CapabilityType: String, CaseIterable, Codable, Sendable {
    /// Large Language Model capability (text generation, chat)
    case llm = "LLM"

    /// Speech-to-Text capability (transcription)
    case stt = "STT"

    /// Text-to-Speech capability (voice synthesis)
    case tts = "TTS"

    /// Voice Activity Detection capability
    case vad = "VAD"

    // MARK: - Display Properties

    /// Human-readable name for the capability
    public var displayName: String {
        switch self {
        case .llm: return "Language Model"
        case .stt: return "Speech to Text"
        case .tts: return "Text to Speech"
        case .vad: return "Voice Activity Detection"
        }
    }

    /// Analytics key for the capability
    public var analyticsKey: String {
        rawValue.lowercased()
    }
}

// MARK: - Hashable Conformance

extension CapabilityType: Hashable {}
