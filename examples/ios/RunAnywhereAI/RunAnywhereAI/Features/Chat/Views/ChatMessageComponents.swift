//
//  ChatMessageComponents.swift
//  RunAnywhereAI
//
//  Chat message components - extracted from ChatInterfaceView for file length compliance
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Typing Indicator

struct TypingIndicatorView: View {
    @State private var animationPhase = 0

    var body: some View {
        HStack(spacing: AppSpacing.xSmall) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(AppColors.primaryAccent.opacity(0.7))
                    .frame(width: AppSpacing.iconSmall, height: AppSpacing.iconSmall)
                    .scaleEffect(animationPhase == index ? 1.3 : 0.8)
                    .animation(
                        Animation.easeInOut(duration: AppLayout.animationVerySlow)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2),
                        value: animationPhase
                    )
            }

            Spacer(minLength: AppSpacing.padding60)
        }
        .padding(.vertical, AppSpacing.smallMedium)
        .onAppear {
            withAnimation {
                animationPhase = 1
            }
        }
    }
}

// MARK: - Streaming Cursor

/// Pulsing brand dot shown while tokens stream into the tail message.
struct StreamingCursorDot: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(AppColors.primaryAccent)
            .frame(width: 9, height: 9)
            .scaleEffect(pulsing ? 0.75 : 1.0)
            .opacity(pulsing ? 0.4 : 1.0)
            .animation(
                .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                value: pulsing
            )
            .onAppear { pulsing = true }
    }
}

// MARK: - Message Bubble

struct MessageBubbleView: View {
    let message: Message
    let isGenerating: Bool
    /// True only for the assistant message currently receiving tokens.
    var isStreamingTail: Bool = false
    @State private var showToolCallSheet = false
    @State private var previewAttachment: MessageAttachment?

    var hasThinking: Bool {
        message.thinkingContent != nil && !(message.thinkingContent?.isEmpty ?? true)
    }

    var hasToolCall: Bool {
        message.toolCallInfo != nil
    }

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: AppSpacing.padding60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.role == .assistant && (isStreamingTail || hasThinking) {
                    ReasoningDisclosureView(
                        reasoning: message.thinkingContent ?? "",
                        isStreaming: isStreamingTail
                    )
                }

                if message.role == .assistant && hasToolCall {
                    toolCallSection
                }

                mainMessageBubble

                timestampAndAnalyticsSection
            }

            if message.role != .user {
                Spacer(minLength: AppSpacing.padding60)
            }
        }
        .adaptiveSheet(isPresented: $showToolCallSheet) {
            if let toolCallInfo = message.toolCallInfo {
                ToolCallDetailSheet(toolCallInfo: toolCallInfo)
                    .adaptiveSheetFrame()
            }
        }
        .adaptiveSheet(isPresented: isAttachmentPreviewPresented) {
            if let previewAttachment {
                MessageAttachmentPreviewSheet(attachment: previewAttachment)
                    .adaptiveSheetFrame(
                        minWidth: 420,
                        idealWidth: 640,
                        maxWidth: 900,
                        minHeight: 360,
                        idealHeight: 560,
                        maxHeight: 800
                    )
            }
        }
    }

    private var isAttachmentPreviewPresented: Binding<Bool> {
        Binding {
            previewAttachment != nil
        } set: { isPresented in
            if !isPresented {
                previewAttachment = nil
            }
        }
    }

    @ViewBuilder var toolCallSection: some View {
        if let toolCallInfo = message.toolCallInfo {
            ToolCallIndicator(toolCallInfo: toolCallInfo) {
                showToolCallSheet = true
            }
        }
    }
}

// MARK: - Reasoning Disclosure

/// Shared reasoning presentation for Apple chat surfaces. Streaming forces the
/// disclosure open so model-emitted thought deltas remain visible. Once the
/// request finishes, the disclosure returns to its user-controlled collapsed
/// state while keeping the final answer directly below it.
struct ReasoningDisclosureView: View {
    let reasoning: String
    let isStreaming: Bool
    @State private var isUserExpanded = false

    private var isExpanded: Bool {
        isStreaming || isUserExpanded
    }

