// SPDX-License-Identifier: Apache-2.0
//
// LLM capability — aligned to Swift + proto. Returns proto
// LLMGenerationResult; streams Stream<LLMStreamEvent>.

import 'dart:async';

import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/chat.pb.dart' as chat_pb;
import 'package:runanywhere/generated/chat.pbenum.dart' show MessageRole;
import 'package:runanywhere/generated/component_types.pbenum.dart'
    show ComponentLifecycleState;
import 'package:runanywhere/generated/convenience/ra_convenience.dart';
import 'package:runanywhere/generated/llm_options.pb.dart'
    show LLMGenerationOptions, LLMGenerationResult;
import 'package:runanywhere/generated/llm_service.pb.dart'
    show LLMGenerateRequest, LLMStreamEvent;
import 'package:runanywhere/generated/model_types.pb.dart' as model_pb;
import 'package:runanywhere/generated/model_types.pb.dart' show ModelInfo;
import 'package:runanywhere/generated/sdk_events.pb.dart'
    show ComponentLifecycleSnapshot;
import 'package:runanywhere/generated/sdk_events.pbenum.dart' show SDKComponent;
import 'package:runanywhere/generated/structured_output.pb.dart'
    show StructuredOutputResult;
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_llm.dart';
import 'package:runanywhere/native/dart_bridge_structured_output.dart';
import 'package:runanywhere/public/capabilities/runanywhere_model_lifecycle.dart';

