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
        var c = RAVLMConfiguration()
        c.modelID = modelId
        c.maxImageSizePx = 1_024
        c.maxTokens = 0
        return c
    }
}

// MARK: - RAVLMGenerationOptions

extension RAVLMGenerationOptions {
    public static func defaults(prompt: String = "") -> RAVLMGenerationOptions {
        var o = RAVLMGenerationOptions()
        o.prompt = prompt
        o.maxTokens = 256
        o.temperature = 0.7
        o.topP = 0.9
        o.topK = 40
        return o
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

// MARK: - UIImage factory

#if canImport(UIKit)
extension RAVLMImage {
    /// Create a proto VLM image from a UIImage. Returns nil if conversion fails.
    public static func fromUIImage(_ image: UIImage) -> RAVLMImage? {
        guard let rgb = image._raToRGBData(), let cgImage = image.cgImage else { return nil }
        return fromRawRGB(rgb, width: cgImage.width, height: cgImage.height)
    }
}

extension UIImage {
    fileprivate func _raToRGBData() -> Data? {
        guard let cgImage = self.cgImage else { return nil }
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

// MARK: - CVPixelBuffer factory

#if canImport(CoreVideo)
extension RAVLMImage {
    /// Create a proto VLM image from a CVPixelBuffer (BGRA only).
    public static func fromPixelBuffer(_ buffer: CVPixelBuffer) -> RAVLMImage? {
        guard let rgb = buffer._raToRGBData() else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        return fromRawRGB(rgb, width: width, height: height)
    }
}

extension CVPixelBuffer {
    fileprivate func _raToRGBData() -> Data? {
        CVPixelBufferLockBaseAddress(self, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(self, .readOnly) }

        let pixelFormat = CVPixelBufferGetPixelFormatType(self)
        guard pixelFormat == kCVPixelFormatType_32BGRA else {
            return nil
        }

        let width = CVPixelBufferGetWidth(self)
        let height = CVPixelBufferGetHeight(self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(self)
        guard let baseAddress = CVPixelBufferGetBaseAddress(self) else { return nil }

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
