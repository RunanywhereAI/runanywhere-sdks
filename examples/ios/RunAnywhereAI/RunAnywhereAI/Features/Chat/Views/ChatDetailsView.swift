//
//  ChatDetailsView.swift
//  RunAnywhereAI
//
//  Chat analytics and details views
//

import SwiftUI

// MARK: - Chat Details View

struct ChatDetailsView: View {
    let messages: [Message]
    let conversation: Conversation?

    @Environment(\.dismiss)
    private var dismiss

    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            #if os(macOS)
            macOSView
            #else
            iOSView
            #endif
        }
        .navigationTitle("Chat Analytics")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
            #else
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
            #endif
        }
        .adaptiveSheetFrame(
            minWidth: 500,
            idealWidth: 650,
            maxWidth: 800,
            minHeight: 450,
            idealHeight: 550,
            maxHeight: 700
        )
    }

    private var macOSView: some View {
        VStack(spacing: 0) {
            Picker("Analytics", selection: $selectedTab) {
                Text("Overview").tag(0)
                Text("Messages").tag(1)
                Text("Performance").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            Group {
                switch selectedTab {
                case 0:
                    ChatOverviewTab(messages: messages, conversation: conversation)
                case 1:
                    MessageAnalyticsTab(messages: messages)
                case 2:
                    PerformanceTab(messages: messages)
                default:
                    ChatOverviewTab(messages: messages, conversation: conversation)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var iOSView: some View {
        TabView(selection: $selectedTab) {
            ChatOverviewTab(messages: messages, conversation: conversation)
                .tabItem {
                    Label("Overview", systemImage: "chart.bar")
                }
                .tag(0)

            MessageAnalyticsTab(messages: messages)
                .tabItem {
                    Label("Messages", systemImage: "message")
                }
                .tag(1)

            PerformanceTab(messages: messages)
                .tabItem {
                    Label("Performance", systemImage: "speedometer")
                }
                .tag(2)
        }
    }
}

// MARK: - Overview Tab

struct ChatOverviewTab: View {
    let messages: [Message]
    let conversation: Conversation?

    private var analyticsMessages: [MessageAnalytics] {
        messages.compactMap { $0.analytics }
    }

    private var conversationSummary: String {
        let messageCount = messages.count
        let userMessages = messages.filter { $0.role == .user }.count
        let assistantMessages = messages.filter { $0.role == .assistant }.count
        return "\(messageCount) messages • \(userMessages) from you, \(assistantMessages) from AI"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xLarge) {
                VStack(alignment: .leading, spacing: AppSpacing.mediumLarge) {
                    Text("Conversation Summary")
                        .font(AppTypography.headlineSemibold)

                    VStack(alignment: .leading, spacing: AppSpacing.smallMedium) {
                        HStack {
                            Image(systemName: "message.circle")
                                .foregroundColor(AppColors.primaryAccent)
                            Text(conversationSummary)
                                .font(AppTypography.subheadline)
                        }

                        if let conversation = conversation {
                            HStack {
                                Image(systemName: "clock")
                                    .foregroundColor(AppColors.primaryAccent)
                                Text("Created \(conversation.createdAt, style: .relative)")
                                    .font(AppTypography.subheadline)
                            }
                        }

                        if !analyticsMessages.isEmpty {
                            HStack {
                                Image(systemName: "cube")
                                    .foregroundColor(AppColors.primaryAccent)
                                let models = Set(analyticsMessages.map { $0.modelName })
                                Text("\(models.count) model\(models.count == 1 ? "" : "s") used")
                                    .font(AppTypography.subheadline)
                            }
                        }
                    }
                }
                .padding(AppSpacing.large)
                .background(
                    RoundedRectangle(cornerRadius: AppSpacing.mediumLarge)
                        .fill(AppColors.backgroundGray6)
                )

                if !analyticsMessages.isEmpty {
                    VStack(alignment: .leading, spacing: AppSpacing.mediumLarge) {
                        Text("Performance Highlights")
                            .font(.headline)
                            .fontWeight(.semibold)

                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: AppSpacing.mediumLarge) {
                            PerformanceCard(
                                title: "Avg Response Time",
                                value: String(format: "%.1fs", averageResponseTime),
                                icon: "timer",
                                color: AppColors.statusGreen
                            )

                            PerformanceCard(
                                title: "Avg Speed",
                                value: "\(Int(averageTokensPerSecond)) tok/s",
                                icon: "speedometer",
                                color: AppColors.primaryAccent
                            )

                            PerformanceCard(
                                title: "Total Tokens",
                                value: "\(totalTokens)",
                                icon: "textformat.123",
                                color: AppColors.primaryPurple
                            )

                            PerformanceCard(
                                title: "Success Rate",
                                value: "\(Int(completionRate * 100))%",
                                icon: "checkmark.circle",
                                color: AppColors.statusOrange
                            )
                        }
                    }
                    .padding(AppSpacing.large)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(AppColors.backgroundGray6)
                    )
                }

                Spacer()
            }
            .padding(AppSpacing.large)
        }
    }

    private var averageResponseTime: Double {
        guard !analyticsMessages.isEmpty else { return 0 }
        return analyticsMessages.map { $0.totalGenerationTime }.reduce(0, +) / Double(analyticsMessages.count)
    }

    private var averageTokensPerSecond: Double {
        guard !analyticsMessages.isEmpty else { return 0 }
        return analyticsMessages.map { $0.averageTokensPerSecond }.reduce(0, +) / Double(analyticsMessages.count)
    }

    private var totalTokens: Int {
        analyticsMessages.reduce(0) { $0 + $1.inputTokens + $1.outputTokens }
    }

    private var completionRate: Double {
        guard !analyticsMessages.isEmpty else { return 0 }
        let completed = analyticsMessages.filter { $0.completionStatus == .complete }.count
        return Double(completed) / Double(analyticsMessages.count)
    }
}

