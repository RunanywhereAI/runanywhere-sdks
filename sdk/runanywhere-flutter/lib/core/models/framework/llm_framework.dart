import 'package:runanywhere/core/models/framework/framework_modality.dart';

/// Supported LLM frameworks
///
/// Note: For iOS parity, use [InferenceFramework] from core/module/inference_framework.dart
/// This enum provides backward compatibility but [InferenceFramework] is preferred.
enum LLMFramework {
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
  simpleEnergyVAD('SimpleEnergyVAD', 'Simple Energy VAD');

  final String rawValue;
  final String displayName;

  const LLMFramework(this.rawValue, this.displayName);

  /// Create from raw string value
  static LLMFramework? fromRawValue(String value) {
    return LLMFramework.values.cast<LLMFramework?>().firstWhere(
          (f) => f?.rawValue == value,
          orElse: () => null,
        );
  }

  /// Supported modalities for this framework
  /// Matches iOS LLMFramework+Modalities extension
  Set<FrameworkModality> get supportedModalities {
    switch (this) {
      // LLM frameworks
      case LLMFramework.llamaCpp:
      case LLMFramework.mlx:
      case LLMFramework.foundationModels:
      case LLMFramework.coreML:
      case LLMFramework.picoLLM:
      case LLMFramework.mlc:
        return {FrameworkModality.textToText};

      // STT frameworks
      case LLMFramework.whisperKit:
      case LLMFramework.openAIWhisper:
        return {FrameworkModality.voiceToText};

      // TTS frameworks
      case LLMFramework.systemTTS:
        return {FrameworkModality.textToVoice};

      // VAD frameworks
      case LLMFramework.simpleEnergyVAD:
        return {FrameworkModality.voiceActivityDetection};

      // Multi-modal frameworks
      case LLMFramework.onnx:
        return {
          FrameworkModality.textToText,
          FrameworkModality.voiceToText,
          FrameworkModality.textToVoice,
          FrameworkModality.voiceActivityDetection,
        };

      case LLMFramework.tensorFlowLite:
      case LLMFramework.execuTorch:
        return {
          FrameworkModality.textToText,
          FrameworkModality.visionToText,
        };

      case LLMFramework.mediaPipe:
        return {
          FrameworkModality.textToText,
          FrameworkModality.visionToText,
          FrameworkModality.voiceToText,
        };

      case LLMFramework.swiftTransformers:
        return {FrameworkModality.textToText, FrameworkModality.visionToText};
    }
  }
}
