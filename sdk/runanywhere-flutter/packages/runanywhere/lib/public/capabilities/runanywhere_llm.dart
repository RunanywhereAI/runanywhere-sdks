// SPDX-License-Identifier: Apache-2.0
//
// Wave 2 LLM capability — aligned to Swift + proto. Returns proto
// LLMGenerationResult; streams Stream<LLMStreamEvent>.

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/foundation/error_types/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/component_types.pbenum.dart' show ComponentLifecycleState;
import 'package:runanywhere/generated/llm_options.pb.dart'
    show LLMGenerationOptions, LLMGenerationResult;
import 'package:runanywhere/generated/llm_service.pb.dart'
    show LLMGenerateRequest, LLMStreamEvent;
import 'package:runanywhere/generated/model_types.pb.dart' as model_pb;
import 'package:runanywhere/generated/model_types.pb.dart' show ModelInfo;
import 'package:runanywhere/generated/sdk_events.pb.dart'
    show ComponentLifecycleSnapshot, SDKEvent;
import 'package:runanywhere/generated/sdk_events.pbenum.dart' show SDKComponent;
import 'package:runanywhere/internal/sdk_event_factories.dart';
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_proto_utils.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/public/capabilities/runanywhere_model_lifecycle.dart';
import 'package:runanywhere/public/events/event_bus.dart';

/// LLM (text generation) capability surface.
///
/// Access via `RunAnywhereSDK.instance.llm`.
class RunAnywhereLLM {
  RunAnywhereLLM._();
  static final RunAnywhereLLM _instance = RunAnywhereLLM._();
  static RunAnywhereLLM get shared => _instance;

  /// True when commons lifecycle has a ready LLM model.
  bool get isLoaded {
    final snapshot = _lifecycleSnapshot;
    return snapshot != null &&
        snapshot.state ==
            ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY &&
        snapshot.modelId.isNotEmpty;
  }

  /// Currently-loaded LLM model ID from commons lifecycle, or null.
  String? get currentModelId {
    final snapshot = _lifecycleSnapshot;
    if (snapshot == null ||
        snapshot.state !=
            ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY ||
        snapshot.modelId.isEmpty) {
      return null;
    }
    return snapshot.modelId;
  }

  /// Currently-loaded LLM model metadata from commons lifecycle, or null.
  Future<ModelInfo?> currentModel() async {
    final current = await RunAnywhereModelLifecycle.shared.current(
      model_pb.CurrentModelRequest(
        category: model_pb.ModelCategory.MODEL_CATEGORY_LANGUAGE,
        includeModelMetadata: true,
      ),
    );
    if (current.modelId.isEmpty || !current.hasModel()) return null;
    return current.model;
  }

