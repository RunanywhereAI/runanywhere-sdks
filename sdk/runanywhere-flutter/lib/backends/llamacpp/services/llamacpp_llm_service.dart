import 'dart:async';

import '../../../core/module_registry.dart';
import '../../../foundation/logging/sdk_logger.dart';
import '../../../native/native_backend.dart';
import '../llamacpp_error.dart';
import '../llamacpp_template_resolver.dart';

/// LlamaCpp-based Language Model service.
///
/// This is the Flutter equivalent of Swift's `LLMSwiftService`.
/// It uses the native runanywhere-core library (llamacpp backend) for LLM inference.
///
/// ## Usage
///
/// ```dart
/// final backend = NativeBackend();
/// backend.create('llamacpp'); // Use llamacpp backend from runanywhere-core
///
/// final llm = LlamaCppLLMService(backend);
/// await llm.initialize(modelPath: '/path/to/model.gguf');
///
/// final result = await llm.generate(
///   prompt: 'Hello!',
///   options: LLMGenerationOptions(maxTokens: 100),
/// );
/// print(result.text);
/// ```
class LlamaCppLLMService implements LLMService {
  final NativeBackend _backend;
  final SDKLogger _logger = SDKLogger(category: 'LlamaCppLLMService');
  String? _modelPath;
  bool _isInitialized = false;
  LLMTemplate? _currentTemplate;

  /// Create a new LlamaCpp LLM service.
  LlamaCppLLMService(this._backend);

  @override
  bool get isReady => _isInitialized && _backend.isTextModelLoaded;

  /// Get the current model name.
  String? get currentModel {
    if (_modelPath == null) return null;
    return _modelPath!.split('/').last;
  }

  @override
  Future<void> initialize({String? modelPath}) async {
    if (modelPath == null || modelPath.isEmpty || modelPath == 'default') {
      // Use default/already loaded model
      _isInitialized = true;
      return;
    }

    _modelPath = modelPath;

    // Determine template from model path
    _currentTemplate = LlamaCppTemplateResolver.determineTemplate(modelPath);

    _logger.debug('Loading model from path: $modelPath');
    _logger.debug('Template: ${_currentTemplate?.name ?? 'chatML'}');

    // Load the model through native backend
    try {
      _backend.loadTextModel(
        modelPath,
        config: {
          'template': _currentTemplate?.name ?? 'chatML',
          'context_length': 2048,
        },
      );

      // Check if model actually loaded
      if (!_backend.isTextModelLoaded) {
        throw Exception(
            'Model failed to load - native backend reports not loaded');
      }

      _logger.info('Model loaded successfully');
      _isInitialized = true;
    } catch (e) {
      _logger.error('Failed to load model: $e');
      _isInitialized = false;
      rethrow;
    }
  }

  @override
  Future<LLMGenerationResult> generate({
    required String prompt,
    required LLMGenerationOptions options,
  }) async {
    if (!isReady) {
      throw LlamaCppError.notInitialized();
    }

    // Apply system prompt to template if provided
    if (options.systemPrompt != null && _modelPath != null) {
      _currentTemplate = LlamaCppTemplateResolver.determineTemplate(
        _modelPath!,
        systemPrompt: options.systemPrompt,
      );
    }

    // Build the full prompt with context
    final fullPrompt = _buildPromptWithContext(prompt, options);

    try {
      final result = _backend.generate(
        fullPrompt,
        systemPrompt: options.systemPrompt,
        maxTokens: options.maxTokens,
        temperature: options.temperature,
      );

      var responseText = result['text'] as String? ?? '';

      // Apply stop sequences if specified
      if (options.stopSequences.isNotEmpty) {
        for (final sequence in options.stopSequences) {
          final index = responseText.indexOf(sequence);
          if (index >= 0) {
            responseText = responseText.substring(0, index);
            break;
          }
        }
      }

      // Limit to max tokens if specified (approximate)
      if (options.maxTokens > 0) {
        final tokens = responseText.split(' ');
        if (tokens.length > options.maxTokens) {
          responseText = tokens.take(options.maxTokens).join(' ');
        }
      }

      return LLMGenerationResult(text: responseText);
    } catch (e) {
      throw LlamaCppError.generationFailed(e.toString());
    }
  }

  @override
  Stream<String> generateStream({
    required String prompt,
    required LLMGenerationOptions options,
  }) async* {
    if (!isReady) {
      throw LlamaCppError.notInitialized();
    }

    // Apply system prompt to template if provided
    if (options.systemPrompt != null && _modelPath != null) {
      _currentTemplate = LlamaCppTemplateResolver.determineTemplate(
        _modelPath!,
        systemPrompt: options.systemPrompt,
      );
    }

    // For now, use batch generation and emit tokens
    // TODO: Implement true streaming when supported by native backend
    try {
      final result = await generate(prompt: prompt, options: options);

      // Simulate streaming by yielding words
      final words = result.text.split(' ');
      for (final word in words) {
        yield '$word ';
        // Small delay to simulate streaming
        await Future.delayed(const Duration(milliseconds: 10));
      }
    } catch (e) {
      throw LlamaCppError.generationFailed(e.toString());
    }
  }

  @override
  Future<void> cleanup() async {
    if (_backend.isTextModelLoaded) {
      _backend.unloadTextModel();
    }
    _isInitialized = false;
    _modelPath = null;
    _currentTemplate = null;
  }

  /// Clear conversation history.
  void clearHistory() {
    // Native backend doesn't maintain history, so this is a no-op
    // In a full implementation, we might maintain history in Dart
  }

  /// Cancel ongoing text generation.
  void cancel() {
    _backend.cancelTextGeneration();
  }

  /// Get estimated memory usage for the current model.
  Future<int> getModelMemoryUsage() async {
    if (_modelPath == null) {
      throw LlamaCppError.notInitialized();
    }

    // Estimate based on model file and context
    final memoryUsage = _backend.getMemoryUsage();

    // Add context memory (approximately 10MB per 1000 context tokens)
    const contextMemory = 2048 * 10 * 1024; // ~20MB for 2048 context

    return memoryUsage + contextMemory;
  }

  // ============================================================================
  // Private Helpers
  // ============================================================================

  String _buildPromptWithContext(String prompt, LLMGenerationOptions options) {
    // For now, just return the prompt as the native backend
    // handles context internally
    return prompt;
  }
}
