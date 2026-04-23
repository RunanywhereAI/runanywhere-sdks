// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_vlm.dart — v4 VLM (vision-language model) capability.

import 'dart:async';
import 'dart:io';

import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/data/network/telemetry_service.dart';
import 'package:runanywhere/foundation/error_types/sdk_error.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/internal/sdk_state.dart';
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_vlm.dart';
import 'package:runanywhere/native/ffi_types.dart' show RacVlmImageFormat;
import 'package:runanywhere/public/capabilities/runanywhere_models.dart';
import 'package:runanywhere/public/events/event_bus.dart';
import 'package:runanywhere/public/events/sdk_event.dart';
import 'package:runanywhere/public/types/vlm_types.dart';

/// VLM (vision-language model) capability surface.
///
/// Access via `RunAnywhereSDK.instance.vlm`.
class RunAnywhereVLM {
  RunAnywhereVLM._();
  static final RunAnywhereVLM _instance = RunAnywhereVLM._();
  static RunAnywhereVLM get shared => _instance;

  /// True when a VLM model is currently loaded.
  bool get isLoaded => DartBridge.vlm.isLoaded;

  /// Currently-loaded VLM model ID, or null.
  String? get currentModelId => DartBridge.vlm.currentModelId;

  /// Load a VLM model by ID. Resolves the main model `.gguf` plus
  /// the paired `*mmproj*.gguf` from the model folder.
  Future<void> load(String modelId) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKError.notInitialized();
    }

    final logger = SDKLogger('RunAnywhere.LoadVLMModel');
    logger.info('Loading VLM model: $modelId');
    final startTime = DateTime.now().millisecondsSinceEpoch;

    EventBus.shared.publish(SDKModelEvent.loadStarted(modelId: modelId));

    try {
      final models = await RunAnywhereModels.shared.available();
      final model = models.where((m) => m.id == modelId).firstOrNull;

      if (model == null) {
        throw SDKError.modelNotFound('VLM model not found: $modelId');
      }

      if (model.localPath == null) {
        throw SDKError.modelNotDownloaded(
          'VLM model is not downloaded. Call downloadModel() first.',
        );
      }

      final modelFolder = model.localPath!.toFilePath();
      logger.info('VLM model folder: $modelFolder');

      final modelPath = await _resolveVLMModelFilePath(modelFolder, model);
      if (modelPath == null) {
        throw SDKError.modelNotFound(
          'Could not find main VLM model file in: $modelFolder',
        );
      }
      logger.info('Resolved VLM model path: $modelPath');

      final modelDir = Directory(modelPath).parent.path;
      final mmprojPath = await _findMmprojFile(modelDir);
      logger.info('mmproj path: ${mmprojPath ?? "not found"}');

      if (DartBridge.vlm.isLoaded) {
        logger.debug('Unloading previous VLM model');
        DartBridge.vlm.unload();
      }

      logger.debug('Loading VLM model via C++ bridge');
      await DartBridge.vlm.loadModel(
        modelPath,
        mmprojPath,
        modelId,
        model.name,
      );

      if (!DartBridge.vlm.isLoaded) {
        throw SDKError.vlmModelLoadFailed(
          'VLM model failed to load - model may not be compatible',
        );
      }

      final loadTimeMs = DateTime.now().millisecondsSinceEpoch - startTime;
      logger.info(
        'VLM model loaded successfully: ${model.name} (isLoaded=${DartBridge.vlm.isLoaded})',
      );

      TelemetryService.shared.trackModelLoad(
        modelId: modelId,
        modelType: 'vlm',
        success: true,
        loadTimeMs: loadTimeMs,
      );

      EventBus.shared.publish(SDKModelEvent.loadCompleted(modelId: modelId));
    } catch (e) {
      logger.error('Failed to load VLM model: $e');
      TelemetryService.shared.trackModelLoad(
        modelId: modelId,
        modelType: 'vlm',
        success: false,
      );
      TelemetryService.shared.trackError(
        errorCode: 'vlm_model_load_failed',
        errorMessage: e.toString(),
        context: {'model_id': modelId},
      );
      EventBus.shared.publish(SDKModelEvent.loadFailed(
        modelId: modelId,
        error: e.toString(),
      ));
      rethrow;
    }
  }

  /// Load a VLM model via C++ path resolution (model must be
  /// pre-registered in the C++ registry).
  Future<void> loadById(String modelId) async {
    if (!SdkState.shared.isInitialized) throw SDKError.notInitialized();

    final logger = SDKLogger('RunAnywhere.LoadVLMModelById');
    logger.info('Loading VLM model by ID: $modelId');
    final startTime = DateTime.now().millisecondsSinceEpoch;

    EventBus.shared.publish(SDKModelEvent.loadStarted(modelId: modelId));

    try {
      if (DartBridge.vlm.isLoaded) {
        logger.debug('Unloading previous VLM model');
        DartBridge.vlm.unload();
      }

      await DartBridge.vlm.loadModelById(modelId);

      if (!DartBridge.vlm.isLoaded) {
        throw SDKError.vlmModelLoadFailed(
          'VLM model failed to load - model may not be compatible',
        );
      }

      final loadTimeMs = DateTime.now().millisecondsSinceEpoch - startTime;
      logger.info('VLM model loaded by ID: $modelId');

      TelemetryService.shared.trackModelLoad(
        modelId: modelId,
        modelType: 'vlm',
        success: true,
        loadTimeMs: loadTimeMs,
      );

      EventBus.shared.publish(SDKModelEvent.loadCompleted(modelId: modelId));
    } catch (e) {
      logger.error('Failed to load VLM model by ID: $e');
      TelemetryService.shared.trackModelLoad(
        modelId: modelId,
        modelType: 'vlm',
        success: false,
      );
      TelemetryService.shared.trackError(
        errorCode: 'vlm_model_load_failed',
        errorMessage: e.toString(),
        context: {'model_id': modelId},
      );
      EventBus.shared.publish(SDKModelEvent.loadFailed(
        modelId: modelId,
        error: e.toString(),
      ));
      rethrow;
    }
  }

  /// Load a VLM model from explicit file paths (bypasses registry).
  Future<void> loadWithPath(
    String modelPath, {
    String? mmprojPath,
    required String modelId,
    required String modelName,
  }) async {
    if (!SdkState.shared.isInitialized) throw SDKError.notInitialized();

    final logger = SDKLogger('RunAnywhere.LoadVLMModelWithPath');
    logger.info('Loading VLM model from path: $modelPath');
    final startTime = DateTime.now().millisecondsSinceEpoch;

    EventBus.shared.publish(SDKModelEvent.loadStarted(modelId: modelId));

    try {
      if (DartBridge.vlm.isLoaded) {
        logger.debug('Unloading previous VLM model');
        DartBridge.vlm.unload();
      }

      await DartBridge.vlm.loadModel(modelPath, mmprojPath, modelId, modelName);

      if (!DartBridge.vlm.isLoaded) {
        throw SDKError.vlmModelLoadFailed(
          'VLM model failed to load - model may not be compatible',
        );
      }

      final loadTimeMs = DateTime.now().millisecondsSinceEpoch - startTime;
      logger.info('VLM model loaded from path: $modelPath');

      TelemetryService.shared.trackModelLoad(
        modelId: modelId,
        modelType: 'vlm',
        success: true,
        loadTimeMs: loadTimeMs,
      );

      EventBus.shared.publish(SDKModelEvent.loadCompleted(modelId: modelId));
    } catch (e) {
      logger.error('Failed to load VLM model from path: $e');
      TelemetryService.shared.trackModelLoad(
        modelId: modelId,
        modelType: 'vlm',
        success: false,
      );
      TelemetryService.shared.trackError(
        errorCode: 'vlm_model_load_failed',
        errorMessage: e.toString(),
        context: {'model_id': modelId, 'model_path': modelPath},
      );
      EventBus.shared.publish(SDKModelEvent.loadFailed(
        modelId: modelId,
        error: e.toString(),
      ));
      rethrow;
    }
  }

  /// Unload the currently-loaded VLM model.
  Future<void> unload() async {
    if (!SdkState.shared.isInitialized) throw SDKError.notInitialized();
    final logger = SDKLogger('RunAnywhere.UnloadVLMModel');
    logger.debug('Unloading VLM model');
    DartBridge.vlm.unload();
    logger.info('VLM model unloaded');
  }

  /// Cancel any in-flight VLM generation.
  Future<void> cancel() async {
    DartBridge.vlm.cancel();
  }

  /// Describe an image with a default or custom prompt.
  Future<String> describe(
    VLMImage image, {
    String prompt = "What's in this image?",
    VLMGenerationOptions options = const VLMGenerationOptions(),
  }) async {
    final result = await processImage(image, prompt: prompt, options: options);
    return result.text;
  }

  /// Ask a specific question about an image.
  Future<String> askAbout(
    String question, {
    required VLMImage image,
    VLMGenerationOptions options = const VLMGenerationOptions(),
  }) async {
    final result =
        await processImage(image, prompt: question, options: options);
    return result.text;
  }

  /// Process an image with VLM (full result with metrics).
  Future<VLMResult> processImage(
    VLMImage image, {
    required String prompt,
    VLMGenerationOptions options = const VLMGenerationOptions(),
  }) async {
    if (!SdkState.shared.isInitialized) throw SDKError.notInitialized();
    if (!DartBridge.vlm.isLoaded) throw SDKError.vlmNotInitialized();

    final logger = SDKLogger('RunAnywhere.VLM.ProcessImage');
    final modelId = DartBridge.vlm.currentModelId ?? 'unknown';

    try {
      final bridgeResult = await _processImageViaBridge(image, prompt, options);

      logger.info(
        'VLM processing complete: ${bridgeResult.completionTokens} tokens, '
        '${bridgeResult.tokensPerSecond.toStringAsFixed(1)} tok/s',
      );

      TelemetryService.shared.trackGeneration(
        modelId: modelId,
        modelName: DartBridge.vlm.currentModelId,
        promptTokens: bridgeResult.promptTokens,
        completionTokens: bridgeResult.completionTokens,
        latencyMs: bridgeResult.totalTimeMs.round(),
        temperature: options.temperature,
        maxTokens: options.maxTokens,
        tokensPerSecond: bridgeResult.tokensPerSecond,
        isStreaming: false,
      );

      return bridgeResult;
    } catch (e) {
      logger.error('VLM processing failed: $e');
      TelemetryService.shared.trackError(
        errorCode: 'vlm_processing_failed',
        errorMessage: e.toString(),
        context: {'model_id': modelId},
      );
      rethrow;
    }
  }

  /// Stream image processing with real-time tokens.
  Future<VLMStreamingResult> processImageStream(
    VLMImage image, {
    required String prompt,
    VLMGenerationOptions options = const VLMGenerationOptions(),
  }) async {
    if (!SdkState.shared.isInitialized) throw SDKError.notInitialized();
    if (!DartBridge.vlm.isLoaded) throw SDKError.vlmNotInitialized();

    final logger = SDKLogger('RunAnywhere.VLM.ProcessImageStream');
    final modelId = DartBridge.vlm.currentModelId ?? 'unknown';
    final startTime = DateTime.now();
    DateTime? firstTokenTime;

    final controller = StreamController<String>.broadcast();
    final allTokens = <String>[];

    try {
      final tokenStream =
          _processImageStreamViaBridge(image, prompt, options);

      final subscription = tokenStream.listen(
        (token) {
          firstTokenTime ??= DateTime.now();
          allTokens.add(token);
          if (!controller.isClosed) {
            controller.add(token);
          }
        },
        onError: (Object error) {
          logger.error('VLM streaming error: $error');
          TelemetryService.shared.trackError(
            errorCode: 'vlm_streaming_failed',
            errorMessage: error.toString(),
            context: {'model_id': modelId},
          );
          if (!controller.isClosed) {
            controller.addError(error);
          }
        },
        onDone: () {
          if (!controller.isClosed) {
            unawaited(controller.close());
          }
        },
      );

      final metricsFuture = controller.stream.toList().then((_) {
        final endTime = DateTime.now();
        final totalTimeMs =
            endTime.difference(startTime).inMicroseconds / 1000.0;
        final tokensPerSecond =
            totalTimeMs > 0 ? allTokens.length / (totalTimeMs / 1000) : 0.0;

        int? timeToFirstTokenMs;
        if (firstTokenTime != null) {
          timeToFirstTokenMs =
              firstTokenTime!.difference(startTime).inMilliseconds;
        }

        logger.info(
          'VLM streaming complete: ${allTokens.length} tokens, '
          '${tokensPerSecond.toStringAsFixed(1)} tok/s',
        );

        TelemetryService.shared.trackGeneration(
          modelId: modelId,
          modelName: DartBridge.vlm.currentModelId,
          promptTokens: 0,
          completionTokens: allTokens.length,
          latencyMs: totalTimeMs.round(),
          temperature: options.temperature,
          maxTokens: options.maxTokens,
          tokensPerSecond: tokensPerSecond,
          timeToFirstTokenMs: timeToFirstTokenMs,
          isStreaming: true,
        );

        return VLMResult(
          text: allTokens.join(),
          promptTokens: 0,
          completionTokens: allTokens.length,
          totalTimeMs: totalTimeMs,
          tokensPerSecond: tokensPerSecond,
        );
      });

      return VLMStreamingResult(
        stream: controller.stream,
        metrics: metricsFuture,
        cancel: () {
          logger.debug('Cancelling VLM streaming');
          DartBridge.vlm.cancel();
          unawaited(subscription.cancel());
          if (!controller.isClosed) {
            unawaited(controller.close());
          }
        },
      );
    } catch (e) {
      logger.error('Failed to start VLM streaming: $e');
      TelemetryService.shared.trackError(
        errorCode: 'vlm_streaming_start_failed',
        errorMessage: e.toString(),
        context: {'model_id': modelId},
      );
      rethrow;
    }
  }

  // -- private helpers ------------------------------------------------------

  Future<VLMResult> _processImageViaBridge(
    VLMImage image,
    String prompt,
    VLMGenerationOptions options,
  ) async {
    final format = image.format;
    final VlmBridgeResult bridgeResult;

    if (format is VLMImageFormatFilePath) {
      bridgeResult = await DartBridge.vlm.processImage(
        imageFormat: RacVlmImageFormat.filePath,
        filePath: format.path,
        prompt: prompt,
        maxTokens: options.maxTokens,
        temperature: options.temperature,
        topP: options.topP,
        useGpu: options.useGpu,
        systemPrompt: options.systemPrompt,
        maxImageSize: options.maxImageSize,
        nThreads: options.nThreads,
      );
    } else if (format is VLMImageFormatRgbPixels) {
      bridgeResult = await DartBridge.vlm.processImage(
        imageFormat: RacVlmImageFormat.rgbPixels,
        pixelData: format.data,
        width: format.width,
        height: format.height,
        prompt: prompt,
        maxTokens: options.maxTokens,
        temperature: options.temperature,
        topP: options.topP,
        useGpu: options.useGpu,
        systemPrompt: options.systemPrompt,
        maxImageSize: options.maxImageSize,
        nThreads: options.nThreads,
      );
    } else if (format is VLMImageFormatBase64) {
      bridgeResult = await DartBridge.vlm.processImage(
        imageFormat: RacVlmImageFormat.base64,
        base64Data: format.encoded,
        prompt: prompt,
        maxTokens: options.maxTokens,
        temperature: options.temperature,
        topP: options.topP,
        useGpu: options.useGpu,
        systemPrompt: options.systemPrompt,
        maxImageSize: options.maxImageSize,
        nThreads: options.nThreads,
      );
    } else {
      throw SDKError.vlmInvalidImage('Unsupported image format');
    }

    return VLMResult(
      text: bridgeResult.text,
      promptTokens: bridgeResult.promptTokens,
      completionTokens: bridgeResult.completionTokens,
      totalTimeMs: bridgeResult.totalTimeMs.toDouble(),
      tokensPerSecond: bridgeResult.tokensPerSecond,
    );
  }

  Stream<String> _processImageStreamViaBridge(
    VLMImage image,
    String prompt,
    VLMGenerationOptions options,
  ) {
    final format = image.format;

    if (format is VLMImageFormatFilePath) {
      return DartBridge.vlm.processImageStream(
        imageFormat: RacVlmImageFormat.filePath,
        filePath: format.path,
        prompt: prompt,
        maxTokens: options.maxTokens,
        temperature: options.temperature,
        topP: options.topP,
        useGpu: options.useGpu,
        systemPrompt: options.systemPrompt,
        maxImageSize: options.maxImageSize,
        nThreads: options.nThreads,
      );
    } else if (format is VLMImageFormatRgbPixels) {
      return DartBridge.vlm.processImageStream(
        imageFormat: RacVlmImageFormat.rgbPixels,
        pixelData: format.data,
        width: format.width,
        height: format.height,
        prompt: prompt,
        maxTokens: options.maxTokens,
        temperature: options.temperature,
        topP: options.topP,
        useGpu: options.useGpu,
        systemPrompt: options.systemPrompt,
        maxImageSize: options.maxImageSize,
        nThreads: options.nThreads,
      );
    } else if (format is VLMImageFormatBase64) {
      return DartBridge.vlm.processImageStream(
        imageFormat: RacVlmImageFormat.base64,
        base64Data: format.encoded,
        prompt: prompt,
        maxTokens: options.maxTokens,
        temperature: options.temperature,
        topP: options.topP,
        useGpu: options.useGpu,
        systemPrompt: options.systemPrompt,
        maxImageSize: options.maxImageSize,
        nThreads: options.nThreads,
      );
    } else {
      throw SDKError.vlmInvalidImage('Unsupported image format');
    }
  }

  Future<String?> _resolveVLMModelFilePath(
    String modelFolder,
    ModelInfo model,
  ) async {
    final file = File(modelFolder);
    final dir = await file.exists() ? file.parent : Directory(modelFolder);
    if (!await dir.exists()) return null;
    final dirPath = dir.path;

    try {
      final entities = await dir.list().toList();
      final files = entities
          .whereType<File>()
          .map((f) => f.path.split('/').last)
          .toList();

      final ggufFiles =
          files.where((f) => f.toLowerCase().endsWith('.gguf')).toList();
      final mainModelFiles = ggufFiles
          .where((f) => !f.toLowerCase().contains('mmproj'))
          .toList();

      if (mainModelFiles.isNotEmpty) {
        return '$dirPath/${mainModelFiles.first}';
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _findMmprojFile(String modelDirPath) async {
    final dir = Directory(modelDirPath);
    if (!await dir.exists()) return null;
    try {
      await for (final entity in dir.list()) {
        if (entity is File) {
          final name = entity.path.split('/').last.toLowerCase();
          if (name.contains('mmproj') && name.endsWith('.gguf')) {
            return entity.path;
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
