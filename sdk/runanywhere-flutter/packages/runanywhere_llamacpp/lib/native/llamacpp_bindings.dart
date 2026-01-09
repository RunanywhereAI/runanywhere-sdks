import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';

/// LlamaCPP backend FFI bindings.
///
/// Maps to rac_llm_llamacpp.h C API.
/// Provides direct access to native LlamaCPP functions.
class LlamaCppBindings {
  final DynamicLibrary _lib;

  // Cached function pointers
  RacBackendLlamacppRegisterDart? _register;
  RacBackendLlamacppUnregisterDart? _unregister;
  RacLlmLlamacppCreateDart? _create;
  RacLlmLlamacppLoadModelDart? _loadModel;
  RacLlmLlamacppUnloadModelDart? _unloadModel;
  RacLlmLlamacppIsModelLoadedDart? _isModelLoaded;
  RacLlmLlamacppGenerateDart? _generate;
  RacLlmLlamacppGenerateStreamDart? _generateStream;
  RacLlmLlamacppCancelDart? _cancel;
  RacLlmLlamacppDestroyDart? _destroy;

  // For streaming callback management
  static final Map<int, StreamController<LlamaCppStreamToken>>
      _streamControllers = {};
  static int _streamIdCounter = 0;

  /// Create bindings using the LlamaCPP library.
  LlamaCppBindings() : _lib = PlatformLoader.loadLlamaCpp() {
    _bindFunctions();
  }

  /// Create bindings with a specific library (for testing).
  LlamaCppBindings.withLibrary(this._lib) {
    _bindFunctions();
  }

  void _bindFunctions() {
    try {
      _register = _lib.lookupFunction<RacBackendLlamacppRegisterNative,
          RacBackendLlamacppRegisterDart>('rac_backend_llamacpp_register');
    } catch (_) {
      // Function might not be available
    }

    try {
      _unregister = _lib.lookupFunction<RacBackendLlamacppUnregisterNative,
          RacBackendLlamacppUnregisterDart>('rac_backend_llamacpp_unregister');
    } catch (_) {}

    try {
      _create = _lib.lookupFunction<RacLlmLlamacppCreateNative,
          RacLlmLlamacppCreateDart>('rac_llm_llamacpp_create');
    } catch (_) {}

    try {
      _loadModel = _lib.lookupFunction<RacLlmLlamacppLoadModelNative,
          RacLlmLlamacppLoadModelDart>('rac_llm_llamacpp_load_model');
    } catch (_) {}

    try {
      _unloadModel = _lib.lookupFunction<RacLlmLlamacppUnloadModelNative,
          RacLlmLlamacppUnloadModelDart>('rac_llm_llamacpp_unload_model');
    } catch (_) {}

    try {
      _isModelLoaded = _lib.lookupFunction<RacLlmLlamacppIsModelLoadedNative,
          RacLlmLlamacppIsModelLoadedDart>('rac_llm_llamacpp_is_model_loaded');
    } catch (_) {}

    try {
      _generate = _lib.lookupFunction<RacLlmLlamacppGenerateNative,
          RacLlmLlamacppGenerateDart>('rac_llm_llamacpp_generate');
    } catch (_) {}

    try {
      _generateStream = _lib.lookupFunction<RacLlmLlamacppGenerateStreamNative,
          RacLlmLlamacppGenerateStreamDart>('rac_llm_llamacpp_generate_stream');
    } catch (_) {}

    try {
      _cancel = _lib.lookupFunction<RacLlmLlamacppCancelNative,
          RacLlmLlamacppCancelDart>('rac_llm_llamacpp_cancel');
    } catch (_) {}

    try {
      _destroy = _lib.lookupFunction<RacLlmLlamacppDestroyNative,
          RacLlmLlamacppDestroyDart>('rac_llm_llamacpp_destroy');
    } catch (_) {}
  }

  /// Check if bindings are available.
  bool get isAvailable => _create != null;

  // ============================================================================
  // Backend Registration
  // ============================================================================

  /// Register the LlamaCPP backend with the commons module registry.
  ///
  /// Returns RAC_SUCCESS on success, or an error code.
  int register() {
    if (_register == null) {
      return RacResultCode.errorNotSupported;
    }
    return _register!();
  }

