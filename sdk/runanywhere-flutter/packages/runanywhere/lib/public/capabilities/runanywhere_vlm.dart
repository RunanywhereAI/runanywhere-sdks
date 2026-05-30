// SPDX-License-Identifier: Apache-2.0
//
// VLM capability — uses proto VLMImage / VLMGenerationOptions / VLMResult.

import 'dart:async';

import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/component_types.pbenum.dart'
    show ComponentLifecycleState;
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
      if (!lifecycleResult.success) {
        throw SDKException.vlmModelLoadFailed(
          lifecycleResult.errorMessage.isNotEmpty
              ? lifecycleResult.errorMessage
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
    if (!result.success) {
      throw SDKException.invalidState(
        result.errorMessage.isNotEmpty
            ? result.errorMessage
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
    if (!DartBridge.isInitialized) throw SDKException.notInitialized();
    final modelId = await _requireLoadedModelId();

    final logger = SDKLogger('RunAnywhere.VLM.ProcessImage');
    final opts = _effectiveOptions(prompt, options ?? VLMGenerationOptions());

    try {
      final result = await DartBridge.vlm.processImageProto(
        _toGenerationRequest(image, opts, modelId),
      );

      logger.info(
        'VLM processing complete: ${result.completionTokens} tokens, '
        '${result.tokensPerSecond.toStringAsFixed(1)} tok/s',
      );

      return result;
    } catch (e) {
      logger.error('VLM processing failed: $e');
      rethrow;
    }
  }

  /// Stream image processing with generated VLM stream events.
  Stream<VLMStreamEvent> processImageStream(
    VLMImage image, {
    required String prompt,
    VLMGenerationOptions? options,
  }) async* {
    if (!DartBridge.isInitialized) throw SDKException.notInitialized();
    final modelId = await _requireLoadedModelId();

    final logger = SDKLogger('RunAnywhere.VLM.ProcessImageStream');
    final opts = _effectiveOptions(
      prompt,
      options ?? VLMGenerationOptions(),
      streaming: true,
    );

    try {
      yield* DartBridge.vlm.processImageStreamProto(
        _toGenerationRequest(image, opts, modelId),
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

  VLMGenerationRequest _toGenerationRequest(
    VLMImage image,
    VLMGenerationOptions options,
    String modelId,
  ) {
    return VLMGenerationRequest(
      images: [image],
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
