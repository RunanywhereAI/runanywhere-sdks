import 'llm_framework.dart';

/// Defines the input/output modalities a framework supports
/// Matches iOS FrameworkModality from Core/Models/Framework/FrameworkModality.swift
enum FrameworkModality {
  textToText('text-to-text', 'Text Generation', 'text_fields'),
  voiceToText('voice-to-text', 'Speech Recognition', 'mic'),
  textToVoice('text-to-voice', 'Text-to-Speech', 'volume_up'),
  imageToText('image-to-text', 'Image Understanding', 'image'),
  textToImage('text-to-image', 'Image Generation', 'add_photo_alternate'),
  multimodal('multimodal', 'Multimodal', 'auto_awesome');

  final String rawValue;
  final String displayName;
  final String iconName;

  const FrameworkModality(this.rawValue, this.displayName, this.iconName);

  /// Create from raw string value
  static FrameworkModality? fromRawValue(String value) {
    return FrameworkModality.values.cast<FrameworkModality?>().firstWhere(
          (m) => m?.rawValue == value,
          orElse: () => null,
        );
  }
}

/// Extension to categorize frameworks by their primary modality
extension LLMFrameworkModality on LLMFramework {
  /// The primary modality this framework supports
  FrameworkModality get primaryModality {
    switch (this) {
      // Voice frameworks
      case LLMFramework.whisperKit:
      case LLMFramework.openAIWhisper:
        return FrameworkModality.voiceToText;

      // Text generation frameworks
      case LLMFramework.llamaCpp:
      case LLMFramework.mlx:
      case LLMFramework.mlc:
      case LLMFramework.execuTorch:
      case LLMFramework.picoLLM:
        return FrameworkModality.textToText;

      // General ML frameworks that can support multiple modalities
      case LLMFramework.coreML:
      case LLMFramework.tensorFlowLite:
      case LLMFramework.onnx:
      case LLMFramework.mediaPipe:
        return FrameworkModality.multimodal;

      // Text-focused frameworks
      case LLMFramework.swiftTransformers:
      case LLMFramework.foundationModels:
        return FrameworkModality.textToText;

      // System TTS
      case LLMFramework.systemTTS:
        return FrameworkModality.textToVoice;
    }
  }

  /// All modalities this framework can support
  Set<FrameworkModality> get supportedModalities {
    switch (this) {
      // Voice-only frameworks
      case LLMFramework.whisperKit:
      case LLMFramework.openAIWhisper:
        return {FrameworkModality.voiceToText};

      // Text-only frameworks
      case LLMFramework.llamaCpp:
      case LLMFramework.mlx:
      case LLMFramework.mlc:
      case LLMFramework.execuTorch:
      case LLMFramework.picoLLM:
        return {FrameworkModality.textToText};

      // Foundation Models might support multimodal in future
      case LLMFramework.foundationModels:
        return {FrameworkModality.textToText};

      // Swift Transformers could support various modalities
      case LLMFramework.swiftTransformers:
        return {FrameworkModality.textToText, FrameworkModality.imageToText};

      // General frameworks can support multiple modalities
      case LLMFramework.coreML:
        return {
          FrameworkModality.textToText,
          FrameworkModality.voiceToText,
          FrameworkModality.textToVoice,
          FrameworkModality.imageToText,
          FrameworkModality.textToImage,
        };

      case LLMFramework.tensorFlowLite:
      case LLMFramework.onnx:
        return {
          FrameworkModality.textToText,
          FrameworkModality.voiceToText,
          FrameworkModality.imageToText,
        };

      case LLMFramework.mediaPipe:
        return {
          FrameworkModality.textToText,
          FrameworkModality.voiceToText,
          FrameworkModality.imageToText,
        };

      // System TTS - text-to-voice only
      case LLMFramework.systemTTS:
        return {FrameworkModality.textToVoice};
    }
  }

  /// Whether this framework is primarily for voice/audio processing
  bool get isVoiceFramework =>
      primaryModality == FrameworkModality.voiceToText ||
      primaryModality == FrameworkModality.textToVoice;

  /// Whether this framework is primarily for text generation
  bool get isTextGenerationFramework =>
      primaryModality == FrameworkModality.textToText;

  /// Whether this framework supports image processing
  bool get supportsImageProcessing =>
      supportedModalities.contains(FrameworkModality.imageToText) ||
      supportedModalities.contains(FrameworkModality.textToImage);
}
