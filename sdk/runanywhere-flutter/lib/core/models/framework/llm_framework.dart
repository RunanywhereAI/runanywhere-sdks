/// Supported LLM frameworks
/// Matches iOS LLMFramework from Core/Models/Framework/LLMFramework.swift
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
  systemTTS('SystemTTS', 'System TTS');

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
}
