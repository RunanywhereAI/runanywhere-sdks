// SPDX-License-Identifier: Apache-2.0
//
// Diffusion capability backed by commons model lifecycle and lifecycle-owned
// generated-proto image generation.

import 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;
import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/generated/component_types.pbenum.dart'
    show ComponentLifecycleState;
import 'package:runanywhere/generated/diffusion_options.pb.dart'
    show
        DiffusionCapabilities,
        DiffusionConfiguration,
        DiffusionGenerationOptions,
        DiffusionGenerationRequest,
        DiffusionProgress,
        DiffusionResult;
import 'package:runanywhere/generated/model_types.pb.dart' as model_pb;
import 'package:runanywhere/generated/sdk_events.pb.dart'
    show ComponentLifecycleSnapshot;
import 'package:runanywhere/generated/sdk_events.pbenum.dart' show SDKComponent;
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_diffusion.dart';
import 'package:runanywhere/public/capabilities/runanywhere_model_lifecycle.dart';

/// Diffusion (image generation) capability surface.
///
/// NOTE: This namespace is NOT part of the Swift-as-reference cross-SDK v2
/// public contract yet — the `RunAnywhere.diffusion` getter and the public
/// barrel export were removed under swift-parity-002-followup-flutter so
/// Flutter does not advertise a surface that other SDKs do not implement.
/// The class is retained for the day the cross-SDK v2 contract for image
/// generation lands (proto-backed lifecycle stream/cancel/capabilities ABIs
/// across Swift/Kotlin/RN/Web); callers that absolutely need it today must
/// import this file directly and treat it as experimental/internal.
///
/// Load/current/unload state is owned by commons lifecycle; one-shot
/// generation uses the lifecycle-owned generated-proto commons ABI.
class RunAnywhereDiffusion {
  RunAnywhereDiffusion._();
  static final RunAnywhereDiffusion _instance = RunAnywhereDiffusion._();
  static RunAnywhereDiffusion get shared => _instance;

  /// True when commons lifecycle has a ready diffusion model.
  bool get isLoaded {
    final snapshot = _lifecycleSnapshot;
    return snapshot != null &&
        snapshot.state ==
            ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY &&
        snapshot.modelId.isNotEmpty;
  }

  /// Currently-loaded diffusion model id, or null.
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

  /// Load a diffusion model by registry ID through commons lifecycle routing.
  Future<void> load(String modelId, [DiffusionConfiguration? config]) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }

    final result = await RunAnywhereModelLifecycle.shared.load(
      model_pb.ModelLoadRequest(
        modelId: modelId,
        category: _diffusionCategory,
        forceReload: true,
        validateAvailability: true,
      ),
    );
    if (!result.success) {
      throw SDKException.modelLoadFailed(
        modelId,
        result.errorMessage.isNotEmpty
            ? result.errorMessage
            : 'Diffusion lifecycle load failed',
      );
    }
  }

  /// Unload the currently-loaded diffusion model.
  Future<void> unload() async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }

    final modelId = currentModelId ??
        (await RunAnywhereModelLifecycle.shared.current(
          model_pb.CurrentModelRequest(category: _diffusionCategory),
        ))
            .modelId;
    if (modelId.isEmpty) return;

    final result = await RunAnywhereModelLifecycle.shared.unload(
      model_pb.ModelUnloadRequest(
        modelId: modelId,
        category: _diffusionCategory,
      ),
    );
    if (!result.success) {
      throw SDKException.invalidState(
        result.errorMessage.isNotEmpty
            ? result.errorMessage
            : 'Diffusion lifecycle unload failed',
      );
    }
  }

  /// Generate an image from a text prompt.
  Future<DiffusionResult> generate(
    String prompt, [
    DiffusionGenerationOptions? options,
  ]) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    final modelId = await _requireLoadedModelId();
    return DartBridgeDiffusion.generateProto(
      DiffusionGenerationRequest(
        modelId: modelId,
        options: _effectiveOptions(prompt, options),
        metadata: <String, String>{'model_id': modelId}.entries,
      ),
    );
  }

  /// Stream generation progress.
  Stream<DiffusionProgress> generateStream(
    String prompt, [
    DiffusionGenerationOptions? options,
  ]) async* {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    await _requireLoadedModelId();
    _effectiveOptions(prompt, options, reportProgress: true);
    throw SDKException.featureNotAvailable(
      'Lifecycle-owned diffusion progress streaming is unavailable in '
      'Flutter. Use generate() for one-shot generation until commons exposes '
      'rac_diffusion_generate_stream_lifecycle_proto.',
    );
  }

  /// Cancel any in-flight generation.
  Future<void> cancel() async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    throw SDKException.featureNotAvailable(
      'Lifecycle-owned diffusion cancellation is unavailable in Flutter until '
      'commons exposes rac_diffusion_cancel_lifecycle_proto.',
    );
  }

  /// Backend capability discovery.
  DiffusionCapabilities capabilities() {
    if (!DartBridge.isInitialized) return DiffusionCapabilities();
    throw SDKException.featureNotAvailable(
      'Lifecycle-owned diffusion capability discovery is unavailable in '
      'Flutter until commons exposes rac_diffusion_capabilities_proto.',
    );
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

  Future<String> _requireLoadedModelId() async {
    final snapshotModelId = currentModelId;
    if (snapshotModelId != null) {
      return snapshotModelId;
    }
    final current = await RunAnywhereModelLifecycle.shared.current(
      model_pb.CurrentModelRequest(category: _diffusionCategory),
    );
    if (current.found && current.modelId.isNotEmpty) {
      return current.modelId;
    }
    throw SDKException.componentNotReady(
      'No diffusion model loaded through commons lifecycle. Call load() first.',
    );
  }

  ComponentLifecycleSnapshot? get _lifecycleSnapshot =>
      RunAnywhereModelLifecycle.shared.componentSnapshot(
        SDKComponent.SDK_COMPONENT_DIFFUSION,
      );

  static const _diffusionCategory =
      model_pb.ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION;
}
