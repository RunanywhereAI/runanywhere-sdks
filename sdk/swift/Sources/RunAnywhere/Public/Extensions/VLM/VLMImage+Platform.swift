// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Platform-specific `VLMImage` constructors. Match main-branch call sites:
//   VLMImage(image: UIImage)        // iOS
//   VLMImage(image: NSImage)        // macOS
//   VLMImage(pixelBuffer: CVPixelBuffer)

import Foundation

#if canImport(CoreVideo)
import CoreVideo
#endif
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

#if canImport(CoreGraphics)
import CoreGraphics
#endif

public extension VLMImage {

#if canImport(UIKit)
    /// Construct a `VLMImage` from a `UIImage`. Converts to RGBA bytes at
    /// the image's natural size. Falls back to an empty 1x1 RGBA buffer
    /// when the backing CGImage can't be rendered — non-failable to match
    /// main-branch sample call sites.
    init(image: UIImage) {
        if let cg = image.cgImage, let img = VLMImage.fromCGImage(cg) {
            self = img
        } else {
            self.init(bytes: Data(count: 4), width: 1, height: 1, format: .rgba)
        }
    }
#endif

#if canImport(AppKit)
    /// Construct a `VLMImage` from an `NSImage`. Non-failable mirror of
    /// the `UIImage` overload — falls back to an empty 1x1 image when
    /// the conversion can't complete.
    init(image: NSImage) {
        var rect = CGRect(origin: .zero, size: image.size)
        if let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
           let img = VLMImage.fromCGImage(cg) {
            self = img
        } else {
            self.init(bytes: Data(count: 4), width: 1, height: 1, format: .rgba)
        }
    }
#endif

#if canImport(CoreVideo)
    /// Construct a `VLMImage` from a `CVPixelBuffer`. Supports BGRA 8-bit
    /// (the most common camera / AVFoundation output format).
    init?(pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let bpr = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let len = bpr * h
        let data = Data(bytes: base, count: len)
        let fmt = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let format: VLMImage.Format = (fmt == kCVPixelFormatType_32BGRA) ? .bgra : .rgba
        self.init(bytes: data, width: w, height: h, format: format)
    }
#endif

#if canImport(CoreGraphics)
    fileprivate static func fromCGImage(_ cg: CGImage) -> VLMImage? {
        let w = cg.width, h = cg.height
        let bytesPerRow = 4 * w
        var buf = [UInt8](repeating: 0, count: bytesPerRow * h)
        guard let ctx = CGContext(
            data: &buf,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return VLMImage(bytes: Data(buf), width: w, height: h, format: .rgba)
    }
#endif
}
