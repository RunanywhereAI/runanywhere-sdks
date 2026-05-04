//
//  VLMTypes.swift
//  RunAnywhere SDK
//
//  Minimal Swift types for VLM - only platform-specific conversions.
//  All heavy logic is in C++ (rac_vlm_types.h).
//

import CRACommons
import Foundation

#if canImport(UIKit)
import UIKit
#endif

#if canImport(CoreVideo)
import CoreVideo
#endif

// MARK: - VLM Image Input (Platform-specific conversions)

/// Image input for VLM - handles Apple platform types (UIImage, CVPixelBuffer)
public struct VLMImage: Sendable {

    public enum Format: Sendable {
        case filePath(String)
        case rgbPixels(data: Data, width: Int, height: Int)
        case base64(String)
        #if canImport(UIKit)
        case uiImage(UIImage)
        #endif
        #if canImport(CoreVideo)
        case pixelBuffer(CVPixelBuffer)
        #endif
    }

    public let format: Format

    public init(filePath: String) { self.format = .filePath(filePath) }
    public init(rgbPixels data: Data, width: Int, height: Int) { self.format = .rgbPixels(data: data, width: width, height: height) }
    public init(base64: String) { self.format = .base64(base64) }
    #if canImport(UIKit)
    public init(image: UIImage) { self.format = .uiImage(image) }
    #endif
    #if canImport(CoreVideo)
    public init(pixelBuffer: CVPixelBuffer) { self.format = .pixelBuffer(pixelBuffer) }
    #endif

    // MARK: - Convert to C struct

    internal func toCImage() -> (rac_vlm_image_t, Data?)? {
        var cImage = rac_vlm_image_t()

        switch format {
        case .filePath:
            cImage.format = RAC_VLM_IMAGE_FORMAT_FILE_PATH
            return (cImage, nil)

        case .rgbPixels(let data, let width, let height):
            cImage.format = RAC_VLM_IMAGE_FORMAT_RGB_PIXELS
            cImage.width = UInt32(width)
            cImage.height = UInt32(height)
            cImage.data_size = data.count
            return (cImage, data)

        case .base64:
            cImage.format = RAC_VLM_IMAGE_FORMAT_BASE64
            return (cImage, nil)

        #if canImport(UIKit)
        case .uiImage(let image):
            guard let rgbData = image.toRGBData() else { return nil }
            guard let cgImage = image.cgImage else { return nil }
            cImage.format = RAC_VLM_IMAGE_FORMAT_RGB_PIXELS
            cImage.width = UInt32(cgImage.width)
            cImage.height = UInt32(cgImage.height)
            cImage.data_size = rgbData.count
            return (cImage, rgbData)
        #endif

        #if canImport(CoreVideo)
        case .pixelBuffer(let buffer):
            guard let rgbData = buffer.toRGBData() else { return nil }
            cImage.format = RAC_VLM_IMAGE_FORMAT_RGB_PIXELS
            cImage.width = UInt32(CVPixelBufferGetWidth(buffer))
            cImage.height = UInt32(CVPixelBufferGetHeight(buffer))
            cImage.data_size = rgbData.count
            return (cImage, rgbData)
        #endif
        }
    }

    /// Setup pointers and call body
    internal func withCPointers<T>(cImage: inout rac_vlm_image_t, rgbData: Data?, body: (UnsafePointer<rac_vlm_image_t>) -> T) -> T {
        switch format {
        case .filePath(let path):
            return path.withCString { ptr in
                cImage.file_path = ptr
                return body(&cImage)
            }
        case .base64(let encoded):
            return encoded.withCString { ptr in
                cImage.base64_data = ptr
                cImage.data_size = encoded.utf8.count
                return body(&cImage)
            }
        case .rgbPixels(let data, _, _):
            return data.withUnsafeBytes { buffer in
                cImage.pixel_data = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self)
                return body(&cImage)
            }
        #if canImport(UIKit)
        case .uiImage:
            guard let rgbData = rgbData else { return body(&cImage) }
            return rgbData.withUnsafeBytes { buffer in
                cImage.pixel_data = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self)
                return body(&cImage)
            }
        #endif
        #if canImport(CoreVideo)
        case .pixelBuffer:
            guard let rgbData = rgbData else { return body(&cImage) }
            return rgbData.withUnsafeBytes { buffer in
                cImage.pixel_data = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self)
                return body(&cImage)
            }
        #endif
        }
    }
}

// MARK: - Platform Image Conversion Extensions

#if canImport(UIKit)
extension UIImage {
    func toRGBData() -> Data? {
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

#if canImport(CoreVideo)
extension CVPixelBuffer {
    func toRGBData() -> Data? {
        CVPixelBufferLockBaseAddress(self, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(self, .readOnly) }

        let pixelFormat = CVPixelBufferGetPixelFormatType(self)
        guard pixelFormat == kCVPixelFormatType_32BGRA else {
            SDKLogger.shared.error("[VLMImage] Unsupported pixel format. Expected BGRA.")
            return nil
        }

        let width = CVPixelBufferGetWidth(self)
        let height = CVPixelBufferGetHeight(self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(self)
        guard let baseAddress = CVPixelBufferGetBaseAddress(self) else { return nil }

        // BGRA → RGB
        var rgbData = Data(capacity: width * height * 3)
        let pixels = baseAddress.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                rgbData.append(pixels[offset + 2]) // R
                rgbData.append(pixels[offset + 1]) // G
                rgbData.append(pixels[offset])     // B
            }
        }
        return rgbData
    }
}
#endif

// MARK: - VLM Result (from C struct)

/// Result from VLM generation - maps directly from rac_vlm_result_t
public struct VLMResult: Sendable {
    public let text: String
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTimeMs: Double
    public let tokensPerSecond: Double

