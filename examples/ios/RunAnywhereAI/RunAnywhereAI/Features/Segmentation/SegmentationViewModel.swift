//
//  SegmentationViewModel.swift
//  RunAnywhereAI
//
//  Semantic image segmentation over `RunAnywhere.segmentation`.
//
//  This view model is pure platform plumbing: it loads a catalog SegFormer
//  model, hands the picked image to the SDK as an `ImageInput`, and paints the
//  returned class mask. All pixel packing, inference, and model routing live in
//  the SDK / C++ commons.
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
    private(set) var isProcessing = false

    // Image input
    private(set) var sourceImage: UIImage?

    // Segmentation output
    private(set) var isSegmenting = false
    private(set) var maskImage: UIImage?
    private(set) var classSummaries: [ClassInfo] = []
    private(set) var processingTimeMs: Int64 = 0

    private(set) var statusMessage = ""
    private(set) var error: String?

    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "Segmentation")

    /// Longest edge handed to the model; larger pictures are downscaled first so
    /// a full-resolution camera roll image cannot exhaust memory.
    private static let maxDimension = 1024

    // MARK: - Model status

    func refreshModelStatus() async {
        let state = await RunAnywhere.models.state()
        guard let model = state.loaded[.semanticSegmentation] else {
            isModelLoaded = false
            return
        }
        isModelLoaded = true
        loadedModelName = model.name.isEmpty ? model.id : model.name
    }

    // MARK: - Model supply (catalog Get → Use)

    /// Load a model chosen from `ModelSelectionSheet`.
    func loadModelFromSelection(_ model: RAModelInfo) async {
        isProcessing = true
        error = nil
        statusMessage = "Loading model…"
        defer { isProcessing = false }

        do {
            try await RunAnywhere.models.load(id: model.id)
        } catch {
            self.error = "Model load failed: \(error.localizedDescription)"
            statusMessage = ""
            return
        }
        loadedModelName = model.name.isEmpty ? model.id : model.name
        isModelLoaded = true
        statusMessage = "Model loaded: \(loadedModelName ?? model.id)."
    }

    // MARK: - Image input

    func setImage(_ image: UIImage) {
        let prepared = Self.downscaled(image, maxDimension: Self.maxDimension)
        sourceImage = prepared
        maskImage = nil
        classSummaries = []
        error = nil
        let size = prepared.size
        statusMessage = "Image ready (\(Int(size.width))×\(Int(size.height)))."
    }

    // MARK: - Segmentation

    func runSegmentation() async {
        guard isModelLoaded else { error = "Load a segmentation model first."; return }
        guard let image = sourceImage else { error = "Pick an image first."; return }

        isSegmenting = true
        error = nil
        maskImage = nil
        classSummaries = []
        statusMessage = "Running segmentation…"
        defer { isSegmenting = false }

        do {
            let started = Date()
            let result = try await RunAnywhere.segmentation.segment(.uiImage(image))
            processingTimeMs = Int64((Date().timeIntervalSince(started) * 1000).rounded())

            classSummaries = result.classes.sorted { $0.pixelCount > $1.pixelCount }
            maskImage = Self.overlay(
                classMask: result.classMask,
                width: result.width,
                height: result.height
            )
            statusMessage = "Done — \(result.classes.count) classes in \(processingTimeMs)ms."
        } catch {
            logger.error("Segmentation failed: \(error.localizedDescription)")
            self.error = "Segmentation failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Rendering helpers

    /// Redraw `image` so its longest edge is at most `maxDimension`.
    private static func downscaled(_ image: UIImage, maxDimension: Int) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > CGFloat(maxDimension) else { return image }
        let scale = CGFloat(maxDimension) / longest
        let target = CGSize(width: (image.size.width * scale).rounded(),
                            height: (image.size.height * scale).rounded())
        return UIGraphicsImageRenderer(size: target).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// Paint the little-endian UInt16 class mask into a translucent overlay.
    /// Colours are a presentation choice, so the palette lives here and not in
    /// the SDK.
    private static func overlay(classMask: Data, width: Int, height: Int) -> UIImage? {
        let pixelCount = width * height
        guard pixelCount > 0, classMask.count >= pixelCount * 2 else { return nil }

        var rgba = Data(count: pixelCount * 4)
        classMask.withUnsafeBytes { maskBuffer in
            rgba.withUnsafeMutableBytes { outBuffer in
                let mask = maskBuffer.bindMemory(to: UInt8.self)
                let out = outBuffer.bindMemory(to: UInt8.self)
                for index in 0..<pixelCount {
                    let classId = Int(mask[index * 2]) | (Int(mask[index * 2 + 1]) << 8)
                    let color = paletteColor(for: classId)
                    out[index * 4] = color.0
                    out[index * 4 + 1] = color.1
                    out[index * 4 + 2] = color.2
                    out[index * 4 + 3] = classId == 0 ? 0 : 255
                }
            }
        }
        return image(fromRGBA: rgba, width: width, height: height)
    }

    /// Deterministic, well-spread colour per class id (golden-ratio hue walk).
    private static func paletteColor(for classId: Int) -> (UInt8, UInt8, UInt8) {
        let hue = (Double(classId) * 0.61803398875).truncatingRemainder(dividingBy: 1.0)
        let color = UIColor(hue: hue, saturation: 0.85, brightness: 0.95, alpha: 1)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (UInt8(red * 255), UInt8(green * 255), UInt8(blue * 255))
    }

    /// Build a UIImage from a straight-alpha RGBA8 buffer.
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
