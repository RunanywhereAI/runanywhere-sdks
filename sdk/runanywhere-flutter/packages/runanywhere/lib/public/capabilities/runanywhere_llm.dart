// SPDX-License-Identifier: Apache-2.0
//
// Wave 2 LLM capability — aligned to Swift + proto. Returns proto
// LLMGenerationResult; streams Stream<LLMStreamEvent>.

import 'dart:async';

import 'package:runanywhere/data/network/telemetry_service.dart';
import 'package:runanywhere/foundation/error_types/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/llm_options.pb.dart'
    show LLMGenerationOptions, LLMGenerationResult;
import 'package:runanywhere/generated/llm_service.pb.dart'
    show LLMGenerateRequest, LLMStreamEvent;
import 'package:runanywhere/generated/model_types.pb.dart' show ModelInfo;
import 'package:runanywhere/generated/model_types.pb.dart' as model_pb;
import 'package:runanywhere/internal/sdk_state.dart';
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_model_registry.dart'
    hide ModelInfo;
import 'package:runanywhere/public/capabilities/runanywhere_models.dart';
import 'package:runanywhere/public/events/event_bus.dart';
import 'package:runanywhere/public/events/sdk_event.dart';

/// LLM (text generation) capability surface.
///
/// Access via `RunAnywhereSDK.instance.llm`.
class RunAnywhereLLM {
  RunAnywhereLLM._();
  static final RunAnywhereLLM _instance = RunAnywhereLLM._();
  static RunAnywhereLLM get shared => _instance;

  /// True when an LLM model is currently loaded in the C++ backend.
  bool get isLoaded => DartBridge.llm.isLoaded;

  /// Currently-loaded LLM model ID, or null.
  String? get currentModelId => DartBridge.llm.currentModelId;

  /// Currently-loaded LLM model as `ModelInfo`, or null.
  Future<ModelInfo?> currentModel() async {
    final modelId = currentModelId;
    if (modelId == null) return null;
    final models = await RunAnywhereModels.shared.available();
    return models.cast<ModelInfo?>().firstWhere(
          (m) => m?.id == modelId,
          orElse: () => null,
        );
  }