    internal init(from cResult: rac_vlm_result_t) {
        self.text = cResult.text.map { String(cString: $0) } ?? ""
        self.promptTokens = Int(cResult.prompt_tokens)
        self.completionTokens = Int(cResult.completion_tokens)
        self.totalTimeMs = Double(cResult.total_time_ms)
        self.tokensPerSecond = Double(cResult.tokens_per_second)
    }

    internal init(from proto: RAVLMResult) {
        self.text = proto.text
        self.promptTokens = Int(proto.promptTokens)
        self.completionTokens = Int(proto.completionTokens)
        self.totalTimeMs = Double(proto.processingTimeMs)
        self.tokensPerSecond = Double(proto.tokensPerSecond)
    }
}

// MARK: - VLM Streaming (Swift concurrency)

/// Streaming result - Swift-only (AsyncThrowingStream)
public struct VLMStreamingResult: Sendable {
    public let stream: AsyncThrowingStream<String, Error>
    public let metrics: Task<VLMResult, Error>
}

// MARK: - VLMGenerationOptions canonical typealias (CANONICAL_API §7)
//
// The proto-generated type `RAVLMGenerationOptions` (vlm_options.pb.swift)
// IS the canonical wire type. Expose it under the spec name so callers can
// write `VLMGenerationOptions` without knowing the `RA` prefix.
//
/// Canonical generation options for `processImage` / `processImageStream`.
/// Backed by the proto-generated `RAVLMGenerationOptions` (idl/vlm_options.proto).
public typealias VLMGenerationOptions = RAVLMGenerationOptions

// MARK: - Phase C1: Generated Proto Bridges
//
// Canonical wire types live in `Sources/RunAnywhere/Generated/vlm_options.pb.swift`:
//   • RAVLMImage           (oneof source: filePath/encoded/rawRgb/base64,
//                            width, height, format: RAVLMImageFormat)
//   • RAVLMConfiguration   (modelID, maxImageSizePx, maxTokens)
//   • RAVLMGenerationOptions (prompt, maxTokens, temperature, topP, topK)
//   • RAVLMResult          (text, promptTokens, completionTokens, totalTokens,
//                            totalTimeMs, tokensPerSecond, …)
//   • RAVLMImageFormat enum (.unspecified, .filePath, .jpeg, .png, .webp,
//                             .rawRgb, .rawRgba, .base64)
//   • RAVLMErrorCode enum
//
// Hand-rolled `VLMImage` is KEPT because it carries Apple-specific image
// pipeline cases (UIImage, CVPixelBuffer) and the platform-side conversion
// helpers (toCImage / withCPointers) that allocate scratch buffers for the
// underlying C ABI call. The proto type only models the wire contract.
// `VLMResult` keeps a custom `init(from cResult: rac_vlm_result_t)` C bridge.

extension VLMResult {
    /// Convert to canonical generated proto `RAVLMResult`.
    public func toRAVLMResult() -> RAVLMResult {
        var proto = RAVLMResult()
        proto.text = text
        proto.promptTokens = Int32(promptTokens)
        proto.completionTokens = Int32(completionTokens)
        proto.totalTokens = Int64(promptTokens + completionTokens)
        return proto
    }
}

extension VLMImage {
    /// Convert to canonical generated proto `RAVLMImage`. Notes on cases:
    /// • UIImage / CVPixelBuffer are NOT representable on the wire — they are
    ///   converted to raw RGB bytes (caller-side) before being placed into the
    ///   `rawRgb` oneof case. This matches the `withCPointers` C bridge
    ///   semantics.
    /// • RAVLMImageFormat values:
    ///     .filePath, .jpeg/.png/.webp (encoded), .rawRgb/.rawRgba, .base64.
    public func toRAVLMImage() -> RAVLMImage? {
        var proto = RAVLMImage()
        switch format {
        case .filePath(let path):
            proto.filePath = path
            proto.format = .filePath
        case .rgbPixels(let data, let w, let h):
            proto.rawRgb = data
            proto.width = Int32(w)
            proto.height = Int32(h)
            proto.format = .rawRgb
        case .base64(let str):
            proto.base64 = str
            proto.format = .base64
        #if canImport(UIKit)
        case .uiImage(let img):
            guard let rgb = img.toRGBData(), let cgImage = img.cgImage else { return nil }
            proto.rawRgb = rgb
            proto.width = Int32(cgImage.width)
            proto.height = Int32(cgImage.height)
            proto.format = .rawRgb
        #endif
        #if canImport(CoreVideo)
        case .pixelBuffer(let buf):
            guard let rgb = buf.toRGBData() else { return nil }
            proto.rawRgb = rgb
            proto.width = Int32(CVPixelBufferGetWidth(buf))
            proto.height = Int32(CVPixelBufferGetHeight(buf))
            proto.format = .rawRgb
        #endif
        }
        return proto
    }
}
