//
//  ChatMessageComponents.swift
//  RunAnywhereAI
//
//  One turn in the transcript: the reasoning disclosure, the bubble, the meta
//  row, and the actions.
//
//  Three decisions here are load-bearing:
//
//  1. **The meta row keys off `isStreamingTail`, not `isGenerating`.** It used to
//     hide whenever *any* generation was running, so sending a second message
//     made every earlier reply's timestamp and metrics vanish and then pop back.
//     Only the message actually receiving tokens should hide its metrics.
//  2. **Actions are visible, not just long-press.** A `.contextMenu` is the only
//     way to copy or retry a reply today, and a long press on a wall of text is
//     undiscoverable. The row below the last reply is the affordance; hover
//     reveals it on the others; the context menu stays as the shortcut.
//  3. **No `.animation(nil, ...)` on content.** Suppressing all animation on a
//     streaming bubble was a blunt fix for the transcript's six competing scroll
//     drivers (see `ChatMessageListView`). With one coalesced driver the tail can
//     grow normally, so the kill switch is gone.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Streaming Cursor

/// Pulsing brand dot shown while tokens stream into the tail message.
struct StreamingCursorDot: View {
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(AppColors.primaryAccent)
            .frame(width: 9, height: 9)
            .scaleEffect(pulsing ? 0.75 : 1.0)
            .opacity(pulsing ? 0.4 : 1.0)
            // Suppressed rather than shortened under Reduce Motion: collapsing a
            // `repeatForever` to a 0.15s fade still repeats forever.
            .animation(Motion.resolveAmbient(reduceMotion: reduceMotion), value: pulsing)
            .onAppear { pulsing = !reduceMotion }
            .accessibilityLabel("Generating")
    }
}

// MARK: - Message Actions

/// What a reader can do with one turn. A value of closures rather than a
/// `LLMViewModel` reference: the bubble stays a pure function of its message, so
/// a token arriving in the tail cannot invalidate all 200 earlier bubbles.
struct MessageActions {
    var regenerate: (() -> Void)?
    var edit: (() -> Void)?
    var delete: (() -> Void)?

    static let none = MessageActions()
}

// MARK: - Message Bubble

struct MessageBubbleView: View {
    let message: Message
    /// True only for the assistant message currently receiving tokens.
    var isStreamingTail: Bool = false
    /// True for the newest turn, which shows its actions without a hover.
    var isLatestTurn: Bool = false
    /// True when the currently loaded model can emit reasoning; gates the
    /// "Thinking…" disclosure so non-thinking models never show it.
    var loadedModelSupportsThinking: Bool = false
    var actions: MessageActions = .none

    @State private var showToolCallSheet = false
    @State private var previewAttachment: MessageAttachment?
    @State private var isHovering = false
    @State private var didCopy = false

    private var hasThinking: Bool {
        !(message.thinkingContent ?? "").isEmpty
    }

    private var isUser: Bool { message.role == .user }

    /// Metrics and actions belong to a finished turn. The streaming tail hides
    /// them because its numbers do not exist yet and its text is still moving.
    private var isSettled: Bool { !isStreamingTail }