  /// Unregister the LlamaCPP backend.
  int unregister() {
    if (_unregister == null) {
      return RacResultCode.errorNotSupported;
    }
    return _unregister!();
  }

  // ============================================================================
  // Service Creation
  // ============================================================================

  /// Create a LlamaCPP LLM service.
  ///
  /// [modelPath] - Path to the GGUF model file.
  /// [config] - Optional configuration.
  ///
  /// Returns a handle to the service, or null on failure.
  RacHandle? create(String modelPath, {LlamaCppConfig? config}) {
    if (_create == null) {
      return null;
    }

    final pathPtr = modelPath.toNativeUtf8();
    final handlePtr = calloc<RacHandle>();
    final configPtr = config != null ? _allocConfig(config) : nullptr;

    try {
      final result = _create!(pathPtr, configPtr, handlePtr);

      if (result != RAC_SUCCESS) {
        return null;
      }

      return handlePtr.value;
    } finally {
      calloc.free(pathPtr);
      calloc.free(handlePtr);
      if (configPtr != nullptr) {
        calloc.free(configPtr);
      }
    }
  }

  /// Load a model into an existing service.
  int loadModel(RacHandle handle, String modelPath, {LlamaCppConfig? config}) {
    if (_loadModel == null) {
      return RacResultCode.errorNotSupported;
    }

    final pathPtr = modelPath.toNativeUtf8();
    final configPtr = config != null ? _allocConfig(config) : nullptr;

    try {
      return _loadModel!(handle, pathPtr, configPtr);
    } finally {
      calloc.free(pathPtr);
      if (configPtr != nullptr) {
        calloc.free(configPtr);
      }
    }
  }

  /// Unload the current model.
  int unloadModel(RacHandle handle) {
    if (_unloadModel == null) {
      return RacResultCode.errorNotSupported;
    }
    return _unloadModel!(handle);
  }

  /// Check if a model is loaded.
  bool isModelLoaded(RacHandle handle) {
    if (_isModelLoaded == null) {
      return false;
    }
    return _isModelLoaded!(handle) == RAC_TRUE;
  }

  // ============================================================================
  // Generation
  // ============================================================================

  /// Generate text (non-streaming).
  ///
  /// [handle] - Service handle.
  /// [prompt] - Input prompt.
  /// [options] - Generation options.
  ///
  /// Returns the generation result, or null on failure.
  LlamaCppResult? generate(
    RacHandle handle,
    String prompt, {
    LlamaCppOptions? options,
  }) {
    if (_generate == null) {
      return null;
    }

    final promptPtr = prompt.toNativeUtf8();
    final optionsPtr = options != null ? _allocOptions(options) : nullptr;
    final resultPtr = calloc<RacLlmResultStruct>();

    try {
      final status =
          _generate!(handle, promptPtr, optionsPtr, resultPtr.cast());

      if (status != RAC_SUCCESS) {
        return null;
      }

      final result = resultPtr.ref;
      return LlamaCppResult(
        text: result.text != nullptr ? result.text.toDartString() : '',
        promptTokens: result.promptTokens,
        completionTokens: result.completionTokens,
        totalTokens: result.totalTokens,
        timeToFirstTokenMs: result.timeToFirstTokenMs,
        totalTimeMs: result.totalTimeMs,
        tokensPerSecond: result.tokensPerSecond,
      );
    } finally {
      calloc.free(promptPtr);
      if (optionsPtr != nullptr) {
        calloc.free(optionsPtr);
      }
      calloc.free(resultPtr);
    }
  }

  /// Generate text with streaming support.
  ///
  /// [handle] - Service handle.
  /// [prompt] - Input prompt.
  /// [options] - Generation options (must have streaming = true).
  ///
  /// Returns a stream of tokens as they are generated.
  Stream<LlamaCppStreamToken> generateStream(
    RacHandle handle,
    String prompt, {
    LlamaCppOptions? options,
  }) {
    if (_generateStream == null) {
      throw UnsupportedError('Streaming generation not available');
    }

    // Create stream controller for this generation
    final streamId = _streamIdCounter++;
    final controller = StreamController<LlamaCppStreamToken>();
    _streamControllers[streamId] = controller;

    final promptPtr = prompt.toNativeUtf8();
    final effectiveOptions = options ?? const LlamaCppOptions(streaming: true);
    final optionsPtr =
        _allocOptions(effectiveOptions.copyWith(streaming: true));

    // Start generation in background
    _startStreamingGeneration(
      handle,
      promptPtr,
      optionsPtr,
      streamId,
      controller,
    );

    controller.onCancel = () {
      // Cancel native generation when stream is cancelled
      cancel(handle);
      _streamControllers.remove(streamId);
    };

    return controller.stream;
  }

