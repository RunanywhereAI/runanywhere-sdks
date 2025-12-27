import Foundation

/// Defines the category/type of a model based on its input/output modality
public enum ModelCategory: String, CaseIterable, Codable, Sendable {
    case language = "language"              // Text-to-text models (LLMs)
    case speechRecognition = "speech-recognition"  // Voice-to-text models (ASR)
    case speechSynthesis = "speech-synthesis"      // Text-to-voice models (TTS)
    case vision = "vision"                  // Image understanding models
    case imageGeneration = "image-generation"      // Text-to-image models
    case multimodal = "multimodal"          // Models that handle multiple modalities
    case audio = "audio"                    // Audio processing (diarization, etc.)

    /// Whether this category typically requires context length
    public var requiresContextLength: Bool {
        switch self {
        case .language, .multimodal:
            return true
        case .speechRecognition, .speechSynthesis, .vision, .imageGeneration, .audio:
            return false
        }
    }

    /// Whether this category typically supports thinking/reasoning
    public var supportsThinking: Bool {
        switch self {
        case .language, .multimodal:
            return true
        case .speechRecognition, .speechSynthesis, .vision, .imageGeneration, .audio:
            return false
        }
    }
}

/// Extension to help determine model category
public extension ModelCategory {
    /// Determine category from a framework
    static func from(framework: InferenceFramework) -> ModelCategory {
        switch framework {
        case .llamaCpp, .foundationModels:
            return .language
        case .onnx:
            // General-purpose framework - default to multimodal
            return .multimodal
        case .systemTTS:
            return .speechSynthesis
        case .fluidAudio:
            return .audio
        case .builtIn, .none, .unknown:
            // Services without models or unknown frameworks
            return .audio
        }
    }
}
