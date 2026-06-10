//
//  RAVLMImage+Helpers.swift
//  RunAnywhere SDK
//
//  Ergonomic helpers for canonical VLM proto types.
//

import Foundation

// MARK: - RAVLMConfiguration

extension RAVLMConfiguration {
    public static func defaults(modelId: String = "") -> RAVLMConfiguration {
        var container = RAVLMConfiguration()
        container.modelID = modelId
        container.maxImageSizePx = 1_024
        container.maxTokens = 0
        return container
    }
}

// MARK: - RAVLMGenerationOptions

extension RAVLMGenerationOptions {
    public static func defaults(prompt: String = "") -> RAVLMGenerationOptions {
        var options = RAVLMGenerationOptions()
        options.prompt = prompt
        options.maxTokens = 256
        options.temperature = 0.7
        options.topP = 0.9
        options.topK = 40
        return options
    }
}

#if canImport(UIKit)
import UIKit
#endif

#if canImport(CoreVideo)
import CoreVideo
#endif

#if canImport(CoreGraphics)
import CoreGraphics
#endif

// MARK: - File path / base64 / raw RGB / encoded factories

extension RAVLMImage {
    /// Create a proto VLM image from an encoded JPEG / PNG / WebP byte buffer.
    public static func fromEncoded(_ data: Data, format: RAVLMImageFormat) -> RAVLMImage {
        var img = RAVLMImage()
        img.encoded = data
        img.format = format
        return img
    }

    /// Create a proto VLM image from an on-disk file path.
    public static func fromFilePath(_ path: String) -> RAVLMImage {
        var img = RAVLMImage()
        img.filePath = path
        img.format = .filePath
        return img
    }

    /// Create a proto VLM image from a base64-encoded string.
    public static func fromBase64(_ base64: String) -> RAVLMImage {
        var img = RAVLMImage()
        img.base64 = base64
        img.format = .base64
        return img
    }

    /// Create a proto VLM image from raw RGB bytes.
    public static func fromRawRGB(_ data: Data, width: Int, height: Int) -> RAVLMImage {
        var img = RAVLMImage()
        img.rawRgb = data
        img.width = Int32(width)
        img.height = Int32(height)
        img.format = .rawRgb
        return img
    }

    /// Create a proto VLM image from raw RGBA bytes.
    /// (Stored in the same `rawRgb` oneof slot; format flag distinguishes it.)
    public static func fromRawRGBA(_ data: Data, width: Int, height: Int) -> RAVLMImage {
        var img = RAVLMImage()
        img.rawRgb = data
        img.width = Int32(width)
        img.height = Int32(height)
        img.format = .rawRgba
        return img
    }
}

// MARK: - CGImage factory (shared core for UIImage / NSImage)

#if canImport(CoreGraphics)
extension RAVLMImage {
    /// Create a proto VLM image from a CGImage. Returns nil if conversion fails.
    ///
    /// This is the platform-neutral pixel path: the image is drawn into an
    /// RGBA bitmap context and stripped to the packed RGB bytes the native
    /// VLM ABI expects. `fromUIImage` / `fromNSImage` are thin wrappers.
    public static func fromCGImage(_ cgImage: CGImage) -> RAVLMImage? {
        guard let rgb = rgbData(from: cgImage) else { return nil }
        return fromRawRGB(rgb, width: cgImage.width, height: cgImage.height)
    }

    private static func rgbData(from cgImage: CGImage) -> Data? {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = 4 * width
        let totalBytes = bytesPerRow * height

        var pixelData = Data(count: totalBytes)
        pixelData.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        // RGBA → RGB
        var rgbData = Data(capacity: width * height * 3)
        pixelData.withUnsafeBytes { buffer in
            let pixels = buffer.bindMemory(to: UInt8.self)
            for i in stride(from: 0, to: totalBytes, by: 4) {
                rgbData.append(pixels[i])
                rgbData.append(pixels[i + 1])
                rgbData.append(pixels[i + 2])
            }
        }
        return rgbData
    }
}
#endif

// MARK: - UIImage factory

#if canImport(UIKit)
extension RAVLMImage {
    /// Create a proto VLM image from a UIImage. Returns nil if conversion fails.
    public static func fromUIImage(_ image: UIImage) -> RAVLMImage? {
        guard let cgImage = image.cgImage else { return nil }
        return fromCGImage(cgImage)
    }
}
#endif

// MARK: - NSImage factory (macOS)

#if canImport(AppKit) && !canImport(UIKit)
import AppKit

extension RAVLMImage {
    /// Create a proto VLM image from an NSImage. Returns nil if conversion fails.
    public static func fromNSImage(_ image: NSImage) -> RAVLMImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return fromCGImage(cgImage)
    }
}
#endif

// MARK: - CVPixelBuffer factory

#if canImport(CoreVideo)
extension RAVLMImage {
    /// Create a proto VLM image from a CVPixelBuffer (BGRA only).
    public static func fromPixelBuffer(_ buffer: CVPixelBuffer) -> RAVLMImage? {
        guard let rgb = rgbData(from: buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        return fromRawRGB(rgb, width: width, height: height)
    }

    private static func rgbData(from buffer: CVPixelBuffer) -> Data? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let pixelFormat = CVPixelBufferGetPixelFormatType(buffer)
        guard pixelFormat == kCVPixelFormatType_32BGRA else {
            return nil
        }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return nil }

        var rgbData = Data(capacity: width * height * 3)
        let pixels = baseAddress.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                rgbData.append(pixels[offset + 2])
                rgbData.append(pixels[offset + 1])
                rgbData.append(pixels[offset])
            }
        }
        return rgbData
    }
}
#endif
