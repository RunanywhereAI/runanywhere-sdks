/// LLM Framework enum
///
/// Defines the inference framework/runtime used for model execution.
/// Matches the InferenceFramework from model_types.dart but with LLM-specific naming.
library llm_framework;

/// Inference frameworks for LLM models
enum LLMFramework {
  llamaCpp('llama_cpp', 'llama.cpp'),
  onnx('onnx', 'ONNX Runtime'),
  foundationModels('foundation_models', 'Foundation Models'),
  mediaPipe('mediapipe', 'MediaPipe'),
  systemTTS('system_tts', 'System TTS'),
  whisperKit('whisperkit', 'WhisperKit'),
  unknown('unknown', 'Unknown');

  final String rawValue;
  final String displayName;

  const LLMFramework(this.rawValue, this.displayName);

  /// Create from raw string value
  static LLMFramework fromRawValue(String value) {
    final lowercased = value.toLowerCase();
    return LLMFramework.values.firstWhere(
      (f) =>
          f.rawValue.toLowerCase() == lowercased ||
          f.name.toLowerCase() == lowercased,
      orElse: () => LLMFramework.unknown,
    );
  }
}
