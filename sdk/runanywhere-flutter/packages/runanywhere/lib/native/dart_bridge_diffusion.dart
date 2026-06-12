// SPDX-License-Identifier: Apache-2.0
//
// Thin generated-proto diffusion bridge. Commons lifecycle owns the loaded
// diffusion service; Dart passes generated request bytes and receives generated
// result bytes.

import 'dart:async';

import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/generated/diffusion_options.pb.dart'
    show
        DiffusionCapabilities,
        DiffusionGenerationRequest,
        DiffusionProgress,
        DiffusionResult;
import 'package:runanywhere/native/dart_bridge_proto_utils.dart';

/// FFI bridge for lifecycle-owned diffusion operations.
class DartBridgeDiffusion {
  DartBridgeDiffusion._();

  static DiffusionResult Function(DiffusionGenerationRequest)?
      _generateLifecycleProtoForTesting;

  static void setGenerateLifecycleProtoForTesting(
    DiffusionResult Function(DiffusionGenerationRequest)? override,
  ) {
    _generateLifecycleProtoForTesting = override;
  }

  static DiffusionResult generateProto(DiffusionGenerationRequest request) {
    _validateGenerateRequest(request);

    final override = _generateLifecycleProtoForTesting;
    if (override != null) {
      return override(request);
    }

    final fn = RacNative.bindings.rac_diffusion_generate_lifecycle_proto;
    if (fn == null) {
      throw UnsupportedError(
        'rac_diffusion_generate_lifecycle_proto is unavailable',
      );
    }

    return DartBridgeProtoUtils.callRequest<DiffusionResult>(
      request: request,
      invoke: fn,
      decode: DiffusionResult.fromBuffer,
      symbol: 'rac_diffusion_generate_lifecycle_proto',
    );
  }

  static Stream<DiffusionProgress> generateWithProgressProto(
    DiffusionGenerationRequest request,
  ) async* {
    _validateGenerateRequest(request);
    throw UnsupportedError(
      'Lifecycle-owned diffusion progress streaming is unavailable',
    );
  }

  static int cancel() {
    throw UnsupportedError(
      'Lifecycle-owned diffusion cancellation is unavailable',
    );
  }

  static DiffusionCapabilities capabilitiesProto() {
    throw UnsupportedError(
      'Lifecycle-owned diffusion capability discovery is unavailable',
    );
  }

  static void _validateGenerateRequest(DiffusionGenerationRequest request) {
    if (!request.hasOptions()) {
      throw ArgumentError(
        'DiffusionGenerationRequest.options is required',
      );
    }
    if (request.options.prompt.isEmpty) {
      throw ArgumentError(
        'DiffusionGenerationOptions.prompt is required',
      );
    }
  }
}
