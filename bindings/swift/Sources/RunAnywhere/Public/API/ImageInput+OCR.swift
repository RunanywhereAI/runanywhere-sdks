//
//  ImageInput+OCR.swift
//  RunAnywhere SDK
//
//  `ImageInput` -> `RAOCRImage`. Split out of Inputs.swift rather than added to
//  it: that file is at SwiftLint's 800-line ceiling, and one more per-modality
//  conversion is exactly the kind of growth the ceiling exists to redirect.
//

import Foundation

extension ImageInput {

    /// Packed RGB8 pixels for OCR.
    ///
    /// `rawPixels()` already normalises every source to three tightly-packed
    /// channels, so commons' RGBA8/BGRA8 arms exist for SDKs whose platform
    /// decoders hand back four — not for this one.
    func toOCRImage() throws -> RAOCRImage {
        let pixels = try rawPixels()
        var image = RAOCRImage()
        image.data = pixels.data
        image.width = UInt32(pixels.width)
        image.height = UInt32(pixels.height)
        image.pixelFormat = .rgb8
        return image
    }
}
