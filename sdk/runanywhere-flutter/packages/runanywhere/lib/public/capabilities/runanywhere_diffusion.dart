// SPDX-License-Identifier: Apache-2.0
//
// Wave 2: Diffusion namespace extension. Mirrors Swift's
// `RunAnywhere+Diffusion.swift`. Each public method now calls the
// `rac_diffusion_*` C ABI through `lib/native/dart_bridge_diffusion.dart`.
// If commons returns `RAC_ERROR_FEATURE_NOT_AVAILABLE` (Apple-only
// engine), the SDKException naturally propagates — we no longer
// pre-empt the call.
//
// §15 type-discipline: all `dart:ffi` work lives in the native bridge;
// this capability holds no FFI types.

import 'dart:typed_data';

import 'package:runanywhere/foundation/error_types/sdk_exception.dart';
import 'package:runanywhere/generated/diffusion_options.pb.dart'
    show
        DiffusionConfiguration,
        DiffusionGenerationOptions,
        DiffusionResult,
        DiffusionCapabilities,
        DiffusionProgress;
import 'package:runanywhere/internal/sdk_state.dart';
import 'package:runanywhere/native/dart_bridge_diffusion.dart';
import 'package:runanywhere/native/types/basic_types.dart' show RacResultCode;

/// Diffusion (image generation) capability surface.
///
/// Access via `RunAnywhereSDK.instance.diffusion`. Mirrors Swift
/// `RunAnywhere.Diffusion`. Wired to the `rac_diffusion_*` C ABI; if
/// the underlying engine isn't available the C layer returns
/// `RAC_ERROR_FEATURE_NOT_AVAILABLE` and we surface that as
/// `SDKException.featureNotAvailable`.
class RunAnywhereDiffusion {
  RunAnywhereDiffusion._();
  static final RunAnywhereDiffusion _instance = RunAnywhereDiffusion._();
  static RunAnywhereDiffusion get shared => _instance;

  String? _currentModelId;

  // -- state ---------------------------------------------------------------

  /// True when a diffusion model is currently loaded.
  bool get isLoaded => DartBridgeDiffusion.isLoaded();

  /// Currently-loaded diffusion model id, or null.
  String? get currentModelId => _currentModelId;

  // -- internal helpers ----------------------------------------------------

  static Never _throwForCode(String op, int code) {
    if (code == RacResultCode.errorFeatureNotAvailable ||
        code == RacResultCode.errorNotImplemented ||
        code == RacResultCode.errorBackendNotFound ||
        code == RacResultCode.errorBackendUnavailable) {
      throw SDKException.featureNotAvailable('Diffusion: $op');
    }
    throw SDKException.generationFailed(
      '$op failed: ${RacResultCode.getMessage(code)}',
    );
  }

  void _ensureHandle() {
    final rc = DartBridgeDiffusion.ensureHandle();
    if (rc != 0) {
      _throwForCode('rac_diffusion_component_create', rc);
    }
  }

  /// Load a diffusion model by ID.
  Future<void> load(String modelId, [DiffusionConfiguration? config]) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    _ensureHandle();
    final rc = DartBridgeDiffusion.loadModel(modelId);
    if (rc != 0) {
      _throwForCode('rac_diffusion_component_load_model', rc);
    }
    _currentModelId = modelId;
  }

  /// Unload the currently-loaded diffusion model.
  Future<void> unload() async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    if (!DartBridgeDiffusion.hasHandle) return;
    final rc = DartBridgeDiffusion.unload();
    if (rc != 0) {
      _throwForCode('rac_diffusion_component_unload', rc);
    }
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
    _ensureHandle();
    final optsBytes = options?.writeToBuffer() ?? Uint8List(0);
    final result = DartBridgeDiffusion.generate(prompt, optsBytes);
    if (!result.success || result.payload == null) {
      _throwForCode('rac_diffusion_component_generate', result.resultCode);
    }
    return DiffusionResult.fromBuffer(result.payload!);
  }

  /// Stream generation progress.
  ///
  /// Subscribes to the `rac_diffusion_component_set_progress_callback`
  /// proto-byte stream. If the engine has no streaming support the C
  /// ABI returns `RAC_ERROR_FEATURE_NOT_AVAILABLE` which propagates.
  Stream<DiffusionProgress> generateStream(
    String prompt, [
    DiffusionGenerationOptions? options,
  ]) async* {
    // Streaming variant is implemented in commons via a proto-byte
    // callback (mirrors the LLM/voice agent pattern). The callback wiring
    // is non-trivial; we emit the final result as a single progress event
    // until the streaming bridge lands. The blocking call still executes
    // through the C ABI so the SDKException semantics are preserved.
    final result = await generate(prompt, options);
    yield DiffusionProgress(
      progressPercent: 100.0,
      stage: 'completed',
      intermediateImageData: result.imageData,
    );
  }

  /// Cancel any in-flight generation.
  Future<void> cancel() async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    if (!DartBridgeDiffusion.hasHandle) return;
    final rc = DartBridgeDiffusion.cancel();
    if (rc != 0) {
      _throwForCode('rac_diffusion_component_cancel', rc);
    }
  }

  /// Backend capability discovery.
  DiffusionCapabilities capabilities() {
    if (!SdkState.shared.isInitialized) return DiffusionCapabilities();
    _ensureHandle();
    final result = DartBridgeDiffusion.capabilities();
    if (!result.success || result.payload == null) {
      _throwForCode('rac_diffusion_component_get_capabilities',
          result.resultCode);
    }
    return DiffusionCapabilities.fromBuffer(result.payload!);
  }
}
