//
//  RASDKComponent+DisplayName.swift
//  RunAnywhere SDK
//
//  Human-readable display name for the proto-generated RASDKComponent enum.
//


public extension RASDKComponent {
    var displayName: String {
        switch self {
        case .llm:                return "Language Model"
        case .vlm:                return "Vision Language Model"
        case .stt:                return "Speech to Text"
        case .tts:                return "Text to Speech"
        case .vad:                return "Voice Activity Detection"
        case .voiceAgent:         return "Voice Agent"
        case .embeddings:         return "Embedding"
        case .diffusion:          return "Image Generation"
        case .rag:                return "Retrieval-Augmented Generation"
        case .wakeword:           return "Wake Word"
        case .speakerDiarization: return "Speaker Diarization"
        default:                  return "Unknown"
        }
    }
}