/// LLM (text generation) capability surface.
///
/// Access via `RunAnywhere.llm`.
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
    await DartBridge.ensureServicesReady();

    final logger = SDKLogger('RunAnywhere.LoadModel');
    logger.info('Loading model: $modelId');

    // C++ commons auto-emits model load started/completed/failed events
    // via `llm_component.cpp`; Dart does not re-emit duplicates.
    try {
      final lifecycleResult = await RunAnywhereModelLifecycle.shared.load(
        model_pb.ModelLoadRequest(
          modelId: modelId,
          category: model_pb.ModelCategory.MODEL_CATEGORY_LANGUAGE,
          forceReload: true,
          validateAvailability: true,
        ),
      );
      if (lifecycleResult.hasError()) {
        throw SDKException(lifecycleResult.error);
      }

      logger.info('Model loaded successfully: $modelId');
    } catch (e) {
      logger.error('Failed to load model: $e');
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
    // C++ commons auto-emits model unload started/completed events.
    final result = await RunAnywhereModelLifecycle.shared.unload(
      model_pb.ModelUnloadRequest(
        modelId: modelId,
        category: model_pb.ModelCategory.MODEL_CATEGORY_LANGUAGE,
      ),
    );
    if (result.hasError()) {
      throw SDKException(result.error);
    }
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
    return generateRequest(_toGenerateRequest(prompt, options));
  }

  /// Generated-proto text generation. Mirrors Swift
  /// `RunAnywhere.generate(_ request: RALLMGenerateRequest)`.
  Future<LLMGenerationResult> generateRequest(
    LLMGenerateRequest request,
  ) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    // Phase-2 readiness gate, mirroring Swift's `try await
    // ensureServicesReady()` (RunAnywhere+TextGeneration.swift:48). With the
    // http_applicable latch this is O(1) offline — commons marks HTTP setup
    // not-applicable and the guard short-circuits instead of re-attempting
    // a remote round-trip per call.
    await DartBridge.ensureServicesReady();

    // No "model loaded" pre-flight here — Swift has none; commons surfaces
    // a structured error when no model is loaded.
    final modelId = currentModelId;

    try {
      final effectiveRequest = request.deepCopy();
      effectiveRequest.options = _canonicalOptions(
        request.hasOptions() ? request.options : null,
      );
      final result = await _generateProto(effectiveRequest);

      if ((!result.hasModelUsed() || result.modelUsed.isEmpty) &&
          modelId != null) {
        result.modelUsed = modelId;
      }
      // generation_time_ms is commons-owned — never backfill from wall clock.

      return result;
    } catch (e) {
      if (e is SDKException) rethrow;
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
    return generateStreamRequest(_toGenerateRequest(prompt, options));
  }

  /// Generated-proto streaming text generation. Mirrors Swift
  /// `RunAnywhere.generateStream(_ request: RALLMGenerateRequest)`.
  Stream<LLMStreamEvent> generateStreamRequest(LLMGenerateRequest request) {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }

    // No "model loaded" pre-flight here — Swift has none; commons surfaces
    // a structured error when no model is loaded.
    final effectiveRequest = request.deepCopy();
    effectiveRequest.options = _canonicalOptions(
      request.hasOptions() ? request.options : null,
    );
    return _generateStreamProto(effectiveRequest);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  LLMGenerateRequest _toGenerateRequest(
    String prompt,
    LLMGenerationOptions? options,
  ) {
    // `LLMGenerateRequest.prompt` is reserved (idl/llm_service.proto): the
    // whole conversation now travels as `messages`, oldest first, ending
    // with the turn the model must answer. This single-prompt entry point
    // has no history, so `messages` is just the one live user turn.
    return LLMGenerateRequest(
      options: _canonicalOptions(options),
      messages: [chat_pb.ChatMessage(role: MessageRole.MESSAGE_ROLE_USER, content: prompt)],
    );
  }

  LLMGenerationOptions _canonicalOptions(LLMGenerationOptions? options) {
    // Fill unset fields from the generated defaults, which come from the
    // rac_default annotations in idl/llm_options.proto.
    final d = LLMGenerationOptionsConvenience.defaults();
    final requestOptions = (options ?? LLMGenerationOptions()).deepCopy();
    if (!requestOptions.hasMaxOutputTokens() ||
        requestOptions.maxOutputTokens <= 0) {
      requestOptions.maxOutputTokens = d.maxOutputTokens;
    }
    if (!requestOptions.hasTemperature()) {
      requestOptions.temperature = d.temperature;
    }
    if (!requestOptions.hasTopP() || requestOptions.topP <= 0) {
      requestOptions.topP = d.topP;
    }
    if (!requestOptions.hasRepeatPenalty() ||
        requestOptions.repeatPenalty <= 0) {
      requestOptions.repeatPenalty = d.repeatPenalty;
    }
    return requestOptions;
  }

  /// Cancel any in-flight LLM generation.
  ///
  /// Mirrors Swift `RunAnywhere.cancelGeneration()`: no-op when not
  /// initialized; logs a warning on failure rather than surfacing the
  /// exception to the caller (cancel is best-effort).
  void cancelGeneration() {
    if (!DartBridge.isInitialized) return;
    try {
      _cancelProto();
    } catch (e) {
      SDKLogger(
        'RunAnywhere.cancelGeneration',
      ).warning('cancelGeneration failed: $e');
    }
  }

  /// Extract structured output from arbitrary [text] using the provided JSON
  /// [schema]. Delegates to the generated structured-output parse proto ABI
  /// so commons owns extraction, canonicalization, and schema validation.
  ///
  /// Mirrors Swift's `RunAnywhere.extractStructuredOutput(text:schema:)` in
  /// `RunAnywhere+TextGeneration.swift`.
  StructuredOutputResult extractStructuredOutput({
    required String text,
    required String schema,
  }) {
    return DartBridgeStructuredOutput.shared.parse(
      DartBridgeStructuredOutput.shared.makeParseRequest(
        text: text,
        schema: schema,
      ),
    );
  }

  ComponentLifecycleSnapshot? get _lifecycleSnapshot =>
      RunAnywhereModelLifecycle.shared.componentSnapshot(
        SDKComponent.SDK_COMPONENT_LLM,
      );

  Future<LLMGenerationResult> _generateProto(LLMGenerateRequest request) {
    return DartBridgeLLM.shared.generateProto(request);
  }

  Stream<LLMStreamEvent> _generateStreamProto(LLMGenerateRequest request) {
    final controller = StreamController<LLMStreamEvent>(sync: false);
    // onCancel also fires on normal completion; only cancel a still-running
    // generation so a finished stream doesn't emit a spurious cancellation.
    var completed = false;

    // `run()` is started detached from `onListen`, so anything it throws is an
    // unhandled async error rather than something the caller can catch. The
    // whole body therefore has to funnel failures into the controller and
    // close it on every path, or a consumer awaiting the stream hangs forever.
    // Mirrors the STT capability's try/catch/finally.
    Future<void> run() async {
      try {
        // Phase-2 readiness gate, mirroring Swift's `try await
        // ensureServicesReady()` (RunAnywhere+TextGeneration.swift:77).
        // The http_applicable latch keeps this O(1) offline — commons marks
        // HTTP setup not-applicable, so the guard no longer re-attempts a
        // remote round-trip (the old ~4s DNS stall) on every send.
        await DartBridge.ensureServicesReady();
        final upstream = DartBridgeLLM.shared.generateStreamProto(request);
        await controller.addStream(upstream);
        // Set before the `finally` closes: closing delivers `done`, which
        // fires `onCancel`, and a finished generation must not be cancelled.
        completed = true;
      } catch (e) {
        // The generation is over either way — nothing left to cancel.
        completed = true;
        if (!controller.isClosed) {
          controller.addError(
            e is SDKException ? e : SDKException.generationFailed('$e'),
          );
        }
      } finally {
        if (!controller.isClosed) {
          await controller.close();
        }
      }
    }

    // Start the worker only once a listener attaches (canonical lazy pattern),
    // so generation can't begin — and tokens can't be produced — before the
    // subscriber is ready. Mirrors the VLM bridge's onListen deferral.
    controller.onListen = () => unawaited(run());
    controller.onCancel = () {
      if (!completed) _cancelProto();
    };
    return controller.stream;
  }

  void _cancelProto() {
    DartBridgeLLM.shared.cancelProto();
  }
}
