// SPDX-License-Identifier: Apache-2.0
//
// Wave 2 VLM capability — uses proto VLMImage / VLMGenerationOptions / VLMResult.

import 'dart:async';

import 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;
import 'package:runanywhere/data/network/telemetry_service.dart';
import 'package:runanywhere/foundation/error_types/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/vlm_options.pb.dart';
import 'package:runanywhere/internal/sdk_state.dart';
import 'package:runanywhere/native/dart_bridge.dart';
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

      if (model.localPath.isEmpty) {
        throw SDKException.modelNotDownloaded(
          'VLM model is not downloaded. Call downloadModel() first.',
        );
      }

      final resolution = DartBridge.modelPaths.resolveArtifact(model);
      final modelPath = resolution?.primaryModelPath;
      if (modelPath == null) {
        throw SDKException.modelNotFound(
          'Could not resolve main VLM model path for: $modelId',
        );
      }

      final mmprojPath = resolution?.mmprojPath;

      if (DartBridge.vlm.isLoaded) {
        DartBridge.vlm.unload();
      }

      await DartBridge.vlm
          .loadModel(modelPath, mmprojPath, modelId, model.name);

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
    final opts = _effectiveOptions(prompt, options ?? VLMGenerationOptions());

    try {
      final result = DartBridge.vlm.processImageProto(image, opts);

      logger.info(
        'VLM processing complete: ${result.completionTokens} tokens, '
        '${result.tokensPerSecond.toStringAsFixed(1)} tok/s',
      );

      TelemetryService.shared.trackGeneration(
        modelId: modelId,
        modelName: DartBridge.vlm.currentModelId,
        promptTokens: result.promptTokens,
        completionTokens: result.completionTokens,
        latencyMs: result.processingTimeMs.toInt(),
        temperature: opts.hasTemperature() ? opts.temperature : 0.7,
        maxTokens: opts.hasMaxTokens() ? opts.maxTokens : 2048,
        tokensPerSecond: result.tokensPerSecond,
        isStreaming: false,
      );

      return result;
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
    final opts = _effectiveOptions(
      prompt,
      options ?? VLMGenerationOptions(),
      streaming: true,
    );

    try {
      final stream = DartBridge.vlm.processImageStreamProto(image, opts);
      return VLMStreamingResult(
        stream: stream.stream,
        metrics: stream.metrics,
        cancel: stream.cancel,
      );
    } catch (e) {
      logger.error('Failed to start VLM streaming: $e');
      rethrow;
    }
  }

  VLMGenerationOptions _effectiveOptions(
    String prompt,
    VLMGenerationOptions options, {
    bool streaming = false,
  }) {
    final opts = options.deepCopy();
    if (!opts.hasPrompt()) {
      opts.prompt = prompt;
    }
    if (!opts.hasMaxTokens()) {
      opts.maxTokens = 2048;
    }
    if (!opts.hasTemperature()) {
      opts.temperature = 0.7;
    }
    if (!opts.hasTopP()) {
      opts.topP = 0.9;
    }
    if (!opts.hasUseGpu()) {
      opts.useGpu = true;
    }
    opts.streamingEnabled = streaming;
    return opts;
  }
}
