import '../../../core/module_registry.dart';
import '../../native/native_backend.dart';

/// ONNX-based Language Model service.
///
/// This is a placeholder for future LLM capabilities via ONNX.
/// Currently, the primary LLM backend will be llama.cpp (future).
///
/// ## Usage
///
/// ```dart
/// final backend = NativeBackend();
/// backend.create('onnx');
///
/// final llm = OnnxLLMService(backend);
/// await llm.initialize(modelPath: '/path/to/model');
///
/// final result = await llm.generate(
///   prompt: 'Hello, ',
///   options: LLMGenerationOptions(maxTokens: 100),
/// );
/// print(result.text);
/// ```
class OnnxLLMService implements LLMService {
  final NativeBackend _backend;
  bool _isInitialized = false;

  /// Create a new ONNX LLM service.
  OnnxLLMService(this._backend);

  @override
  Future<void> initialize({String? modelPath}) async {
    if (modelPath != null) {
      _backend.loadTextModel(modelPath);
    }

    _isInitialized = true;
  }

  @override
  bool get isReady => _isInitialized && _backend.isTextModelLoaded;

  @override
  Future<LLMGenerationResult> generate({
    required String prompt,
    required LLMGenerationOptions options,
  }) async {
    final result = _backend.generate(
      prompt,
      systemPrompt: options.systemPrompt,
      maxTokens: options.maxTokens,
      temperature: options.temperature,
    );

    return LLMGenerationResult(
      text: result['text'] as String? ?? '',
    );
  }

  @override
  Stream<String> generateStream({
    required String prompt,
    required LLMGenerationOptions options,
  }) async* {
    // For now, use batch generation and emit as single token
    // TODO: Implement true streaming when supported by native backend
    final result = await generate(prompt: prompt, options: options);
    yield result.text;
  }

  @override
  Future<void> cleanup() async {
    if (_backend.isTextModelLoaded) {
      _backend.unloadTextModel();
    }
    _isInitialized = false;
  }

  /// Cancel ongoing text generation.
  void cancel() {
    _backend.cancelTextGeneration();
  }
}
