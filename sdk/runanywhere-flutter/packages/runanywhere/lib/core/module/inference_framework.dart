//
// inference_framework.dart
// RunAnywhere Flutter SDK
//
// Supported inference frameworks/runtimes for running models.
// Matches iOS InferenceFramework from Infrastructure/ModelManagement/Models/Domain/InferenceFramework.swift
//

/// Supported inference frameworks/runtimes for executing models.
///
/// Each framework represents a different runtime environment for AI model inference.
/// Modules register with specific frameworks to provide their capabilities.
enum InferenceFramework {
  coreML('CoreML', 'Core ML'),
  tensorFlowLite('TFLite', 'TensorFlow Lite'),
  mlx('MLX', 'MLX'),
  swiftTransformers('SwiftTransformers', 'Swift Transformers'),
  onnx('ONNX', 'ONNX Runtime'),
  execuTorch('ExecuTorch', 'ExecuTorch'),
  llamaCpp('LlamaCpp', 'llama.cpp'),
  foundationModels('FoundationModels', 'Foundation Models'),
  picoLLM('PicoLLM', 'Pico LLM'),
  mlc('MLC', 'MLC'),
  mediaPipe('MediaPipe', 'MediaPipe'),
  whisperKit('WhisperKit', 'WhisperKit'),
  openAIWhisper('OpenAIWhisper', 'OpenAI Whisper'),
  systemTTS('SystemTTS', 'System TTS'),
  fluidAudio('FluidAudio', 'FluidAudio');

  /// Raw string value for serialization (matches iOS rawValue)
  final String rawValue;

  /// Human-readable display name for the framework
  final String displayName;

  const InferenceFramework(this.rawValue, this.displayName);

  /// Create from raw string value
  static InferenceFramework? fromRawValue(String value) {
    for (final framework in InferenceFramework.values) {
      if (framework.rawValue == value) {
        return framework;
      }
    }
    return null;
  }

  /// Whether this framework supports LLM (text-to-text)
  bool get supportsLLM {
    switch (this) {
      case InferenceFramework.llamaCpp:
      case InferenceFramework.mlx:
      case InferenceFramework.coreML:
      case InferenceFramework.onnx:
      case InferenceFramework.foundationModels:
      case InferenceFramework.picoLLM:
      case InferenceFramework.mlc:
        return true;
      default:
        return false;
    }
  }

  /// Whether this framework supports STT (speech-to-text)
  bool get supportsSTT {
    switch (this) {
      case InferenceFramework.whisperKit:
      case InferenceFramework.openAIWhisper:
      case InferenceFramework.mediaPipe:
        return true;
      default:
        return false;
    }
  }

  /// Whether this framework supports TTS (text-to-speech)
  bool get supportsTTS {
    switch (this) {
      case InferenceFramework.systemTTS:
        return true;
      default:
        return false;
    }
  }
}
