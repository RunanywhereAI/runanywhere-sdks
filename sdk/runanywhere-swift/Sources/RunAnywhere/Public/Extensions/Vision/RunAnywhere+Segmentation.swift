//
//  RunAnywhere+Segmentation.swift
//  RunAnywhere SDK
//
//  Deprecated flat segmentation verb. The v3 surface is
//  `RunAnywhere.segmentation`.
//

public extension RunAnywhere {

    /// Segment one packed RGB8, RGBA8, or BGRA8 image.
    @available(*, deprecated, renamed: "segmentation.segment(_:options:)")
    static func segment(
        _ request: RASegmentationRequest
    ) async throws -> RASegmentationResult {
        try await segmentProto(request)
    }

    /// Shared readiness gate kept separate from native dispatch so focused
    /// tests can prove the no-model contract without mutating process-global
    /// SDK initialization state.
    internal static func requireSemanticSegmentationModel(
        _ snapshot: RACurrentModelResult
    ) throws {
        guard snapshot.found else {
            throw SDKException(
                code: .modelNotLoaded,
                message: "Semantic-segmentation model not loaded",
                category: .component
            )
        }
    }
}
