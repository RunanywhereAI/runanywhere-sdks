import 'dart:async';

import '../../core/module_registry.dart';
import '../native_backend.dart';

/// Native LLM service using LlamaCPP/ONNX backend via FFI.
///
/// This is the Flutter equivalent of iOS's native LLM implementation.
class NativeLLMService implements LLMService {
  final NativeBackend _backend;
  bool _isInitialized = false;

  NativeLLMService(this._backend);

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
    if (!isReady) {
      throw Exception('LLM service not initialized');
    }

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
    // For now, use non-streaming and yield the full result
    // Streaming requires callback handling which is more complex with FFI
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
}

/// Provider for native LLM service.
class NativeLLMServiceProvider implements LLMServiceProvider {
  final NativeBackend _backend;

  NativeLLMServiceProvider(this._backend);

  @override
  String get name => 'NativeLLM';

  @override
  bool canHandle({String? modelId}) {
    if (modelId == null) return true;

    final lower = modelId.toLowerCase();
    // Handle LlamaCPP GGUF models and ONNX models
    return lower.endsWith('.gguf') ||
        lower.endsWith('.onnx') ||
        lower.contains('llama') ||
        lower.contains('mistral') ||
        lower.contains('gemma') ||
        lower.contains('phi');
  }

  @override
  Future<LLMService> createLLMService(dynamic configuration) async {
    final service = NativeLLMService(_backend);

    String? modelPath;
    if (configuration is Map) {
      modelPath = configuration['modelPath'] as String?;
    } else if (configuration is String) {
      modelPath = configuration;
    }

    await service.initialize(modelPath: modelPath);
    return service;
  }
}
