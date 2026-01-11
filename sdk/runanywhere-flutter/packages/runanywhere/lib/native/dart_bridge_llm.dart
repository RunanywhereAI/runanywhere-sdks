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
    unawaited(_activeStreamSubscription?.cancel());
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
  ///
  /// IMPORTANT: This runs in a separate isolate to prevent heap corruption
  /// from C++ Metal/GPU background threads.
  Future<LLMComponentResult> generate(
    String prompt, {
    int maxTokens = 512,
    double temperature = 0.7,
  }) async {
    final handle = getHandle();

    if (!isLoaded) {
      throw StateError('No LLM model loaded. Call loadModel() first.');
    }

    // Run FFI call in a separate isolate to avoid heap corruption
    // from C++ background threads (Metal GPU operations)
    final handleAddress = handle.address;
    final tokens = maxTokens;
    final temp = temperature;

    final result = await Isolate.run(() {
      return _generateInIsolate(handleAddress, prompt, tokens, temp);
    });

    if (result.error != null) {
      throw StateError(result.error!);
    }

    return LLMComponentResult(
      text: result.text ?? '',
      promptTokens: result.promptTokens,
      completionTokens: result.completionTokens,
      totalTimeMs: result.totalTimeMs,
    );
  }

  /// Generate text with streaming.
  ///
  /// Returns a stream of tokens as they are generated.
  /// Uses native C++ streaming via an isolate with ReceivePort for safe
  /// communication between the FFI callbacks and the main isolate.
  Stream<String> generateStream(
    String prompt, {
    int maxTokens = 512,
    double temperature = 0.7,
  }) {
    final handle = getHandle();

    if (!isLoaded) {
      throw StateError('No LLM model loaded. Call loadModel() first.');
    }

    // Create stream controller for emitting tokens
    final controller = StreamController<String>();

    // Start streaming generation asynchronously (fire-and-forget, errors are sent to controller)
    unawaited(_startStreamingGeneration(
      handle.address,
      prompt,
      maxTokens,
      temperature,
      controller,
    ));

    return controller.stream;
  }

  /// Start the streaming generation using isolate with ReceivePort.
  Future<void> _startStreamingGeneration(
    int handleAddress,
    String prompt,
    int maxTokens,
    double temperature,
    StreamController<String> controller,
  ) async {
    // Create a ReceivePort to receive tokens from the isolate
    final receivePort = ReceivePort();

    // Listen for messages from the isolate
    receivePort.listen((message) {
      if (controller.isClosed) return;

      if (message is String) {
        if (message == '__DONE__') {
          unawaited(controller.close());
          receivePort.close();
        } else if (message.startsWith('__ERROR__:')) {
          controller.addError(StateError(message.substring(10)));
          unawaited(controller.close());
          receivePort.close();
        } else {
          // It's a token
          controller.add(message);
        }
      }
    });

    // Run the streaming generation in an isolate
    try {
      await Isolate.spawn(
        _streamingIsolateEntry,
        _StreamingParams(
          handleAddress: handleAddress,
          prompt: prompt,
          maxTokens: maxTokens,
          temperature: temperature,
          sendPort: receivePort.sendPort,
        ),
      );
    } catch (e) {
      controller.addError(e);
      await controller.close();
      receivePort.close();
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

// =============================================================================
// Isolate Helper for FFI Generation
// =============================================================================

/// Result container for isolate communication (must be simple types).
class _IsolateGenerationResult {
  final String? text;
  final int promptTokens;
  final int completionTokens;
  final int totalTimeMs;
  final String? error;

  const _IsolateGenerationResult({
    this.text,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTimeMs = 0,
    this.error,
  });
}

// =============================================================================
// Streaming Generation via Isolate
// =============================================================================

/// Parameters for streaming generation isolate.
class _StreamingParams {
  final int handleAddress;
  final String prompt;
  final int maxTokens;
  final double temperature;
  final SendPort sendPort;

  const _StreamingParams({
    required this.handleAddress,
    required this.prompt,
    required this.maxTokens,
    required this.temperature,
    required this.sendPort,
  });
}

/// Global SendPort for static callbacks (set before generation starts).
/// This is needed because Pointer.fromFunction can only call static/top-level
/// functions that can't capture variables.
SendPort? _globalSendPort;

/// Token callback - called from C++ for each token.
/// Must be static for Pointer.fromFunction.
@pragma('vm:entry-point')
int _tokenCallback(Pointer<Utf8> token, Pointer<Void> userData) {
  if (token != nullptr && _globalSendPort != null) {
    final tokenStr = token.toDartString();
    _globalSendPort!.send(tokenStr);
  }
  return RAC_TRUE; // Continue generation
}

/// Complete callback - called from C++ when generation finishes.
@pragma('vm:entry-point')
void _completeCallback(
    Pointer<RacLlmResultStruct> result, Pointer<Void> userData) {
  _globalSendPort?.send('__DONE__');
}

/// Error callback - called from C++ on error.
@pragma('vm:entry-point')
void _errorCallback(
    int errorCode, Pointer<Utf8> errorMessage, Pointer<Void> userData) {
  final message =
      errorMessage != nullptr ? errorMessage.toDartString() : 'Unknown error';
  _globalSendPort?.send('__ERROR__:$message (code: $errorCode)');
}

/// Isolate entry point for streaming generation.
@pragma('vm:entry-point')
void _streamingIsolateEntry(_StreamingParams params) {
  // Set global SendPort for callbacks
  _globalSendPort = params.sendPort;

  final handle = Pointer<Void>.fromAddress(params.handleAddress);
  final promptPtr = params.prompt.toNativeUtf8();
  final optionsPtr = calloc<RacLlmOptionsStruct>();

  try {
    // Set options
    optionsPtr.ref.maxTokens = params.maxTokens;
    optionsPtr.ref.temperature = params.temperature;
    optionsPtr.ref.topP = 1.0;
    optionsPtr.ref.stopSequences = nullptr;
    optionsPtr.ref.numStopSequences = 0;
    optionsPtr.ref.streamingEnabled = RAC_TRUE;
    optionsPtr.ref.systemPrompt = nullptr;

    final lib = PlatformLoader.loadCommons();

    // Get callback function pointers using Pointer.fromFunction
    final tokenCallbackPtr =
        Pointer.fromFunction<Int32 Function(Pointer<Utf8>, Pointer<Void>)>(
            _tokenCallback, 0);
    final completeCallbackPtr = Pointer.fromFunction<
        Void Function(
            Pointer<RacLlmResultStruct>, Pointer<Void>)>(_completeCallback);
    final errorCallbackPtr = Pointer.fromFunction<
        Void Function(Int32, Pointer<Utf8>, Pointer<Void>)>(_errorCallback);

    final generateStreamFn = lib.lookupFunction<
        Int32 Function(
          RacHandle,
          Pointer<Utf8>,
          Pointer<RacLlmOptionsStruct>,
          Pointer<NativeFunction<Int32 Function(Pointer<Utf8>, Pointer<Void>)>>,
          Pointer<
              NativeFunction<
                  Void Function(Pointer<RacLlmResultStruct>, Pointer<Void>)>>,
          Pointer<
              NativeFunction<
                  Void Function(Int32, Pointer<Utf8>, Pointer<Void>)>>,
          Pointer<Void>,
        ),
        int Function(
          RacHandle,
          Pointer<Utf8>,
          Pointer<RacLlmOptionsStruct>,
          Pointer<NativeFunction<Int32 Function(Pointer<Utf8>, Pointer<Void>)>>,
          Pointer<
              NativeFunction<
                  Void Function(Pointer<RacLlmResultStruct>, Pointer<Void>)>>,
          Pointer<
              NativeFunction<
                  Void Function(Int32, Pointer<Utf8>, Pointer<Void>)>>,
          Pointer<Void>,
        )>('rac_llm_component_generate_stream');

    final status = generateStreamFn(
      handle,
      promptPtr,
      optionsPtr,
      tokenCallbackPtr,
      completeCallbackPtr,
      errorCallbackPtr,
      nullptr,
    );

    if (status != RAC_SUCCESS) {
      params.sendPort.send(
          '__ERROR__:Failed to start streaming: ${RacResultCode.getMessage(status)}');
    }
  } catch (e) {
    params.sendPort.send('__ERROR__:$e');
  } finally {
    calloc.free(promptPtr);
    calloc.free(optionsPtr);
    _globalSendPort = null;
  }
}

// =============================================================================
// Isolate Helper for Non-Streaming Generation
// =============================================================================

/// Run LLM generation in an isolate.
///
/// This function is called from Isolate.run() and performs the actual FFI call.
/// Running in a separate isolate prevents heap corruption from C++ background
/// threads (Metal GPU operations on iOS).
_IsolateGenerationResult _generateInIsolate(
  int handleAddress,
  String prompt,
  int maxTokens,
  double temperature,
) {
  final handle = Pointer<Void>.fromAddress(handleAddress);
  final promptPtr = prompt.toNativeUtf8();
  final optionsPtr = calloc<RacLlmOptionsStruct>();
  final resultPtr = calloc<RacLlmResultStruct>();

  try {
    // Set options - matching C++ rac_llm_options_t
    optionsPtr.ref.maxTokens = maxTokens;
    optionsPtr.ref.temperature = temperature;
    optionsPtr.ref.topP = 1.0;
    optionsPtr.ref.stopSequences = nullptr;
    optionsPtr.ref.numStopSequences = 0;
    optionsPtr.ref.streamingEnabled = RAC_FALSE;
    optionsPtr.ref.systemPrompt = nullptr;

    final lib = PlatformLoader.loadCommons();
    final generateFn = lib.lookupFunction<
        Int32 Function(RacHandle, Pointer<Utf8>, Pointer<RacLlmOptionsStruct>,
            Pointer<RacLlmResultStruct>),
        int Function(RacHandle, Pointer<Utf8>, Pointer<RacLlmOptionsStruct>,
            Pointer<RacLlmResultStruct>)>('rac_llm_component_generate');

    final status = generateFn(handle, promptPtr, optionsPtr, resultPtr);

    if (status != RAC_SUCCESS) {
      return _IsolateGenerationResult(
        error: 'LLM generation failed: ${RacResultCode.getMessage(status)}',
      );
    }

    final result = resultPtr.ref;
    final text = result.text != nullptr ? result.text.toDartString() : '';

    return _IsolateGenerationResult(
      text: text,
      promptTokens: result.promptTokens,
      completionTokens: result.completionTokens,
      totalTimeMs: result.totalTimeMs,
    );
  } catch (e) {
    return _IsolateGenerationResult(error: 'Generation exception: $e');
  } finally {
    calloc.free(promptPtr);
    calloc.free(optionsPtr);
    calloc.free(resultPtr);
  }
}
