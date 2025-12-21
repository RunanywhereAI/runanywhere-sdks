import 'dart:async';

import '../../../core/module_registry.dart';
import '../../../native/native_backend.dart';
import '../services/onnx_llm_service.dart';

/// Provider for ONNX-based LLM service.
///
/// This is a placeholder for future ONNX-based LLM capabilities.
/// Primary LLM support will be via llama.cpp backend (future).
class OnnxLLMServiceProvider implements LLMServiceProvider {
  final NativeBackend _backend;

  /// Create a new ONNX LLM provider.
  OnnxLLMServiceProvider(this._backend);

  @override
  String get name => 'ONNX Runtime LLM';

  @override
  bool canHandle({String? modelId}) {
    if (modelId == null) return false; // Don't default to ONNX for LLM

    final lower = modelId.toLowerCase();

    // Handle ONNX LLM models
    if (lower.endsWith('.onnx') &&
        (lower.contains('llm') ||
            lower.contains('phi') ||
            lower.contains('gpt'))) {
      return true;
    }

    return false;
  }

  @override
  Future<LLMService> createLLMService(dynamic configuration) async {
    final service = OnnxLLMService(_backend);

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
