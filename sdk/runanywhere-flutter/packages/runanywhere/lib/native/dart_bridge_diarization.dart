// SPDX-License-Identifier: Apache-2.0
//
// Thin generated-proto diarization bridge. Commons lifecycle owns the loaded
// speaker-diarization service; the offline verb is handle-free.

import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/generated/diarization.pb.dart'
    show DiarizationRequest, DiarizationResult;
import 'package:runanywhere/native/dart_bridge_proto_utils.dart';

/// Bridge over `rac_diarization_diarize_lifecycle_proto`.
class DartBridgeDiarization {
  DartBridgeDiarization._();

  /// Process-wide bridge instance.
  static final DartBridgeDiarization shared = DartBridgeDiarization._();

  /// Diarize [request] through the lifecycle-owned commons ABI.
  ///
  /// Throws [UnsupportedError] when the commons binary predates the verb.
  DiarizationResult diarize(DiarizationRequest request) {
    final fn = RacNative.bindings.rac_diarization_diarize_lifecycle_proto;
    if (fn == null) {
      throw UnsupportedError(
        'rac_diarization_diarize_lifecycle_proto is unavailable',
      );
    }
    return DartBridgeProtoUtils.callRequest<DiarizationResult>(
      request: request,
      invoke: fn,
      decode: DiarizationResult.fromBuffer,
      symbol: 'rac_diarization_diarize_lifecycle_proto',
    );
  }
}