    private var hasReasoning: Bool {
        !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Button {
                guard !isStreaming else { return }
                withAnimation(.easeInOut(duration: AppLayout.animationFast)) {
                    isUserExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.min")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.primaryPurple)

                    Text(headerTitle)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.primaryPurple)
                        .lineLimit(1)

                    Spacer()

                    if isStreaming {
                        StreamingCursorDot()
                    } else {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.right")
                            .font(AppTypography.caption2)
                            .foregroundColor(AppColors.primaryPurple.opacity(0.6))
                    }
                }
                .padding(.horizontal, AppSpacing.regular)
                .padding(.vertical, AppSpacing.padding9)
                .background(headerBackground)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(headerTitle)
            .accessibilityHint(
                isStreaming
                    ? "Reasoning is expanded while generation is active"
                    : "Toggles reasoning"
            )

            if isExpanded {
                reasoningContent
                .padding(AppSpacing.mediumLarge)
                .background(
                    RoundedRectangle(cornerRadius: AppSpacing.medium)
                        .fill(AppColors.backgroundGray6)
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .slide),
                    removal: .opacity.combined(with: .slide)
                ))
            }
        }
    }

    private var headerTitle: String {
        if isStreaming {
            return hasReasoning ? "Thinking live…" : "Thinking…"
        }
        return isExpanded ? "Hide reasoning" : "Show reasoning"
    }

    private var reasoningContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.smallMedium) {
                    if hasReasoning {
                        Text(reasoning)
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    } else {
                        HStack(spacing: AppSpacing.smallMedium) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Waiting for model output…")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("reasoning-stream-end")
                }
            }
            .frame(maxHeight: AppSpacing.minFrameHeight)
            .onAppear {
                scrollToLatestReasoning(using: proxy)
            }
            .onChange(of: reasoning) { _, _ in
                scrollToLatestReasoning(using: proxy)
            }
        }
    }

    private func scrollToLatestReasoning(using proxy: ScrollViewProxy) {
        guard isStreaming else { return }
        proxy.scrollTo("reasoning-stream-end", anchor: .bottom)
    }

    private var headerBackground: some View {
        RoundedRectangle(cornerRadius: AppSpacing.mediumLarge)
            .fill(
                LinearGradient(
                    colors: [
                        AppColors.primaryPurple.opacity(0.1),
                        AppColors.primaryPurple.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .shadow(color: AppColors.primaryPurple.opacity(0.2), radius: 2, x: 0, y: 1)
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.mediumLarge)
                    .strokeBorder(
                        AppColors.primaryPurple.opacity(0.2),
                        lineWidth: AppSpacing.strokeThin
                    )
            )
    }
}

// MARK: - MessageBubbleView Badge and Analytics

extension MessageBubbleView {
    @ViewBuilder var timestampAndAnalyticsSection: some View {
        // Only show timestamp for assistant messages when content exists and not generating
        if message.role == .assistant && !message.content.isEmpty && !isGenerating {
            HStack(spacing: 6) {
                Spacer()

                Text(message.timestamp, style: .time)
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.textSecondary)

                if let analytics = message.analytics {
                    analyticsContent(analytics)
                }
            }
            .padding(.leading, AppSpacing.mediumLarge)
        }
    }

    @ViewBuilder
    private func analyticsContent(_ analytics: MessageAnalytics) -> some View {
        Group {
            Text("\u{2022}")
                .foregroundColor(AppColors.textSecondary.opacity(0.5))

            Text("\(String(format: "%.1f", analytics.totalGenerationTime))s")
                .font(AppTypography.caption2)
                .foregroundColor(AppColors.textSecondary)

            if analytics.averageTokensPerSecond > 0 {
                Text("\u{2022}")
                    .foregroundColor(AppColors.textSecondary.opacity(0.5))

                Text("\(Int(analytics.averageTokensPerSecond)) tok/s")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if analytics.wasThinkingMode {
                Image(systemName: "lightbulb.min")
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.primaryPurple.opacity(0.7))
            }
        }
    }
}

// MARK: - MessageBubbleView Main Bubble

