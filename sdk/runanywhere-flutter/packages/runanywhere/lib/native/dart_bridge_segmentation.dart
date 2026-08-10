// SPDX-License-Identifier: Apache-2.0
//
// Thin generated-proto segmentation bridge. Commons lifecycle owns the loaded
// semantic-segmentation service; the verb is handle-free.

import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/generated/segmentation.pb.dart'
    show SegmentationRequest, SegmentationResult;
import 'package:runanywhere/native/dart_bridge_proto_utils.dart';

/// Bridge over `rac_segmentation_segment_lifecycle_proto`.
class DartBridgeSegmentation {
  DartBridgeSegmentation._();

  /// Process-wide bridge instance.
  static final DartBridgeSegmentation shared = DartBridgeSegmentation._();

  /// Segment [request] through the lifecycle-owned commons ABI.
  ///
  /// Throws [UnsupportedError] when the commons binary predates the verb.
  SegmentationResult segment(SegmentationRequest request) {
    final fn = RacNative.bindings.rac_segmentation_segment_lifecycle_proto;
    if (fn == null) {
      throw UnsupportedError(
        'rac_segmentation_segment_lifecycle_proto is unavailable',
      );
    }
    return DartBridgeProtoUtils.callRequest<SegmentationResult>(
      request: request,
      invoke: fn,
      decode: SegmentationResult.fromBuffer,
      symbol: 'rac_segmentation_segment_lifecycle_proto',
    );
  }
}
