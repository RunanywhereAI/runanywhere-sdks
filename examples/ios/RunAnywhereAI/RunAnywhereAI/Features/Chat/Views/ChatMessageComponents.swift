//
//  ChatMessageComponents.swift
//  RunAnywhereAI
//
//  Chat message components - extracted from ChatInterfaceView for file length compliance
//

import SwiftUI

// MARK: - Typing Indicator

struct TypingIndicatorView: View {
    @State private var animationPhase = 0

    var body: some View {
        HStack {
            Spacer(minLength: AppSpacing.padding60)

            HStack(spacing: AppSpacing.mediumLarge) {
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
                }
                .padding(.horizontal, AppSpacing.mediumLarge)
                .padding(.vertical, AppSpacing.smallMedium)
                .background(typingIndicatorBackground)

                Text("AI is thinking...")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
                    .opacity(0.8)
            }

            Spacer(minLength: AppSpacing.padding60)
        }
        .onAppear {
            withAnimation {
                animationPhase = 1
            }
        }
    }

    private var typingIndicatorBackground: some View {
        RoundedRectangle(cornerRadius: AppSpacing.large)
            .fill(AppColors.backgroundGray5)
            .shadow(color: AppColors.shadowLight, radius: 3, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.large)
                    .strokeBorder(AppColors.borderLight, lineWidth: AppSpacing.strokeThin)
            )
    }
}

// MARK: - Message Bubble

struct MessageBubbleView: View {
    let message: Message
    let isGenerating: Bool
    @State private var isThinkingExpanded = false
    @State private var showToolCallSheet = false

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
                if message.role == .assistant && hasThinking {
                    thinkingSection
                }

                if message.role == .assistant && hasToolCall {
                    toolCallSection
                }

                if message.role == .assistant &&
                    message.content.isEmpty &&
                    !(message.thinkingContent ?? "").isEmpty &&
                    isGenerating {
                    thinkingProgressIndicator
                }

                mainMessageBubble

                timestampAndAnalyticsSection
            }

            if message.role != .user {
                Spacer(minLength: AppSpacing.padding60)
            }
        }
        .sheet(isPresented: $showToolCallSheet) {
            if let toolCallInfo = message.toolCallInfo {
                ToolCallDetailSheet(toolCallInfo: toolCallInfo)
                    .adaptiveSheetFrame()
            }
        }
    }

    @ViewBuilder
    var toolCallSection: some View {
        if let toolCallInfo = message.toolCallInfo {
            ToolCallIndicator(toolCallInfo: toolCallInfo) {
                showToolCallSheet = true
            }
        }
    }
}

// MARK: - MessageBubbleView Thinking Section

extension MessageBubbleView {
    var thinkingSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Button {
                withAnimation(.easeInOut(duration: AppLayout.animationFast)) {
                    isThinkingExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.min")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.primaryPurple)

                    Text(isThinkingExpanded ? "Hide reasoning" : thinkingSummary)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.primaryPurple)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: isThinkingExpanded ? "chevron.up" : "chevron.right")
                        .font(AppTypography.caption2)
                        .foregroundColor(AppColors.primaryPurple.opacity(0.6))
                }
                .padding(.horizontal, AppSpacing.regular)
                .padding(.vertical, AppSpacing.padding9)
                .background(thinkingButtonBackground)
            }
            .buttonStyle(PlainButtonStyle())

            if isThinkingExpanded {
                ScrollView {
                    Text(message.thinkingContent ?? "")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxHeight: AppSpacing.minFrameHeight)
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

    var thinkingSummary: String {
        guard let thinking = message.thinkingContent?
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return ""
        }

        let sentences = thinking.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if sentences.count >= 2 {
            let firstSentence = sentences[0].trimmingCharacters(in: .whitespacesAndNewlines)
            if firstSentence.count > 20 {
                return firstSentence + "..."
            }
        }

        if thinking.count > 80 {
            let truncated = String(thinking.prefix(80))
            if let lastSpace = truncated.lastIndex(of: " ") {
                return String(truncated[..<lastSpace]) + "..."
            }
            return truncated + "..."
        }

        return thinking
    }

    var thinkingButtonBackground: some View {
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

    var thinkingProgressBackground: some View {
        RoundedRectangle(cornerRadius: AppSpacing.medium)
            .fill(
                LinearGradient(
                    colors: [
                        AppColors.primaryPurple.opacity(0.12),
                        AppColors.primaryPurple.opacity(0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .shadow(color: AppColors.primaryPurple.opacity(0.2), radius: 2, x: 0, y: 1)
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.medium)
                    .strokeBorder(
                        AppColors.primaryPurple.opacity(0.3),
                        lineWidth: AppSpacing.strokeThin
                    )
            )
    }

    var thinkingProgressIndicator: some View {
        HStack(spacing: AppSpacing.smallMedium) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(AppColors.primaryPurple)
                        .frame(width: AppSpacing.small, height: AppSpacing.small)
                        .scaleEffect(isGenerating ? 1.0 : 0.5)
                        .animation(
                            Animation.easeInOut(duration: AppLayout.animationVerySlow)
                                .repeatForever()
                                .delay(Double(index) * 0.2),
                            value: isGenerating
                        )
                }
            }

            Text("Thinking...")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.primaryPurple.opacity(0.8))
        }
        .padding(.horizontal, AppSpacing.mediumLarge)
        .padding(.vertical, AppSpacing.smallMedium)
        .background(thinkingProgressBackground)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}

// MARK: - MessageBubbleView Badge and Analytics

extension MessageBubbleView {

    @ViewBuilder
    var timestampAndAnalyticsSection: some View {
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

    var messageBubbleBackground: some View {
        RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusBubble)
            .fill(message.role == .user ? userBubbleGradient : assistantBubbleGradient)
            .shadow(color: AppColors.shadowMedium, radius: 4, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusBubble)
                    .strokeBorder(
                        message.role == .user ? AppColors.borderLight : AppColors.borderMedium,
                        lineWidth: AppSpacing.strokeThin
                    )
            )
    }

    var shouldPulse: Bool {
        isGenerating && message.role == .assistant && message.content.count < 50
    }

    @ViewBuilder var mainMessageBubble: some View {
        // Only show message bubble if there's content
        if !message.content.isEmpty {
            ZStack(alignment: .bottomTrailing) {
                // Intelligent adaptive rendering: Content analysis → Best renderer
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

                            // Extra spacing at bottom for model badge
                            if message.modelInfo != nil {
                                Spacer()
                                    .frame(height: 16)
                            }
                        }
                    } else {
                        Text(message.content)
                            .foregroundColor(AppColors.textWhite)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, AppSpacing.large)
                .padding(.vertical, AppSpacing.mediumLarge)

                // Model name badge in bottom-right corner (assistant only)
                if message.role == .assistant, let modelInfo = message.modelInfo {
                    HStack(spacing: 3) {
                        Image(systemName: "cube")
                            .font(.system(size: 8))
                        Text(modelInfo.modelName)
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(AppColors.textSecondary.opacity(0.6))
                    .padding(.trailing, AppSpacing.mediumLarge)
                    .padding(.bottom, AppSpacing.small)
                }
            }
            .background(messageBubbleBackground)
            .animation(nil, value: message.content)
        }
    }
}