extension MessageBubbleView {
    var userBubbleGradient: LinearGradient {
        LinearGradient(
            colors: [
                AppColors.userBubbleGradientStart,
                AppColors.userBubbleGradientEnd
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var assistantBubbleGradient: LinearGradient {
        LinearGradient(
            colors: [
                AppColors.backgroundGray5,
                AppColors.backgroundGray6
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// User turns keep a brand bubble; assistant replies read as a document
    /// (full-width, no bubble) — the consumer chat idiom.
    @ViewBuilder var messageBubbleBackground: some View {
        if message.role == .user {
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusBubble)
                .fill(userBubbleGradient)
                .shadow(color: AppColors.shadowLight, radius: 3, x: 0, y: 2)
        } else {
            Color.clear
        }
    }

    var shouldPulse: Bool {
        isGenerating && message.role == .assistant && message.content.count < 50
    }

    @ViewBuilder var mainMessageBubble: some View {
        if !message.content.isEmpty || message.attachment != nil {
            Group {
                if message.role == .assistant {
                    VStack(alignment: .leading, spacing: 0) {
                        AdaptiveMarkdownText(
                            message.content,
                            font: AppTypography.body,
                            color: AppColors.textPrimary
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)

                        if isStreamingTail {
                            StreamingCursorDot()
                                .padding(.top, AppSpacing.small)
                        }
                    }
                    .padding(.vertical, AppSpacing.smallMedium)
                } else {
                    VStack(alignment: .leading, spacing: AppSpacing.smallMedium) {
                        if let attachment = message.attachment {
                            MessageAttachmentInlineCard(attachment: attachment, role: message.role) {
                                previewAttachment = attachment
                            }
                        }

                        if !message.content.isEmpty {
                            Text(message.content)
                                .foregroundColor(AppColors.textWhite)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, AppSpacing.large)
                    .padding(.vertical, AppSpacing.mediumLarge)
                }
            }
            .background(messageBubbleBackground)
            .animation(nil, value: message.content)
            .contextMenu {
                Button {
                    copyMessageContent()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
        }
    }

    private func copyMessageContent() {
        #if canImport(UIKit)
        UIPasteboard.general.string = message.content
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        #endif
    }
}

// MARK: - Message Attachments

private struct MessageAttachmentInlineCard: View {
    let attachment: MessageAttachment
    let role: Message.Role
    let onOpen: () -> Void

    private var foreground: Color {
        role == .user ? AppColors.textWhite : AppColors.textPrimary
    }

    private var secondary: Color {
        role == .user ? AppColors.textWhite.opacity(0.8) : AppColors.textSecondary
    }

    private var background: Color {
        role == .user ? AppColors.textWhite.opacity(0.16) : AppColors.backgroundTertiary
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: AppSpacing.smallMedium) {
                attachmentIcon

                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.filename)
                        .font(AppTypography.captionMedium)
                        .foregroundColor(foreground)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(attachment.detail ?? defaultDetail)
                        .font(AppTypography.caption2)
                        .foregroundColor(secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: AppSpacing.xSmall)

                Image(systemName: "arrow.up.right")
                    .font(AppTypography.caption2)
                    .foregroundColor(secondary)
            }
            .padding(AppSpacing.smallMedium)
            .background(background)
            .cornerRadius(AppSpacing.cornerRadiusRegular)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(attachment.filename)")
    }

    @ViewBuilder private var attachmentIcon: some View {
        switch attachment.kind {
        case .image:
            MessageAttachmentThumbnail(attachment: attachment)
        case .document:
            RoundedRectangle(cornerRadius: 7)
                .fill(AppColors.primaryPurple.opacity(role == .user ? 0.28 : 0.14))
                .frame(width: 42, height: 42)
                .overlay(
                    Image(systemName: "doc.text")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(role == .user ? AppColors.textWhite : AppColors.primaryPurple)
                )
        }
    }

    private var defaultDetail: String {
        switch attachment.kind {
        case .image:
            return "Image"
        case .document:
            return "Document"
        }
    }
}

private struct MessageAttachmentThumbnail: View {
    let attachment: MessageAttachment
    @State private var imageData: Data?

    var body: some View {
        Group {
            #if canImport(UIKit)
            if let image = imageData.flatMap(UIImage.init(data:)) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                fallback
            }
            #elseif canImport(AppKit)
            if let image = imageData.flatMap(NSImage.init(data:)) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                fallback
            }
            #else
            fallback
            #endif
        }
        .frame(width: 42, height: 42)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .task(id: attachment.previewIdentity) {
            imageData = await attachment.loadImageData()
        }
    }

    private var fallback: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(AppColors.textWhite.opacity(0.2))
            .overlay(
                Image(systemName: "photo")
                    .foregroundColor(AppColors.textWhite)
            )
    }
}

private struct MessageAttachmentPreviewSheet: View {
    let attachment: MessageAttachment
    @Environment(\.dismiss)
    private var dismiss
    @State private var imageData: Data?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.large) {
                    switch attachment.kind {
                    case .image:
                        imagePreview
                    case .document:
                        documentPreview
                    }
                }
                .padding(AppSpacing.large)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(AppColors.backgroundPrimary)
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
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .cornerRadius(AppSpacing.cornerRadiusRegular)
        } else {
            missingPreview
        }
        #elseif canImport(AppKit)
        if let image = imageData.flatMap(NSImage.init(data:)) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .cornerRadius(AppSpacing.cornerRadiusRegular)
        } else {
            missingPreview
        }
        #else
        missingPreview
        #endif
    }

    private var documentPreview: some View {
        VStack(alignment: .leading, spacing: AppSpacing.mediumLarge) {
            HStack(spacing: AppSpacing.mediumLarge) {
                Image(systemName: "doc.text")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(AppColors.primaryPurple)
                    .frame(width: 48, height: 48)
                    .background(AppColors.primaryPurple.opacity(0.12))
                    .cornerRadius(AppSpacing.cornerRadiusRegular)

                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.filename)
                        .font(AppTypography.subheadlineMedium)
                        .lineLimit(2)
                    if let detail = attachment.detail {
                        Text(detail)
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
            }

            Text(attachment.previewText ?? attachment.textFromDisk ?? "No preview text is available for this document.")
                .font(AppTypography.body)
                .foregroundColor(AppColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var missingPreview: some View {
        VStack(spacing: AppSpacing.mediumLarge) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundColor(AppColors.primaryOrange)
            Text("Preview is unavailable")
                .font(AppTypography.subheadlineMedium)
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}

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
