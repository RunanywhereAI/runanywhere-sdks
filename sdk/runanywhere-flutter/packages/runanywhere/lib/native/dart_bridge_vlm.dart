/// DartBridge+VLM
///
/// VLM component bridge - manages C++ VLM component lifecycle.
/// Mirrors Swift's CppBridge+VLM.swift pattern exactly.
///
/// This is a thin wrapper around C++ VLM component functions.
/// All business logic is in C++ - Dart only manages the handle.
///
/// STREAMING ARCHITECTURE:
/// Streaming runs in a background isolate to prevent ANR (Application Not Responding).
/// Token callbacks in the background isolate send messages to the main isolate via a SendPort.
library dart_bridge_vlm;

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/sdk_events.pb.dart' as sdk_events_pb;
import 'package:runanywhere/generated/vlm_options.pb.dart'
    show VLMGenerationOptions, VLMImage, VLMResult;
import 'package:runanywhere/native/dart_bridge_proto_utils.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';

/// VLM component bridge for C++ interop.
///
/// Provides access to the C++ VLM component.
/// Handles model loading, image processing, and lifecycle.
///
/// Matches Swift's CppBridge.VLM actor pattern.
///
/// Usage:
/// ```dart
/// final vlm = DartBridgeVLM.shared;
/// await vlm.loadModel('/path/to/model.gguf', '/path/to/mmproj.gguf', 'model-id', 'Model Name');
/// final result = await vlm.processImage(...);
/// ```
class DartBridgeVLM {
  // MARK: - Singleton

  /// Shared instance
  static final DartBridgeVLM shared = DartBridgeVLM._();

  DartBridgeVLM._();

  // MARK: - State (matches Swift CppBridge.VLM exactly)

  RacHandle? _handle;
  RacHandle? _serviceHandle;
  String? _loadedModelId;
  String? _loadedModelPath;
  String? _loadedMmprojPath;
  final _logger = SDKLogger('DartBridge.VLM');

  // MARK: - Handle Management

  /// Get or create the VLM component handle.
  ///
  /// Lazily creates the C++ VLM component on first access.
  /// Throws if creation fails.
  RacHandle getHandle() {
    if (_handle != null) {
      return _handle!;
    }

    try {
      final lib = PlatformLoader.loadCommons();
      final create = lib.lookupFunction<Int32 Function(Pointer<RacHandle>),
          int Function(Pointer<RacHandle>)>('rac_vlm_component_create');

      final handlePtr = calloc<RacHandle>();
      try {
        final result = create(handlePtr);

        if (result != RAC_SUCCESS) {
          throw StateError(
            'Failed to create VLM component: ${RacResultCode.getMessage(result)}',
          );
        }

        _handle = handlePtr.value;
        _logger.debug('VLM component created');
        return _handle!;
      } finally {
        calloc.free(handlePtr);
      }
    } catch (e) {
      _logger.error('Failed to create VLM handle: $e');
      rethrow;
    }
  }

  // MARK: - State Queries

  /// Check if a model is loaded.
  bool get isLoaded {
    if (_serviceHandle != null) return true;
    if (_handle == null) return false;

    try {
      final lib = PlatformLoader.loadCommons();
      final isLoadedFn = lib.lookupFunction<Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_vlm_component_is_loaded');

      return isLoadedFn(_handle!) == RAC_TRUE;
    } catch (e) {
      _logger.debug('isLoaded check failed: $e');
      return false;
    }
  }

  /// Get the currently loaded model ID.
  String? get currentModelId => _loadedModelId;

  /// Get the currently loaded model path.
  String? get currentModelPath => _loadedModelPath;

  /// Get the currently loaded mmproj path.
  String? get currentMmprojPath => _loadedMmprojPath;

  /// Check if streaming is supported.
  bool get supportsStreaming {
    if (_handle == null) return false;

    try {
      final lib = PlatformLoader.loadCommons();
      final supportsStreamingFn = lib.lookupFunction<Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_vlm_component_supports_streaming');

      return supportsStreamingFn(_handle!) == RAC_TRUE;
    } catch (e) {
      return false;
    }
  }

  // MARK: - Model Lifecycle

