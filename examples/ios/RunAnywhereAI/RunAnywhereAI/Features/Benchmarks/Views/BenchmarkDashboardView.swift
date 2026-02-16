//
//  BenchmarkDashboardView.swift
//  RunAnywhereAI
//
//  Main benchmarking screen: device info, category filters, run controls, and history.
//

import SwiftUI

struct BenchmarkDashboardView: View {
    @State private var viewModel = BenchmarkViewModel()
    @StateObject private var deviceService = DeviceInfoService.shared

    var body: some View {
        List {
            // Device Info Header
            if let info = deviceService.deviceInfo {
                Section("Device") {
                    LabeledContent("Model", value: info.modelName)
                    LabeledContent("Chip", value: info.chipName)
                    LabeledContent("RAM", value: ByteCountFormatter.string(fromByteCount: info.totalMemory, countStyle: .memory))
                    LabeledContent("Available", value: ByteCountFormatter.string(fromByteCount: SyntheticInputGenerator.availableMemoryBytes(), countStyle: .memory))
                }
            }

            // Category Selection
            Section("Categories") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.smallMedium) {
                        ForEach(BenchmarkCategory.allCases) { category in
                            CategoryChip(
                                category: category,
                                isSelected: viewModel.selectedCategories.contains(category)
                            ) {
                                if viewModel.selectedCategories.contains(category) {
                                    viewModel.selectedCategories.remove(category)
                                } else {
                                    viewModel.selectedCategories.insert(category)
                                }
                            }
                        }
                    }
                    .padding(.vertical, AppSpacing.xSmall)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: AppSpacing.large, bottom: 0, trailing: AppSpacing.large))
            }

            // Run Controls
            Section {
                Button {
                    viewModel.selectedCategories = Set(BenchmarkCategory.allCases)
                    viewModel.runBenchmarks()
                } label: {
                    Label("Run All Benchmarks", systemImage: "play.fill")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .disabled(viewModel.isRunning)

                if viewModel.selectedCategories.count < BenchmarkCategory.allCases.count {
                    Button {
                        viewModel.runBenchmarks()
                    } label: {
                        Label("Run Selected (\(viewModel.selectedCategories.count))", systemImage: "play")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .disabled(viewModel.isRunning || viewModel.selectedCategories.isEmpty)
                }
            }

            // Past Runs
            if !viewModel.pastRuns.isEmpty {
                Section("History") {
                    ForEach(viewModel.pastRuns) { run in
                        NavigationLink(destination: BenchmarkDetailView(run: run)) {
                            RunRow(run: run)
                        }
                    }
                }
            } else {
                Section {
                    VStack(spacing: AppSpacing.mediumLarge) {
                        Image(systemName: "gauge.with.dots.needle.33percent")
                            .font(AppTypography.system48)
                            .foregroundColor(AppColors.textSecondary.opacity(0.5))
                        Text("No benchmark results yet")
                            .font(AppTypography.callout)
                            .foregroundColor(AppColors.textSecondary)
                        Text("Run a benchmark to see performance data")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.xxLarge)
                }
            }
        }
        .navigationTitle("Benchmarks")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if !viewModel.pastRuns.isEmpty {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Clear All", role: .destructive) {
                        viewModel.showClearConfirmation = true
                    }
                }
            }
        }
        .alert("Clear All Results?", isPresented: $viewModel.showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                viewModel.clearAllResults()
            }
        } message: {
            Text("This will permanently delete all benchmark history.")
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
        .sheet(isPresented: $viewModel.isRunning) {
            BenchmarkProgressView(
                progress: viewModel.progress,
                currentScenario: viewModel.currentScenario,
                currentModel: viewModel.currentModel,
                completedCount: viewModel.completedCount,
                totalCount: viewModel.totalCount,
                onCancel: { viewModel.cancel() }
            )
            .interactiveDismissDisabled()
        }
        .task {
            viewModel.loadPastRuns()
        }
    }
}

// MARK: - Category Chip

private struct CategoryChip: View {
    let category: BenchmarkCategory
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Label(category.displayName, systemImage: category.iconName)
                .font(AppTypography.caption)
                .padding(.horizontal, AppSpacing.mediumLarge)
                .padding(.vertical, AppSpacing.smallMedium)
                .background(isSelected ? AppColors.primaryAccent.opacity(0.2) : AppColors.backgroundTertiary)
                .foregroundColor(isSelected ? AppColors.primaryAccent : AppColors.textSecondary)
                .cornerRadius(AppSpacing.cornerRadiusLarge)
                .overlay(
                    RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge)
                        .stroke(isSelected ? AppColors.primaryAccent.opacity(0.5) : Color.clear, lineWidth: AppSpacing.strokeRegular)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Run Row

private struct RunRow: View {
    let run: BenchmarkRun

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            HStack {
                Text(run.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(AppTypography.subheadlineMedium)
                Spacer()
                RunStatusBadge(status: run.status)
            }
            HStack(spacing: AppSpacing.mediumLarge) {
                if let duration = run.duration {
                    Label(String(format: "%.1fs", duration), systemImage: "clock")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                }
                Label("\(run.results.count) results", systemImage: "list.bullet")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)

                let successCount = run.results.filter { $0.metrics.didSucceed }.count
                if successCount < run.results.count {
                    Label("\(run.results.count - successCount) failed", systemImage: "exclamationmark.triangle")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.statusOrange)
                }
            }
        }
        .padding(.vertical, AppSpacing.xSmall)
    }
}

// MARK: - Run Status Badge

private struct RunStatusBadge: View {
    let status: BenchmarkRunStatus

    var body: some View {
        Text(status.rawValue.capitalized)
            .font(AppTypography.caption2Medium)
            .padding(.horizontal, AppSpacing.smallMedium)
            .padding(.vertical, AppSpacing.xxSmall)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(AppSpacing.cornerRadiusSmall)
    }

    private var color: Color {
        switch status {
        case .completed: return AppColors.statusGreen
        case .running: return AppColors.statusBlue
        case .cancelled: return AppColors.statusOrange
        case .failed: return AppColors.statusRed
        }
    }
}
