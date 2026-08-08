//
//  ChatMessageAttachmentViews.swift
//  RunAnywhereAI
//
//  How an image or a document reads inside a sent message: the inline card in
//  the bubble, its thumbnail, and the preview sheet it opens.
//
//  Split out of `ChatMessageComponents.swift`, which had grown to hold the
//  bubble, the reasoning disclosure, the meta row, and all of this at once.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Inline Card

struct MessageAttachmentInlineCard: View {
    let attachment: MessageAttachment
    let role: Message.Role
    let onOpen: () -> Void

    /// A card inside the user's brand bubble sits on orange, so it tints off
    /// white; the same card on the assistant's plain background tints off the
    /// app's own surface colors.
    private var isOnBrand: Bool { role == .user }

    private var foreground: Color {
        isOnBrand ? AppColors.textWhite : AppColors.textPrimary
    }

    private var secondary: Color {
        isOnBrand ? AppColors.textWhite.opacity(0.8) : AppColors.textSecondary
    }

    private var background: Color {
        isOnBrand ? AppColors.textWhite.opacity(0.16) : AppColors.backgroundTertiary
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: Space.sm) {
                attachmentIcon

                VStack(alignment: .leading, spacing: Space.hair) {
                    Text(attachment.filename)
                        .appType(.cardTitle)
                        .foregroundStyle(foreground)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(attachment.detail ?? defaultDetail)
                        .appType(.caption)
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: Space.xs)

                Image(systemName: "arrow.up.right")
                    .appType(.caption)
                    .foregroundStyle(secondary)
            }
            .padding(Space.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(background)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(attachment.filename)")
    }

    @ViewBuilder private var attachmentIcon: some View {
        switch attachment.kind {
        case .image:
            MessageAttachmentThumbnail(attachment: attachment)
        case .document:
            RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                .fill(AppColors.primaryPurple.opacity(isOnBrand ? 0.28 : 0.14))
                .frame(width: 42, height: 42)
                .overlay(
                    Image(systemName: "doc.text")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isOnBrand ? AppColors.textWhite : AppColors.primaryPurple)
                )
        }
    }

    private var defaultDetail: String {
        switch attachment.kind {
        case .image: return "Image"
        case .document: return "Document"
        }
    }
}

// MARK: - Thumbnail

private struct MessageAttachmentThumbnail: View {
    let attachment: MessageAttachment
    @State private var imageData: Data?

    var body: some View {
        Group {
            #if canImport(UIKit)
            if let image = imageData.flatMap(UIImage.init(data:)) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                fallback
            }
            #elseif canImport(AppKit)
            if let image = imageData.flatMap(NSImage.init(data:)) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                fallback
            }
            #else
            fallback
            #endif
        }
        .frame(width: 42, height: 42)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
        .task(id: attachment.previewIdentity) {
            imageData = await attachment.loadImageData()
        }
    }

    private var fallback: some View {
        RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
            .fill(AppColors.textWhite.opacity(0.2))
            .overlay(Image(systemName: "photo").foregroundStyle(AppColors.textWhite))
    }
}

// MARK: - Preview Sheet

struct MessageAttachmentPreviewSheet: View {
    let attachment: MessageAttachment
    @Environment(\.dismiss)
    private var dismiss
    @State private var imageData: Data?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    switch attachment.kind {
                    case .image:
                        imagePreview
                    case .document:
                        documentPreview
                    }
                }
                .padding(Space.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(AppColors.backgroundGrouped)
            .navigationTitle(attachment.filename)
            #if os(iOS)
            .navigationBarTitleDisplayModeCompat(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: attachment.previewIdentity) {
            imageData = await attachment.loadImageData()
        }
    }

    @ViewBuilder private var imagePreview: some View {
        #if canImport(UIKit)
        if let image = imageData.flatMap(UIImage.init(data:)) {
            previewImage(Image(uiImage: image))
        } else {
            missingPreview
        }
        #elseif canImport(AppKit)
        if let image = imageData.flatMap(NSImage.init(data:)) {
            previewImage(Image(nsImage: image))
        } else {
            missingPreview
        }
        #else
        missingPreview
        #endif
    }

    private func previewImage(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var documentPreview: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.md) {
                Image(systemName: "doc.text")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(AppColors.primaryPurple)
                    .frame(width: 48, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(AppColors.primaryPurple.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: Space.hair) {
                    Text(attachment.filename)
                        .appType(.cardTitle)
                        .lineLimit(2)
                    if let detail = attachment.detail {
                        Text(detail)
                            .appType(.meta)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }

            Text(attachment.previewText ?? attachment.textFromDisk ?? "No preview text is available for this document.")
                .appType(.body)
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private var missingPreview: some View {
        VStack(spacing: Space.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(AppColors.warning)
            Text("Preview is unavailable")
                .appType(.cardTitle)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}

// MARK: - Loading

private extension MessageAttachment {
    var previewIdentity: String {
        relativePath ?? id.uuidString
    }

    func loadImageData() async -> Data? {
        guard kind == .image, let fileURL else { return nil }
        return await Task.detached(priority: .utility) {
            try? Data(contentsOf: fileURL)
        }.value
    }

    var textFromDisk: String? {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }
}