  /// Load a VLM model.
  ///
  /// [modelPath] - Full path to the main model file (LLM weights).
  /// [mmprojPath] - Path to vision projector (required for llama.cpp, null for MLX).
  /// [modelId] - Unique identifier for the model.
  /// [modelName] - Human-readable name.
  ///
  /// Throws on failure.
  Future<void> loadModel(
    String modelPath,
    String? mmprojPath,
    String modelId,
    String modelName,
  ) async {
    _createAndInitializeService(modelId, modelPath, mmprojPath);
    _loadedModelId = modelId;
    _loadedModelPath = modelPath;
    _loadedMmprojPath = mmprojPath;
    _logger.info('VLM service loaded: $modelId ($modelName)');
  }

  /// Load a VLM model by ID.
  ///
  /// The C++ layer resolves the model path from the global registry.
  /// Matches Swift: `CppBridge.VLM.loadModelById(_:)`
  ///
  /// [modelId] - Unique identifier for the model (must be registered).
  ///
  /// Throws on failure.
  Future<void> loadModelById(String modelId) async {
    final handle = getHandle();

    final idPtr = modelId.toNativeUtf8();

    try {
      final lib = PlatformLoader.loadCommons();
      final loadByIdFn = lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Utf8>),
          int Function(
              RacHandle, Pointer<Utf8>)>('rac_vlm_component_load_model_by_id');

      _logger.debug('Calling rac_vlm_component_load_model_by_id: $modelId');
      final result = loadByIdFn(handle, idPtr);
      _logger.debug(
          'rac_vlm_component_load_model_by_id returned: $result (${RacResultCode.getMessage(result)})');

      if (result != RAC_SUCCESS) {
        throw StateError(
          'Failed to load VLM model by ID: Error (code: $result)',
        );
      }

      _loadedModelId = modelId;
      _logger.info('VLM model loaded by ID: $modelId');
    } finally {
      calloc.free(idPtr);
    }
  }

  /// Unload the current model.
  void unload() {
    try {
      final serviceHandle = _serviceHandle;
      if (serviceHandle != null) {
        RacNative.bindings.rac_vlm_destroy?.call(serviceHandle);
      }
      _serviceHandle = null;
      _loadedModelId = null;
      _loadedModelPath = null;
      _loadedMmprojPath = null;
      if (_handle != null) {
        final lib = PlatformLoader.loadCommons();
        final cleanupFn = lib.lookupFunction<Int32 Function(RacHandle),
            int Function(RacHandle)>('rac_vlm_component_cleanup');

        cleanupFn(_handle!);
      }
      _logger.info('VLM model unloaded');
    } catch (e) {
      _logger.error('Failed to unload VLM model: $e');
    }
  }

  /// Cancel ongoing image processing.
  void cancel() {
    final serviceHandle = _serviceHandle;
    if (serviceHandle != null) {
      final rc = RacNative.bindings.rac_vlm_cancel_proto?.call(serviceHandle);
      if (rc == RAC_SUCCESS) {
        _logger.debug('VLM service processing cancelled');
        return;
      }
    }
    if (_handle == null) return;

    try {
      final lib = PlatformLoader.loadCommons();
      final cancelFn = lib.lookupFunction<Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_vlm_component_cancel');

      cancelFn(_handle!);
      _logger.debug('VLM processing cancelled');
    } catch (e) {
      _logger.error('Failed to cancel processing: $e');
    }
  }

  // MARK: - Image Processing (Non-Streaming)

  VLMResult processImageProto(
    VLMImage image,
    VLMGenerationOptions options,
  ) {
    final handle = _requireServiceHandle();
    final fn = RacNative.bindings.rac_vlm_process_proto;
    if (fn == null) {
      throw UnsupportedError('rac_vlm_process_proto is unavailable');
    }

    final imageBytes = image.writeToBuffer();
    final optionsBytes = options.writeToBuffer();
    final imagePtr = DartBridgeProtoUtils.copyBytes(imageBytes);
    final optionsPtr = DartBridgeProtoUtils.copyBytes(optionsBytes);
    final out = calloc<RacProtoBuffer>();
    final bindings = RacNative.bindings;

    try {
      bindings.rac_proto_buffer_init(out);
      final code = fn(
        handle,
        imagePtr,
        imageBytes.length,
        optionsPtr,
        optionsBytes.length,
        out,
      );
      DartBridgeProtoUtils.ensureSuccess(out, code, 'rac_vlm_process_proto');
      return DartBridgeProtoUtils.decodeBuffer(out, VLMResult.fromBuffer);
    } finally {
      bindings.rac_proto_buffer_free(out);
      calloc.free(imagePtr);
      calloc.free(optionsPtr);
      calloc.free(out);
    }
  }

  VlmProtoStreamingResult processImageStreamProto(
    VLMImage image,
    VLMGenerationOptions options,
  ) {
    final handle = _requireServiceHandle();
    final fn = RacNative.bindings.rac_vlm_process_stream_proto;
    if (fn == null) {
      throw UnsupportedError('rac_vlm_process_stream_proto is unavailable');
    }

    final controller = StreamController<String>();
    final metrics = Completer<VLMResult>();
    NativeCallable<RacVlmStreamProtoCallbackNative>? callback;

    unawaited(Future<void>(() {
      final imageBytes = image.writeToBuffer();
      final optionsBytes = options.writeToBuffer();
      final imagePtr = DartBridgeProtoUtils.copyBytes(imageBytes);
      final optionsPtr = DartBridgeProtoUtils.copyBytes(optionsBytes);
      final out = calloc<RacProtoBuffer>();
      final bindings = RacNative.bindings;

      try {
        bindings.rac_proto_buffer_init(out);
        callback = NativeCallable<RacVlmStreamProtoCallbackNative>.isolateLocal(
          (
            Pointer<Uint8> data,
            int size,
            Pointer<Void> userData,
          ) {
            try {
              final event =
                  sdk_events_pb.SDKEvent.fromBuffer(data.asTypedList(size));
              if (event.hasGeneration() && event.generation.token.isNotEmpty) {
                controller.add(event.generation.token);
              }
              return RAC_TRUE;
            } catch (e, st) {
              controller.addError(e, st);
              return RAC_FALSE;
            }
          },
          exceptionalReturn: RAC_FALSE,
        );

        final code = fn(
          handle,
          imagePtr,
          imageBytes.length,
          optionsPtr,
          optionsBytes.length,
          callback!.nativeFunction,
          nullptr,
          out,
        );
        DartBridgeProtoUtils.ensureSuccess(
          out,
          code,
          'rac_vlm_process_stream_proto',
        );
        final result =
            DartBridgeProtoUtils.decodeBuffer(out, VLMResult.fromBuffer);
        if (!metrics.isCompleted) {
          metrics.complete(result);
        }
      } catch (e, st) {
        if (!metrics.isCompleted) {
          metrics.completeError(e, st);
        }
        controller.addError(e, st);
      } finally {
        bindings.rac_proto_buffer_free(out);
        calloc.free(imagePtr);
        calloc.free(optionsPtr);
        calloc.free(out);
        callback?.close();
        callback = null;
        unawaited(controller.close());
      }
    }));

    return VlmProtoStreamingResult(
      stream: controller.stream,
      metrics: metrics.future,
      cancel: () {
        cancel();
        callback?.close();
        callback = null;
      },
    );
  }

  RacHandle _requireServiceHandle() {
    final handle = _serviceHandle;
    if (handle == null) {
      throw StateError('No VLM service loaded. Call loadModel() first.');
    }
    return handle;
  }

  void _createAndInitializeService(
    String modelId,
    String modelPath,
    String? mmprojPath,
  ) {
    final create = RacNative.bindings.rac_vlm_create;
    final initialize = RacNative.bindings.rac_vlm_initialize;
    if (create == null || initialize == null) {
      throw UnsupportedError('VLM service proto ABI is unavailable');
    }

    final oldHandle = _serviceHandle;
    if (oldHandle != null) {
      RacNative.bindings.rac_vlm_destroy?.call(oldHandle);
      _serviceHandle = null;
    }

    final modelIdPtr = modelId.toNativeUtf8();
    final modelPathPtr = modelPath.toNativeUtf8();
    final mmprojPtr = mmprojPath?.toNativeUtf8();
    final out = calloc<RacHandle>();

    try {
      var rc = create(modelIdPtr, out);
      if (rc != RAC_SUCCESS) {
        throw StateError(
          'rac_vlm_create failed: ${RacResultCode.getMessage(rc)}',
        );
      }

      rc = initialize(out.value, modelPathPtr, mmprojPtr ?? nullptr);
      if (rc != RAC_SUCCESS) {
        RacNative.bindings.rac_vlm_destroy?.call(out.value);
        throw StateError(
          'rac_vlm_initialize failed: ${RacResultCode.getMessage(rc)}',
        );
      }

      _serviceHandle = out.value;
    } finally {
      calloc.free(modelIdPtr);
      calloc.free(modelPathPtr);
      if (mmprojPtr != null) {
        calloc.free(mmprojPtr);
      }
      calloc.free(out);
    }
  }

  /// Process an image with a text prompt (non-streaming).
  ///
  /// [handleAddress] - Handle address for isolate execution.
  /// [prompt] - Text prompt describing what to generate.
  /// [imageFormat] - Image format (filePath, rgbPixels, or base64).
  /// [filePath] - Path to image file (for filePath format).
  /// [pixelData] - RGB pixel data (for rgbPixels format).
  /// [width] - Image width in pixels (for rgbPixels format).
  /// [height] - Image height in pixels (for rgbPixels format).
  /// [base64Data] - Base64-encoded image (for base64 format).
  /// [maxTokens] - Maximum tokens to generate (default: 2048).
  /// [temperature] - Sampling temperature (default: 0.7).
  /// [topP] - Top-p sampling parameter (default: 0.9).
  /// [useGpu] - Use GPU for vision encoding (default: true).
  ///
  /// Returns the generated text and metrics.
  ///
  /// IMPORTANT: This runs in a separate isolate to prevent heap corruption
  /// from C++ Metal/GPU background threads.
  Future<VlmBridgeResult> processImage({
    required String prompt,
    required int imageFormat,
    String? filePath,
    Uint8List? pixelData,
    int width = 0,
    int height = 0,
    String? base64Data,
    int maxTokens = 2048,
    double temperature = 0.7,
    double topP = 0.9,
    bool useGpu = true,
    String? systemPrompt,
    int maxImageSize = 0,
    int nThreads = 0,
  }) async {
    final handle = getHandle();

    if (!isLoaded) {
      throw StateError('No VLM model loaded. Call loadModel() first.');
    }

    // Run FFI call in a separate isolate to avoid heap corruption
    final handleAddress = handle.address;

    _logger.debug(
        '[PARAMS] processImage: temperature=$temperature, maxTokens=$maxTokens, format=$imageFormat, useGpu=$useGpu');

    final result = await Isolate.run(() {
      return _processInIsolate(
        handleAddress,
        prompt,
        imageFormat,
        filePath,
        pixelData,
        width,
        height,
        base64Data,
        maxTokens,
        temperature,
        topP,
        useGpu,
        systemPrompt,
        maxImageSize,
        nThreads,
      );
    });

    if (result.error != null) {
      throw StateError(result.error!);
    }

    return result;
  }

  // MARK: - Image Processing (Streaming)

  /// Process an image with streaming.
  ///
  /// Returns a stream of tokens as they are generated.
  ///
  /// ARCHITECTURE: Runs in a background isolate to prevent ANR.
  /// Tokens are sent back to the main isolate via SendPort for UI updates.
  Stream<String> processImageStream({
    required String prompt,
    required int imageFormat,
    String? filePath,
    Uint8List? pixelData,
    int width = 0,
    int height = 0,
    String? base64Data,
    int maxTokens = 2048,
    double temperature = 0.7,
    double topP = 0.9,
    bool useGpu = true,
    String? systemPrompt,
    int maxImageSize = 0,
    int nThreads = 0,
  }) {
    final handle = getHandle();

    if (!isLoaded) {
      throw StateError('No VLM model loaded. Call loadModel() first.');
    }

    // Create stream controller for emitting tokens to the caller
    final controller = StreamController<String>();

    _logger.debug(
        '[PARAMS] processImageStream: temperature=$temperature, maxTokens=$maxTokens, format=$imageFormat, useGpu=$useGpu');

    // Start streaming processing in a background isolate
    unawaited(
      _startBackgroundStreaming(
        handle.address,
        prompt,
        imageFormat,
        filePath,
        pixelData,
        width,
        height,
        base64Data,
        maxTokens,
        temperature,
        topP,
        useGpu,
        controller,
        systemPrompt,
        maxImageSize,
        nThreads,
      ).catchError((Object e) {
        if (!controller.isClosed) {
          controller.addError(e);
          unawaited(controller.close());
        }
      }),
    );

    return controller.stream;
  }

  /// Start streaming processing in a background isolate.
  Future<void> _startBackgroundStreaming(
    int handleAddress,
    String prompt,
    int imageFormat,
    String? filePath,
    Uint8List? pixelData,
    int width,
    int height,
    String? base64Data,
    int maxTokens,
    double temperature,
    double topP,
    bool useGpu,
    StreamController<String> controller,
    String? systemPrompt,
    int maxImageSize,
    int nThreads,
  ) async {
    // Create a ReceivePort to receive tokens from the background isolate
    final receivePort = ReceivePort();

    // Listen for messages from the background isolate
    receivePort.listen((message) {
      if (controller.isClosed) return;

      if (message is String) {
        // It's a token
        controller.add(message);
      } else if (message is _VlmStreamingMessage) {
        if (message.isComplete) {
          unawaited(controller.close());
          receivePort.close();
        } else if (message.error != null) {
          controller.addError(StateError(message.error!));
          unawaited(controller.close());
          receivePort.close();
        }
      }
    });

    // Spawn background isolate for streaming
    try {
      await Isolate.spawn(
        _vlmStreamingIsolateEntry,
        _VlmStreamingIsolateParams(
          sendPort: receivePort.sendPort,
          handleAddress: handleAddress,
          prompt: prompt,
          imageFormat: imageFormat,
          filePath: filePath,
          pixelData: pixelData,
          width: width,
          height: height,
          base64Data: base64Data,
          maxTokens: maxTokens,
          temperature: temperature,
          topP: topP,
          useGpu: useGpu,
          systemPrompt: systemPrompt,
          maxImageSize: maxImageSize,
          nThreads: nThreads,
        ),
      );
    } catch (e) {
      if (!controller.isClosed) {
        controller.addError(e);
        await controller.close();
      }
      receivePort.close();
    }
  }

  // MARK: - Cleanup

  /// Destroy the component and release resources.
  void destroy() {
    final serviceHandle = _serviceHandle;
    if (serviceHandle != null) {
      RacNative.bindings.rac_vlm_destroy?.call(serviceHandle);
      _serviceHandle = null;
    }
    if (_handle != null) {
      try {
        final lib = PlatformLoader.loadCommons();
        final destroyFn = lib.lookupFunction<Void Function(RacHandle),
            void Function(RacHandle)>('rac_vlm_component_destroy');

        destroyFn(_handle!);
        _handle = null;
        _loadedModelId = null;
        _loadedModelPath = null;
        _loadedMmprojPath = null;
        _logger.debug('VLM component destroyed');
      } catch (e) {
        _logger.error('Failed to destroy VLM component: $e');
      }
    }
  }
}

