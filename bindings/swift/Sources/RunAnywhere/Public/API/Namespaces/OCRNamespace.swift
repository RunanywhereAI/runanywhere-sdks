//
//  OCRNamespace.swift
//  RunAnywhere SDK
//
//  `RunAnywhere.ocr` — text and its geometry, read off a page image.
//

import Foundation

public extension RunAnywhere {

    /// Optical character recognition.
    static var ocr: OCR { OCR() }

    /// Read the text on a page.
    struct OCR: Sendable {

        /// Detect every text region on `image` and read each one.
        ///
        /// ```swift
        /// let page = try await RunAnywhere.ocr.readPage(.file(path))
        /// print(page.regions.map(\.text).joined(separator: "\n"))
        /// ```
        ///
        /// - Throws: `SDKException` when no OCR model is loaded, the image
        ///   cannot be decoded, or inference fails.
        public func readPage(
            _ image: ImageInput,
            modelId: String? = nil
        ) async throws -> OCRPageResult {
            var request = RAOCRRequest()
            request.image = try image.toOCRImage()
            if let modelId {
                request.modelID = modelId
            }
            return OCRPageResult(proto: try await RunAnywhere.readPageProto(request))
        }

        /// Read one already-cropped LINE image.
        ///
        /// Most OCR models here cannot serve this. The detector-coupled
        /// families take a grid-sampled crop of the detector's own feature map
        /// rather than pixels, so their recognizer has no standalone form —
        /// they throw `.notSupported` and `readPage` is the only entry point.
        /// `OCRPageResult.supportsLineRecognition` on any result reports which
        /// kind the loaded model is.
        public func recognizeLine(
            _ image: ImageInput,
            modelId: String? = nil
        ) async throws -> OCRPageResult {
            var request = RAOCRRequest()
            request.image = try image.toOCRImage()
            request.recognizeSingleLine = true
            if let modelId {
                request.modelID = modelId
            }
            return OCRPageResult(proto: try await RunAnywhere.readPageProto(request))
        }
    }
}

// MARK: - Internal proto-level helper

extension RunAnywhere {

    internal static func readPageProto(_ request: RAOCRRequest) async throws -> RAOCRResult {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()
        try requireOCRModel(loadedModelSnapshot(category: .ocr))
        return try await CppBridge.OCR.readPage(request)
    }
}
