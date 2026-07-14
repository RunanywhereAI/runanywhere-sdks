// SPDX-License-Identifier: Apache-2.0
//
// Diffusion (image generation) capability backed by commons model lifecycle
// and the lifecycle-owned generated-proto image-generation ABI.
//
// Mirrors the Swift facade that landed in 0.20.10
// (`RunAnywhere+Diffusion.swift` + `CppBridge+Diffusion.swift`):
//   - generateImage(options)        -> DiffusionResult
//   - generateImageStream(options)  -> Stream<DiffusionStreamEvent>
//   - cancelImageGeneration()
// Load flows through the canonical lifecycle (`RunAnywhere.loadModel` with the
// image-generation component), so inference is handle-free —
// `rac_diffusion_generate_lifecycle_proto` resolves the loaded model internally.
//
// Apple-only: the sole diffusion backend is Apple CoreML Stable-Diffusion. On
// non-Apple platforms every image-generation entry point returns a clear
// unsupported SDKException instead of calling the (absent) native ABI.
//
// Streaming note: commons' native diffusion stream kickoff
// (`rac_diffusion_stream_start_proto`) is a documented NOT_IMPLEMENTED stub, so
// — exactly like Swift's `CppBridge.Diffusion.generateStream` —
// [generateImageStream] adapts the real, working lifecycle generate into a
// stream: it emits STARTED, runs the CoreML pipeline, then emits a terminal
// COMPLETED (carrying the full DiffusionResult) or ERROR. The generated image is
// genuine; only intermediate per-step progress is unavailable until commons
// wires the native stream kickoff.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/generated/component_types.pbenum.dart'
    show ComponentLifecycleState;
import 'package:runanywhere/generated/diffusion_options.pb.dart'
    show
        DiffusionConfiguration,
        DiffusionGenerationOptions,
        DiffusionGenerationRequest,
        DiffusionResult,
        DiffusionStreamEvent,
        DiffusionStreamEventKind;
import 'package:runanywhere/generated/model_types.pb.dart' as model_pb;
import 'package:runanywhere/generated/sdk_events.pb.dart'
    show ComponentLifecycleSnapshot;
import 'package:runanywhere/generated/sdk_events.pbenum.dart' show SDKComponent;
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_diffusion.dart';
import 'package:runanywhere/public/capabilities/runanywhere_model_lifecycle.dart';

/// Diffusion (image generation) capability surface. Access via
/// `RunAnywhere.diffusion`.
///
/// Load/current/unload state is owned by commons lifecycle; one-shot generation
/// uses the lifecycle-owned generated-proto commons ABI. Only Apple platforms
/// (iOS/macOS, CoreML) ship a diffusion backend — see the class header.
class RunAnywhereDiffusion {
  RunAnywhereDiffusion._();
  static final RunAnywhereDiffusion _instance = RunAnywhereDiffusion._();
  static RunAnywhereDiffusion get shared => _instance;

  /// Cooperative cancel latch. There is no native cancel for the single
  /// (uninterruptible) CoreML generate call, so cancellation takes effect at
  /// the next checkpoint — the streaming path drops its terminal COMPLETED
  /// event when this is set. Mirrors Swift `CppBridge.Diffusion.cancel()`.
  bool _cancelRequested = false;

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
  ///
  /// Reuses the canonical `RunAnywhere.loadModel` path with the image-generation
  /// component, exactly like every other modality (VLM/embeddings/…).
  Future<void> load(String modelId, [DiffusionConfiguration? config]) async {
    _ensureInitialized();
    _ensureApplePlatform();

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
    _ensureInitialized();

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

  /// Generate an image from the lifecycle-loaded diffusion model.
  ///
  /// The prompt and all generation parameters travel in [options]. Load a
  /// diffusion model first (via [load] or `RunAnywhere.loadModel`). Mirrors
  /// Swift `RunAnywhere.generateImage(_:)`.
  Future<DiffusionResult> generateImage(
    DiffusionGenerationOptions options,
  ) async {
    _ensureInitialized();
    _ensureApplePlatform();
    final modelId = await _requireLoadedModelId();
    _cancelRequested = false;
    return DartBridgeDiffusion.generateProto(
      _toGenerationRequest(options, modelId),
    );
  }

  /// Stream typed diffusion events for an image generation.
  ///
  /// Yields STARTED → terminal COMPLETED (carrying the full [DiffusionResult])
  /// or ERROR. Intermediate per-step progress is not yet emitted (the native
  /// diffusion stream kickoff in commons is a documented stub); the generated
  /// image itself is genuine. Mirrors Swift
  /// `RunAnywhere.generateImageStream(_:)`.
  Stream<DiffusionStreamEvent> generateImageStream(
    DiffusionGenerationOptions options,
  ) async* {
    _ensureInitialized();
    _ensureApplePlatform();
    final modelId = await _requireLoadedModelId();
    _cancelRequested = false;

    yield DiffusionStreamEvent(
      kind: DiffusionStreamEventKind.DIFFUSION_STREAM_EVENT_KIND_STARTED,
    );

    final DiffusionResult result;
    try {
      result = DartBridgeDiffusion.generateProto(
        _toGenerationRequest(options, modelId),
      );
    } on SDKException catch (e) {
      yield DiffusionStreamEvent(
        kind: DiffusionStreamEventKind.DIFFUSION_STREAM_EVENT_KIND_ERROR,
        errorMessage: e.message,
      );
      return;
    } catch (e) {
      yield DiffusionStreamEvent(
        kind: DiffusionStreamEventKind.DIFFUSION_STREAM_EVENT_KIND_ERROR,
        errorMessage: e.toString(),
      );
      return;
    }

    // Honour a cancellation observed at this checkpoint: skip the terminal
    // event (the single CoreML generate cannot be interrupted mid-flight).
    if (_cancelRequested) {
      _cancelRequested = false;
      return;
    }

    yield DiffusionStreamEvent(
      kind: DiffusionStreamEventKind.DIFFUSION_STREAM_EVENT_KIND_COMPLETED,
      result: result,
    );
  }

  /// Cancel the current (streaming) image generation.
  ///
  /// Sets the cooperative cancel latch; the in-flight CoreML generate cannot be
  /// interrupted, so cancellation takes effect at the next checkpoint (before
  /// the terminal event is emitted). Never throws — mirrors Swift
  /// `RunAnywhere.cancelImageGeneration()`.
  Future<void> cancelImageGeneration() async {
    _cancelRequested = true;
  }

  DiffusionGenerationRequest _toGenerationRequest(
    DiffusionGenerationOptions options,
    String modelId,
  ) {
    return DiffusionGenerationRequest(
      modelId: modelId,
      options: options,
      metadata: <String, String>{'model_id': modelId}.entries,
    );
  }

  void _ensureInitialized() {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
  }

  /// Diffusion runs only on the Apple CoreML backend. Fail closed elsewhere.
  void _ensureApplePlatform() {
    if (!(Platform.isIOS || Platform.isMacOS)) {
      throw SDKException.featureNotAvailable(
        'Image generation (diffusion) is only supported on Apple/CoreML '
        'platforms',
      );
    }
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