  Future<void> _startStreamingGeneration(
    RacHandle handle,
    Pointer<Utf8> promptPtr,
    Pointer<Void> optionsPtr,
    int streamId,
    StreamController<LlamaCppStreamToken> controller,
  ) async {
    // ReceivePort is prepared for future native callback integration.
    // Currently unused as we use a word-by-word emission workaround.
    final receivePort = ReceivePort();

    // Listener is set up for future native streaming callback support
    receivePort.listen((message) {
      if (message is Map) {
        final type = message['type'] as String?;
        if (type == 'token') {
          final token = message['token'] as String;
          final index = message['index'] as int? ?? 0;
          controller.add(LlamaCppStreamToken(
            text: token,
            tokenIndex: index,
            isFirst: index == 0,
            isFinal: false,
          ));
        } else if (type == 'done') {
          final promptTokens = message['promptTokens'] as int? ?? 0;
          final completionTokens = message['completionTokens'] as int? ?? 0;
          final totalTimeMs = message['totalTimeMs'] as int? ?? 0;
          controller.add(LlamaCppStreamToken(
            text: '',
            tokenIndex: completionTokens,
            isFirst: false,
            isFinal: true,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            totalTimeMs: totalTimeMs,
          ));
          controller.close();
          _streamControllers.remove(streamId);
          receivePort.close();
        } else if (type == 'error') {
          final errorMsg = message['message'] as String? ?? 'Unknown error';
          controller.addError(Exception(errorMsg));
          controller.close();
          _streamControllers.remove(streamId);
          receivePort.close();
        }
      }
    });

    // Native streaming via C callbacks is complex in Dart FFI.
    // We use a practical workaround: call the non-streaming generate function
    // and emit the result as a stream of word-sized tokens.
    // This provides streaming UX while the underlying native call is synchronous.
    //
    // A true native streaming implementation would require:
    // 1. NativeCallable from Dart FFI for the token callback
    // 2. Proper thread safety between the C++ generation thread and Dart isolate
    // 3. Memory management for callback data
    try {
      final resultPtr = calloc<RacLlmResultStruct>();

      if (_generate != null) {
        final status =
            _generate!(handle, promptPtr, optionsPtr, resultPtr.cast());

        if (status == RAC_SUCCESS) {
          final result = resultPtr.ref;
          final text = result.text != nullptr ? result.text.toDartString() : '';

          // Emit text as stream of word-sized tokens
          // This provides a smooth streaming experience to the user
          final words = text.split(' ');
          for (var i = 0; i < words.length; i++) {
            final word = i == 0 ? words[i] : ' ${words[i]}';
            controller.add(LlamaCppStreamToken(
              text: word,
              tokenIndex: i,
              isFirst: i == 0,
              isFinal: false,
            ));
            // Small delay between words for streaming effect
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }

          // Emit final token with generation stats
          controller.add(LlamaCppStreamToken(
            text: '',
            tokenIndex: words.length,
            isFirst: false,
            isFinal: true,
            promptTokens: result.promptTokens,
            completionTokens: result.completionTokens,
            totalTimeMs: result.totalTimeMs,
          ));
        } else {
          controller
              .addError(Exception('Generation failed with code: $status'));
        }
      } else {
        controller.addError(Exception('Generate function not available'));
      }

      calloc.free(resultPtr);
    } catch (e) {
      controller.addError(e);
    } finally {
      calloc.free(promptPtr);
      calloc.free(optionsPtr);
      if (!controller.isClosed) {
        controller.close();
      }
      _streamControllers.remove(streamId);
      receivePort.close();
    }
  }

  /// Cancel ongoing generation.
  void cancel(RacHandle handle) {
    if (_cancel == null) return;
    _cancel!(handle);
  }

  /// Destroy a service and release resources.
  void destroy(RacHandle handle) {
    if (_destroy == null) return;
    _destroy!(handle);
  }

