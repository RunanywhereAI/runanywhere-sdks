/// Common models used across the SDK

/// Model information
class ModelInfo {
  final String id;
  final String name;
  final String framework;
  final String? format;
  final int size;
  final int memoryRequirement;
  final String? localPath;
  final String? downloadURL;

  ModelInfo({
    required this.id,
    required this.name,
    required this.framework,
    this.format,
    required this.size,
    required this.memoryRequirement,
    this.localPath,
    this.downloadURL,
  });
}

/// Model category
enum ModelCategory {
  languageModel,
  speechRecognition,
  textToSpeech,
  visionLanguageModel,
  wakeWord,
  speakerDiarization,
}

/// Framework type
enum LLMFramework {
  llamaCpp,
  whisperKit,
  foundationModels,
  coreML,
  mlx,
  tensorFlowLite,
}

extension LLMFrameworkExtension on LLMFramework {
  String get value {
    switch (this) {
      case LLMFramework.llamaCpp:
        return 'llama.cpp';
      case LLMFramework.whisperKit:
        return 'WhisperKit';
      case LLMFramework.foundationModels:
        return 'Foundation Models';
      case LLMFramework.coreML:
        return 'Core ML';
      case LLMFramework.mlx:
        return 'MLX';
      case LLMFramework.tensorFlowLite:
        return 'TensorFlow Lite';
    }
  }
}