class VlmProtoStreamingResult {
  const VlmProtoStreamingResult({
    required this.stream,
    required this.metrics,
    required this.cancel,
  });

  final Stream<String> stream;
  final Future<VLMResult> metrics;
  final void Function() cancel;
}

/// Result from VLM image processing.
class VlmBridgeResult {
  final String text;
  final int promptTokens;
  final int imageTokens;
  final int completionTokens;
  final int totalTokens;
  final int timeToFirstTokenMs;
  final int imageEncodeTimeMs;
  final int totalTimeMs;
  final double tokensPerSecond;
  final String? error;

  const VlmBridgeResult({
    required this.text,
    this.promptTokens = 0,
    this.imageTokens = 0,
    this.completionTokens = 0,
    this.totalTokens = 0,
    this.timeToFirstTokenMs = 0,
    this.imageEncodeTimeMs = 0,
    this.totalTimeMs = 0,
    this.tokensPerSecond = 0.0,
    this.error,
  });
}

// =============================================================================
// Isolate Helper for Non-Streaming Processing
// =============================================================================

/// Run VLM processing in an isolate.
///
/// This function is called from Isolate.run() and performs the actual FFI call.
/// Running in a separate isolate prevents heap corruption from C++ background
/// threads (Metal GPU operations on iOS).
VlmBridgeResult _processInIsolate(
  int handleAddress,
  String prompt,
  int imageFormat,
  String? filePath,
  Uint8List? pixelData,
  int width,
  int height,
  String? base64Data,
  int maxTokens,
  double temperature,
  double topP,
  bool useGpu,
  String? systemPrompt,
  int maxImageSize,
  int nThreads,
) {
  final handle = Pointer<Void>.fromAddress(handleAddress);
  final promptPtr = prompt.toNativeUtf8();
  final imagePtr = calloc<RacVlmImageStruct>();
  final optionsPtr = calloc<RacVlmOptionsStruct>();
  final resultPtr = calloc<RacVlmResultStruct>();

  Pointer<Utf8>? filePathPtr;
  Pointer<Uint8>? pixelDataPtr;
  Pointer<Utf8>? base64DataPtr;
  Pointer<Utf8>? systemPromptPtr;

  try {
    // Set up image struct based on format
    imagePtr.ref.format = imageFormat;
    imagePtr.ref.width = width;
    imagePtr.ref.height = height;

    if (imageFormat == RacVlmImageFormat.filePath && filePath != null) {
      filePathPtr = filePath.toNativeUtf8();
      imagePtr.ref.filePath = filePathPtr;
      imagePtr.ref.pixelData = nullptr;
      imagePtr.ref.base64Data = nullptr;
      imagePtr.ref.dataSize = 0;
    } else if (imageFormat == RacVlmImageFormat.rgbPixels &&
        pixelData != null) {
      // Allocate native memory for pixel data
      final pixelPtr = calloc<Uint8>(pixelData.length);
      pixelDataPtr = pixelPtr;
      for (int i = 0; i < pixelData.length; i++) {
        pixelPtr[i] = pixelData[i];
      }
      imagePtr.ref.filePath = nullptr;
      imagePtr.ref.pixelData = pixelPtr;
      imagePtr.ref.base64Data = nullptr;
      imagePtr.ref.dataSize = pixelData.length;
    } else if (imageFormat == RacVlmImageFormat.base64 && base64Data != null) {
      base64DataPtr = base64Data.toNativeUtf8();
      imagePtr.ref.filePath = nullptr;
      imagePtr.ref.pixelData = nullptr;
      imagePtr.ref.base64Data = base64DataPtr;
      imagePtr.ref.dataSize = base64Data.length;
    } else {
      return const VlmBridgeResult(
        text: '',
        error: 'Invalid image format or missing image data',
      );
    }

    // Set options - matching C++ rac_vlm_options_t
    optionsPtr.ref.maxTokens = maxTokens;
    optionsPtr.ref.temperature = temperature;
    optionsPtr.ref.topP = topP;
    optionsPtr.ref.stopSequences = nullptr;
    optionsPtr.ref.numStopSequences = 0;
    optionsPtr.ref.streamingEnabled = RAC_FALSE;
    if (systemPrompt != null) {
      systemPromptPtr = systemPrompt.toNativeUtf8();
      optionsPtr.ref.systemPrompt = systemPromptPtr;
    } else {
      optionsPtr.ref.systemPrompt = nullptr;
    }
    optionsPtr.ref.maxImageSize = maxImageSize;
    optionsPtr.ref.nThreads = nThreads;
    optionsPtr.ref.useGpu = useGpu ? RAC_TRUE : RAC_FALSE;

    final lib = PlatformLoader.loadCommons();
    final processFn = lib.lookupFunction<
        Int32 Function(RacHandle, Pointer<RacVlmImageStruct>, Pointer<Utf8>,
            Pointer<RacVlmOptionsStruct>, Pointer<RacVlmResultStruct>),
        int Function(
            RacHandle,
            Pointer<RacVlmImageStruct>,
            Pointer<Utf8>,
            Pointer<RacVlmOptionsStruct>,
            Pointer<RacVlmResultStruct>)>('rac_vlm_component_process');

    final status =
        processFn(handle, imagePtr, promptPtr, optionsPtr, resultPtr);

    if (status != RAC_SUCCESS) {
      return VlmBridgeResult(
        text: '',
        error: 'VLM processing failed: ${RacResultCode.getMessage(status)}',
      );
    }

    final result = resultPtr.ref;
    final text = result.text != nullptr ? result.text.toDartString() : '';

    return VlmBridgeResult(
      text: text,
      promptTokens: result.promptTokens,
      imageTokens: result.imageTokens,
      completionTokens: result.completionTokens,
      totalTokens: result.totalTokens,
      timeToFirstTokenMs: result.timeToFirstTokenMs,
      imageEncodeTimeMs: result.imageEncodeTimeMs,
      totalTimeMs: result.totalTimeMs,
      tokensPerSecond: result.tokensPerSecond,
    );
  } catch (e) {
    return VlmBridgeResult(text: '', error: 'Processing exception: $e');
  } finally {
    calloc.free(promptPtr);
    calloc.free(imagePtr);
    calloc.free(optionsPtr);
    calloc.free(resultPtr);
    if (filePathPtr != null) calloc.free(filePathPtr);
    if (pixelDataPtr != null) calloc.free(pixelDataPtr);
    if (base64DataPtr != null) calloc.free(base64DataPtr);
    if (systemPromptPtr != null) calloc.free(systemPromptPtr);
  }
}

