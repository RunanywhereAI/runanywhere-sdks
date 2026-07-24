//
//  SegmentationViewModel.swift
//  RunAnywhereAI
//
//  Semantic image segmentation over the canonical `RunAnywhere.segment` facade.
//
//  This view model is pure platform plumbing: it converts a picked image to
//  packed RGBA8 pixels, drives the SDK model lifecycle, and calls
//  `RunAnywhere.segment`. All inference and model routing live in the SDK /
//  C++ commons.
//

#if canImport(UIKit)
import Foundation
import SwiftUI
import RunAnywhere
import UIKit
import os.log

@MainActor
@Observable
final class SegmentationViewModel {
    // Model lifecycle
    private(set) var isModelLoaded = false
    private(set) var loadedModelName: String?
    private(set) var isImportingModel = false

    // Image input
    private(set) var sourceImage: UIImage?
    private var sourcePixels: (data: Data, width: Int, height: Int)?

    // Segmentation output
    private(set) var isSegmenting = false
    private(set) var maskImage: UIImage?
    private(set) var classSummaries: [RASegmentationClassSummary] = []
    private(set) var lastModelID = ""
    private(set) var processingTimeMs: Int64 = 0

    private(set) var statusMessage = ""
    private(set) var error: String?

    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "Segmentation")

    private static let maxDimension = 1024

    // MARK: - Model status

    func refreshModelStatus() {
        var request = RACurrentModelRequest()
        request.category = .semanticSegmentation
        isModelLoaded = RunAnywhere.currentModel(request).found
    }

    // MARK: - Model supply (user-supplied, uncataloged)

    /// Import a user-supplied SegFormer model directory and load it under the
    /// `.semanticSegmentation` category through the canonical SDK lifecycle.
    func importAndLoadModel(from url: URL) async {
        isImportingModel = true
        error = nil
        statusMessage = "Importing model…"
        defer { isImportingModel = false }

        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        do {
            var importRequest = RAModelImportRequest()
            importRequest.sourcePath = url.path
            importRequest.copyIntoManagedStorage = true
            importRequest.validateBeforeRegister = false
            let importResult = try await RunAnywhere.importModel(importRequest)
            guard importResult.success else {
                error = importResult.errorMessage.isEmpty ? "Model import failed." : importResult.errorMessage
                statusMessage = ""
                return
            }
            let modelID = importResult.model.id
            guard !modelID.isEmpty else {
                error = "Imported model has no identifier; cannot load."
                statusMessage = ""
                return
            }

            statusMessage = "Loading model…"
            var loadRequest = RAModelLoadRequest()
            loadRequest.modelID = modelID
            loadRequest.category = .semanticSegmentation
            loadRequest.framework = .onnx
            let loadResult = await RunAnywhere.loadModel(loadRequest)
            guard loadResult.success else {
                error = loadResult.errorMessage.isEmpty ? "Model load failed." : loadResult.errorMessage
                statusMessage = ""
                return
            }
            loadedModelName = modelID
            isModelLoaded = true
            statusMessage = "Model loaded: \(modelID)."
        } catch {
            logger.error("Segmentation model import/load failed: \(error.localizedDescription)")
            self.error = "Model import/load failed: \(error.localizedDescription)"
            statusMessage = ""
        }
    }

    // MARK: - Image input

    func setImage(_ image: UIImage) {
        sourceImage = image
        maskImage = nil
        classSummaries = []
        error = nil
        guard let pixels = Self.rgbaPixels(from: image, maxDimension: Self.maxDimension) else {
            sourcePixels = nil
            error = "Could not read pixels from the selected image."
            return
        }
        sourcePixels = pixels
        statusMessage = "Image ready (\(pixels.width)×\(pixels.height))."
    }

    // MARK: - Segmentation

    func runSegmentation() async {
        guard isModelLoaded else { error = "Load a segmentation model first."; return }
        guard let pixels = sourcePixels else { error = "Pick an image first."; return }

        isSegmenting = true
        error = nil
        maskImage = nil
        classSummaries = []
        statusMessage = "Running segmentation…"
        defer { isSegmenting = false }

        do {
            var image = RASegmentationImage()
            image.data = pixels.data
            image.width = UInt32(pixels.width)
            image.height = UInt32(pixels.height)
            image.pixelFormat = .rgba8

            var options = RASegmentationOptions()
            options.includeDiagnosticRgba = true

            var request = RASegmentationRequest()
            request.image = image
            request.options = options

            let result = try await RunAnywhere.segment(request)
            classSummaries = result.classSummaries.sorted { $0.pixelCount > $1.pixelCount }
            lastModelID = result.modelID
            processingTimeMs = result.processingTimeMs
            if result.hasDiagnosticRgba,
               result.diagnosticRgba.count == Int(result.width) * Int(result.height) * 4 {
                maskImage = Self.image(fromRGBA: result.diagnosticRgba,
                                       width: Int(result.width),
                                       height: Int(result.height))
            }
            statusMessage = "Done — \(result.classSummaries.count) classes in \(result.processingTimeMs)ms."
        } catch {
            logger.error("Segmentation failed: \(error.localizedDescription)")
            self.error = "Segmentation failed: \(error.localizedDescription)"
        }
    }

    func reportError(_ message: String) {
        error = message
    }

    // MARK: - Pixel helpers

    /// Draw an image into a tightly-packed RGBA8 buffer, downscaling so the
    /// longest edge is at most `maxDimension`.
    private static func rgbaPixels(from image: UIImage, maxDimension: Int) -> (data: Data, width: Int, height: Int)? {
        guard let cgImage = image.cgImage else { return nil }
        let srcWidth = cgImage.width
        let srcHeight = cgImage.height
        guard srcWidth > 0, srcHeight > 0 else { return nil }

        let longest = max(srcWidth, srcHeight)
        let scale = longest > maxDimension ? Double(maxDimension) / Double(longest) : 1.0
        let width = max(1, Int((Double(srcWidth) * scale).rounded()))
        let height = max(1, Int((Double(srcHeight) * scale).rounded()))
        let bytesPerRow = 4 * width

        var data = Data(count: bytesPerRow * height)
        let ok = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return ok ? (data, width, height) : nil
    }

    /// Build a UIImage from a straight-alpha RGBA8 buffer (the SDK diagnostic mask).
    private static func image(fromRGBA data: Data, width: Int, height: Int) -> UIImage? {
        guard data.count == width * height * 4 else { return nil }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
#endif