  /// Load an LLM model by ID. Resolves the model path, unloads any
  /// previously-loaded model, then hands off to the native bridge.
  Future<void> load(String modelId) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }

    final logger = SDKLogger('RunAnywhere.LoadModel');
    logger.info('Loading model: $modelId');
    final startTime = DateTime.now().millisecondsSinceEpoch;

    EventBus.shared.publish(SDKModelEvent.loadStarted(modelId: modelId));

    try {
      final models = await RunAnywhereModels.shared.available();
      final model = models.where((m) => m.id == modelId).firstOrNull;

      if (model == null) {
        throw SDKException.modelNotFound('Model not found: $modelId');
      }

      if (model.localPath.isEmpty) {
        throw SDKException.modelNotDownloaded(
          'Model is not downloaded. Call downloadModel() first.',
        );
      }

      final resolvedPath =
          await DartBridge.modelPaths.resolveModelFilePath(model);
      if (resolvedPath == null) {
        throw SDKException.modelNotFound(
            'Could not resolve model file path for: $modelId');
      }
      logger.info('Resolved model path: $resolvedPath');

      if (DartBridge.llm.isLoaded) {
        logger.debug('Unloading previous model');
        DartBridge.llm.unload();
      }

      logger.debug('Loading model via C++ bridge: $resolvedPath');
      await DartBridge.llm.loadModel(
        resolvedPath,
        modelId,
        model.name,
        model.contextLength,
      );

      final framework = model.framework ==
              model_pb.InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED
          ? model_pb.InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP
          : model.framework;
      final lifecycleResult = await DartBridge.modelLifecycle.load(
        model_pb.ModelLoadRequest(
          modelId: modelId,
          category: model_pb.ModelCategory.MODEL_CATEGORY_LANGUAGE,
          framework: framework,
          forceReload: true,
        ),
      );
      if (!lifecycleResult.success) {
        throw SDKException.modelLoadFailed(
          modelId,
          lifecycleResult.errorMessage.isNotEmpty
              ? lifecycleResult.errorMessage
              : 'Model lifecycle proto load failed',
        );
      }

      if (!DartBridge.llm.isLoaded) {
        throw SDKException.modelLoadFailed(
          modelId,
          'LLM model failed to load - model may not be compatible',
        );
      }

      final loadTimeMs = DateTime.now().millisecondsSinceEpoch - startTime;
      logger.info(
          'Model loaded successfully: ${model.name} (isLoaded=${DartBridge.llm.isLoaded})');

      TelemetryService.shared.trackModelLoad(
        modelId: modelId,
        modelType: 'llm',
        success: true,
        loadTimeMs: loadTimeMs,
      );

      EventBus.shared.publish(SDKModelEvent.loadCompleted(modelId: modelId));
    } catch (e) {
      logger.error('Failed to load model: $e');
      TelemetryService.shared.trackModelLoad(
        modelId: modelId,
        modelType: 'llm',
        success: false,
      );
      TelemetryService.shared.trackError(
        errorCode: 'model_load_failed',
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

  /// Unload the currently-loaded LLM model.
  Future<void> unload() async {
    if (!SdkState.shared.isInitialized) return;

    final logger = SDKLogger('RunAnywhere.UnloadModel');
    if (DartBridge.llm.isLoaded) {
      final modelId = DartBridge.llm.currentModelId ?? 'unknown';
      logger.info('Unloading model: $modelId');
      EventBus.shared.publish(SDKModelEvent.unloadStarted(modelId: modelId));
      DartBridge.llm.unload();
      EventBus.shared.publish(SDKModelEvent.unloadCompleted(modelId: modelId));
      logger.info('Model unloaded');
    }
  }

  /// Simple text generation — returns just the generated text.
  Future<String> chat(String prompt) async {
    final result = await generate(prompt);
    return result.text;
  }

  /// Full LLM generation — canonical cross-SDK positional signature.
  /// Returns proto [LLMGenerationResult].
  Future<LLMGenerationResult> generate(
    String prompt, [
    LLMGenerationOptions? options,
  ]) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }

    final opts = options ?? LLMGenerationOptions();
    final startTime = DateTime.now();

    if (!DartBridge.llm.isLoaded) {
      throw SDKException.componentNotReady(
        'LLM model not loaded. Call loadModel() first.',
      );
    }

    final modelId = DartBridge.llm.currentModelId ?? 'unknown';
    final modelInfo =
        await DartBridgeModelRegistry.instance.getProtoModel(modelId);
    final modelName = modelInfo?.name;

    try {
      final request = _toGenerateRequest(prompt, opts);
      final result = DartBridge.llm.generateProto(request);

      final endTime = DateTime.now();
      final latencyMs = endTime.difference(startTime).inMicroseconds / 1000.0;
      if (!result.hasModelUsed() || result.modelUsed.isEmpty) {
        result.modelUsed = modelId;
      }
      if (!result.hasGenerationTimeMs() || result.generationTimeMs <= 0) {
        result.generationTimeMs = latencyMs;
      }

      TelemetryService.shared.trackGeneration(
        modelId: modelId,
        modelName: modelName,
        promptTokens: result.inputTokens,
        completionTokens: result.tokensGenerated,
        latencyMs: latencyMs.round(),
        temperature: opts.hasTemperature() ? opts.temperature : 0.8,
        maxTokens: opts.hasMaxTokens() ? opts.maxTokens : 100,
        contextLength: modelInfo?.contextLength,
        tokensPerSecond: result.tokensPerSecond,
        isStreaming: false,
      );

      return result;
    } catch (e) {
      TelemetryService.shared.trackError(
        errorCode: 'generation_failed',
        errorMessage: e.toString(),
        context: {'model_id': modelId},
      );
      throw SDKException.generationFailed('$e');
    }
  }

  /// Streaming LLM generation — canonical cross-SDK positional signature.
  /// Returns `Stream<LLMStreamEvent>` — one event per token plus a
  /// terminal event (`isFinal == true`).
  Stream<LLMStreamEvent> generateStream(
    String prompt, [
    LLMGenerationOptions? options,
  ]) {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }

    final opts = options ?? LLMGenerationOptions();

    if (!DartBridge.llm.isLoaded) {
      throw SDKException.componentNotReady(
        'LLM model not loaded. Call loadModel() first.',
      );
    }

    return DartBridge.llm.generateStreamProto(
      _toGenerateRequest(prompt, opts, streaming: true),
    );
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  LLMGenerateRequest _toGenerateRequest(
    String prompt,
    LLMGenerationOptions? options, {
    bool streaming = false,
  }) {
    final opts = options ?? LLMGenerationOptions();
    return LLMGenerateRequest(
      prompt: prompt,
      maxTokens: opts.hasMaxTokens() ? opts.maxTokens : 100,
      temperature: opts.hasTemperature() ? opts.temperature : 0.8,
      topP: opts.hasTopP() ? opts.topP : null,
      topK: opts.hasTopK() ? opts.topK : null,
      repetitionPenalty:
          opts.hasRepetitionPenalty() ? opts.repetitionPenalty : null,
      stopSequences: opts.stopSequences,
      systemPrompt: opts.hasSystemPrompt() ? opts.systemPrompt : null,
      emitThoughts: opts.hasThinkingPattern(),
      streamingEnabled: streaming,
      preferredFramework:
          opts.hasPreferredFramework() ? opts.preferredFramework.name : null,
      jsonSchema: opts.hasJsonSchema() ? opts.jsonSchema : null,
      executionTarget:
          opts.hasExecutionTarget() ? opts.executionTarget.name : null,
    );
  }

  /// Cancel any in-flight LLM generation.
  Future<void> cancel() async {
    DartBridge.llm.cancelProto();
  }
}
