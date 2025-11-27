import Foundation

/// Defines the category/type of a model based on its input/output modality
/// This aligns with FrameworkModality for consistency across the SDK
public enum ModelCategory: String, CaseIterable, Codable, Sendable {
    case language = "language"              // Text-to-text models (LLMs)
    case speechRecognition = "speech-recognition"  // Voice-to-text models (ASR)
    case speechSynthesis = "speech-synthesis"      // Text-to-voice models (TTS)
    case vision = "vision"                  // Image understanding models
    case imageGeneration = "image-generation"      // Text-to-image models
    case multimodal = "multimodal"          // Models that handle multiple modalities
    case audio = "audio"                    // Audio processing (diarization, etc.)

    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .language: return "Language Model"
        case .speechRecognition: return "Speech Recognition"
        case .speechSynthesis: return "Text-to-Speech"
        case .vision: return "Vision Model"
        case .imageGeneration: return "Image Generation"
        case .multimodal: return "Multimodal"
        case .audio: return "Audio Processing"
        }
    }

    /// Icon name for UI display
    public var iconName: String {
        switch self {
        case .language: return "text.bubble"
        case .speechRecognition: return "mic"
        case .speechSynthesis: return "speaker.wave.2"
        case .vision: return "photo.badge.arrow.down"
        case .imageGeneration: return "photo.badge.plus"
        case .multimodal: return "sparkles"
        case .audio: return "waveform"
        }
    }

    /// Maps to the corresponding FrameworkModality
    public var frameworkModality: FrameworkModality {
        switch self {
        case .language: return .textToText
        case .speechRecognition: return .voiceToText
        case .speechSynthesis: return .textToVoice
        case .vision: return .imageToText
        case .imageGeneration: return .textToImage
        case .multimodal: return .multimodal
        case .audio: return .voiceToText  // Audio processing often involves voice-to-text
        }
    }

    /// Initialize from a FrameworkModality
    public init?(from modality: FrameworkModality) {
        switch modality {
        case .textToText:
            self = .language
        case .voiceToText:
            self = .speechRecognition
        case .textToVoice:
            self = .speechSynthesis
        case .imageToText:
            self = .vision
        case .textToImage:
            self = .imageGeneration
        case .multimodal:
            self = .multimodal
        }
    }

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

/// Extension to help adapters check compatibility
public extension ModelCategory {
    /// Check if this category is compatible with a framework modality
    func isCompatible(with modality: FrameworkModality) -> Bool {
        switch (self, modality) {
        case (.language, .textToText),
             (.speechRecognition, .voiceToText),
             (.speechSynthesis, .textToVoice),
             (.vision, .imageToText),
             (.imageGeneration, .textToImage),
             (.multimodal, .multimodal):
            return true
        case (.audio, .voiceToText):
            // Audio processing often uses voice-to-text frameworks
            return true
        case (.multimodal, _):
            // Multimodal models can work with any modality
            return true
        default:
            return false
        }
    }

    /// Determine category from a FrameworkModality (non-failable)
    static func from(modality: FrameworkModality) -> ModelCategory {
        switch modality {
        case .textToText: return .language
        case .voiceToText: return .speechRecognition
        case .textToVoice: return .speechSynthesis
        case .imageToText: return .vision
        case .textToImage: return .imageGeneration
        case .multimodal: return .multimodal
        }
    }

    /// Determine category from a framework
    static func from(framework: LLMFramework) -> ModelCategory {
        switch framework {
        case .whisperKit, .openAIWhisper:
            return .speechRecognition
        case .llamaCpp, .mlx, .mlc, .execuTorch, .picoLLM, .foundationModels, .swiftTransformers:
            return .language
        case .coreML, .tensorFlowLite, .onnx, .mediaPipe:
            // These are general frameworks that could be any category
            // Default to multimodal since they can handle various types
            return .multimodal
        }
    }

    /// Determine category from format and frameworks
    static func from(format: ModelFormat, frameworks: [LLMFramework]) -> ModelCategory {
        // First check if we have framework hints
        if let firstFramework = frameworks.first {
            return from(framework: firstFramework)
        }

        // Otherwise guess from format
        switch format {
        case .mlmodel, .mlpackage:
            return .multimodal // Core ML models can be anything
        case .gguf, .ggml, .safetensors, .bin:
            return .language // Usually LLMs
        case .tflite, .onnx:
            return .multimodal // Could be anything
        default:
            return .language // Default to language
        }
    }
}
