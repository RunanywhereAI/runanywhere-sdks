//
//  BenchmarkDetailView.swift
//  RunAnywhereAI
//
//  Shows details of a single benchmark run with export actions.
//

import SwiftUI

struct BenchmarkDetailView: View {
    let run: BenchmarkRun
    @State private var viewModel = BenchmarkViewModel()

    var body: some View {
        List {
            // Metadata
            Section("Run Info") {
                LabeledContent("Started", value: run.startedAt.formatted(date: .abbreviated, time: .shortened))
                if let completedAt = run.completedAt {
                    LabeledContent("Completed", value: completedAt.formatted(date: .abbreviated, time: .shortened))
                }
                if let duration = run.duration {
                    LabeledContent("Duration", value: String(format: "%.1fs", duration))
                }
                HStack {
                    Text("Status")
                    Spacer()
                    StatusBadge(status: run.status)
                }
                LabeledContent("Results", value: "\(run.results.count)")
            }

            // Device Info
            Section("Device") {
                LabeledContent("Model", value: run.deviceInfo.modelName)
                LabeledContent("Chip", value: run.deviceInfo.chipName)
                LabeledContent("RAM", value: ByteCountFormatter.string(fromByteCount: run.deviceInfo.totalMemoryBytes, countStyle: .memory))
                LabeledContent("OS", value: run.deviceInfo.osVersion)
            }

            // Results grouped by category
            let grouped = Dictionary(grouping: run.results, by: { $0.category })
            ForEach(BenchmarkCategory.allCases) { category in
                if let results = grouped[category], !results.isEmpty {
                    Section {
                        ForEach(results) { result in
                            ResultCard(result: result)
                        }
                    } header: {
                        Label(category.displayName, systemImage: category.iconName)
                    }
                }
            }
        }
        .navigationTitle("Benchmark Details")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        viewModel.copyReportToClipboard(run: run)
                    } label: {
                        Label("Copy Report", systemImage: "doc.on.doc")
                    }

                    ShareLink(item: viewModel.shareJSON(run: run)) {
                        Label("Export JSON", systemImage: "curlybraces")
                    }

                    ShareLink(item: viewModel.shareCSV(run: run)) {
                        Label("Export CSV", systemImage: "tablecells")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }
}

// MARK: - Result Card

private struct ResultCard: View {
    let result: BenchmarkResult

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.smallMedium) {
            HStack {
                Text(result.scenario.name)
                    .font(AppTypography.subheadlineMedium)
                Spacer()
                if result.metrics.didSucceed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppColors.statusGreen)
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppColors.statusRed)
                }
            }

            Text("\(result.modelInfo.name) · \(result.modelInfo.framework)")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)

            if let error = result.metrics.errorMessage {
                Text(error)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.statusRed)
            } else {
                MetricsGrid(metrics: result.metrics, category: result.category)
            }
        }
        .padding(.vertical, AppSpacing.xSmall)
    }
}

// MARK: - Metrics Grid

private struct MetricsGrid: View {
    let metrics: BenchmarkMetrics
    let category: BenchmarkCategory

    var body: some View {
        let items = metricItems
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: AppSpacing.xSmall) {
            ForEach(items, id: \.label) { item in
                HStack(spacing: AppSpacing.xSmall) {
                    Text(item.label)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                    Spacer()
                    Text(item.value)
                        .font(AppTypography.monospacedCaption)
                        .foregroundColor(AppColors.textPrimary)
                }
            }
        }
    }

    private var metricItems: [(label: String, value: String)] {
        var items: [(String, String)] = []
        items.append(("Load", String(format: "%.0fms", metrics.loadTimeMs)))
        items.append(("E2E", String(format: "%.0fms", metrics.endToEndLatencyMs)))

        switch category {
        case .llm:
            if let tps = metrics.tokensPerSecond { items.append(("tok/s", String(format: "%.1f", tps))) }
            if let ttft = metrics.ttftMs { items.append(("TTFT", String(format: "%.0fms", ttft))) }
            if let out = metrics.outputTokens { items.append(("Tokens", "\(out)")) }
        case .stt:
            if let rtf = metrics.realTimeFactor { items.append(("RTF", String(format: "%.2fx", rtf))) }
            if let dur = metrics.audioLengthSeconds { items.append(("Audio", String(format: "%.1fs", dur))) }
        case .tts:
            if let dur = metrics.audioDurationSeconds { items.append(("Audio", String(format: "%.1fs", dur))) }
            if let chars = metrics.charactersProcessed { items.append(("Chars", "\(chars)")) }
        case .vlm:
            if let tps = metrics.tokensPerSecond { items.append(("tok/s", String(format: "%.1f", tps))) }
            if let ct = metrics.completionTokens { items.append(("Tokens", "\(ct)")) }
        case .diffusion:
            if let gen = metrics.generationTimeMs { items.append(("Gen", String(format: "%.0fms", gen))) }
        }

        if metrics.memoryDeltaBytes != 0 {
            items.append(("Mem Δ", ByteCountFormatter.string(fromByteCount: metrics.memoryDeltaBytes, countStyle: .memory)))
        }
        return items
    }
}

// MARK: - Status Badge

private struct StatusBadge: View {
    let status: BenchmarkRunStatus

    var body: some View {
        Text(status.rawValue.capitalized)
            .font(AppTypography.caption2Medium)
            .padding(.horizontal, AppSpacing.smallMedium)
            .padding(.vertical, AppSpacing.xxSmall)
            .background(backgroundColor.opacity(0.2))
            .foregroundColor(backgroundColor)
            .cornerRadius(AppSpacing.cornerRadiusSmall)
    }

    private var backgroundColor: Color {
        switch status {
        case .completed: return AppColors.statusGreen
        case .running: return AppColors.statusBlue
        case .cancelled: return AppColors.statusOrange
        case .failed: return AppColors.statusRed
        }
    }
}
