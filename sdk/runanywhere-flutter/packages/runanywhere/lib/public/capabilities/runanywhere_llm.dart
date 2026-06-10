// SPDX-License-Identifier: Apache-2.0
//
// LLM capability — aligned to Swift + proto. Returns proto
// LLMGenerationResult; streams Stream<LLMStreamEvent>.

import 'dart:async';
import 'dart:io' as io;

import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/component_types.pbenum.dart'
    show ComponentLifecycleState;
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
    show JSONSchema, StructuredOutputResult;
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

    // Ensure the registry has a resolved `local_path`
    // before delegating to commons. Without this, `rac_llm_create` falls
    // through to `model_path_owned = model_id` (see
    // sdk/runanywhere-commons/src/features/llm/rac_llm_service.cpp:108-127)
    // and the engine ends up trying to open a path that's literally the
    // model ID (`smollm2-360m-q8_0`), which `stat()` rejects with -111 on
    // Android. Swift implicitly hits the same code path but its example
    // app populates `local_path` during registration / post-download;
    // Flutter Android relies on a downstream populate that misses for
    // downloaded llama.cpp models, so we backfill here. Mirrors Swift
    // `CppBridge+ModelLifecycle.swift` + `CppBridge+ModelPaths.swift`.
    await _ensureLocalPathPopulated(modelId, logger);

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
      if (!lifecycleResult.success) {
        throw SDKException.modelLoadFailed(
          modelId,
          lifecycleResult.errorMessage.isNotEmpty
              ? lifecycleResult.errorMessage
              : 'Model lifecycle proto load failed',
        );
      }

      logger.info('Model loaded successfully: $modelId');
    } catch (e) {
      logger.error('Failed to load model: $e');
      rethrow;
    }
  }

  /// Ensure the C++ model registry has a resolved primary-artifact path for
  /// [modelId] before commons hands the path to the engine plugin. No-op
  /// when the registry already has a non-empty `local_path` that points at a
  /// real file, when the model is not registered yet, or when path
  /// resolution fails (commons will surface a meaningful error in those
  /// cases).
  ///
  /// Mirrors the Swift SDK's reliance on `ModelInfo.localPath` already being
  /// resolved by the download / import pipeline (see
  /// `CppBridge+ModelRegistry.swift` -> `updateDownloadStatus`). On Flutter
  /// Android we observe gaps in that pipeline for llama.cpp gguf bundles
  /// post-download, so this helper backfills using
  /// `rac_model_paths_get_model_folder` + an extension-aware filesystem scan.
  Future<void> _ensureLocalPathPopulated(
    String modelId,
    SDKLogger logger,
  ) async {
    final ModelInfo? model =
        await DartBridge.modelRegistry.getProtoModel(modelId);
    if (model == null) {
      // Not registered yet; commons load will return a structured error.
      return;
    }

    final existing = model.localPath.trim();
    if (existing.isNotEmpty && _looksLikeReadableFile(existing)) {
      return;
    }

    final folder =
        DartBridge.modelPaths.getModelFolder(modelId, model.framework);
    if (folder == null || folder.isEmpty) {
      logger.debug(
        'Could not resolve model folder for $modelId; commons load will '
        'fall back to model_id as path',
      );
      return;
    }

    final resolved = _scanForPrimaryArtifact(folder, model);
    if (resolved == null) {
      logger.debug(
        'No primary artifact found under $folder for $modelId; commons load '
        'will fall back to model_id as path',
      );
      return;
    }

    if (resolved == existing) {
      return;
    }

    final updated = await DartBridge.modelRegistry.updateDownloadStatus(
      modelId,
      resolved,
    );
    if (!updated) {
      logger.debug(
        'updateDownloadStatus failed for $modelId (path=$resolved); commons '
        'load may still succeed via path-based registry lookup',
      );
      return;
    }
    logger.debug('Resolved local_path for $modelId: $resolved');
  }

  bool _looksLikeReadableFile(String path) {
    try {
      return io.FileSystemEntity.typeSync(path) ==
              io.FileSystemEntityType.file ||
          io.FileSystemEntity.typeSync(path) ==
              io.FileSystemEntityType.directory;
    } catch (_) {
      return false;
    }
  }

  /// Scan [folder] for the primary artifact of [model]. Picks the largest
  /// file matching the framework-canonical extension(s) so multi-shard
  /// bundles still resolve to a stable entry point. Returns `null` if the
  /// folder doesn't exist or no candidate is found.
  String? _scanForPrimaryArtifact(String folder, ModelInfo model) {
    final dir = io.Directory(folder);
    if (!dir.existsSync()) return null;

    final extensions = _canonicalExtensionsFor(model);
    io.File? best;
    int bestSize = -1;

    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! io.File) continue;
      final path = entity.path.toLowerCase();
      if (!extensions.any(path.endsWith)) continue;
      try {
        final size = entity.lengthSync();
        if (size > bestSize) {
          bestSize = size;
          best = entity;
        }
      } catch (_) {
        // Stat failed; skip this candidate.
      }
    }
    return best?.path;
  }

  /// Canonical primary-artifact extensions per framework. Mirrors the
  /// commons `rac_model_paths_resolve_artifact` heuristics; the registry
  /// path scan only needs to disambiguate the *primary* file, not the
  /// companion artifacts.
  List<String> _canonicalExtensionsFor(ModelInfo model) {
    switch (model.framework) {
      case model_pb.InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP:
        return const <String>['.gguf'];
      case model_pb.InferenceFramework.INFERENCE_FRAMEWORK_ONNX:
        return const <String>['.onnx'];
      case model_pb.InferenceFramework.INFERENCE_FRAMEWORK_TFLITE:
        return const <String>['.tflite'];
      case model_pb.InferenceFramework.INFERENCE_FRAMEWORK_MLX:
        return const <String>['.safetensors', '.npz'];
      default:
        return const <String>['.gguf', '.onnx', '.tflite', '.bin'];
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
    if (!result.success) {
      throw SDKException.invalidState(
        result.errorMessage.isNotEmpty
            ? result.errorMessage
            : 'LLM lifecycle unload failed',
      );
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

    final startTime = DateTime.now();

    // No "model loaded" pre-flight here — Swift has none; commons surfaces
    // a structured error when no model is loaded.
    final modelId = currentModelId;

    try {
      final effectiveRequest = LLMGenerateRequest()
        ..mergeFromMessage(request)
        ..streamingEnabled = false;
      final result = await _generateProto(effectiveRequest);

      final endTime = DateTime.now();
      final latencyMs = endTime.difference(startTime).inMicroseconds / 1000.0;
      if ((!result.hasModelUsed() || result.modelUsed.isEmpty) &&
          modelId != null) {
        result.modelUsed = modelId;
      }
      if (!result.hasGenerationTimeMs() || result.generationTimeMs <= 0) {
        result.generationTimeMs = latencyMs;
      }

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
    return generateStreamRequest(
      _toGenerateRequest(prompt, options, streaming: true),
    );
  }

  /// Generated-proto streaming text generation. Mirrors Swift
  /// `RunAnywhere.generateStream(_ request: RALLMGenerateRequest)`.
  Stream<LLMStreamEvent> generateStreamRequest(LLMGenerateRequest request) {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }

    // No "model loaded" pre-flight here — Swift has none; commons surfaces
    // a structured error when no model is loaded.
    final effectiveRequest = LLMGenerateRequest()
      ..mergeFromMessage(request)
      ..streamingEnabled = true;
    return _generateStreamProto(effectiveRequest);
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
    // Defaults mirror Swift `RALLMGenerationOptions.defaults()`
    // (RALLMTypes+CppBridge.swift:13-21): maxTokens=100, temperature=0.8,
    // topP=1.0, topK=0, repetitionPenalty=1.0.
    return LLMGenerateRequest(
      prompt: prompt,
      maxTokens: opts.hasMaxTokens() ? opts.maxTokens : 100,
      temperature: opts.hasTemperature() ? opts.temperature : 0.8,
      topP: opts.hasTopP() ? opts.topP : 1.0,
      topK: opts.hasTopK() ? opts.topK : 0,
      repetitionPenalty:
          opts.hasRepetitionPenalty() ? opts.repetitionPenalty : 1.0,
      stopSequences: opts.stopSequences,
      systemPrompt: opts.hasSystemPrompt() ? opts.systemPrompt : null,
      emitThoughts: opts.hasThinkingPattern(),
      streamingEnabled: streaming,
      preferredFramework:
          opts.hasPreferredFramework() ? opts.preferredFramework.name : null,
      jsonSchema: _jsonSchemaForOptions(opts),
      executionTarget:
          opts.hasExecutionTarget() ? opts.executionTarget.name : null,
      seed: opts.hasSeed() ? opts.seed : null,
      frequencyPenalty:
          opts.hasFrequencyPenalty() ? opts.frequencyPenalty : null,
      presencePenalty: opts.hasPresencePenalty() ? opts.presencePenalty : null,
      minP: opts.hasMinP() ? opts.minP : null,
      grammar: opts.hasGrammar() ? opts.grammar : null,
      responseFormat: opts.hasResponseFormat() ? opts.responseFormat : null,
      echoPrompt: opts.hasEchoPrompt() ? opts.echoPrompt : null,
      nThreads: opts.hasNThreads() ? opts.nThreads : null,
    );
  }

  String? _jsonSchemaForOptions(LLMGenerationOptions opts) {
    if (opts.hasStructuredOutput()) {
      final structured = opts.structuredOutput;
      if (structured.hasJsonSchema() && structured.jsonSchema.isNotEmpty) {
        return structured.jsonSchema;
      }
      if (structured.hasSchema() && structured.schema.rawJson.isNotEmpty) {
        return structured.schema.rawJson;
      }
    }
    return opts.hasJsonSchema() ? opts.jsonSchema : null;
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
      SDKLogger('RunAnywhere.cancelGeneration')
          .warning('cancelGeneration failed: $e');
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
    required JSONSchema schema,
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

    Future<void> run() async {
      try {
        // Phase-2 readiness gate, mirroring Swift's `try await
        // ensureServicesReady()` (RunAnywhere+TextGeneration.swift:77).
        // The http_applicable latch keeps this O(1) offline — commons marks
        // HTTP setup not-applicable, so the guard no longer re-attempts a
        // remote round-trip (the old ~4s DNS stall) on every send.
        await DartBridge.ensureServicesReady();
      } catch (e) {
        if (!controller.isClosed) {
          controller
              .addError(e is SDKException ? e : SDKException.generationFailed('$e'));
          await controller.close();
        }
        return;
      }
      final upstream = DartBridgeLLM.shared.generateStreamProto(request);
      await controller.addStream(upstream);
      await controller.close();
    }

    controller.onCancel = _cancelProto;

    unawaited(run());
    return controller.stream;
  }

  void _cancelProto() {
    DartBridgeLLM.shared.cancelProto();
  }
}
