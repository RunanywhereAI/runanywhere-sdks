// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:async';

import '../foundation/logging/sdk_logger.dart';
import 'native_backend.dart';

/// LLM bridge for C++ text generation operations.
/// Matches Swift's `CppBridge+LLM.swift`.
class DartBridgeLLM {
  DartBridgeLLM._();

  static final _logger = SDKLogger('DartBridge.LLM');
  static final DartBridgeLLM instance = DartBridgeLLM._();

  NativeBackend? _backend;

  /// Set the native backend for LLM operations
  void setBackend(NativeBackend backend) {
    _backend = backend;
  }

  /// Load an LLM model
  Future<bool> loadModel({
    required String modelPath,
    Map<String, dynamic>? config,
  }) async {
    final backend = _backend;
    if (backend == null) {
      _logger.warning('No backend set for LLM operations');
      return false;
    }

    try {
      backend.loadTextModel(modelPath, config: config);
      return true;
    } catch (e) {
      _logger
          .error('Failed to load LLM model', metadata: {'error': e.toString()});
      return false;
    }
  }

  /// Check if model is loaded
  bool isModelLoaded() {
    return _backend?.isTextModelLoaded ?? false;
  }

  /// Unload the current model
  Future<bool> unloadModel() async {
    final backend = _backend;
    if (backend == null) return true;

    try {
      backend.unloadTextModel();
      return true;
    } catch (e) {
      _logger
          .error('Failed to unload model', metadata: {'error': e.toString()});
      return false;
    }
  }

  /// Generate text (non-streaming)
  Future<LLMGenerationResult?> generate({
    required String prompt,
    String? systemPrompt,
    int maxTokens = 512,
    double temperature = 0.7,
  }) async {
    final backend = _backend;
    if (backend == null) {
      _logger.warning('No backend set for LLM generation');
      return null;
    }

    try {
      final result = backend.generate(
        prompt,
        systemPrompt: systemPrompt,
        maxTokens: maxTokens,
        temperature: temperature,
      );

      return LLMGenerationResult(
        text: result['text'] as String? ?? '',
        tokensGenerated: result['tokens_generated'] as int? ?? 0,
        generationTimeMs: result['generation_time_ms'] as int? ?? 0,
      );
    } catch (e) {
      _logger.error('Generation failed', metadata: {'error': e.toString()});
      return null;
    }
  }

  /// Generate text with streaming.
  ///
  /// Uses non-streaming generation internally and emits result as word tokens.
  /// This provides streaming UX while the underlying native call is synchronous.
  Stream<String> generateStream({
    required String prompt,
    String? systemPrompt,
    int maxTokens = 512,
    double temperature = 0.7,
  }) async* {
    final backend = _backend;
    if (backend == null) {
      _logger.warning('No backend set for LLM streaming');
      return;
    }

    try {
      // Fall back to non-streaming generation
      final result = backend.generate(
        prompt,
        systemPrompt: systemPrompt,
        maxTokens: maxTokens,
        temperature: temperature,
      );

      final text = result['text'] as String? ?? '';
      if (text.isNotEmpty) {
        yield text;
      }
    } catch (e) {
      _logger.error('Streaming generation failed',
          metadata: {'error': e.toString()});
    }
  }

  /// Cancel ongoing generation
  void cancel() {
    _backend?.cancelTextGeneration();
  }
}

/// Result of LLM text generation
class LLMGenerationResult {
  final String text;
  final int tokensGenerated;
  final int generationTimeMs;

  LLMGenerationResult({
    required this.text,
    required this.tokensGenerated,
    required this.generationTimeMs,
  });

  double get tokensPerSecond {
    if (generationTimeMs == 0) return 0;
    return tokensGenerated / (generationTimeMs / 1000);
  }
}
