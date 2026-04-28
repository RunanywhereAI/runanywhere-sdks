// SPDX-License-Identifier: Apache-2.0
//
// Wave 2: Diffusion namespace extension. Mirrors Swift's
// `RunAnywhere+Diffusion.swift`. The diffusion C++ component is not
// yet wired through the Flutter FFI bridges, so this surface throws
// `SDKException.featureNotAvailable` for now — enabling a stable public
// API contract that downstream apps can target ahead of the FFI bridge
// landing.

import 'package:runanywhere/foundation/error_types/sdk_exception.dart';
import 'package:runanywhere/generated/diffusion_options.pb.dart'
    show
        DiffusionConfiguration,
        DiffusionGenerationOptions,
        DiffusionResult,
        DiffusionCapabilities,
        DiffusionProgress;

/// Diffusion (image generation) capability surface.
///
/// Access via `RunAnywhereSDK.instance.diffusion`. Mirrors Swift
/// `RunAnywhere.Diffusion`. All methods currently throw
/// `SDKException.featureNotAvailable` — the FFI bridge for diffusion
/// will be wired in a follow-up wave.
class RunAnywhereDiffusion {
  RunAnywhereDiffusion._();
  static final RunAnywhereDiffusion _instance = RunAnywhereDiffusion._();
  static RunAnywhereDiffusion get shared => _instance;

  /// True when a diffusion model is currently loaded.
  bool get isLoaded => false;

  /// Currently-loaded diffusion model id, or null.
  String? get currentModelId => null;

  /// Load a diffusion model by ID.
  Future<void> load(String modelId, [DiffusionConfiguration? config]) async {
    throw SDKException.featureNotAvailable('Diffusion');
  }

  /// Unload the currently-loaded diffusion model.
  Future<void> unload() async {
    throw SDKException.featureNotAvailable('Diffusion');
  }

  /// Generate an image from a text prompt.
  Future<DiffusionResult> generate(
    String prompt, [
    DiffusionGenerationOptions? options,
  ]) async {
    throw SDKException.featureNotAvailable('Diffusion');
  }

  /// Stream generation progress.
  Stream<DiffusionProgress> generateStream(
    String prompt, [
    DiffusionGenerationOptions? options,
  ]) async* {
    throw SDKException.featureNotAvailable('Diffusion');
  }

  /// Cancel any in-flight generation.
  Future<void> cancel() async {
    throw SDKException.featureNotAvailable('Diffusion');
  }

  /// Backend capability discovery.
  DiffusionCapabilities capabilities() {
    return DiffusionCapabilities();
  }
}
