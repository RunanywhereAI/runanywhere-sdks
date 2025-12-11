//
//  Modality.swift
//  RunAnywhere SDK
//
//  Supported modalities for model lifecycle tracking
//

import Foundation

/// Supported modalities for model lifecycle tracking
/// Defines the type of AI capability a model provides
public enum Modality: String, CaseIterable, Sendable, Codable {
    /// Large Language Models for text generation
    case llm = "llm"

    /// Speech-to-Text models for transcription
    case stt = "stt"

    /// Text-to-Speech models for voice synthesis
    case tts = "tts"

    /// Speaker diarization models for multi-speaker identification
    case speakerDiarization = "speaker_diarization"

    /// Wake word detection models
    case wakeWord = "wake_word"

    /// Vision-Language Models for image understanding
    case vlm = "vlm"

    /// Voice Activity Detection models
    case vad = "vad"

    // MARK: - Display Properties

    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .llm: return "Language Model"
        case .stt: return "Speech Recognition"
        case .tts: return "Text to Speech"
        case .speakerDiarization: return "Speaker Diarization"
        case .wakeWord: return "Wake Word"
        case .vlm: return "Vision Language Model"
        case .vad: return "Voice Activity Detection"
        }
    }

    /// Short description of what this modality does
    public var description: String {
        switch self {
        case .llm: return "Text generation and chat"
        case .stt: return "Convert speech to text"
        case .tts: return "Convert text to speech"
        case .speakerDiarization: return "Identify different speakers"
        case .wakeWord: return "Detect wake word triggers"
        case .vlm: return "Analyze and understand images"
        case .vad: return "Detect voice activity"
        }
    }

    // MARK: - Framework Mapping

    /// Map to the corresponding FrameworkModality
    public var frameworkModality: FrameworkModality {
        switch self {
        case .llm: return .textToText
        case .stt: return .voiceToText
        case .tts: return .textToVoice
        case .vlm: return .imageToText
        case .speakerDiarization, .wakeWord, .vad: return .voiceToText
        }
    }

    /// Create from FrameworkModality
    public static func from(_ frameworkModality: FrameworkModality) -> Modality {
        switch frameworkModality {
        case .textToText: return .llm
        case .voiceToText: return .stt
        case .textToVoice: return .tts
        case .imageToText, .multimodal: return .vlm
        case .textToImage: return .llm // Default fallback
        }
    }
}
