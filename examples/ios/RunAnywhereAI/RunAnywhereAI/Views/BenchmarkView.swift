import SwiftUI
import Charts

struct BenchmarkView: View {
    @StateObject private var benchmarkService = BenchmarkService()
    @StateObject private var modelManager = ModelManager.shared
    @State private var selectedModels: Set<String> = []
    @State private var showingResults = false
    @State private var selectedMetric: BenchmarkService.BenchmarkMetric = .tokensPerSecond
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if benchmarkService.isRunning {
                    runningView
                } else if !benchmarkService.benchmarkResults.isEmpty {
                    resultsView
                } else {
                    setupView
                }
            }
            .navigationTitle("Benchmark")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !benchmarkService.benchmarkResults.isEmpty {
                        Button("Export") {
                            benchmarkService.saveResults()
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Setup View
    
    private var setupView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Framework Selection
                VStack(alignment: .leading, spacing: 10) {
                    Text("Select Frameworks")
                        .font(.headline)
                    
                    ForEach(LLMFramework.allCases, id: \.self) { framework in
                        HStack {
                            Image(systemName: benchmarkService.selectedFrameworks.contains(framework) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(.accentColor)
                            Text(framework.rawValue)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if benchmarkService.selectedFrameworks.contains(framework) {
                                benchmarkService.selectedFrameworks.remove(framework)
                            } else {
                                benchmarkService.selectedFrameworks.insert(framework)
                            }
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(10)
                
                // Model Selection
                VStack(alignment: .leading, spacing: 10) {
                    Text("Select Models")
                        .font(.headline)
                    
                    if modelManager.downloadedModels.isEmpty {
                        Text("No models downloaded. Please download models first.")
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        ForEach(modelManager.downloadedModels) { model in
                            HStack {
                                Image(systemName: selectedModels.contains(model.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(.accentColor)
                                VStack(alignment: .leading) {
                                    Text(model.name)
                                    Text("\(model.framework.rawValue) • \(model.size)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedModels.contains(model.id) {
                                    selectedModels.remove(model.id)
                                } else {
                                    selectedModels.insert(model.id)
                                }
                            }
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(10)
                
                // Prompt Categories
                VStack(alignment: .leading, spacing: 10) {
                    Text("Prompt Categories")
                        .font(.headline)
                    
                    ForEach(["short", "medium", "long"], id: \.self) { category in
                        HStack {
                            Image(systemName: benchmarkService.selectedPromptCategories.contains(category) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(.accentColor)
                            Text(category.capitalized)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if benchmarkService.selectedPromptCategories.contains(category) {
                                benchmarkService.selectedPromptCategories.remove(category)
                            } else {
                                benchmarkService.selectedPromptCategories.insert(category)
                            }
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(10)
                
                // Run Button
                Button(action: runBenchmark) {
                    HStack {
                        Image(systemName: "speedometer")
                        Text("Run Benchmark")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(selectedModels.isEmpty || benchmarkService.selectedFrameworks.isEmpty)
            }
            .padding()
        }
    }
    
    // MARK: - Running View
    
    private var runningView: some View {
        VStack(spacing: 30) {
            ProgressView(value: benchmarkService.currentProgress) {
                Text("Running Benchmark...")
                    .font(.headline)
            }
            .progressViewStyle(LinearProgressViewStyle())
            
            Text(benchmarkService.currentStatus)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Text("\(Int(benchmarkService.currentProgress * 100))%")
                .font(.largeTitle)
                .bold()
        }
        .padding(40)
    }
    
    // MARK: - Results View
    
    private var resultsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Metric Selector
                Picker("Metric", selection: $selectedMetric) {
                    ForEach([BenchmarkService.BenchmarkMetric.tokensPerSecond,
                            .timeToFirstToken,
                            .memoryUsage,
                            .successRate], id: \.self) { metric in
                        Text(metric.name).tag(metric)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                
                // Chart
                if #available(iOS 16.0, *) {
                    chartView
                        .frame(height: 300)
                        .padding()
                }
                
                // Detailed Results
                ForEach(benchmarkService.benchmarkResults) { benchmark in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(benchmark.framework.rawValue)
                                .font(.headline)
                            Spacer()
                            Text("\(Int(benchmark.successRate * 100))% Success")
                                .font(.caption)
                                .foregroundColor(benchmark.successRate > 0.8 ? .green : .orange)
                        }
                        
                        HStack(spacing: 20) {
                            VStack(alignment: .leading) {
                                Text("Avg Tokens/s")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(String(format: "%.1f", benchmark.averageTokensPerSecond))
                                    .font(.title3)
                                    .bold()
                            }
                            
                            VStack(alignment: .leading) {
                                Text("Time to 1st Token")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(String(format: "%.3fs", benchmark.averageTimeToFirstToken))
                                    .font(.title3)
                                    .bold()
                            }
                            
                            VStack(alignment: .leading) {
                                Text("Avg Memory")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(String(format: "%.0f MB", benchmark.averageMemoryMB))
                                    .font(.title3)
                                    .bold()
                            }
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(10)
                }
                
                // New Benchmark Button
                Button(action: {
                    benchmarkService.benchmarkResults = []
                    selectedModels = []
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Run New Benchmark")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
            .padding()
        }
    }
    
    // MARK: - Chart View
    
    @available(iOS 16.0, *)
    private var chartView: some View {
        Chart {
            ForEach(benchmarkService.getTopPerformers(metric: selectedMetric), id: \.framework) { item in
                BarMark(
                    x: .value("Framework", item.framework.rawValue),
                    y: .value(selectedMetric.name, item.value)
                )
                .foregroundStyle(by: .value("Framework", item.framework.rawValue))
                .annotation(position: .top) {
                    Text(formatValue(item.value, metric: selectedMetric))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(.caption)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let doubleValue = value.as(Double.self) {
                        Text(formatValue(doubleValue, metric: selectedMetric))
                            .font(.caption)
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func runBenchmark() {
        let models = modelManager.downloadedModels.filter { selectedModels.contains($0.id) }
        
        Task {
            await benchmarkService.runBenchmark(models: models)
        }
    }
    
    private func formatValue(_ value: Double, metric: BenchmarkService.BenchmarkMetric) -> String {
        switch metric {
        case .tokensPerSecond:
            return String(format: "%.1f", value)
        case .timeToFirstToken:
            return String(format: "%.3f", value)
        case .memoryUsage:
            return String(format: "%.0f", value)
        case .successRate:
            return String(format: "%.0f%%", value * 100)
        }
    }
}

// MARK: - Preview

struct BenchmarkView_Previews: PreviewProvider {
    static var previews: some View {
        BenchmarkView()
    }
}
