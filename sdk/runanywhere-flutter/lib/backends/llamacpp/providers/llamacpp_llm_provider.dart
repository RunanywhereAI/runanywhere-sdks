import '../../../core/module_registry.dart';
import '../../native/native_backend.dart';
import '../services/llamacpp_llm_service.dart';

/// Provider for LlamaCpp-based LLM service.
///
/// This is the Flutter equivalent of Swift's `LLMSwiftServiceProvider`.
class LlamaCppLLMServiceProvider implements LLMServiceProvider {
  final NativeBackend _backend;

  /// Create a new LlamaCpp LLM provider.
  LlamaCppLLMServiceProvider(this._backend);

  @override
  String get name => 'LlamaCpp (llama.cpp)';

  @override
  bool canHandle({String? modelId}) {
    // Accept null or empty modelId
    if (modelId == null || modelId.isEmpty) {
      return true;
    }

    // Accept "default" to use currently loaded model
    if (modelId == 'default') {
      return true;
    }

    final lower = modelId.toLowerCase();

    // Check for supported file extensions (GGUF/GGML/BIN formats)
    if (lower.endsWith('.gguf') ||
        lower.endsWith('.ggml') ||
        lower.endsWith('.bin')) {
      return true;
    }

    // Check for common LLM model identifiers
    if (lower.contains('llama') ||
        lower.contains('mistral') ||
        lower.contains('qwen') ||
        lower.contains('gemma') ||
        lower.contains('phi') ||
        lower.contains('tinyllama') ||
        lower.contains('vicuna') ||
        lower.contains('alpaca')) {
      return true;
    }

    return false;
  }

  @override
  Future<LLMService> createLLMService(dynamic configuration) async {
    final service = LlamaCppLLMService(_backend);

    String? modelPath;
    if (configuration is Map) {
      modelPath = configuration['modelPath'] as String? ??
          configuration['modelId'] as String?;
    } else if (configuration is String) {
      modelPath = configuration;
    }

    // Initialize with model path if provided and not "default"
    if (modelPath != null && modelPath.isNotEmpty && modelPath != 'default') {
      await service.initialize(modelPath: modelPath);
    } else {
      // Initialize without specific model
      await service.initialize();
    }

    return service;
  }
}
