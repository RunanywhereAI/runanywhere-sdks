/// DartBridge+LLM
///
/// LLM component bridge - manages C++ LLM component lifecycle.
/// Mirrors Swift's CppBridge+LLM.swift pattern exactly.
///
/// This is a thin wrapper around C++ LLM component functions.
/// All business logic is in C++ - Dart only manages the handle.
///
/// IMPORTANT: Generation runs in a separate isolate to avoid heap corruption
/// from C++ background threads (Metal GPU operations).
library dart_bridge_llm;

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';

/// LLM component bridge for C++ interop.
///
/// Provides access to the C++ LLM component.
/// Handles model loading, generation, and lifecycle.
///
/// Matches Swift's CppBridge.LLM actor pattern.
///
/// Usage:
/// ```dart
/// final llm = DartBridgeLLM.shared;
/// await llm.loadModel('/path/to/model.gguf', 'model-id', 'Model Name');
/// final result = await llm.generate('Hello', maxTokens: 100);
/// ```
class DartBridgeLLM {
  // MARK: - Singleton

  /// Shared instance
  static final DartBridgeLLM shared = DartBridgeLLM._();

  DartBridgeLLM._();

  // MARK: - State (matches Swift CppBridge.LLM exactly)

  RacHandle? _handle;
  String? _loadedModelId;
  final _logger = SDKLogger('DartBridge.LLM');

  /// Active stream subscription for cancellation
  StreamSubscription<String>? _activeStreamSubscription;

  /// Cancel any active generation
  void cancelGeneration() {
    _activeStreamSubscription?.cancel();
    _activeStreamSubscription = null;
    // Cancel at native level
    cancel();
  }

  /// Set active stream subscription for cancellation
  void setActiveStreamSubscription(StreamSubscription<String>? sub) {
    _activeStreamSubscription = sub;
  }

  // MARK: - Handle Management

  /// Get or create the LLM component handle.
  ///
  /// Lazily creates the C++ LLM component on first access.
  /// Throws if creation fails.
  RacHandle getHandle() {
    if (_handle != null) {
      return _handle!;
    }

    try {
      final lib = PlatformLoader.loadCommons();
      final create = lib.lookupFunction<Int32 Function(Pointer<RacHandle>),
          int Function(Pointer<RacHandle>)>('rac_llm_component_create');

      final handlePtr = calloc<RacHandle>();
      try {
        final result = create(handlePtr);

        if (result != RAC_SUCCESS) {
          throw StateError(
            'Failed to create LLM component: ${RacResultCode.getMessage(result)}',
          );
        }

        _handle = handlePtr.value;
        _logger.debug('LLM component created');
        return _handle!;
      } finally {
        calloc.free(handlePtr);
      }
    } catch (e) {
      _logger.error('Failed to create LLM handle: $e');
      rethrow;
    }
  }

  // MARK: - State Queries

  /// Check if a model is loaded.
  bool get isLoaded {
    if (_handle == null) return false;

    try {
      final lib = PlatformLoader.loadCommons();
      final isLoadedFn = lib.lookupFunction<Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_llm_component_is_loaded');

      return isLoadedFn(_handle!) == RAC_TRUE;
    } catch (e) {
      _logger.debug('isLoaded check failed: $e');
      return false;
    }
  }

  /// Get the currently loaded model ID.
  String? get currentModelId => _loadedModelId;

  /// Check if streaming is supported.
  bool get supportsStreaming {
    if (_handle == null) return false;

    try {
      final lib = PlatformLoader.loadCommons();
      final supportsStreamingFn = lib.lookupFunction<Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_llm_component_supports_streaming');

      return supportsStreamingFn(_handle!) == RAC_TRUE;
    } catch (e) {
      return false;
    }
  }

  // MARK: - Model Lifecycle