    var body: some View {
        HStack(spacing: 0) {
            if isUser { Spacer(minLength: Space.xxl) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: Space.sm) {
                if !isUser && loadedModelSupportsThinking && (isStreamingTail || hasThinking) {
                    ReasoningDisclosureView(
                        reasoning: message.thinkingContent ?? "",
                        isStreaming: isStreamingTail
                    )
                }

                if !isUser, let toolCallInfo = message.toolCallInfo {
                    ToolCallIndicator(toolCallInfo: toolCallInfo) { showToolCallSheet = true }
                }

                mainMessageBubble

                if isSettled {
                    metaRow
                }
            }

            if !isUser { Spacer(minLength: Space.xxl) }
        }
        .onHover { isHovering = $0 }
        .motionAware(Motion.microFade, value: isHovering)
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
            if !isPresented { previewAttachment = nil }
        }
    }

    // MARK: - Bubble

    /// User turns keep a brand bubble; assistant replies read as a document —
    /// full width, no container. That is the consumer chat idiom, and it is also
    /// what lets a long reply use the full reading measure instead of losing a
    /// bubble's inset on both sides.
    @ViewBuilder private var mainMessageBubble: some View {
        if !message.content.isEmpty || message.attachment != nil {
            Group {
                if isUser { userBubble } else { assistantBody }
            }
            .contextMenu { messageMenu }
        }
    }

    private var assistantBody: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            AdaptiveMarkdownText(
                message.content.trimmingCharacters(in: .whitespacesAndNewlines),
                font: AppType.font(.body),
                color: message.isError == true ? AppColors.dangerText : AppColors.textPrimary
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)

            if isStreamingTail {
                StreamingCursorDot()
            }
        }
    }

    private var userBubble: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            if let attachment = message.attachment {
                MessageAttachmentInlineCard(attachment: attachment, role: message.role) {
                    previewAttachment = attachment
                }
            }

            if !message.content.isEmpty {
                Text(message.content)
                    .appType(.body)
                    .foregroundStyle(AppColors.textWhite)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AppColors.userBubbleGradientStart, AppColors.userBubbleGradientEnd],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    // MARK: - Meta Row

    /// Timestamp, metrics, and actions on one line.
    ///
    /// The actions show for the newest turn and on hover elsewhere. On a phone
    /// there is no hover, so the newest turn — the one a reader actually wants to
    /// copy or retry — is the one that always offers them, and the context menu
    /// covers the rest.
    private var metaRow: some View {
        HStack(spacing: Space.sm) {
            if isUser { Spacer(minLength: 0) }

            if !isUser, message.analytics != nil || !message.content.isEmpty {
                analyticsSummary
            }

            actionButtons
                .opacity(isLatestTurn || isHovering ? 1 : 0)
                .allowsHitTesting(isLatestTurn || isHovering)

            if !isUser { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    /// One dot-separated run rather than several sibling `Text`s: concatenated
    /// `Text` wraps as a single paragraph, so a narrow phone breaks it between
    /// metrics instead of clipping the last one.
    ///
    /// Three metrics, not five. All five (`+ 351 tok + 12ms to first token`) ran
    /// past the four action buttons on a 393pt phone and truncated to `351 to…`,
    /// which is worse than not showing them — verified on an iPhone 17 Pro. Token
    /// count and TTFT stay in the analytics sheet, where there is room to label
    /// them properly; the summary keeps what a reader can act on.
    @ViewBuilder private var analyticsSummary: some View {
        if let analytics = message.analytics {
            Text(metricsRun(analytics))
                .appType(.caption)
                .monospacedDigit()
                .foregroundStyle(AppColors.textTertiary)
                .lineLimit(1)
                // The numbers arrive in one step when the turn finalizes; without
                // this they hard-cut in beside the timestamp.
                .contentTransition(.numericText())
                .accessibilityLabel(metricsAccessibilityLabel(analytics))

            if analytics.wasThinkingMode {
                Image(systemName: "lightbulb.min")
                    .appType(.caption)
                    .foregroundStyle(AppColors.primaryPurple.opacity(0.7))
                    .accessibilityLabel("Used reasoning")
            }
        } else {
            Text(message.timestamp, style: .time)
                .appType(.caption)
                .monospacedDigit()
                .foregroundStyle(AppColors.textTertiary)
        }
    }

    private func metricsRun(_ analytics: MessageAnalytics) -> String {
        var parts: [String] = [message.timestamp.formatted(date: .omitted, time: .shortened)]
        if analytics.averageTokensPerSecond > 0 {
            parts.append("\(Int(analytics.averageTokensPerSecond)) tok/s")
        }
        parts.append(String(format: "%.1fs", analytics.totalGenerationTime))
        return parts.joined(separator: " · ")
    }

    /// VoiceOver reads the numbers the row drops, since a screen reader has no
    /// width limit and the analytics sheet is several taps away.
    private func metricsAccessibilityLabel(_ analytics: MessageAnalytics) -> String {
        var parts: [String] = [
            "Replied at \(message.timestamp.formatted(date: .omitted, time: .shortened))"
        ]
        if analytics.averageTokensPerSecond > 0 {
            parts.append("\(Int(analytics.averageTokensPerSecond)) tokens per second")
        }
        parts.append(String(format: "%.1f seconds", analytics.totalGenerationTime))
        if analytics.outputTokens > 0 {
            parts.append("\(analytics.outputTokens) tokens")
        }
        if let ttft = analytics.timeToFirstToken, ttft > 0 {
            parts.append("\(Int(ttft * 1000)) milliseconds to first token")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Actions

    private var actionButtons: some View {
        HStack(spacing: Space.xs) {
            MessageActionButton(
                icon: didCopy ? "checkmark" : "doc.on.doc",
                label: didCopy ? "Copied" : "Copy",
                action: copyMessageContent
            )

            if let regenerate = actions.regenerate {
                MessageActionButton(icon: "arrow.clockwise", label: "Regenerate", action: regenerate)
            }

            if let edit = actions.edit {
                MessageActionButton(icon: "pencil", label: "Edit", action: edit)
            }

            if let delete = actions.delete {
                MessageActionButton(icon: "trash", label: "Delete", action: delete)
            }
        }
    }

    @ViewBuilder private var messageMenu: some View {
        Button(action: copyMessageContent) {
            Label("Copy", systemImage: "doc.on.doc")
        }

        if let regenerate = actions.regenerate {
            Button(action: regenerate) {
                Label("Regenerate", systemImage: "arrow.clockwise")
            }
        }

        if let edit = actions.edit {
            Button(action: edit) {
                Label("Edit and Resend", systemImage: "pencil")
            }
        }

        if let delete = actions.delete {
            Section {
                Button(role: .destructive, action: delete) {
                    Label(isUser ? "Delete Exchange" : "Delete Reply", systemImage: "trash")
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

        Haptics.success()
        // The clipboard gives no feedback of its own, so the button reports it.
        // Reverting after two seconds keeps the row from claiming a copy the
        // reader made minutes ago is still the one on the clipboard.
        withMotion(Motion.snappy) { didCopy = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withMotion(Motion.snappy) { didCopy = false }
        }
    }
}

// MARK: - Action Button

/// A 28pt icon button. Label-only in the accessibility tree and in the tooltip,
/// so the row stays quiet without hiding what the buttons do.
private struct MessageActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isHovering ? AppColors.textPrimary : AppColors.textTertiary)
                .frame(width: 28, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                        .fill(isHovering ? AppColors.muted : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(label)
        .accessibilityLabel(label)
        // Requires the button keep its identity across the symbol change, which
        // is why Copy swaps its `icon` rather than being replaced by a sibling.
        .contentTransition(.symbolEffect(.replace))
        .motionAware(Motion.microFade, value: isHovering)
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

    /// Roughly six lines — enough to read the model's current thought, small
    /// enough that the answer below stays on screen on the shortest phone.
    private static let streamingReasoningHeight: CGFloat = 132

    private var isExpanded: Bool { isStreaming || isUserExpanded }

    private var hasReasoning: Bool {
        !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            disclosureHeader

            if isExpanded {
                reasoningContent
                    .padding(Space.md)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(AppColors.primaryPurple.opacity(0.06))
                    )
                    // Slides down from under its own header rather than in from
                    // the side: reasoning belongs to the header above it, and a
                    // horizontal slide reads as a page change.
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: -6)),
                        removal: .opacity
                    ))
            }
        }
        .motionAware(Motion.snappy, value: isExpanded)
    }

    private var disclosureHeader: some View {
        Button {
            guard !isStreaming else { return }
            isUserExpanded.toggle()
        } label: {
            HStack(spacing: Space.sm) {
                Image(systemName: "lightbulb.min")
                    .appType(.caption)

                Text(headerTitle)
                    .appType(.chip)
                    .lineLimit(1)

                if isStreaming {
                    StreamingCursorDot()
                } else {
                    Image(systemName: "chevron.down")
                        .appType(.caption)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .motionAware(Motion.snappy, value: isExpanded)
                }
            }
            .foregroundStyle(AppColors.primaryPurple)
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
            .background(Capsule().fill(AppColors.primaryPurple.opacity(0.10)))
        }
        .buttonStyle(.plain)
        .disabled(isStreaming)
        .accessibilityLabel(headerTitle)
        .accessibilityHint(
            isStreaming
                ? "Reasoning stays expanded while the model is thinking"
                : "Shows or hides the model's reasoning"
        )
    }

    private var headerTitle: String {
        if isStreaming {
            return hasReasoning ? "Thinking…" : "Starting to think…"
        }
        return isExpanded ? "Hide reasoning" : "Show reasoning"
    }

    /// While streaming, the reasoning is capped and scrolls internally; once the
    /// turn is done and the reader opens it deliberately, it sizes to its content.
    ///
    /// Uncapped streaming reasoning is what made the answer unreachable: a 0.6B
    /// model emitted five paragraphs of thinking, the disclosure grew to fill the
    /// viewport, and the reply arrived below the fold — verified on an iPhone 17
    /// Pro. A bounded, bottom-anchored ticker shows the model is working without
    /// taking the screen hostage.
    @ViewBuilder private var reasoningContent: some View {
        if hasReasoning {
            let text = Text(reasoning.trimmingCharacters(in: .whitespacesAndNewlines))
                .appType(.secondary)
                .foregroundStyle(AppColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if isStreaming {
                ScrollView {
                    text
                }
                .frame(maxHeight: Self.streamingReasoningHeight)
                .defaultScrollAnchor(.bottom)
                .scrollIndicators(.hidden)
            } else {
                text
            }
        } else {
            HStack(spacing: Space.sm) {
                ProgressView().controlSize(.small)
                Text("Waiting for the model…")
                    .appType(.secondary)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
