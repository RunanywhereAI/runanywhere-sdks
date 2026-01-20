//
//  BenchmarkView.swift
//  RunAnywhereAI
//
//  UI for running and viewing model benchmarks
//

import SwiftUI
import RunAnywhere

struct BenchmarkView: View {
    @State private var viewModel = BenchmarkViewModel()
    @State private var availableModels: [ModelInfo] = []
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.large) {
                    // Configuration Section
                    configurationSection
                    
                    // Model Selection Section
                    modelSelectionSection
                    
                    // Control Buttons
                    controlButtons
                    
                    // Progress Section
                    if viewModel.state.isRunning {
                        progressSection
                    }
                    
                    // Results Section
                    if !viewModel.results.isEmpty {
                        resultsSection
                    }
                    
                    // Error Section
                    if let error = viewModel.error {
                        errorSection(error)
                    }
                }
                .padding()
            }
            .navigationTitle("Benchmark")
            .task {
                availableModels = await viewModel.availableLLMModels
            }
        }
    }
    
    // MARK: - Configuration Section
    
    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("Configuration")
                .font(.headline)
            
            Picker("Test Configuration", selection: $viewModel.selectedConfig) {
                ForEach(BenchmarkViewModel.ConfigOption.allCases) { option in
                    VStack(alignment: .leading) {
                        Text(option.rawValue)
                    }
                    .tag(option)
                }
            }
            .pickerStyle(.segmented)
            
            Text(viewModel.selectedConfig.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Model Selection Section
    
    private var modelSelectionSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            HStack {
                Text("Models")
                    .font(.headline)
                
                Spacer()
                
                Button(viewModel.selectedModelIds.isEmpty ? "Select All" : "Deselect All") {
                    if viewModel.selectedModelIds.isEmpty {
                        viewModel.selectAllModels(availableModels)
                    } else {
                        viewModel.deselectAllModels()
                    }
                }
                .font(.caption)
            }
            
            if availableModels.isEmpty {
                Text("No downloaded LLM models found. Download a model first.")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ForEach(availableModels, id: \.id) { model in
                    ModelSelectionRow(
                        model: model,
                        isSelected: viewModel.selectedModelIds.contains(model.id),
                        onToggle: { viewModel.toggleModelSelection(model.id) }
                    )
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Control Buttons
    
    private var controlButtons: some View {
        HStack(spacing: AppSpacing.medium) {
            if viewModel.state.isRunning {
                Button(action: { viewModel.cancelBenchmark() }) {
                    Label("Cancel", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            } else {
                Button(action: {
                    Task { await viewModel.startBenchmark() }
                }) {
                    Label("Run Benchmark", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canStartBenchmark)
                
                if !viewModel.results.isEmpty {
                    Button(action: { viewModel.clearResults() }) {
                        Label("Clear", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
    
    // MARK: - Progress Section
    
    private var progressSection: some View {
        VStack(spacing: AppSpacing.medium) {
            if let progress = viewModel.progress {
                ProgressView(value: progress.overallProgress)
                    .progressViewStyle(.linear)
                
                HStack {
                    Text(stateDescription(viewModel.state))
                        .font(.caption)
                    
                    Spacer()
                    
                    Text(viewModel.formatProgress(progress.overallProgress))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Elapsed: \(viewModel.formatDuration(progress.elapsedTime))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    if let remaining = progress.estimatedRemainingTime {
                        Text("Remaining: ~\(viewModel.formatDuration(remaining))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Results Section
    
    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Text("Results")
                .font(.headline)
            
            ForEach(viewModel.results) { result in
                BenchmarkResultCard(result: result, viewModel: viewModel)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Error Section
    
    private func errorSection(_ error: Error) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.red)
            Text(error.localizedDescription)
                .font(.caption)
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Helpers
    
    private func stateDescription(_ state: BenchmarkState) -> String {
        switch state {
        case .idle:
            return "Ready"
        case .preparing:
            return "Preparing..."
        case .warmingUp(let model, let iteration, let total):
            return "Warming up \(model) (\(iteration)/\(total))"
        case .running(let model, let prompt, let iteration, let total):
            return "Testing \(model) - \(prompt) (\(iteration)/\(total))"
        case .completed:
            return "Completed"
        case .failed(let error):
            return "Failed: \(error)"
        }
    }
}

// MARK: - Model Selection Row

struct ModelSelectionRow: View {
    let model: ModelInfo
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    
                    Text(model.framework.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Benchmark Result Card

struct BenchmarkResultCard: View {
    let result: BenchmarkResult
    let viewModel: BenchmarkViewModel
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            // Header
            Button(action: { isExpanded.toggle() }) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.modelName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text(result.framework)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(viewModel.formatTokensPerSecond(result.avgTokensPerSecond))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.blue)
                        
                        Text("avg")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                Divider()
                
                // Detailed metrics
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: AppSpacing.small) {
                    MetricItem(
                        label: "TTFT (avg)",
                        value: viewModel.formatLatency(result.avgTtftMs)
                    )
                    MetricItem(
                        label: "Latency (avg)",
                        value: viewModel.formatLatency(result.avgLatencyMs)
                    )
                    MetricItem(
                        label: "P95 tok/s",
                        value: viewModel.formatTokensPerSecond(result.p95TokensPerSecond)
                    )
                    MetricItem(
                        label: "Load Time",
                        value: viewModel.formatLatency(result.modelLoadTimeMs)
                    )
                    MetricItem(
                        label: "Peak Memory",
                        value: viewModel.formatMemory(result.peakMemoryBytes)
                    )
                    MetricItem(
                        label: "Total Runs",
                        value: "\(result.totalRuns)"
                    )
                }
                
                // Per-prompt breakdown
                if !result.promptResults.isEmpty {
                    Divider()
                    
                    Text("Per-Prompt Results")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.top, 4)
                    
                    ForEach(result.promptResults) { promptResult in
                        HStack {
                            Text(promptResult.promptId)
                                .font(.caption2)
                            
                            Spacer()
                            
                            Text(viewModel.formatTokensPerSecond(promptResult.avgTokensPerSecond))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Metric Item

struct MetricItem: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    BenchmarkView()
}
