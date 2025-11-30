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

/// Framework type for AI inference
/// Matches iOS LLMFramework from shared types
enum LLMFramework {
  llamaCpp('llama.cpp'),
  onnx('ONNX'),
  coreML('CoreML'),
  tensorflowLite('TFLite'),
  foundationModels('FoundationModels'),
  whisperKit('WhisperKit'),
  systemTTS('SystemTTS'),
  mlx('MLX');

  final String displayName;
  const LLMFramework(this.displayName);

  /// Legacy getter for backward compatibility
  String get value => displayName;
}
