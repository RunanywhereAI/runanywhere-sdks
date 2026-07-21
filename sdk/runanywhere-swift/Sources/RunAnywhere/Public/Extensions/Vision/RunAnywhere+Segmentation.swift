//
//  RunAnywhere+Segmentation.swift
//  RunAnywhere SDK
//
//  Public semantic image-segmentation facade.
//

public extension RunAnywhere {
    /// Segment one packed RGB8, RGBA8, or BGRA8 image through the currently
    /// loaded `.semanticSegmentation` model.
    ///
    /// Model ownership stays in the canonical lifecycle. Import/register a
    /// local model, then call `loadModel(_:)` with
    /// `category = .semanticSegmentation` before invoking this method.
    /// RunAnywhere does not implicitly download or load restricted model
    /// weights from this inference entry point.
    static func segment(
        _ request: RASegmentationRequest
    ) async throws -> RASegmentationResult {
        guard isInitialized else {
            throw SDKException(
                code: .notInitialized,
                message: "SDK not initialized",
                category: .internal
            )
        }
        try await ensureServicesReady()

        let snapshot = loadedModelSnapshot(category: .semanticSegmentation)
        try requireSemanticSegmentationModel(snapshot)
        return try await CppBridge.Segmentation.segment(request)
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