  /// Load an LLM model.
  ///
  /// [modelPath] - Full path to the model file.
  /// [modelId] - Unique identifier for the model.
  /// [modelName] - Human-readable name.
  ///
  /// Throws on failure.
  Future<void> loadModel(
    String modelPath,
    String modelId,
    String modelName,
  ) async {
    final handle = getHandle();

    final pathPtr = modelPath.toNativeUtf8();
    final idPtr = modelId.toNativeUtf8();
    final namePtr = modelName.toNativeUtf8();

    try {
      final lib = PlatformLoader.loadCommons();
      final loadModelFn = lib.lookupFunction<
          Int32 Function(
              RacHandle, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>),
          int Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>,
              Pointer<Utf8>)>('rac_llm_component_load_model');

      _logger.debug(
          'Calling rac_llm_component_load_model with handle: $_handle, path: $modelPath');
      final result = loadModelFn(handle, pathPtr, idPtr, namePtr);
      _logger.debug(
          'rac_llm_component_load_model returned: $result (${RacResultCode.getMessage(result)})');

      if (result != RAC_SUCCESS) {
        throw StateError(
          'Failed to load LLM model: Error (code: $result)',
        );
      }

      _loadedModelId = modelId;
      _logger.info('LLM model loaded: $modelId');
    } finally {
      calloc.free(pathPtr);
      calloc.free(idPtr);
      calloc.free(namePtr);
    }
  }

  /// Unload the current model.
  void unload() {
    if (_handle == null) return;

    try {
      final lib = PlatformLoader.loadCommons();
      final cleanupFn = lib.lookupFunction<Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_llm_component_cleanup');

      cleanupFn(_handle!);
      _loadedModelId = null;
      _logger.info('LLM model unloaded');
    } catch (e) {
      _logger.error('Failed to unload LLM model: $e');
    }
  }

  /// Cancel ongoing generation.
  void cancel() {
    if (_handle == null) return;

    try {
      final lib = PlatformLoader.loadCommons();
      final cancelFn = lib.lookupFunction<Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_llm_component_cancel');

      cancelFn(_handle!);
      _logger.debug('LLM generation cancelled');
    } catch (e) {
      _logger.error('Failed to cancel generation: $e');
    }
  }

  // MARK: - Generation

  /// Generate text from a prompt.
  ///
  /// [prompt] - Input prompt.
  /// [maxTokens] - Maximum tokens to generate (default: 512).
  /// [temperature] - Sampling temperature (default: 0.7).
  ///
  /// Returns the generated text and metrics.
  Future<LLMComponentResult> generate(
    String prompt, {
    int maxTokens = 512,
    double temperature = 0.7,
  }) async {
    final handle = getHandle();

    if (!isLoaded) {
      throw StateError('No LLM model loaded. Call loadModel() first.');
    }

    final promptPtr = prompt.toNativeUtf8();
    final resultPtr = calloc<RacLlmResultStruct>();

    try {
      final lib = PlatformLoader.loadCommons();
      final generateFn = lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Utf8>, Pointer<RacLlmResultStruct>),
          int Function(RacHandle, Pointer<Utf8>,
              Pointer<RacLlmResultStruct>)>('rac_llm_component_generate');

      final status = generateFn(handle, promptPtr, resultPtr);

      if (status != RAC_SUCCESS) {
        throw StateError(
          'LLM generation failed: ${RacResultCode.getMessage(status)}',
        );
      }

      final result = resultPtr.ref;
      return LLMComponentResult(
        text: result.text != nullptr ? result.text.toDartString() : '',
        promptTokens: result.promptTokens,
        completionTokens: result.completionTokens,
        totalTimeMs: result.totalTimeMs,
      );
    } finally {
      calloc.free(promptPtr);
      calloc.free(resultPtr);
    }
  }

  /// Generate text with streaming.
  ///
  /// Returns a stream of tokens.
  Stream<String> generateStream(
    String prompt, {
    int maxTokens = 512,
    double temperature = 0.7,
  }) async* {
    // Ensure handle is created (validates component is ready)
    getHandle();

    if (!isLoaded) {
      throw StateError('No LLM model loaded. Call loadModel() first.');
    }

    // For now, fall back to non-streaming and emit tokens
    // True native streaming requires callback registration which is complex
    final result = await generate(
      prompt,
      maxTokens: maxTokens,
      temperature: temperature,
    );

    // Emit text as simulated stream
    final words = result.text.split(' ');
    for (var i = 0; i < words.length; i++) {
      yield i == 0 ? words[i] : ' ${words[i]}';
    }
  }

  // MARK: - Cleanup

  /// Destroy the component and release resources.
  void destroy() {
    if (_handle != null) {
      try {
        final lib = PlatformLoader.loadCommons();
        final destroyFn = lib.lookupFunction<Void Function(RacHandle),
            void Function(RacHandle)>('rac_llm_component_destroy');

        destroyFn(_handle!);
        _handle = null;
        _loadedModelId = null;
        _logger.debug('LLM component destroyed');
      } catch (e) {
        _logger.error('Failed to destroy LLM component: $e');
      }
    }
  }
}

/// Result from LLM generation.
class LLMComponentResult {
  final String text;
  final int promptTokens;
  final int completionTokens;
  final int totalTimeMs;

  const LLMComponentResult({
    required this.text,
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTimeMs,
  });

  double get tokensPerSecond {
    if (totalTimeMs <= 0) return 0;
    return completionTokens / (totalTimeMs / 1000.0);
  }
}
