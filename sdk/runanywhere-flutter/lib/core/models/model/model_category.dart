import '../framework/framework_modality.dart';
import '../framework/llm_framework.dart';
import '../framework/model_format.dart';

/// Defines the category/type of a model based on its input/output modality
/// Matches iOS ModelCategory from Core/Models/Model/ModelCategory.swift
enum ModelCategory {
  language('language', 'Language Model', 'text_fields'),
  speechRecognition('speech-recognition', 'Speech Recognition', 'mic'),
  speechSynthesis('speech-synthesis', 'Text-to-Speech', 'volume_up'),
  vision('vision', 'Vision Model', 'image'),
  imageGeneration('image-generation', 'Image Generation', 'add_photo_alternate'),
  multimodal('multimodal', 'Multimodal', 'auto_awesome'),
  audio('audio', 'Audio Processing', 'graphic_eq');

  final String rawValue;
  final String displayName;
  final String iconName;

  const ModelCategory(this.rawValue, this.displayName, this.iconName);

  /// Create from raw string value
  static ModelCategory? fromRawValue(String value) {
    return ModelCategory.values.cast<ModelCategory?>().firstWhere(
          (c) => c?.rawValue == value,
          orElse: () => null,
        );
  }

  /// Maps to the corresponding FrameworkModality
  FrameworkModality get frameworkModality {
    switch (this) {
      case ModelCategory.language:
        return FrameworkModality.textToText;
      case ModelCategory.speechRecognition:
        return FrameworkModality.voiceToText;
      case ModelCategory.speechSynthesis:
        return FrameworkModality.textToVoice;
      case ModelCategory.vision:
        return FrameworkModality.imageToText;
      case ModelCategory.imageGeneration:
        return FrameworkModality.textToImage;
      case ModelCategory.multimodal:
        return FrameworkModality.multimodal;
      case ModelCategory.audio:
        return FrameworkModality.voiceToText;
    }
  }

  /// Initialize from a FrameworkModality
  static ModelCategory? fromModality(FrameworkModality modality) {
    switch (modality) {
      case FrameworkModality.textToText:
        return ModelCategory.language;
      case FrameworkModality.voiceToText:
        return ModelCategory.speechRecognition;
      case FrameworkModality.textToVoice:
        return ModelCategory.speechSynthesis;
      case FrameworkModality.imageToText:
        return ModelCategory.vision;
      case FrameworkModality.textToImage:
        return ModelCategory.imageGeneration;
      case FrameworkModality.multimodal:
        return ModelCategory.multimodal;
    }
  }

  /// Whether this category typically requires context length
  bool get requiresContextLength {
    switch (this) {
      case ModelCategory.language:
      case ModelCategory.multimodal:
        return true;
      default:
        return false;
    }
  }

  /// Whether this category typically supports thinking/reasoning
  bool get supportsThinking {
    switch (this) {
      case ModelCategory.language:
      case ModelCategory.multimodal:
        return true;
      default:
        return false;
    }
  }

  /// Check if this category is compatible with a framework modality
  bool isCompatibleWith(FrameworkModality modality) {
    switch (this) {
      case ModelCategory.language:
        return modality == FrameworkModality.textToText;
      case ModelCategory.speechRecognition:
        return modality == FrameworkModality.voiceToText;
      case ModelCategory.speechSynthesis:
        return modality == FrameworkModality.textToVoice;
      case ModelCategory.vision:
        return modality == FrameworkModality.imageToText;
      case ModelCategory.imageGeneration:
        return modality == FrameworkModality.textToImage;
      case ModelCategory.multimodal:
        return true; // Multimodal models can work with any modality
      case ModelCategory.audio:
        return modality == FrameworkModality.voiceToText;
    }
  }

  /// Determine category from a framework
  static ModelCategory fromFramework(LLMFramework framework) {
    switch (framework) {
      case LLMFramework.whisperKit:
      case LLMFramework.openAIWhisper:
        return ModelCategory.speechRecognition;
      case LLMFramework.llamaCpp:
      case LLMFramework.mlx:
      case LLMFramework.mlc:
      case LLMFramework.execuTorch:
      case LLMFramework.picoLLM:
      case LLMFramework.foundationModels:
      case LLMFramework.swiftTransformers:
        return ModelCategory.language;
      case LLMFramework.coreML:
      case LLMFramework.tensorFlowLite:
      case LLMFramework.onnx:
      case LLMFramework.mediaPipe:
        return ModelCategory.multimodal;
      case LLMFramework.systemTTS:
        return ModelCategory.speechSynthesis;
    }
  }

  /// Determine category from format and frameworks
  static ModelCategory fromFormatAndFrameworks(
    ModelFormat format,
    List<LLMFramework> frameworks,
  ) {
    // First check if we have framework hints
    if (frameworks.isNotEmpty) {
      return fromFramework(frameworks.first);
    }

    // Otherwise guess from format
    switch (format) {
      case ModelFormat.mlmodel:
      case ModelFormat.mlpackage:
        return ModelCategory.multimodal;
      case ModelFormat.gguf:
      case ModelFormat.ggml:
      case ModelFormat.safetensors:
      case ModelFormat.bin:
        return ModelCategory.language;
      case ModelFormat.tflite:
      case ModelFormat.onnx:
        return ModelCategory.multimodal;
      default:
        return ModelCategory.language;
    }
  }
}