// MARK: - Performance Card

struct PerformanceCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: AppSpacing.smallMedium) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(AppTypography.title2Semibold)

                Text(title)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusRegular)
                .fill(color.opacity(0.1))
                .strokeBorder(color.opacity(0.3), lineWidth: AppSpacing.strokeRegular)
        )
    }
}

// MARK: - Message Analytics Tab

struct MessageAnalyticsTab: View {
    let messages: [Message]

    private var analyticsMessages: [(Message, MessageAnalytics)] {
        messages.compactMap { message in
            if let analytics = message.analytics {
                return (message, analytics)
            }
            return nil
        }
    }

    var body: some View {
        List {
            ForEach(analyticsMessages.indices, id: \.self) { index in
                let messageWithAnalytics = analyticsMessages[index]
                let (message, analytics) = messageWithAnalytics
                MessageAnalyticsRow(
                    messageNumber: index + 1,
                    message: message,
                    analytics: analytics
                )
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Message Analytics Row

struct MessageAnalyticsRow: View {
    let messageNumber: Int
    let message: Message
    let analytics: MessageAnalytics

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Message #\(messageNumber)")
                    .font(AppTypography.subheadlineSemibold)

                Spacer()

                Text(analytics.modelName)
                    .font(AppTypography.caption)
                    .padding(.horizontal, AppSpacing.small)
                    .padding(.vertical, AppSpacing.xxSmall)
                    .background(AppColors.badgePrimary)
                    .cornerRadius(AppSpacing.cornerRadiusSmall)

                Text(analytics.framework)
                    .font(AppTypography.caption)
                    .padding(.horizontal, AppSpacing.small)
                    .padding(.vertical, AppSpacing.xxSmall)
                    .background(AppColors.badgePurple)
                    .cornerRadius(AppSpacing.cornerRadiusSmall)
            }

            HStack(spacing: AppSpacing.large) {
                MetricView(
                    label: "Time",
                    value: String(format: "%.1fs", analytics.totalGenerationTime),
                    color: AppColors.statusGreen
                )

                if let ttft = analytics.timeToFirstToken {
                    MetricView(
                        label: "TTFT",
                        value: String(format: "%.1fs", ttft),
                        color: AppColors.primaryAccent
                    )
                }

                MetricView(
                    label: "Speed",
                    value: "\(Int(analytics.averageTokensPerSecond)) tok/s",
                    color: AppColors.primaryPurple
                )

                if analytics.wasThinkingMode {
                    Image(systemName: "lightbulb.min")
                        .foregroundColor(AppColors.statusOrange)
                        .font(.caption)
                }
            }

            Text(message.content.prefix(100))
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Metric View

struct MetricView: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: AppSpacing.xxSmall) {
            Text(value)
                .font(AppTypography.captionMedium)
                .foregroundColor(color)

            Text(label)
                .font(AppTypography.caption2)
                .foregroundColor(AppColors.textSecondary)
        }
    }
}

// MARK: - Performance Tab

struct PerformanceTab: View {
    let messages: [Message]

    private var analyticsMessages: [MessageAnalytics] {
        messages.compactMap { $0.analytics }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xLarge) {
                if !analyticsMessages.isEmpty {
                    VStack(alignment: .leading, spacing: AppSpacing.mediumLarge) {
                        Text("Models Used")
                            .font(.headline)
                            .fontWeight(.semibold)

                        let modelGroups = Dictionary(grouping: analyticsMessages) { $0.modelName }

                        ForEach(modelGroups.keys.sorted(), id: \.self) { modelName in
                            if let modelMessages = modelGroups[modelName] {
                                let totalSpeed = modelMessages.map { $0.averageTokensPerSecond }.reduce(0, +)
                                let avgSpeed = totalSpeed / Double(modelMessages.count)
                                let totalTime = modelMessages.map { $0.totalGenerationTime }.reduce(0, +)
                                let avgTime = totalTime / Double(modelMessages.count)

                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(modelName)
                                        .font(AppTypography.subheadline)
                                        .fontWeight(.medium)

                                    Text("\(modelMessages.count) message\(modelMessages.count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(String(format: "%.1fs avg", avgTime))
                                        .font(.caption)
                                        .foregroundColor(.green)

                                    Text("\(Int(avgSpeed)) tok/s")
                                        .font(.caption)
                                        .foregroundColor(AppColors.primaryAccent)
                                }
                            }
                            .padding(AppSpacing.large)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(AppColors.backgroundGray6)
                            )
                        }
                    }

                    if analyticsMessages.contains(where: { $0.wasThinkingMode }) {
                        VStack(alignment: .leading, spacing: AppSpacing.mediumLarge) {
                            Text("Thinking Mode Analysis")
                                .font(.headline)
                                .fontWeight(.semibold)

                            let thinkingMessages = analyticsMessages.filter { $0.wasThinkingMode }
                            let thinkingRatio = Double(thinkingMessages.count) / Double(analyticsMessages.count)
                            let thinkingPercentage = thinkingRatio * 100

                            HStack {
                                Image(systemName: "lightbulb.min")
                                    .foregroundColor(.purple)

                                let percentageText = String(format: "%.0f", thinkingPercentage)
                                let messageText = "Used in \(thinkingMessages.count) messages (\(percentageText)%)"
                                Text(messageText)
                                    .font(AppTypography.subheadline)
                            }
                            .padding(AppSpacing.large)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.purple.opacity(0.1))
                            )
                        }
                    }
                }

                Spacer()
            }
            .padding(AppSpacing.large)
        }
    }
}
