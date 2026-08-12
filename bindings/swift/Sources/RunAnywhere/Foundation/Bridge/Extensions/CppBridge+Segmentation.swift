//
//  CppBridge+Segmentation.swift
//  RunAnywhere SDK
//
//  Semantic image-segmentation bridge over the canonical lifecycle proto ABI.
//

import CRACommons
import Foundation

private enum SegmentationLifecycleProtoABI {
    static let segmentName = "rac_segmentation_segment_lifecycle_proto"
    static let segment: NativeProtoABI.ProtoRequest? = {
        // RACommons ships as a static archive on Apple platforms. Keep a
        // typed reference so the linker retains the segmentation archive
        // member even when RTLD_DEFAULT cannot enumerate executable symbols.
        let linked: NativeProtoABI.ProtoRequest = rac_segmentation_segment_lifecycle_proto
        return NativeProtoABI.load(
            segmentName,
            as: NativeProtoABI.ProtoRequest.self
        ) ?? linked
    }()
}

extension CppBridge {
    /// Stateless semantic-segmentation namespace.
    ///
    /// Commons owns the loaded model through the canonical model lifecycle;
    /// Swift does not create or retain a second component handle. This keeps
    /// unload/reset behavior identical across every SDK consumer.
    public enum Segmentation {
        /// Segment one packed RGB8, RGBA8, or BGRA8 source image with the
        /// lifecycle-loaded semantic-segmentation model.
        public static func segment(
            _ request: RASegmentationRequest
        ) async throws -> RASegmentationResult {
            try await Task.detached(priority: .userInitiated) {
                try NativeProtoABI.invoke(
                    request,
                    symbol: SegmentationLifecycleProtoABI.segment,
                    symbolName: SegmentationLifecycleProtoABI.segmentName,
                    responseType: RASegmentationResult.self
                )
            }.value
        }
    }
}