// =============================================================================
// Background Isolate Streaming Support
// =============================================================================

/// Parameters for the VLM streaming isolate
class _VlmStreamingIsolateParams {
  final SendPort sendPort;
  final int handleAddress;
  final String prompt;
  final int imageFormat;
  final String? filePath;
  final Uint8List? pixelData;
  final int width;
  final int height;
  final String? base64Data;
  final int maxTokens;
  final double temperature;
  final double topP;
  final bool useGpu;
  final String? systemPrompt;
  final int maxImageSize;
  final int nThreads;

  _VlmStreamingIsolateParams({
    required this.sendPort,
    required this.handleAddress,
    required this.prompt,
    required this.imageFormat,
    this.filePath,
    this.pixelData,
    this.width = 0,
    this.height = 0,
    this.base64Data,
    required this.maxTokens,
    required this.temperature,
    required this.topP,
    required this.useGpu,
    this.systemPrompt,
    this.maxImageSize = 0,
    this.nThreads = 0,
  });
}

/// Message sent from streaming isolate to main isolate
class _VlmStreamingMessage {
  final bool isComplete;
  final String? error;

  _VlmStreamingMessage({this.isComplete = false, this.error});
}

/// SendPort for the current streaming operation in the background isolate
SendPort? _vlmIsolateSendPort;

