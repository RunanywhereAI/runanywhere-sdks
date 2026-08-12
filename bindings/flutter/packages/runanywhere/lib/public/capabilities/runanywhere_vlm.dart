// SPDX-License-Identifier: Apache-2.0
//
// VLM capability — uses proto VLMImage / LLMGenerationOptions / VLMResult.
//
// `VLMGenerationOptions` was deleted outright (idl/vlm_options.proto): its 11
// sampling fields were name-for-name copies of `LLMGenerationOptions` with
// drifted defaults, so VLM now shares the exact same generated options type
// the text-generation path uses. `vision`/`VLMVisionOptions` carries the four
// genuinely vision-specific knobs; this legacy capability class does not
// surface them yet (parity with the v3 `RunAnywhere.vlm` namespace, which
// also defaults `vision` unset).

import 'dart:async';

import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/component_types.pbenum.dart'
    show ComponentLifecycleState;
import 'package:runanywhere/generated/convenience/ra_convenience.dart';
import 'package:runanywhere/generated/llm_options.pb.dart'
    show LLMGenerationOptions;
import 'package:runanywhere/generated/model_types.pb.dart' as model_pb;
import 'package:runanywhere/generated/sdk_events.pb.dart'
    show ComponentLifecycleSnapshot;
import 'package:runanywhere/generated/sdk_events.pbenum.dart' show SDKComponent;
import 'package:runanywhere/generated/vlm_options.pb.dart';
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/public/capabilities/runanywhere_model_lifecycle.dart';

/// VLM (vision-language model) capability surface.
///
/// Access via `RunAnywhere.vlm`.
class RunAnywhereVLM {
  RunAnywhereVLM._();
  static final RunAnywhereVLM _instance = RunAnywhereVLM._();
  static RunAnywhereVLM get shared => _instance;

  /// True when commons lifecycle has a ready VLM model.
  bool get isLoaded {
    final snapshot = _lifecycleSnapshot;
    return snapshot != null &&
        snapshot.state ==
            ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY &&
        snapshot.modelId.isNotEmpty;
  }

  /// Currently-loaded VLM model ID from commons lifecycle, or null.
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

