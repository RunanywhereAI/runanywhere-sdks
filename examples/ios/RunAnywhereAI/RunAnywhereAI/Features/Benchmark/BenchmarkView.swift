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
    @ObservedObject private var launchHandler = BenchmarkLaunchHandler.shared
    @State private var hasAutoStarted = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.large) {
                    // Auto-launch banner
                    if launchHandler.shouldAutoStart && !hasAutoStarted {
                        autoBenchmarkBanner
                    }
                    
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
                
                // Auto-start benchmark if launched from CLI
                if launchHandler.shouldAutoStart && !hasAutoStarted {
                    await autoStartBenchmark()
                }
            }
        }
    }
    
    // MARK: - Auto Benchmark Banner
    
    private var autoBenchmarkBanner: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "terminal")
                    .foregroundStyle(.blue)
                Text("CLI Auto-Benchmark Mode")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                if !launchHandler.isDownloadingModel {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            // Show download progress if downloading
            if launchHandler.isDownloadingModel {
                VStack(spacing: 4) {
                    HStack {
                        Text("Downloading: \(launchHandler.pendingModelName ?? "Model")")
                            .font(.caption2)
                        Spacer()
                        Text("\(Int(launchHandler.downloadProgress * 100))%")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    ProgressView(value: launchHandler.downloadProgress)
                        .progressViewStyle(.linear)
                }
            }
            
            // Show error if any
            if let error = launchHandler.downloadError {
                Text("Error: \(error)")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Auto Start
    
    private func autoStartBenchmark() async {
        guard !hasAutoStarted else { return }
        hasAutoStarted = true
        
        print("🚀 Auto-starting benchmark...")
        
        // If a model URL was provided, download it first
        if launchHandler.pendingModelURL != nil {
            print("📥 Model URL provided, downloading first...")
            
            if let downloadedModelId = await launchHandler.downloadAndBenchmarkModel() {
                print("✅ Model downloaded: \(downloadedModelId)")
                
                // Wait for model list to refresh
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                availableModels = await viewModel.availableLLMModels
                
                // Select the downloaded model
                viewModel.selectedModelIds.insert(downloadedModelId)
            } else {
                print("❌ Model download failed")
                return
            }
        } else {
            // Wait for models to load
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            // Refresh models
            availableModels = await viewModel.availableLLMModels
            
            // Select models
            if let modelIds = launchHandler.autoModelIds {
                // Select specified models
                for modelId in modelIds {
                    if let model = availableModels.first(where: { $0.id.contains(modelId) || $0.name.lowercased().contains(modelId.lowercased()) }) {
                        viewModel.selectedModelIds.insert(model.id)
                    }
                }
            } else {
                // Select all downloaded models
                viewModel.selectAllModels(availableModels)
            }
        }
        
        // Apply CLI config if provided
        if let config = launchHandler.autoConfig {
            // Map config to UI selection
            if config.testIterations <= 3 {
                viewModel.selectedConfig = .quick
            } else if config.testIterations >= 10 {
                viewModel.selectedConfig = .comprehensive
            } else {
                viewModel.selectedConfig = .default
            }
        } else {
            viewModel.selectedConfig = .quick // Default to quick for auto
        }
        
        print("📊 Selected \(viewModel.selectedModelIds.count) models for benchmark")
        
        // Start benchmark if we have models
        if viewModel.canStartBenchmark {
            print("▶️ Starting benchmark now...")
            await viewModel.startBenchmark()
        } else {
            print("⚠️ Cannot start: no models selected or available")
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
    
    @State private var showCopiedToast = false
    @State private var showShareSheet = false
    
    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack {
                Text("Results")
                    .font(.headline)
                
                Spacer()
                
                // Export buttons
                Button(action: copyResultsToClipboard) {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button(action: { showShareSheet = true }) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            // Copied toast
            if showCopiedToast {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Results copied to clipboard!")
                        .font(.caption)
                }
                .padding(8)
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .transition(.opacity)
            }
            
            ForEach(viewModel.results) { result in
                BenchmarkResultCard(result: result, viewModel: viewModel)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [getResultsJSON()])
        }
    }
    
    private func copyResultsToClipboard() {
        let json = getResultsJSON()
        #if os(iOS)
        UIPasteboard.general.string = json
        #endif
        
        withAnimation {
            showCopiedToast = true
        }
        
        // Hide toast after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopiedToast = false
            }
        }
    }
    
    private func getResultsJSON() -> String {
        let export = BenchmarkExport(results: viewModel.results)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        if let data = try? encoder.encode(export),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        
        return "{ \"error\": \"Failed to encode results\" }"
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

// MARK: - Share Sheet

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

#Preview {
    BenchmarkView()
}
