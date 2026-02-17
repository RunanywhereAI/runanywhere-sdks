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
    @State private var jsonURL: URL?
    @State private var csvURL: URL?

    var body: some View {
        ZStack {
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
                        RunStatusBadge(status: run.status)
                    }
                    let successCount = run.results.filter(\.metrics.didSucceed).count
                    let failCount = run.results.count - successCount
                    LabeledContent("Results", value: "\(run.results.count) (\(successCount) passed, \(failCount) failed)")
                }

                // Device Info
                Section("Device") {
                    LabeledContent("Model", value: run.deviceInfo.modelName)
                    LabeledContent("Chip", value: run.deviceInfo.chipName)
                    LabeledContent("RAM", value: ByteCountFormatter.string(fromByteCount: run.deviceInfo.totalMemoryBytes, countStyle: .memory))
                    LabeledContent("OS", value: run.deviceInfo.osVersion)
                }

                // Copy & Export actions
                Section("Copy & Export") {
                    // Copy to clipboard
                    ForEach(BenchmarkExportFormat.allCases) { format in
                        Button {
                            viewModel.copyToClipboard(run: run, format: format)
                        } label: {
                            Label("Copy as \(format.displayName)", systemImage: "doc.on.doc")
                        }
                    }

                    // Export files
                    if let url = jsonURL {
                        ShareLink(item: url) {
                            Label("Export JSON File", systemImage: "curlybraces")
                        }
                    }

                    if let url = csvURL {
                        ShareLink(item: url) {
                            Label("Export CSV File", systemImage: "tablecells")
                        }
                    }
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

                // Empty results
                if run.results.isEmpty {
                    Section {
                        VStack(spacing: AppSpacing.mediumLarge) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(AppTypography.system48)
                                .foregroundColor(AppColors.statusOrange.opacity(0.6))
                            Text("No results in this run")
                                .font(AppTypography.callout)
                                .foregroundColor(AppColors.textSecondary)
                            Text("This may happen if no downloaded models were available for the selected categories.")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.textTertiary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.xxLarge)
                    }
                }
            }

            // Copied toast overlay
            if let toast = viewModel.copiedToastMessage {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(AppTypography.subheadlineMedium)
                        .foregroundColor(.white)
                        .padding(.horizontal, AppSpacing.xxLarge)
                        .padding(.vertical, AppSpacing.mediumLarge)
                        .background(AppColors.statusGreen.opacity(0.9))
                        .cornerRadius(AppSpacing.cornerRadiusLarge)
                        .shadow(color: AppColors.shadowLight, radius: AppSpacing.shadowSmall)
                        .padding(.bottom, AppSpacing.xxLarge)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.easeInOut(duration: 0.3), value: toast)
                }
            }
        }
        .navigationTitle("Benchmark Details")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            jsonURL = viewModel.shareJSON(run: run)
            csvURL = viewModel.shareCSV(run: run)
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