  /// Load a VLM model by ID.
  Future<void> load(String modelId) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }

    final logger = SDKLogger('RunAnywhere.LoadVLMModel');
    logger.info('Loading VLM model: $modelId');

    // C++ commons auto-emits VLM model load started/completed/failed events.
    try {
      final lifecycleResult = await RunAnywhereModelLifecycle.shared.load(
        model_pb.ModelLoadRequest(
          modelId: modelId,
          forceReload: true,
          validateAvailability: true,
        ),
      );
      if (lifecycleResult.hasError()) {
        throw SDKException.vlmModelLoadFailed(
          lifecycleResult.error.message.isNotEmpty
              ? lifecycleResult.error.message
              : 'VLM lifecycle load failed',
        );
      }

      logger.info('VLM model loaded successfully: $modelId');
    } catch (e) {
      logger.error('Failed to load VLM model: $e');
      rethrow;
    }
  }

  /// Unload the currently-loaded VLM model.
  Future<void> unload() async {
    if (!DartBridge.isInitialized) throw SDKException.notInitialized();
    var modelId = currentModelId;
    var category = model_pb.ModelCategory.MODEL_CATEGORY_UNSPECIFIED;
    if (modelId == null) {
      final current = await _currentVlmLifecycleResult();
      modelId = current?.modelId;
      category = current?.category ??
          model_pb.ModelCategory.MODEL_CATEGORY_UNSPECIFIED;
    }
    if (modelId == null) {
      return;
    }
    final result = await RunAnywhereModelLifecycle.shared.unload(
      model_pb.ModelUnloadRequest(
        modelId: modelId,
        category: category,
      ),
    );
    if (result.hasError()) {
      throw SDKException.invalidState(
        result.error.message.isNotEmpty
            ? result.error.message
            : 'VLM lifecycle unload failed',
      );
    }
  }

  /// Cancel any in-flight VLM generation.
  ///
  /// Mirrors Swift `RunAnywhere.cancelVLMGeneration()`.
  Future<void> cancelVLMGeneration() async {
    DartBridge.vlm.cancel();
  }

  /// Process an image with VLM (full result with metrics).
  ///
  /// Canonical cross-SDK shape (mirrors Swift
  /// `RunAnywhere.vlm.generate(image:prompt:options:)`): the prompt travels
  /// as [prompt], and sampling is the same generated `LLMGenerationOptions`
  /// the text-generation path uses (`VLMGenerationOptions` was deleted
  /// outright — idl/vlm_options.proto).
  Future<VLMResult> processImage(
    VLMImage image, {
    String? prompt,
    LLMGenerationOptions? options,
  }) async {
    if (!DartBridge.isInitialized) throw SDKException.notInitialized();
    final modelId = await _requireLoadedModelId();

    final logger = SDKLogger('RunAnywhere.VLM.ProcessImage');
    final opts = _effectiveOptions(options);

    try {
      final result = await DartBridge.vlm.processImageProto(
        _toGenerationRequest(image, prompt ?? '', opts, modelId),
      );

      logger.info(
        'VLM processing complete: ${result.usage.outputTokens} tokens, '
        '${result.usage.decodeTokensPerSecond.toStringAsFixed(1)} tok/s',
      );

      return result;
    } catch (e) {
      logger.error('VLM processing failed: $e');
      rethrow;
    }
  }

  /// Stream image processing with generated VLM stream events.
  ///
  /// Canonical cross-SDK shape (mirrors Swift
  /// `RunAnywhere.vlm.generateStream(image:prompt:options:)`): the prompt
  /// travels as [prompt], sampling shares `LLMGenerationOptions` with the
  /// text-generation path.
  Stream<VLMStreamEvent> processImageStream(
    VLMImage image, {
    String? prompt,
    LLMGenerationOptions? options,
  }) async* {
    if (!DartBridge.isInitialized) throw SDKException.notInitialized();
    final modelId = await _requireLoadedModelId();

    final logger = SDKLogger('RunAnywhere.VLM.ProcessImageStream');
    final opts = _effectiveOptions(options);

    try {
      yield* DartBridge.vlm.processImageStreamProto(
        _toGenerationRequest(image, prompt ?? '', opts, modelId),
      );
    } catch (e) {
      logger.error('Failed to start VLM streaming: $e');
      rethrow;
    }
  }

  LLMGenerationOptions _effectiveOptions(LLMGenerationOptions? options) {
    // Fill unset fields from the generated defaults, which come from the
    // rac_default annotations in idl/llm_options.proto (VLM shares the text
    // path's sampling options now).
    final d = LLMGenerationOptionsConvenience.defaults();
    final opts = (options ?? LLMGenerationOptions()).deepCopy();
    if (!opts.hasMaxOutputTokens()) {
      opts.maxOutputTokens = d.maxOutputTokens;
    }
    if (!opts.hasTemperature()) {
      opts.temperature = d.temperature;
    }
    if (!opts.hasTopP()) {
      opts.topP = d.topP;
    }
    if (!opts.hasTopK()) {
      opts.topK = d.topK;
    }
    return opts;
  }

  VLMGenerationRequest _toGenerationRequest(
    VLMImage image,
    String prompt,
    LLMGenerationOptions options,
    String modelId,
  ) {
    return VLMGenerationRequest(
      images: [image],
      prompt: prompt,
      options: options,
      modelId: modelId,
    );
  }

  Future<String> _requireLoadedModelId() async {
    final snapshotModelId = currentModelId;
    if (snapshotModelId != null) {
      return snapshotModelId;
    }
    final current = await _currentVlmLifecycleResult();
    if (current == null) {
      throw SDKException.vlmNotInitialized();
    }
    return current.modelId;
  }

  Future<model_pb.CurrentModelResult?> _currentVlmLifecycleResult() async {
    for (final category in _vlmCategories) {
      final current = await RunAnywhereModelLifecycle.shared.current(
        model_pb.CurrentModelRequest(
          category: category,
          includeModelMetadata: true,
        ),
      );
      if (current.found && current.modelId.isNotEmpty) {
        return current;
      }
    }
    return null;
  }

  ComponentLifecycleSnapshot? get _lifecycleSnapshot =>
      RunAnywhereModelLifecycle.shared.componentSnapshot(
        SDKComponent.SDK_COMPONENT_VLM,
      );

  static const List<model_pb.ModelCategory> _vlmCategories = [
    model_pb.ModelCategory.MODEL_CATEGORY_MULTIMODAL,
    model_pb.ModelCategory.MODEL_CATEGORY_VISION,
  ];
}
