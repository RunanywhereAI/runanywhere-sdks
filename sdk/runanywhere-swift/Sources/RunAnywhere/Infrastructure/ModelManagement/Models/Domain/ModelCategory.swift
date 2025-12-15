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
        case .whisperKit, .openAIWhisper:
            return .speechRecognition
        case .llamaCpp, .mlx, .mlc, .execuTorch, .picoLLM, .foundationModels, .swiftTransformers:
            return .language
        case .coreML, .tensorFlowLite, .onnx, .mediaPipe:
            // These are general frameworks that could be any category
            // Default to multimodal since they can handle various types
            return .multimodal
        case .systemTTS:
            return .speechSynthesis
        case .fluidAudio:
            return .audio
        }
    }

    /// Determine category from format and frameworks
    static func from(format: ModelFormat, frameworks: [InferenceFramework]) -> ModelCategory {
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
