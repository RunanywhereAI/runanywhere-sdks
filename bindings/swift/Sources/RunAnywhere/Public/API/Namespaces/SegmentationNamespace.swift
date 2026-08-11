//
//  SegmentationNamespace.swift
//  RunAnywhere SDK
//
//  `RunAnywhere.segmentation` — per-pixel class masks.
//

import Foundation

public extension RunAnywhere {

    /// Semantic image segmentation.
    static var segmentation: Segmentation { Segmentation() }

    /// Label every pixel of an image.
    struct Segmentation: Sendable {

        /// Segment `image` into a per-pixel class mask.
        ///
        /// ```swift
        /// let result = try await RunAnywhere.segmentation.segment(.file(path))
        /// print(result.classes.map(\.label))
        /// ```
        ///
        /// - Throws: `SDKException` when no segmentation model is loaded, the
        ///   image cannot be decoded, or inference fails.
        public func segment(
            _ image: ImageInput,
            options: SegmentationOptions? = nil
        ) async throws -> SegmentationResult {
            var request = RASegmentationRequest()
            request.image = try image.toSegmentationImage()
            request.options = (options ?? SegmentationOptions()).toProto()
            return SegmentationResult(proto: try await RunAnywhere.segmentProto(request))
        }
    }
}

// MARK: - Internal proto-level helper

extension RunAnywhere {

    internal static func segmentProto(_ request: RASegmentationRequest) async throws -> RASegmentationResult {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()
        try requireSemanticSegmentationModel(loadedModelSnapshot(category: .semanticSegmentation))
        return try await CppBridge.Segmentation.segment(request)
    }
}
