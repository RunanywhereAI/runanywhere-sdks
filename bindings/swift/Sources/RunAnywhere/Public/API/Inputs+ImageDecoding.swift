//
//  Inputs+ImageDecoding.swift
//  RunAnywhere SDK
//
//  Turning image bytes into the packed 24-bit RGB the ABI carries.
//
//  Commons refuses a container arm outright: the C ABI has no carrier for a
//  JPEG or PNG, and handing container bytes to a backend expecting
//  `width * height * 3` crashes it. Decoding is therefore the SDK's job, on the
//  platform that owns image I/O.
//

import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
import ImageIO
#endif

extension ImageInput {
    /// RAVLMImageFormat was deleted along with the rest of the closed VLM
    /// image-format enum (idl/vlm_options.proto); `mediaType` is now a plain
    /// MIME string, so magic-byte sniffing resolves directly to one instead
    /// of to an enum case.
    static func mediaType(of data: Data) -> String {
        guard data.count >= 4 else { return "application/octet-stream" }
        let prefix = [UInt8](data.prefix(4))
        if prefix[0] == 0xFF, prefix[1] == 0xD8 { return "image/jpeg" }
        if prefix[0] == 0x89, prefix[1] == 0x50 { return "image/png" }
        if prefix[0] == 0x52, prefix[1] == 0x49 { return "image/webp" }
        return "application/octet-stream"
    }

    static func decode(_ data: Data) throws -> (data: Data, width: Int, height: Int) {
        #if canImport(CoreGraphics)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let rgb = packedRGB(from: image) else {
            throw SDKException(
                code: .invalidInput,
                message: "Could not decode the supplied image bytes",
                category: .validation
            )
        }
        return (rgb, image.width, image.height)
        #else
        throw SDKException(
            code: .featureNotAvailable,
            message: "Image decoding needs CoreGraphics; supply ImageInput.rawRgb instead",
            category: .validation
        )
        #endif
    }

    #if canImport(CoreGraphics)
    static func packedRGB(from image: CGImage) -> Data? {
        let width = image.width
        let height = image.height
        let bytesPerRow = 4 * width
        let totalBytes = bytesPerRow * height
        guard totalBytes > 0 else { return nil }

        var rgba = Data(count: totalBytes)
        var drew = false
        rgba.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            drew = true
        }
        guard drew else { return nil }

        var rgb = Data(capacity: width * height * 3)
        rgba.withUnsafeBytes { buffer in
            let pixels = buffer.bindMemory(to: UInt8.self)
            for index in stride(from: 0, to: totalBytes, by: 4) {
                rgb.append(pixels[index])
                rgb.append(pixels[index + 1])
                rgb.append(pixels[index + 2])
            }
        }
        return rgb
    }
    #endif
}
