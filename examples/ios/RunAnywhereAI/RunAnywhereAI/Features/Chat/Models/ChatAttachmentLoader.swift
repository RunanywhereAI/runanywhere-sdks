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
import UniformTypeIdentifiers
#if canImport(PhotosUI)
import PhotosUI
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Which of the two chat attachment modes a file belongs to.
enum ChatAttachmentKind {
    case image
    case document
}

enum ChatAttachmentLoader {
    // MARK: - What the chat can accept
    //
    // A picker's `allowedContentTypes` filters the *picker* — it is a
    // convenience, not a guarantee. A drop and a paste never consult it, and the
    // picker itself can be switched to "All Files". Without a check here, a
    // dropped `.pages` file would reach `DocumentService.extractText` and fail
    // with a decode error that reads as the model's fault rather than the
    // file's. So the file decides the mode, and an unsupported one says so.

    /// Document types `DocumentService` can genuinely read. Keep this in step
    /// with `DocumentType(url:)` — a type listed here that the extractor cannot
    /// open is a promise the app then breaks.
    static let documentContentTypes: [UTType] = [.pdf, .json, .plainText]

    /// The same set as filename extensions.
    ///
    /// Checked as well as the declared type because a dropped or pasted file
    /// often arrives with no usable type at all: Finder and several editors hand
    /// over `.md` as `public.data`, and a strict type check would reject a file
    /// the extractor reads perfectly well.
    private static let documentExtensions = ["pdf", "json", "txt", "md", "markdown"]

    /// Ceilings before the attachment is refused. Matched to the web app so the
    /// same file behaves the same way on every platform. An image is allowed to
    /// be larger because a phone photo routinely is.
    static let maxImageBytes = 12 * 1024 * 1024
    static let maxDocumentBytes = 4 * 1024 * 1024

    /// Which mode a file belongs to, or `nil` when neither can take it.
    static func kind(forFileAt url: URL) -> ChatAttachmentKind? {
        if let type = UTType(filenameExtension: url.pathExtension.lowercased()) {
            if type.conforms(to: .image) { return .image }
            if documentContentTypes.contains(where: { type.conforms(to: $0) }) { return .document }
        }
        if documentExtensions.contains(url.pathExtension.lowercased()) { return .document }
        return nil
    }

    /// The sentence to show when a file is refused, or `nil` when it is fine.
    ///
    /// Returns copy rather than a `Bool` so the caller cannot invent its own
    /// wording, and so "wrong type" and "too big" stay distinguishable — the two
    /// need completely different things from the user.
    static func rejectionReason(for url: URL, byteCount: Int) -> String? {
        guard byteCount > 0 else { return "That file is empty." }

        guard let kind = kind(forFileAt: url) else {
            let name = url.lastPathComponent.isEmpty ? "That file" : url.lastPathComponent
            return "\(name) isn't supported. Attach an image, or a PDF, .txt, .md, or .json file."
        }

        let limit = kind == .image ? maxImageBytes : maxDocumentBytes
        guard byteCount > limit else { return nil }
        let formatted = ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file)
        return "\(kind == .image ? "Images" : "Documents") must be \(formatted) or smaller."
    }

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

    /// Build an image attachment from raw bytes.
    ///
    /// The drop and paste path: a screenshot on the pasteboard and an image
    /// dragged out of a browser are both bytes with no file behind them, so
    /// there is no URL to hand `imageAttachment(from: PhotosPickerItem)`.
    /// Conversion is identical — the SDK owns pixels, and nothing here goes
    /// through `CIContext`.
    static func imageAttachment(from data: Data, filename: String) throws -> ChatImageAttachment {
        guard data.count <= maxImageBytes else {
            let limit = ByteCountFormatter.string(fromByteCount: Int64(maxImageBytes), countStyle: .file)
            throw LLMError.custom("Images must be \(limit) or smaller.")
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
            throw LLMError.custom("That image could not be prepared for the vision model.")
        }

        return ChatImageAttachment(data: data, image: image, filename: filename)
    }

    /// Extract a document's text off the main actor.
    static func documentAttachment(from url: URL) async throws -> ChatDocumentAttachment {
        let text = try await Task.detached(priority: .userInitiated) {
            try DocumentService.extractText(from: url)
        }.value

        return ChatDocumentAttachment(filename: url.lastPathComponent, text: text)
    }

    /// Turn a dropped or pasted file URL into whichever attachment it is.
    ///
    /// Type and size are checked here rather than after the read, so a `.pages`
    /// file is refused by name instead of by a decode failure the reader would
    /// blame on the model.
    static func attachment(forFileAt url: URL) async throws -> ChatPendingAttachment {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let byteCount = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if let reason = rejectionReason(for: url, byteCount: byteCount) {
            throw LLMError.custom(reason)
        }

        switch kind(forFileAt: url) {
        case .image:
            let data = try Data(contentsOf: url)
            return .image(try imageAttachment(from: data, filename: url.lastPathComponent))
        case .document:
            return .document(try await documentAttachment(from: url))
        case nil:
            // Unreachable: `rejectionReason` already refused an unknown type.
            throw LLMError.custom("That file isn't supported.")
        }
    }
}

/// One staged attachment, before the user has typed the question that goes with
/// it. A single value rather than two optionals because the composer can only
/// ever hold one, and two optionals made "both set" representable.
enum ChatPendingAttachment {
    case image(ChatImageAttachment)
    case document(ChatDocumentAttachment)
}

// MARK: - Pasteboard

extension ChatAttachmentLoader {
    /// Whether the clipboard currently holds something the chat could take.
    ///
    /// Read so the Paste item can be *disabled* rather than absent: an item that
    /// vanishes when the clipboard is empty is a control the user cannot learn,
    /// and one that is present but fails is a lie. Neither `UIPasteboard`'s
    /// `hasImages` nor `NSPasteboard`'s type query reads the contents, so this
    /// does not trip iOS's "allowed to paste?" prompt.
    static var pasteboardHasAttachment: Bool {
        #if canImport(UIKit)
        return UIPasteboard.general.hasImages
        #elseif canImport(AppKit)
        let board = NSPasteboard.general
        if board.canReadObject(forClasses: [NSImage.self], options: nil) { return true }
        let urls = board.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        return urls?.contains { kind(forFileAt: $0) != nil } ?? false
        #else
        return false
        #endif
    }

    /// Take whatever the clipboard is holding, or `nil` if it holds nothing the
    /// chat can use.
    static func pasteboardAttachment() async throws -> ChatPendingAttachment? {
        #if canImport(UIKit)
        guard let image = UIPasteboard.general.image, let data = image.pngData() else { return nil }
        return .image(try imageAttachment(from: data, filename: "Pasted image"))
        #elseif canImport(AppKit)
        let board = NSPasteboard.general
        // A file on the clipboard is checked first: copying a PDF in Finder puts
        // both the URL and a preview image on the board, and the document is
        // what the user meant.
        if let urls = board.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL],
           let url = urls.first(where: { kind(forFileAt: $0) != nil }) {
            return try await attachment(forFileAt: url)
        }
        guard let image = board.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage,
              let data = pngData(from: image) else { return nil }
        return .image(try imageAttachment(from: data, filename: "Pasted image"))
        #else
        return nil
        #endif
    }

    #if canImport(AppKit) && !canImport(UIKit)
    /// A screenshot arrives on the board as TIFF, which is both enormous and not
    /// what the attachment thumbnail or the on-disk copy should be.
    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
    #endif
}
