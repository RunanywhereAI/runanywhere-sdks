//
//  ChatDetailsView.swift
//  RunAnywhereAI
//
//  Conversation details and generation analytics.
//

import SwiftUI

// MARK: - Chat Details View

struct ChatDetailsView: View {
    let messages: [Message]
    let conversation: Conversation?

    @Environment(\.dismiss)
    private var dismiss

    private var analytics: [MessageAnalytics] {
        messages.compactMap { $0.analytics }
    }

    var body: some View {
        NavigationStack {
            List {
                conversationSection
                performanceSummarySection
                modelSection
                responseDetailsSection
                thinkingSection
            }
            #if os(iOS)
            .background(Color(.systemGroupedBackground))
            #else
            .background(Color(nsColor: .controlBackgroundColor))
            #endif
            .navigationTitle("Conversation Details")
            #if os(iOS)
            .navigationBarTitleDisplayModeCompat(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
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

    private var conversationSection: some View {
        Section("Conversation") {
            detailRow("message", "Messages", "\(messages.count)")
            detailRow("person", "From You", "\(messages.filter { $0.role == .user }.count)")
            detailRow("sparkles", "From RunAnywhere", "\(messages.filter { $0.role == .assistant }.count)")

            if let conversation {
                detailRow("clock", "Created", conversation.createdAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }

    @ViewBuilder private var performanceSummarySection: some View {
        if analytics.isEmpty {
            Section("Performance") {
                ContentUnavailableView(
                    "No responses yet",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Generation analytics appear after the assistant responds.")
                )
            }
        } else {
            Section("Performance") {
                detailRow("timer", "Average Response", String(format: "%.1fs", averageResponseTime))
                detailRow("bolt", "Token Speed", "\(Int(averageTokenSpeed)) tok/s")
                detailRow("number", "Total Tokens", "\(totalTokens)")
                detailRow("checkmark.circle", "Success Rate", "\(Int(successRate * 100))%")
            }
        }
    }

    @ViewBuilder private var modelSection: some View {
        if !analytics.isEmpty {
            Section("Models") {
                let groups = Dictionary(grouping: analytics) { $0.modelName }
                ForEach(groups.keys.sorted(), id: \.self) { name in
                    if let items = groups[name] {
                        let averageTime = items.map { $0.totalGenerationTime }.reduce(0, +) / Double(items.count)
                        let averageSpeed = items.map { $0.averageTokensPerSecond }.reduce(0, +) / Double(items.count)

                        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                            Text(name)
                                .font(AppTypography.subheadlineMedium)

                            HStack(spacing: AppSpacing.smallMedium) {
                                Text("\(items.count) responses")
                                Text(String(format: "%.1fs avg", averageTime))
                                Text("\(Int(averageSpeed)) tok/s")
                            }
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.textSecondary)
                        }
                        .padding(.vertical, AppSpacing.xSmall)
                    }
                }
            }
        }
    }

    @ViewBuilder private var responseDetailsSection: some View {
        let responseItems = messages.compactMap { message in
            message.analytics.map { (message, $0) }
        }

        if !responseItems.isEmpty {
            Section("Responses") {
                ForEach(responseItems.indices, id: \.self) { index in
                    let (message, stats) = responseItems[index]
                    ResponseDetailRow(index: index + 1, message: message, stats: stats)
                }
            }
        }
    }

    @ViewBuilder private var thinkingSection: some View {
        if analytics.contains(where: { $0.wasThinkingMode }) {
            Section("Thinking") {
                let count = analytics.filter { $0.wasThinkingMode }.count
                let percentage = Int((Double(count) / Double(analytics.count)) * 100)

                detailRow("lightbulb", "Responses", "\(count)")
                detailRow("percent", "Usage", "\(percentage)%")
            }
        }
    }

    private func detailRow(_ icon: String, _ title: String, _ value: String) -> some View {
        HStack {
            Label {
                Text(title)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(AppColors.primaryAccent)
            }
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private var averageResponseTime: Double {
        guard !analytics.isEmpty else { return 0 }
        return analytics.map { $0.totalGenerationTime }.reduce(0, +) / Double(analytics.count)
    }

    private var averageTokenSpeed: Double {
        guard !analytics.isEmpty else { return 0 }
        return analytics.map { $0.averageTokensPerSecond }.reduce(0, +) / Double(analytics.count)
    }

    private var totalTokens: Int {
        analytics.reduce(0) { $0 + $1.inputTokens + $1.outputTokens }
    }

    private var successRate: Double {
        guard !analytics.isEmpty else { return 0 }
        return Double(analytics.filter { $0.completionStatus == .complete }.count) / Double(analytics.count)
    }
}

private struct ResponseDetailRow: View {
    let index: Int
    let message: Message
    let stats: MessageAnalytics

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.smallMedium) {
            Text("Response \(index)")
                .font(AppTypography.subheadlineMedium)

            if !message.content.isEmpty {
                Text(String(message.content.prefix(150)))
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(3)
            }

            HStack(spacing: AppSpacing.mediumLarge) {
                metric("clock", String(format: "%.1fs", stats.totalGenerationTime))
                metric("bolt", "\(Int(stats.averageTokensPerSecond)) tok/s")
                metric("cpu", stats.modelName)
            }

            if stats.wasThinkingMode {
                Label("Thinking used", systemImage: "lightbulb")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.primaryAccent)
            }
        }
        .padding(.vertical, AppSpacing.xSmall)
    }

    private func metric(_ icon: String, _ value: String) -> some View {
        Label(value, systemImage: icon)
            .font(AppTypography.caption2)
            .foregroundColor(AppColors.textSecondary)
            .lineLimit(1)
    }
}
