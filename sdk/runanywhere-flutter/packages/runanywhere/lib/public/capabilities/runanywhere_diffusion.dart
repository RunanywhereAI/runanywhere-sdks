// SPDX-License-Identifier: Apache-2.0
//
// Diffusion capability using the generated-proto C++ service ABI.

import 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;
import 'package:runanywhere/foundation/error_types/sdk_exception.dart';
import 'package:runanywhere/generated/diffusion_options.pb.dart'
    show
        DiffusionCapabilities,
        DiffusionConfiguration,
        DiffusionGenerationOptions,
        DiffusionProgress,
        DiffusionResult;
import 'package:runanywhere/internal/sdk_state.dart';
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_diffusion.dart';
import 'package:runanywhere/public/capabilities/runanywhere_models.dart';

/// Diffusion (image generation) capability surface.
///
/// Access via `RunAnywhereSDK.instance.diffusion`.
class RunAnywhereDiffusion {
  RunAnywhereDiffusion._();
  static final RunAnywhereDiffusion _instance = RunAnywhereDiffusion._();
  static RunAnywhereDiffusion get shared => _instance;

  String? _currentModelId;

  /// True when a diffusion model is currently loaded.
  bool get isLoaded => DartBridgeDiffusion.isLoaded();

  /// Currently-loaded diffusion model id, or null.
  String? get currentModelId => _currentModelId;

  /// Load a diffusion model by registry ID.
  Future<void> load(String modelId, [DiffusionConfiguration? config]) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }

    final models = await RunAnywhereModels.shared.available();
    final model = models.where((m) => m.id == modelId).firstOrNull;
    if (model == null) {
      throw SDKException.modelNotFound('Diffusion model not found: $modelId');
    }
    if (model.localPath.isEmpty) {
      throw SDKException.modelNotDownloaded(
        'Diffusion model is not downloaded. Call downloadModel() first.',
      );
    }

    final resolvedPath =
        await DartBridge.modelPaths.resolveModelFilePath(model);
    if (resolvedPath == null) {
      throw SDKException.modelNotFound(
        'Could not resolve diffusion model file path for: $modelId',
      );
    }

    DartBridgeDiffusion.loadModel(modelId, resolvedPath);
    _currentModelId = modelId;
  }

  /// Unload the currently-loaded diffusion model.
  Future<void> unload() async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    DartBridgeDiffusion.unload();
    _currentModelId = null;
  }

  /// Generate an image from a text prompt.
  Future<DiffusionResult> generate(
    String prompt, [
    DiffusionGenerationOptions? options,
  ]) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    return DartBridgeDiffusion.generateProto(
        _effectiveOptions(prompt, options));
  }

  /// Stream generation progress.
  Stream<DiffusionProgress> generateStream(
    String prompt, [
    DiffusionGenerationOptions? options,
  ]) {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    return DartBridgeDiffusion.generateWithProgressProto(
      _effectiveOptions(prompt, options, reportProgress: true),
    );
  }

  /// Cancel any in-flight generation.
  Future<void> cancel() async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    DartBridgeDiffusion.cancel();
  }

  /// Backend capability discovery.
  DiffusionCapabilities capabilities() {
    if (!SdkState.shared.isInitialized) return DiffusionCapabilities();
    return DartBridgeDiffusion.capabilitiesProto();
  }

  DiffusionGenerationOptions _effectiveOptions(
    String prompt,
    DiffusionGenerationOptions? options, {
    bool reportProgress = false,
  }) {
    final request = options?.deepCopy() ?? DiffusionGenerationOptions();
    request.prompt = prompt;
    if (reportProgress && !request.hasReportIntermediateImages()) {
      request.reportIntermediateImages = true;
    }
    if (reportProgress && !request.hasProgressStride()) {
      request.progressStride = 1;
    }
    return request;
  }
}
