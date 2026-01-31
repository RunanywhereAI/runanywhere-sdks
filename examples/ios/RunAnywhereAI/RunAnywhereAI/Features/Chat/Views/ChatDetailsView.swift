//
//  ChatDetailsView.swift
//  RunAnywhereAI
//
//  Chat analytics and details views - Native iOS Design
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
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    Text("Overview").tag(0)
                    Text("Messages").tag(1)
                    Text("Performance").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()

                TabView(selection: $selectedTab) {
                    OverviewTab(messages: messages, conversation: conversation)
                        .tag(0)
                    MessagesTab(messages: messages)
                        .tag(1)
                    PerformanceTab(messages: messages)
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Analytics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .adaptiveSheetFrame(
            minWidth: 500, idealWidth: 650, maxWidth: 800,
            minHeight: 450, idealHeight: 550, maxHeight: 700
        )
    }
}

// MARK: - Overview Tab

private struct OverviewTab: View {
    let messages: [Message]
    let conversation: Conversation?

    private var analytics: [MessageAnalytics] {
        messages.compactMap { $0.analytics }
    }

    var body: some View {
        List {
            // Conversation Section
            Section {
                row("message", "Messages", "\(messages.count)")
                row("person", "From You", "\(messages.filter { $0.role == .user }.count)")
                row("sparkles", "From AI", "\(messages.filter { $0.role == .assistant }.count)")

                if let conv = conversation {
                    row("clock", "Created", conv.createdAt.formatted(date: .abbreviated, time: .shortened))
                }
            }

            // Performance Section
            if !analytics.isEmpty {
                Section("Performance") {
                    row("timer", "Avg Response", String(format: "%.1fs", avgTime))
                    row("bolt", "Token Speed", "\(Int(avgSpeed)) tok/s")
                    row("number", "Total Tokens", "\(totalTokens)")
                    row("checkmark.circle", "Success Rate", "\(Int(successRate * 100))%")
                }

                Section("Model") {
                    let models = Set(analytics.map { $0.modelName })
                    ForEach(Array(models), id: \.self) { model in
                        row("cpu", model, "\(analytics.filter { $0.modelName == model }.count) responses")
                    }
                }
            }
        }
    }

    private func row(_ icon: String, _ title: String, _ value: String) -> some View {
        HStack {
            Label {
                Text(title)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(.orange)
            }
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private var avgTime: Double {
        guard !analytics.isEmpty else { return 0 }
        return analytics.map { $0.totalGenerationTime }.reduce(0, +) / Double(analytics.count)
    }

    private var avgSpeed: Double {
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

// MARK: - Messages Tab

private struct MessagesTab: View {
    let messages: [Message]

    private var items: [(Message, MessageAnalytics)] {
        messages.compactMap { msg in
            msg.analytics.map { (msg, $0) }
        }
    }

    var body: some View {
        List {
            ForEach(items.indices, id: \.self) { i in
                let (msg, stats) = items[i]

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(msg.content.prefix(150))
                            .font(.subheadline)
                    }

                    HStack {
                        Label {
                            Text("Time")
                        } icon: {
                            Image(systemName: "clock")
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                        Text(String(format: "%.1fs", stats.totalGenerationTime))
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label {
                            Text("Speed")
                        } icon: {
                            Image(systemName: "bolt")
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                        Text("\(Int(stats.averageTokensPerSecond)) tok/s")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label {
                            Text("Model")
                        } icon: {
                            Image(systemName: "cpu")
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                        Text(stats.modelName)
                            .foregroundStyle(.secondary)
                    }

                    if stats.wasThinkingMode {
                        Label {
                            Text("Used Thinking Mode")
                                .foregroundStyle(.orange)
                        } icon: {
                            Image(systemName: "lightbulb")
                                .foregroundStyle(.orange)
                        }
                    }
                } header: {
                    Text("Response \(i + 1)")
                }
            }
        }
    }
}

// MARK: - Performance Tab

private struct PerformanceTab: View {
    let messages: [Message]

    private var analytics: [MessageAnalytics] {
        messages.compactMap { $0.analytics }
    }

    var body: some View {
        List {
            if !analytics.isEmpty {
                Section("Models") {
                    let groups = Dictionary(grouping: analytics) { $0.modelName }
                    ForEach(groups.keys.sorted(), id: \.self) { name in
                        if let items = groups[name] {
                            let avg = items.map { $0.totalGenerationTime }.reduce(0, +) / Double(items.count)
                            let speed = items.map { $0.averageTokensPerSecond }.reduce(0, +) / Double(items.count)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(name)
                                    .font(.headline)

                                HStack {
                                    Text("\(items.count) responses")
                                    Text("•")
                                    Text(String(format: "%.1fs avg", avg))
                                    Text("•")
                                    Text("\(Int(speed)) tok/s")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                if analytics.contains(where: { $0.wasThinkingMode }) {
                    Section("Thinking Mode") {
                        let count = analytics.filter { $0.wasThinkingMode }.count
                        let pct = Int((Double(count) / Double(analytics.count)) * 100)

                        HStack {
                            Label {
                                Text("Responses")
                            } icon: {
                                Image(systemName: "lightbulb")
                                    .foregroundStyle(.orange)
                            }
                            Spacer()
                            Text("\(count)")
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Label {
                                Text("Usage")
                            } icon: {
                                Image(systemName: "percent")
                                    .foregroundStyle(.orange)
                            }
                            Spacer()
                            Text("\(pct)%")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
