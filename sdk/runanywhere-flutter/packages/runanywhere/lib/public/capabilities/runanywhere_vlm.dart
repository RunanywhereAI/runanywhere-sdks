// SPDX-License-Identifier: Apache-2.0
//
// Wave 2 VLM capability — uses proto VLMImage / VLMGenerationOptions / VLMResult.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/data/network/telemetry_service.dart';
import 'package:runanywhere/foundation/error_types/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/vlm_options.pb.dart';
import 'package:runanywhere/internal/sdk_state.dart';
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_vlm.dart';
import 'package:runanywhere/native/ffi_types.dart' show RacVlmImageFormat;
import 'package:runanywhere/public/capabilities/runanywhere_models.dart';
import 'package:runanywhere/public/events/event_bus.dart';
import 'package:runanywhere/public/events/sdk_event.dart';

/// Streaming wrapper returned by `processImageStream`.
class VLMStreamingResult {
  /// Stream of tokens as they are generated.
  final Stream<String> stream;

  /// Future that completes with final result metrics when streaming finishes.
  final Future<VLMResult> metrics;

  /// Function to cancel the ongoing generation.
  final void Function() cancel;

  const VLMStreamingResult({
    required this.stream,
    required this.metrics,
    required this.cancel,
  });
}

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

  /// Load a VLM model by ID.
  Future<void> load(String modelId) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }

    final logger = SDKLogger('RunAnywhere.LoadVLMModel');
    logger.info('Loading VLM model: $modelId');
    final startTime = DateTime.now().millisecondsSinceEpoch;

    EventBus.shared.publish(SDKModelEvent.loadStarted(modelId: modelId));

    try {
      final models = await RunAnywhereModels.shared.available();
      final model = models.where((m) => m.id == modelId).firstOrNull;

      if (model == null) {
        throw SDKException.modelNotFound('VLM model not found: $modelId');
      }

      if (model.localPath == null) {
        throw SDKException.modelNotDownloaded(
          'VLM model is not downloaded. Call downloadModel() first.',
        );
      }

      final modelFolder = model.localPath!.toFilePath();
      final modelPath = await _resolveVLMModelFilePath(modelFolder, model);
      if (modelPath == null) {
        throw SDKException.modelNotFound(
          'Could not find main VLM model file in: $modelFolder',
        );
      }

      final modelDir = Directory(modelPath).parent.path;
      final mmprojPath = await _findMmprojFile(modelDir);

      if (DartBridge.vlm.isLoaded) {
        DartBridge.vlm.unload();
      }

      await DartBridge.vlm.loadModel(modelPath, mmprojPath, modelId, model.name);

      if (!DartBridge.vlm.isLoaded) {
        throw SDKException.vlmModelLoadFailed(
          'VLM model failed to load - model may not be compatible',
        );
      }

      final loadTimeMs = DateTime.now().millisecondsSinceEpoch - startTime;
      logger.info('VLM model loaded successfully: ${model.name}');

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

  /// Load a VLM model from explicit file paths.
  Future<void> loadWithPath(
    String modelPath, {
    String? mmprojPath,
    required String modelId,
    required String modelName,
  }) async {
    if (!SdkState.shared.isInitialized) throw SDKException.notInitialized();

    EventBus.shared.publish(SDKModelEvent.loadStarted(modelId: modelId));
    try {
      if (DartBridge.vlm.isLoaded) {
        DartBridge.vlm.unload();
      }
      await DartBridge.vlm.loadModel(modelPath, mmprojPath, modelId, modelName);
      if (!DartBridge.vlm.isLoaded) {
        throw SDKException.vlmModelLoadFailed(
          'VLM model failed to load - model may not be compatible',
        );
      }
      EventBus.shared.publish(SDKModelEvent.loadCompleted(modelId: modelId));
    } catch (e) {
      EventBus.shared.publish(SDKModelEvent.loadFailed(
        modelId: modelId,
        error: e.toString(),
      ));
      rethrow;
    }
  }

  /// Unload the currently-loaded VLM model.
  Future<void> unload() async {
    if (!SdkState.shared.isInitialized) throw SDKException.notInitialized();
    DartBridge.vlm.unload();
  }

  /// Cancel any in-flight VLM generation.
  Future<void> cancel() async {
    DartBridge.vlm.cancel();
  }

  /// Describe an image. Returns the generated text.
  Future<String> describe(
    VLMImage image, {
    String prompt = "What's in this image?",
    VLMGenerationOptions? options,
  }) async {
    final result = await processImage(image, prompt: prompt, options: options);
    return result.text;
  }

  /// Ask a specific question about an image.
  Future<String> askAbout(
    String question, {
    required VLMImage image,
    VLMGenerationOptions? options,
  }) async {
    final result =
        await processImage(image, prompt: question, options: options);
    return result.text;
  }

  /// Process an image with VLM (full result with metrics).
  Future<VLMResult> processImage(
    VLMImage image, {
    required String prompt,
    VLMGenerationOptions? options,
  }) async {
    if (!SdkState.shared.isInitialized) throw SDKException.notInitialized();
    if (!DartBridge.vlm.isLoaded) throw SDKException.vlmNotInitialized();

    final logger = SDKLogger('RunAnywhere.VLM.ProcessImage');
    final modelId = DartBridge.vlm.currentModelId ?? 'unknown';
    final opts = options ?? VLMGenerationOptions();

    try {
      final bridgeResult = await _processImageViaBridge(image, prompt, opts);

      logger.info(
        'VLM processing complete: ${bridgeResult.completionTokens} tokens, '
        '${bridgeResult.tokensPerSecond.toStringAsFixed(1)} tok/s',
      );

      TelemetryService.shared.trackGeneration(
        modelId: modelId,
        modelName: DartBridge.vlm.currentModelId,
        promptTokens: bridgeResult.promptTokens,
        completionTokens: bridgeResult.completionTokens,
        latencyMs: bridgeResult.processingTimeMs.toInt(),
        temperature: opts.hasTemperature() ? opts.temperature : 0.7,
        maxTokens: opts.hasMaxTokens() ? opts.maxTokens : 2048,
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
    VLMGenerationOptions? options,
  }) async {
    if (!SdkState.shared.isInitialized) throw SDKException.notInitialized();
    if (!DartBridge.vlm.isLoaded) throw SDKException.vlmNotInitialized();

    final logger = SDKLogger('RunAnywhere.VLM.ProcessImageStream');
    final startTime = DateTime.now();
    final opts = options ?? VLMGenerationOptions();

    final controller = StreamController<String>.broadcast();
    final allTokens = <String>[];

    try {
      final tokenStream = _processImageStreamViaBridge(image, prompt, opts);

      final subscription = tokenStream.listen(
        (token) {
          allTokens.add(token);
          if (!controller.isClosed) {
            controller.add(token);
          }
        },
        onError: (Object error) {
          logger.error('VLM streaming error: $error');
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

        return VLMResult(
          text: allTokens.join(),
          promptTokens: 0,
          completionTokens: allTokens.length,
          processingTimeMs: Int64(totalTimeMs.round()),
          tokensPerSecond: tokensPerSecond,
        );
      });

      return VLMStreamingResult(
        stream: controller.stream,
        metrics: metricsFuture,
        cancel: () {
          DartBridge.vlm.cancel();
          unawaited(subscription.cancel());
          if (!controller.isClosed) {
            unawaited(controller.close());
          }
        },
      );
    } catch (e) {
      logger.error('Failed to start VLM streaming: $e');
      rethrow;
    }
  }

  // -- private helpers ------------------------------------------------------

  Future<VLMResult> _processImageViaBridge(
    VLMImage image,
    String prompt,
    VLMGenerationOptions options,
  ) async {
    final VlmBridgeResult bridgeResult;
    final maxTokens = options.hasMaxTokens() ? options.maxTokens : 2048;
    final temperature = options.hasTemperature() ? options.temperature : 0.7;
    final topP = options.hasTopP() ? options.topP : 0.9;

    if (image.hasFilePath()) {
      bridgeResult = await DartBridge.vlm.processImage(
        imageFormat: RacVlmImageFormat.filePath,
        filePath: image.filePath,
        prompt: prompt,
        maxTokens: maxTokens,
        temperature: temperature,
        topP: topP,
        useGpu: true,
        systemPrompt: null,
        maxImageSize: 0,
        nThreads: 0,
      );
    } else if (image.hasRawRgb()) {
      bridgeResult = await DartBridge.vlm.processImage(
        imageFormat: RacVlmImageFormat.rgbPixels,
        pixelData: Uint8List.fromList(image.rawRgb),
        width: image.width,
        height: image.height,
        prompt: prompt,
        maxTokens: maxTokens,
        temperature: temperature,
        topP: topP,
        useGpu: true,
        systemPrompt: null,
        maxImageSize: 0,
        nThreads: 0,
      );
    } else if (image.hasBase64()) {
      bridgeResult = await DartBridge.vlm.processImage(
        imageFormat: RacVlmImageFormat.base64,
        base64Data: image.base64,
        prompt: prompt,
        maxTokens: maxTokens,
        temperature: temperature,
        topP: topP,
        useGpu: true,
        systemPrompt: null,
        maxImageSize: 0,
        nThreads: 0,
      );
    } else {
      throw SDKException.vlmInvalidImage('Unsupported image format');
    }

    return VLMResult(
      text: bridgeResult.text,
      promptTokens: bridgeResult.promptTokens,
      completionTokens: bridgeResult.completionTokens,
      processingTimeMs: Int64(bridgeResult.totalTimeMs.round()),
      tokensPerSecond: bridgeResult.tokensPerSecond,
    );
  }

  Stream<String> _processImageStreamViaBridge(
    VLMImage image,
    String prompt,
    VLMGenerationOptions options,
  ) {
    final maxTokens = options.hasMaxTokens() ? options.maxTokens : 2048;
    final temperature = options.hasTemperature() ? options.temperature : 0.7;
    final topP = options.hasTopP() ? options.topP : 0.9;

    if (image.hasFilePath()) {
      return DartBridge.vlm.processImageStream(
        imageFormat: RacVlmImageFormat.filePath,
        filePath: image.filePath,
        prompt: prompt,
        maxTokens: maxTokens,
        temperature: temperature,
        topP: topP,
        useGpu: true,
        systemPrompt: null,
        maxImageSize: 0,
        nThreads: 0,
      );
    } else if (image.hasRawRgb()) {
      return DartBridge.vlm.processImageStream(
        imageFormat: RacVlmImageFormat.rgbPixels,
        pixelData: Uint8List.fromList(image.rawRgb),
        width: image.width,
        height: image.height,
        prompt: prompt,
        maxTokens: maxTokens,
        temperature: temperature,
        topP: topP,
        useGpu: true,
        systemPrompt: null,
        maxImageSize: 0,
        nThreads: 0,
      );
    } else if (image.hasBase64()) {
      return DartBridge.vlm.processImageStream(
        imageFormat: RacVlmImageFormat.base64,
        base64Data: image.base64,
        prompt: prompt,
        maxTokens: maxTokens,
        temperature: temperature,
        topP: topP,
        useGpu: true,
        systemPrompt: null,
        maxImageSize: 0,
        nThreads: 0,
      );
    } else {
      throw SDKException.vlmInvalidImage('Unsupported image format');
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
