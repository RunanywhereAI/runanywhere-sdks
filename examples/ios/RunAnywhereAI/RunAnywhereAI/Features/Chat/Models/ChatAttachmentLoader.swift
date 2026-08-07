//
//  ChatAttachmentLoader.swift
//  RunAnywhereAI
//
//  Turning a picked file into something a model can read.
//
//  Two conversions, both of which have to happen off the main actor and both of
//  which have exactly one correct answer, so neither belongs inline in a view:
//
//  - **Photo → `ChatImageAttachment`.** The SDK owns pixel conversion, so this
//    hands `ImageInput` the platform image type and never bridges through
//    `CIContext`.
//  - **Document URL → `ChatDocumentAttachment`.** PDFKit and JSON parsing of a
//    large file blocks the UI (and risks the watchdog) if run inline, so the
//    extraction runs on a detached task. `DocumentService.extractText` manages
//    its own security-scoped access.
//
//  Free functions on a namespace rather than methods on the view: neither reads
//  a single piece of view state, and as view methods they made
//  `ChatInterfaceView` the only place this logic could be called from or read.
//

import Foundation
import RunAnywhere
// SwiftUI, not just PhotosUI: `PhotosPickerItem` is declared in the SwiftUI
// overlay of PhotosUI, so importing PhotosUI alone leaves it out of scope.
import SwiftUI
#if canImport(PhotosUI)
import PhotosUI
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

enum ChatAttachmentLoader {
    /// Load a picked photo into an attachment the vision model can accept.
    ///
    /// Throws rather than returning an optional: "the image could not be loaded"
    /// and "the image could not be prepared" are different failures, and a
    /// silently-nil return gave the caller no way to say which happened.
    static func imageAttachment(from item: PhotosPickerItem) async throws -> ChatImageAttachment {
        guard let data = try await item.loadTransferable(type: Data.self) else {
            throw LLMError.custom("The selected image could not be loaded.")
        }

        let image: ImageInput?
        #if canImport(UIKit)
        image = try UIImage(data: data).map { try ImageInput.uiImage($0) }
        #elseif canImport(AppKit)
        image = try NSImage(data: data).map { try ImageInput.nsImage($0) }
        #else
        image = nil
        #endif

        guard let image else {
            throw LLMError.custom("The selected image could not be prepared for the vision model.")
        }

        return ChatImageAttachment(
            data: data,
            image: image,
            filename: item.itemIdentifier ?? "Selected image"
        )
    }

    /// Extract a document's text off the main actor.
    static func documentAttachment(from url: URL) async throws -> ChatDocumentAttachment {
        let text = try await Task.detached(priority: .userInitiated) {
            try DocumentService.extractText(from: url)
        }.value

        return ChatDocumentAttachment(filename: url.lastPathComponent, text: text)
    }
}
