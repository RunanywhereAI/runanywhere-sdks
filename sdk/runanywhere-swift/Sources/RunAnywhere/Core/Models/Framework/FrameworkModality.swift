import Foundation

/// Defines the input/output modalities a framework supports
public enum FrameworkModality: String, CaseIterable, Codable, Sendable {
    case textToText = "text-to-text"           // Traditional LLM text generation
    case voiceToText = "voice-to-text"         // Speech recognition/transcription
    case textToVoice = "text-to-voice"         // Text-to-speech synthesis
    case imageToText = "image-to-text"         // Image captioning/OCR
    case textToImage = "text-to-image"         // Image generation
    case multimodal = "multimodal"             // Supports multiple modalities

    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .textToText: return "Text Generation"
        case .voiceToText: return "Speech Recognition"
        case .textToVoice: return "Text-to-Speech"
        case .imageToText: return "Image Understanding"
        case .textToImage: return "Image Generation"
        case .multimodal: return "Multimodal"
        }
    }

    /// Icon name for UI display
    public var iconName: String {
        switch self {
        case .textToText: return "text.bubble"
        case .voiceToText: return "mic"
        case .textToVoice: return "speaker.wave.2"
        case .imageToText: return "photo.badge.arrow.down"
        case .textToImage: return "photo.badge.plus"
        case .multimodal: return "sparkles"
        }
    }
}

/// Extension to categorize frameworks by their primary modality
extension LLMFramework {
    /// The primary modality this framework supports
    public var primaryModality: FrameworkModality {
        switch self {
        // Voice frameworks
        case .whisperKit, .openAIWhisper:
            return .voiceToText

        // Text generation frameworks
        case .llamaCpp, .mlx, .mlc, .execuTorch, .picoLLM:
            return .textToText

        // General ML frameworks that can support multiple modalities
        case .coreML, .tensorFlowLite, .onnx, .mediaPipe:
            return .multimodal

        // Text-focused frameworks
        case .swiftTransformers, .foundationModels:
            return .textToText
        }
    }

    /// All modalities this framework can support
    public var supportedModalities: Set<FrameworkModality> {
        switch self {
        // Voice-only frameworks
        case .whisperKit, .openAIWhisper:
            return [.voiceToText]

        // Text-only frameworks
        case .llamaCpp, .mlx, .mlc, .execuTorch, .picoLLM:
            return [.textToText]

        // Foundation Models might support multimodal in future
        case .foundationModels:
            return [.textToText]

        // Swift Transformers could support various modalities
        case .swiftTransformers:
            return [.textToText, .imageToText]

        // General frameworks can support multiple modalities
        case .coreML:
            return [.textToText, .voiceToText, .textToVoice, .imageToText, .textToImage]

        case .tensorFlowLite, .onnx:
            return [.textToText, .voiceToText, .imageToText]

        case .mediaPipe:
            return [.textToText, .voiceToText, .imageToText]
        }
    }

    /// Whether this framework is primarily for voice/audio processing
    public var isVoiceFramework: Bool {
        primaryModality == .voiceToText || primaryModality == .textToVoice
    }

    /// Whether this framework is primarily for text generation
    public var isTextGenerationFramework: Bool {
        primaryModality == .textToText
    }

    /// Whether this framework supports image processing
    public var supportsImageProcessing: Bool {
        supportedModalities.contains(.imageToText) || supportedModalities.contains(.textToImage)
    }
}
