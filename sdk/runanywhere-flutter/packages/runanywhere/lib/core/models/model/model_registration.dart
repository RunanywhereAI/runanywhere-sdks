/// Model Registration
///
/// Provides a simple way to register models with the SDK from URLs.
library model_registration;

import 'package:runanywhere/core/models/framework/framework_modality.dart';
import 'package:runanywhere/core/models/framework/llm_framework.dart';
import 'package:runanywhere/core/types/model_types.dart';

/// Model registration helper for adding models from URLs
class ModelRegistration {
  final String url;
  final LLMFramework framework;
  final FrameworkModality modality;
  final String? name;
  final int memoryRequirement;
  final bool supportsThinking;

  const ModelRegistration({
    required this.url,
    required this.framework,
    required this.modality,
    this.name,
    this.memoryRequirement = 500000000,
    this.supportsThinking = false,
  });

  /// Convert to ModelInfo for registration
  ModelInfo toModelInfo() {
    final uri = Uri.parse(url);
    final fileName = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : url;
    final modelName = name ?? fileName;
    final modelId =
        modelName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '-');

    // Infer format from URL
    final format = _inferFormat(fileName);

    // Map LLMFramework to InferenceFramework
    final inferenceFramework = _mapToInferenceFramework(framework);

    // Map FrameworkModality to ModelCategory
    final category = _mapToCategory(modality);

    return ModelInfo(
      id: modelId,
      name: modelName,
      category: category,
      format: format,
      framework: inferenceFramework,
      downloadURL: uri,
      downloadSize: memoryRequirement,
      supportsThinking: supportsThinking,
    );
  }

  ModelFormat _inferFormat(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.gguf')) return ModelFormat.gguf;
    if (lower.endsWith('.onnx')) return ModelFormat.onnx;
    if (lower.endsWith('.bin')) return ModelFormat.bin;
    if (lower.endsWith('.ort')) return ModelFormat.ort;
    return ModelFormat.unknown;
  }

  InferenceFramework _mapToInferenceFramework(LLMFramework framework) {
    switch (framework) {
      case LLMFramework.llamaCpp:
        return InferenceFramework.llamaCpp;
      case LLMFramework.onnx:
        return InferenceFramework.onnx;
      case LLMFramework.foundationModels:
        return InferenceFramework.foundationModels;
      case LLMFramework.systemTTS:
        return InferenceFramework.systemTTS;
      default:
        return InferenceFramework.unknown;
    }
  }

  ModelCategory _mapToCategory(FrameworkModality modality) {
    switch (modality) {
      case FrameworkModality.textToText:
        return ModelCategory.language;
      case FrameworkModality.textToSpeech:
        return ModelCategory.speechSynthesis;
      case FrameworkModality.speechToText:
        return ModelCategory.speechRecognition;
      case FrameworkModality.imageToText:
        return ModelCategory.vision;
      case FrameworkModality.textToImage:
        return ModelCategory.imageGeneration;
      case FrameworkModality.audioProcessing:
        return ModelCategory.audio;
    }
  }
}