  // ============================================================================
  // Helper Methods
  // ============================================================================

  Pointer<Void> _allocConfig(LlamaCppConfig config) {
    final ptr = calloc<RacLlmLlamacppConfigStruct>();
    ptr.ref.contextSize = config.contextSize;
    ptr.ref.numThreads = config.numThreads;
    ptr.ref.gpuLayers = config.gpuLayers;
    ptr.ref.batchSize = config.batchSize;
    return ptr.cast();
  }

  Pointer<Void> _allocOptions(LlamaCppOptions options) {
    final ptr = calloc<RacLlmOptionsStruct>();
    ptr.ref.maxTokens = options.maxTokens;
    ptr.ref.temperature = options.temperature;
    ptr.ref.topP = options.topP;
    ptr.ref.streamingEnabled = options.streaming ? RAC_TRUE : RAC_FALSE;
    ptr.ref.systemPrompt = options.systemPrompt?.toNativeUtf8() ?? nullptr;
    return ptr.cast();
  }
}

// =============================================================================
// Configuration and Result Types
// =============================================================================

/// LlamaCPP-specific configuration.
class LlamaCppConfig {
  /// Context size (0 = auto-detect from model).
  final int contextSize;

  /// Number of threads (0 = auto-detect).
  final int numThreads;

  /// Number of layers to offload to GPU (-1 = all).
  final int gpuLayers;

  /// Batch size for prompt processing.
  final int batchSize;

  const LlamaCppConfig({
    this.contextSize = 0,
    this.numThreads = 0,
    this.gpuLayers = -1,
    this.batchSize = 512,
  });

  static const LlamaCppConfig defaults = LlamaCppConfig();
}

/// LlamaCPP generation options.
class LlamaCppOptions {
  /// Maximum tokens to generate.
  final int maxTokens;

  /// Temperature for sampling (0.0 - 2.0).
  final double temperature;

  /// Top-p sampling parameter.
  final double topP;

  /// System prompt.
  final String? systemPrompt;

  /// Enable streaming mode.
  final bool streaming;

  /// Stop sequences.
  final List<String>? stopSequences;

  const LlamaCppOptions({
    this.maxTokens = 512,
    this.temperature = 0.7,
    this.topP = 1.0,
    this.systemPrompt,
    this.streaming = false,
    this.stopSequences,
  });

  static const LlamaCppOptions defaults = LlamaCppOptions();

  /// Create a copy with modified fields.
  LlamaCppOptions copyWith({
    int? maxTokens,
    double? temperature,
    double? topP,
    String? systemPrompt,
    bool? streaming,
    List<String>? stopSequences,
  }) {
    return LlamaCppOptions(
      maxTokens: maxTokens ?? this.maxTokens,
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      streaming: streaming ?? this.streaming,
      stopSequences: stopSequences ?? this.stopSequences,
    );
  }
}

/// LlamaCPP generation result.
class LlamaCppResult {
  /// Generated text.
  final String text;

  /// Number of tokens in prompt.
  final int promptTokens;

  /// Number of tokens generated.
  final int completionTokens;

  /// Total tokens (prompt + completion).
  final int totalTokens;

  /// Time to first token in milliseconds.
  final int timeToFirstTokenMs;

  /// Total generation time in milliseconds.
  final int totalTimeMs;

  /// Tokens per second.
  final double tokensPerSecond;

  const LlamaCppResult({
    required this.text,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTokens = 0,
    this.timeToFirstTokenMs = 0,
    this.totalTimeMs = 0,
    this.tokensPerSecond = 0,
  });
}

/// A single token from streaming generation.
class LlamaCppStreamToken {
  /// The token text.
  final String text;

  /// Index of this token in the sequence.
  final int tokenIndex;

  /// Whether this is the first token.
  final bool isFirst;

  /// Whether this is the final token (generation complete).
  final bool isFinal;

  /// Prompt tokens (only set on final token).
  final int promptTokens;

  /// Completion tokens (only set on final token).
  final int completionTokens;

  /// Total generation time in ms (only set on final token).
  final int totalTimeMs;

  const LlamaCppStreamToken({
    required this.text,
    required this.tokenIndex,
    required this.isFirst,
    required this.isFinal,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTimeMs = 0,
  });
}