  /// Load an LLM model by ID through commons lifecycle routing.
  Future<void> load(String modelId) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }

    final logger = SDKLogger('RunAnywhere.LoadModel');
    logger.info('Loading model: $modelId');

    EventBus.shared.publish(SdkEventFactory.modelLoadStarted(modelId));

    try {
      final lifecycleResult = await RunAnywhereModelLifecycle.shared.load(
        model_pb.ModelLoadRequest(
          modelId: modelId,
          category: model_pb.ModelCategory.MODEL_CATEGORY_LANGUAGE,
          forceReload: true,
          validateAvailability: true,
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

      logger.info('Model loaded successfully: $modelId');

      EventBus.shared.publish(SdkEventFactory.modelLoadCompleted(modelId));
    } catch (e) {
      logger.error('Failed to load model: $e');
      EventBus.shared.publish(SdkEventFactory.modelLoadFailed(modelId, e));
      rethrow;
    }
  }

  /// Unload the currently-loaded LLM model.
  Future<void> unload() async {
    if (!DartBridge.isInitialized) return;

    final logger = SDKLogger('RunAnywhere.UnloadModel');
    final modelId = currentModelId;
    if (modelId == null) return;

    logger.info('Unloading model: $modelId');
    EventBus.shared.publish(SdkEventFactory.modelUnloadStarted(modelId));
    final result = await RunAnywhereModelLifecycle.shared.unload(
      model_pb.ModelUnloadRequest(
        modelId: modelId,
        category: model_pb.ModelCategory.MODEL_CATEGORY_LANGUAGE,
      ),
    );
    if (!result.success) {
      throw SDKException.invalidState(
        result.errorMessage.isNotEmpty
            ? result.errorMessage
            : 'LLM lifecycle unload failed',
      );
    }
    EventBus.shared.publish(SdkEventFactory.modelUnloadCompleted(modelId));
    logger.info('Model unloaded');
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
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }

    final opts = options ?? LLMGenerationOptions();
    final startTime = DateTime.now();

    final modelId = currentModelId;
    if (modelId == null) {
      throw SDKException.componentNotReady(
        'LLM model not loaded. Call loadModel() first.',
      );
    }

    try {
      final request = _toGenerateRequest(prompt, opts);
      final result = _generateProto(request);

      final endTime = DateTime.now();
      final latencyMs = endTime.difference(startTime).inMicroseconds / 1000.0;
      if (!result.hasModelUsed() || result.modelUsed.isEmpty) {
        result.modelUsed = modelId;
      }
      if (!result.hasGenerationTimeMs() || result.generationTimeMs <= 0) {
        result.generationTimeMs = latencyMs;
      }

      return result;
    } catch (e) {
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
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }

    final opts = options ?? LLMGenerationOptions();

    if (currentModelId == null) {
      throw SDKException.componentNotReady(
        'LLM model not loaded. Call loadModel() first.',
      );
    }

    return _generateStreamProto(
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
    _cancelProto();
  }

  ComponentLifecycleSnapshot? get _lifecycleSnapshot =>
      RunAnywhereModelLifecycle.shared.componentSnapshot(
        SDKComponent.SDK_COMPONENT_LLM,
      );

  LLMGenerationResult _generateProto(LLMGenerateRequest request) {
    final fn = RacNative.bindings.rac_llm_generate_proto;
    if (fn == null) {
      throw UnsupportedError('rac_llm_generate_proto is unavailable');
    }

    return DartBridgeProtoUtils.callRequest<LLMGenerationResult>(
      request: request,
      invoke: fn,
      decode: LLMGenerationResult.fromBuffer,
      symbol: 'rac_llm_generate_proto',
    );
  }

  Stream<LLMStreamEvent> _generateStreamProto(LLMGenerateRequest request) {
    final fn = RacNative.bindings.rac_llm_generate_stream_proto;
    if (fn == null) {
      return Stream<LLMStreamEvent>.error(
        UnsupportedError('rac_llm_generate_stream_proto is unavailable'),
      );
    }

    final controller = StreamController<LLMStreamEvent>(sync: false);
    ffi.NativeCallable<RacLlmStreamProtoCallbackNative>? callback;
    var sawTerminalEvent = false;

    Future<void> run() async {
      final bytes = request.writeToBuffer();
      final requestPtr = DartBridgeProtoUtils.copyBytes(bytes);

      try {
        callback = ffi.NativeCallable<RacLlmStreamProtoCallbackNative>.listener(
          (
            ffi.Pointer<ffi.Uint8> bytesPtr,
            int bytesLen,
            ffi.Pointer<ffi.Void> _,
          ) {
            if (controller.isClosed ||
                bytesPtr == ffi.nullptr ||
                bytesLen <= 0) {
              return;
            }

            try {
              final copy = Uint8List.fromList(bytesPtr.asTypedList(bytesLen));
              final event = LLMStreamEvent.fromBuffer(copy);
              sawTerminalEvent = sawTerminalEvent || event.isFinal;
              controller.add(event);
              if (event.isFinal) {
                unawaited(controller.close());
              }
            } catch (e, st) {
              controller.addError(e, st);
              unawaited(controller.close());
            }
          },
        );

        final rc = fn(
          requestPtr,
          bytes.length,
          callback!.nativeFunction,
          ffi.nullptr,
        );
        if (rc != RacResultCode.success && !controller.isClosed) {
          controller.addError(StateError(
            'rac_llm_generate_stream_proto failed: '
            '${RacResultCode.getMessage(rc)}',
          ));
          await controller.close();
        } else if (!sawTerminalEvent && !controller.isClosed) {
          await controller.close();
        }
      } catch (e, st) {
        if (!controller.isClosed) {
          controller.addError(e, st);
          await controller.close();
        }
      } finally {
        calloc.free(requestPtr);
        callback?.close();
        callback = null;
      }
    }

    controller.onCancel = () {
      try {
        _cancelProto();
      } finally {
        callback?.close();
        callback = null;
      }
    };

    unawaited(run());
    return controller.stream;
  }

  void _cancelProto() {
    final fn = RacNative.bindings.rac_llm_cancel_proto;
    if (fn == null) {
      throw UnsupportedError('rac_llm_cancel_proto is unavailable');
    }

    DartBridgeProtoUtils.callOut<SDKEvent>(
      invoke: fn,
      decode: SDKEvent.fromBuffer,
      symbol: 'rac_llm_cancel_proto',
    );
  }
}
