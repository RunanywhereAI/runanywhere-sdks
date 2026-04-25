// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_llm.dart — v4 LLM capability. Owns text generation,
// model loading, and streaming.

import 'dart:async';
import 'dart:convert';

import 'package:runanywhere/adapters/llm_stream_adapter.dart';
import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/data/network/telemetry_service.dart';
import 'package:runanywhere/foundation/error_types/sdk_error.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/llm_service.pb.dart' show LLMStreamEvent;
import 'package:runanywhere/internal/sdk_state.dart';
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_model_registry.dart'
    hide ModelInfo;
import 'package:runanywhere/native/dart_bridge_structured_output.dart';
import 'package:runanywhere/public/capabilities/runanywhere_models.dart';
import 'package:runanywhere/public/events/event_bus.dart';
import 'package:runanywhere/public/events/sdk_event.dart';
import 'package:runanywhere/public/types/generation_types.dart';

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
      throw SDKError.notInitialized();
    }

    final logger = SDKLogger('RunAnywhere.LoadModel');
    logger.info('Loading model: $modelId');
    final startTime = DateTime.now().millisecondsSinceEpoch;

    EventBus.shared.publish(SDKModelEvent.loadStarted(modelId: modelId));

    try {
      final models = await RunAnywhereModels.shared.available();
      final model = models.where((m) => m.id == modelId).firstOrNull;

      if (model == null) {
        throw SDKError.modelNotFound('Model not found: $modelId');
      }

      if (model.localPath == null) {
        throw SDKError.modelNotDownloaded(
          'Model is not downloaded. Call downloadModel() first.',
        );
      }

      final resolvedPath =
          await DartBridge.modelPaths.resolveModelFilePath(model);
      if (resolvedPath == null) {
        throw SDKError.modelNotFound(
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

      if (!DartBridge.llm.isLoaded) {
        throw SDKError.modelLoadFailed(
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

  /// Full LLM generation with options + structured output + telemetry.
  Future<LLMGenerationResult> generate(
    String prompt, {
    LLMGenerationOptions? options,
  }) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKError.notInitialized();
    }

    final opts = options ?? const LLMGenerationOptions();
    final startTime = DateTime.now();

    if (!DartBridge.llm.isLoaded) {
      throw SDKError.componentNotReady(
        'LLM model not loaded. Call loadModel() first.',
      );
    }

    final modelId = DartBridge.llm.currentModelId ?? 'unknown';
    final modelInfo =
        await DartBridgeModelRegistry.instance.getPublicModel(modelId);
    final modelName = modelInfo?.name;

    String? effectiveSystemPrompt = opts.systemPrompt;
    if (opts.structuredOutput != null) {
      final jsonSystemPrompt = DartBridgeStructuredOutput.shared
          .getSystemPrompt(opts.structuredOutput!.schema);
      if (effectiveSystemPrompt != null && effectiveSystemPrompt.isNotEmpty) {
        effectiveSystemPrompt = '$jsonSystemPrompt\n\n$effectiveSystemPrompt';
      } else {
        effectiveSystemPrompt = jsonSystemPrompt;
      }
    }

    try {
      final result = await DartBridge.llm.generate(
        prompt,
        maxTokens: opts.maxTokens,
        temperature: opts.temperature,
        systemPrompt: effectiveSystemPrompt,
      );

      final endTime = DateTime.now();
      final latencyMs = endTime.difference(startTime).inMicroseconds / 1000.0;
      final tokensPerSecond = result.totalTimeMs > 0
          ? (result.completionTokens / result.totalTimeMs) * 1000
          : 0.0;

      TelemetryService.shared.trackGeneration(
        modelId: modelId,
        modelName: modelName,
        promptTokens: result.promptTokens,
        completionTokens: result.completionTokens,
        latencyMs: latencyMs.round(),
        temperature: opts.temperature,
        maxTokens: opts.maxTokens,
        contextLength: modelInfo?.contextLength,
        tokensPerSecond: tokensPerSecond,
        isStreaming: false,
      );

      Map<String, dynamic>? structuredData;
      if (opts.structuredOutput != null) {
        try {
          final jsonString =
              DartBridgeStructuredOutput.shared.extractJson(result.text);
          if (jsonString != null) {
            final parsed = jsonDecode(jsonString);
            structuredData = _normalizeStructuredData(parsed);
          }
        } catch (e) {
          SDKLogger('StructuredOutputHandler')
              .info('JSON extraction/parse failed: $e');
        }
      }

      return LLMGenerationResult(
        text: result.text,
        inputTokens: result.promptTokens,
        tokensUsed: result.completionTokens,
        modelUsed: modelId,
        latencyMs: latencyMs,
        framework: 'llamacpp',
        tokensPerSecond: tokensPerSecond,
        structuredData: structuredData,
      );
    } on SDKError {
      rethrow;
    } catch (e) {
      TelemetryService.shared.trackError(
        errorCode: 'generation_failed',
        errorMessage: e.toString(),
        context: {'model_id': modelId},
      );
      throw SDKError.generationFailed('$e');
    }
  }

  /// v2 close-out Phase G-2: streaming LLM generation returns
  /// `Stream<LLMStreamEvent>` sourced from the Phase G-2
  /// [`LLMStreamAdapter`]. One event per token plus a terminal event
  /// (`isFinal == true`). Callers derive metrics from the event
  /// sequence; the previous `LLMStreamingResult` (stream + result
  /// future + cancel) wrapper was DELETED together with the hand-rolled
  /// StreamController + telemetry-collector shim.
  Stream<LLMStreamEvent> generateStream(
    String prompt, {
    LLMGenerationOptions? options,
  }) {
    if (!SdkState.shared.isInitialized) {
      throw SDKError.notInitialized();
    }

    final opts = options ?? const LLMGenerationOptions();

    if (!DartBridge.llm.isLoaded) {
      throw SDKError.componentNotReady(
        'LLM model not loaded. Call loadModel() first.',
      );
    }

    String? effectiveSystemPrompt = opts.systemPrompt;
    if (opts.structuredOutput != null) {
      final jsonSystemPrompt = DartBridgeStructuredOutput.shared
          .getSystemPrompt(opts.structuredOutput!.schema);
      if (effectiveSystemPrompt != null && effectiveSystemPrompt.isNotEmpty) {
        effectiveSystemPrompt = '$jsonSystemPrompt\n\n$effectiveSystemPrompt';
      } else {
        effectiveSystemPrompt = jsonSystemPrompt;
      }
    }

    final handle = DartBridge.llm.getHandle();
    final adapter = LLMStreamAdapter(handle);
    final eventStream = adapter.stream();

    // Kick off the C++ driver. Events are delivered via the proto-byte
    // callback set by the adapter; the returned Stream<String> of token
    // text from DartBridge.llm.generateStream is ignored here — we only
    // need to drive the engine loop.
    final driver = DartBridge.llm.generateStream(
      prompt,
      maxTokens: opts.maxTokens,
      temperature: opts.temperature,
      systemPrompt: effectiveSystemPrompt,
    );
    DartBridge.llm.setActiveStreamSubscription(
      driver.listen(
        (_) {/* ignore struct-callback tokens; we use proto events */},
        onError: (Object _) {/* surfaced via terminal proto event */},
        onDone: () {
          DartBridge.llm.setActiveStreamSubscription(null);
        },
      ),
    );

    return eventStream;
  }

  /// Cancel any in-flight LLM generation.
  Future<void> cancel() async {
    DartBridge.llm.cancelGeneration();
  }

  // -- private helpers ------------------------------------------------------

  /// Normalize parsed JSON to `Map<String, dynamic>`. Lists are wrapped
  /// in `{'items': ...}`; non-string keys coerce to String; everything
  /// else returns null.
  static Map<String, dynamic>? _normalizeStructuredData(dynamic parsed) {
    if (parsed is Map<String, dynamic>) {
      return parsed;
    } else if (parsed is List) {
      return {'items': parsed};
    } else if (parsed is Map) {
      try {
        return parsed.map((k, v) => MapEntry(k.toString(), v));
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
