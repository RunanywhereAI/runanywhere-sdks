//
//  AnalyticsView.swift
//  RunAnywhereAI
//
//  Analytics display component
//

import SwiftUI
import RunAnywhereSDK

struct SessionAnalyticsView: View {
    let sessionId: UUID?
    @State private var session: GenerationSession?
    @State private var generations: [Generation] = []
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let session = session {

            // Header
            HStack {
                Image(systemName: "chart.bar.xaxis")
                    .foregroundColor(.blue)
                Text("Session Analytics")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    // Session Metrics
                    Group {
                        MetricRow(icon: "number", label: "Generations", value: "\(session.generationCount)")
                        MetricRow(icon: "speedometer", label: "Avg Speed", value: "\(String(format: "%.1f", session.averageTokensPerSecond)) tok/s")
                        MetricRow(icon: "clock", label: "Total Time", value: "\(String(format: "%.1f", session.totalDuration))s")
                    }

                    Divider()

                    // Token Metrics
                    Group {
                        MetricRow(icon: "arrow.right.doc.on.clipboard", label: "Input Tokens", value: "\(session.totalInputTokens)")
                        MetricRow(icon: "arrow.left.doc.on.clipboard", label: "Output Tokens", value: "\(session.totalOutputTokens)")
                        MetricRow(icon: "doc.on.doc", label: "Total Tokens", value: "\(session.totalInputTokens + session.totalOutputTokens)")
                    }

                    Divider()

                    // Model Info
                    Group {
                        MetricRow(icon: "cpu", label: "Model", value: session.modelId)
                        MetricRow(icon: "tag", label: "Session", value: String(session.id.uuidString.prefix(8)))
                    }

                    // Latest generation details
                    if let latestGen = generations.last, let performance = latestGen.performance {
                        Divider()
                        Text("Latest Generation")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        MetricRow(icon: "timer", label: "TTFT", value: "\(String(format: "%.2f", performance.timeToFirstToken))s")
                        MetricRow(icon: "speedometer", label: "Speed", value: "\(String(format: "%.1f", performance.tokensPerSecond)) tok/s")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            } else {
                // Show placeholder when no analytics data available
                HStack {
                    Image(systemName: "chart.bar.xaxis")
                        .foregroundColor(.orange)
                    Text("Analytics Loading...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    if sessionId == nil {
                        Text("No Session")
                            .font(.caption2)
                            .foregroundColor(.red)
                    } else {
                        Text("Session: \(sessionId!.uuidString.prefix(8))")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
        .padding(.vertical, 4)
        .task {
            await loadAnalytics()
        }
    }

    private func loadAnalytics() async {
        guard let sessionId = sessionId else {
            print("📊 [SessionAnalyticsView] No session ID provided")
            return
        }

        print("📊 [SessionAnalyticsView] Loading analytics for session: \(sessionId)")

        // Load session and generations from SDK
        session = await RunAnywhereSDK.shared.getAnalyticsSession(sessionId)
        generations = await RunAnywhereSDK.shared.getGenerationsForSession(sessionId)

        print("📊 [SessionAnalyticsView] Loaded session: \(session != nil ? "YES" : "NO")")
        print("📊 [SessionAnalyticsView] Loaded \(generations.count) generations")

        if let session = session {
            print("📊 [SessionAnalyticsView] Session details - Generations: \(session.generationCount), Model: \(session.modelId)")
        }
    }

}

struct MetricRow: View {
    let icon: String
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 20)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(valueColor)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
        }
    }
}

// Full analytics history view
struct AnalyticsHistoryView: View {
    @State private var sessions: [GenerationSession] = []
    @Environment(\.dismiss) var dismiss

    var totalStats: (sessions: Int, generations: Int, totalTokens: Int) {
        let totalGenerations = sessions.reduce(0) { $0 + $1.generationCount }
        let totalTokens = sessions.reduce(0) { $0 + $1.totalInputTokens + $1.totalOutputTokens }
        return (sessions.count, totalGenerations, totalTokens)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Summary Stats
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Summary")
                            .font(.headline)

                        HStack(spacing: 16) {
                            StatCard(title: "Sessions", value: "\(totalStats.sessions)", icon: "bubble.left.and.bubble.right")
                            StatCard(title: "Generations", value: "\(totalStats.generations)", icon: "sparkles")
                        }

                        HStack(spacing: 16) {
                            StatCard(title: "Total Tokens", value: "\(totalStats.totalTokens)", icon: "doc.text")
                            StatCard(title: "Avg Speed", value: "\(avgSpeed()) tok/s", icon: "speedometer")
                        }
                    }
                    .padding()

                    Divider()

                    // Individual Sessions
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Session History")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(sessions.reversed(), id: \.id) { session in
                            SessionRow(session: session)
                        }
                    }
                }
            }
            .navigationTitle("Analytics History")
            .navigationBarItems(trailing: Button("Done") { dismiss() })
            .task {
                sessions = await RunAnywhereSDK.shared.getAllAnalyticsSessions()
            }
        }
    }

    private func avgSpeed() -> String {
        let totalSpeed = sessions.reduce(0.0) { $0 + $1.averageTokensPerSecond }
        let avg = sessions.isEmpty ? 0 : totalSpeed / Double(sessions.count)
        return String(format: "%.1f", avg)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(10)
    }
}

struct SessionRow: View {
    let session: GenerationSession
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.startTime, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(session.generationCount) gen • \(String(format: "%.1f", session.averageTokensPerSecond)) tok/s")
                        .font(.caption2)
                }

                Spacer()

                Text("\(session.totalOutputTokens) tokens")
                    .font(.caption)
                    .foregroundColor(.green)

                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .padding(.horizontal)

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Model: \(session.modelId)")
                    Text("Type: \(session.sessionType.rawValue)")
                    Text("Duration: \(String(format: "%.2f", session.totalDuration))s")
                    Text("Session: \(String(session.id.uuidString.prefix(8)))")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .padding(.vertical, 8)
        .background(Color(UIColor.tertiarySystemBackground))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}