/// Entry point for the VLM streaming isolate
@pragma('vm:entry-point')
void _vlmStreamingIsolateEntry(_VlmStreamingIsolateParams params) {
  // Store the SendPort for callbacks to use
  _vlmIsolateSendPort = params.sendPort;

  final handle = Pointer<Void>.fromAddress(params.handleAddress);
  final promptPtr = params.prompt.toNativeUtf8();
  final imagePtr = calloc<RacVlmImageStruct>();
  final optionsPtr = calloc<RacVlmOptionsStruct>();

  Pointer<Utf8>? filePathPtr;
  Pointer<Uint8>? pixelDataPtr;
  Pointer<Utf8>? base64DataPtr;
  Pointer<Utf8>? systemPromptPtr;

  try {
    // Set up image struct based on format
    imagePtr.ref.format = params.imageFormat;
    imagePtr.ref.width = params.width;
    imagePtr.ref.height = params.height;

    if (params.imageFormat == RacVlmImageFormat.filePath &&
        params.filePath != null) {
      filePathPtr = params.filePath!.toNativeUtf8();
      imagePtr.ref.filePath = filePathPtr;
      imagePtr.ref.pixelData = nullptr;
      imagePtr.ref.base64Data = nullptr;
      imagePtr.ref.dataSize = 0;
    } else if (params.imageFormat == RacVlmImageFormat.rgbPixels &&
        params.pixelData != null) {
      final pixels = params.pixelData!;
      // Allocate native memory for pixel data
      final pixelPtr = calloc<Uint8>(pixels.length);
      pixelDataPtr = pixelPtr;
      for (int i = 0; i < pixels.length; i++) {
        pixelPtr[i] = pixels[i];
      }
      imagePtr.ref.filePath = nullptr;
      imagePtr.ref.pixelData = pixelPtr;
      imagePtr.ref.base64Data = nullptr;
      imagePtr.ref.dataSize = pixels.length;
    } else if (params.imageFormat == RacVlmImageFormat.base64 &&
        params.base64Data != null) {
      final b64 = params.base64Data!;
      base64DataPtr = b64.toNativeUtf8();
      imagePtr.ref.filePath = nullptr;
      imagePtr.ref.pixelData = nullptr;
      imagePtr.ref.base64Data = base64DataPtr;
      imagePtr.ref.dataSize = b64.length;
    } else {
      params.sendPort.send(
        _VlmStreamingMessage(error: 'Invalid image format or missing data'),
      );
      return;
    }

    // Set options
    optionsPtr.ref.maxTokens = params.maxTokens;
    optionsPtr.ref.temperature = params.temperature;
    optionsPtr.ref.topP = params.topP;
    optionsPtr.ref.stopSequences = nullptr;
    optionsPtr.ref.numStopSequences = 0;
    optionsPtr.ref.streamingEnabled = RAC_TRUE;
    if (params.systemPrompt != null) {
      systemPromptPtr = params.systemPrompt!.toNativeUtf8();
      optionsPtr.ref.systemPrompt = systemPromptPtr;
    } else {
      optionsPtr.ref.systemPrompt = nullptr;
    }
    optionsPtr.ref.maxImageSize = params.maxImageSize;
    optionsPtr.ref.nThreads = params.nThreads;
    optionsPtr.ref.useGpu = params.useGpu ? RAC_TRUE : RAC_FALSE;

    final lib = PlatformLoader.loadCommons();

    // Get callback function pointers
    final tokenCallbackPtr =
        Pointer.fromFunction<Int32 Function(Pointer<Utf8>, Pointer<Void>)>(
            _vlmIsolateTokenCallback, 1);
    final completeCallbackPtr = Pointer.fromFunction<
        Void Function(Pointer<RacVlmResultStruct>,
            Pointer<Void>)>(_vlmIsolateCompleteCallback);
    final errorCallbackPtr = Pointer.fromFunction<
        Void Function(
            Int32, Pointer<Utf8>, Pointer<Void>)>(_vlmIsolateErrorCallback);

    final processStreamFn = lib.lookupFunction<
        Int32 Function(
      RacHandle,
      Pointer<RacVlmImageStruct>,
      Pointer<Utf8>,
      Pointer<RacVlmOptionsStruct>,
      Pointer<NativeFunction<Int32 Function(Pointer<Utf8>, Pointer<Void>)>>,
      Pointer<
          NativeFunction<
              Void Function(Pointer<RacVlmResultStruct>, Pointer<Void>)>>,
      Pointer<
          NativeFunction<Void Function(Int32, Pointer<Utf8>, Pointer<Void>)>>,
      Pointer<Void>,
    ),
        int Function(
      RacHandle,
      Pointer<RacVlmImageStruct>,
      Pointer<Utf8>,
      Pointer<RacVlmOptionsStruct>,
      Pointer<NativeFunction<Int32 Function(Pointer<Utf8>, Pointer<Void>)>>,
      Pointer<
          NativeFunction<
              Void Function(Pointer<RacVlmResultStruct>, Pointer<Void>)>>,
      Pointer<
          NativeFunction<Void Function(Int32, Pointer<Utf8>, Pointer<Void>)>>,
      Pointer<Void>,
    )>('rac_vlm_component_process_stream');

    // This FFI call blocks until processing is complete
    final status = processStreamFn(
      handle,
      imagePtr,
      promptPtr,
      optionsPtr,
      tokenCallbackPtr,
      completeCallbackPtr,
      errorCallbackPtr,
      nullptr,
    );

    if (status != RAC_SUCCESS) {
      params.sendPort.send(_VlmStreamingMessage(
        error: 'Failed to start streaming: ${RacResultCode.getMessage(status)}',
      ));
    }
  } catch (e) {
    params.sendPort
        .send(_VlmStreamingMessage(error: 'Streaming exception: $e'));
  } finally {
    calloc.free(promptPtr);
    calloc.free(imagePtr);
    calloc.free(optionsPtr);
    if (filePathPtr != null) calloc.free(filePathPtr);
    if (pixelDataPtr != null) calloc.free(pixelDataPtr);
    if (base64DataPtr != null) calloc.free(base64DataPtr);
    if (systemPromptPtr != null) calloc.free(systemPromptPtr);
    _vlmIsolateSendPort = null;
  }
}

/// Token callback for background isolate streaming
@pragma('vm:entry-point')
int _vlmIsolateTokenCallback(Pointer<Utf8> token, Pointer<Void> userData) {
  try {
    if (_vlmIsolateSendPort != null && token != nullptr) {
      final tokenStr = token.toDartString();
      _vlmIsolateSendPort!.send(tokenStr);
    }
    return 1; // RAC_TRUE = continue processing
  } catch (e) {
    return 1; // Continue even on error
  }
}

/// Completion callback for background isolate streaming
@pragma('vm:entry-point')
void _vlmIsolateCompleteCallback(
    Pointer<RacVlmResultStruct> result, Pointer<Void> userData) {
  _vlmIsolateSendPort?.send(_VlmStreamingMessage(isComplete: true));
}

/// Error callback for background isolate streaming
@pragma('vm:entry-point')
void _vlmIsolateErrorCallback(
    int errorCode, Pointer<Utf8> errorMsg, Pointer<Void> userData) {
  final message =
      errorMsg != nullptr ? errorMsg.toDartString() : 'Unknown error';
  _vlmIsolateSendPort?.send(
      _VlmStreamingMessage(error: 'Processing error ($errorCode): $message'));
}
