//
//  ComparisonView.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/27/25.
//

import SwiftUI

struct ComparisonView: View {
    @StateObject private var viewModel = ComparisonViewModel()
    @State private var prompt = ""
    @State private var showingSettings = false
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Framework selectors
                frameworkSelectors
                
                // Tab selector
                Picker("View Mode", selection: $selectedTab) {
                    Text("Side by Side").tag(0)
                    Text("Performance").tag(1)
                    Text("Metrics").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Content based on selected tab
                Group {
                    switch selectedTab {
                    case 0:
                        sideBySideView
                    case 1:
                        performanceView
                    case 2:
                        metricsView
                    default:
                        EmptyView()
                    }
                }
                
                // Input area
                inputArea
            }
            .navigationTitle("Framework Comparison")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                ComparisonSettingsView(settings: $viewModel.settings)
            }
        }
    }
    
    // MARK: - Subviews
    
    private var frameworkSelectors: some View {
        HStack(spacing: 16) {
            // Framework A selector
            VStack(alignment: .leading, spacing: 4) {
                Text("Framework A")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Menu {
                    ForEach(LLMFramework.allCases, id: \.self) { framework in
                        Button(framework.displayName) {
                            viewModel.frameworkA = framework
                        }
                    }
                } label: {
                    HStack {
                        Text(viewModel.frameworkA.displayName)
                            .font(.headline)
                        Image(systemName: "chevron.down")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            
            Image(systemName: "arrow.left.arrow.right")
                .font(.title2)
                .foregroundColor(.secondary)
            
            // Framework B selector
            VStack(alignment: .leading, spacing: 4) {
                Text("Framework B")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Menu {
                    ForEach(LLMFramework.allCases, id: \.self) { framework in
                        Button(framework.displayName) {
                            viewModel.frameworkB = framework
                        }
                    }
                } label: {
                    HStack {
                        Text(viewModel.frameworkB.displayName)
                            .font(.headline)
                        Image(systemName: "chevron.down")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }
    
    private var sideBySideView: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Framework A output
                outputView(
                    framework: viewModel.frameworkA,
                    output: viewModel.outputA,
                    isGenerating: viewModel.isGeneratingA,
                    metrics: viewModel.metricsA,
                    color: .blue
                )
                .frame(width: geometry.size.width / 2)
                
                Divider()
                
                // Framework B output
                outputView(
                    framework: viewModel.frameworkB,
                    output: viewModel.outputB,
                    isGenerating: viewModel.isGeneratingB,
                    metrics: viewModel.metricsB,
                    color: .green
                )
                .frame(width: geometry.size.width / 2)
            }
        }
    }
    
    private func outputView(
        framework: LLMFramework,
        output: String,
        isGenerating: Bool,
        metrics: ComparisonMetrics?,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with metrics
            HStack {
                Text(framework.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if let metrics = metrics {
                    HStack(spacing: 4) {
                        Image(systemName: "speedometer")
                            .font(.caption2)
                        Text("\(String(format: "%.1f", metrics.tokensPerSecond)) t/s")
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(color.opacity(0.1))
            
            // Output content
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if !output.isEmpty {
                        Text(output)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    } else if !isGenerating {
                        Text("Ready to generate...")
                            .foregroundColor(.secondary)
                            .italic()
                    }
                    
                    if isGenerating {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Generating...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
            }
            
            // Footer with stats
            if let metrics = metrics {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("\(metrics.tokenCount) tokens", systemImage: "number")
                        Spacer()
                        Label("\(String(format: "%.2fs", metrics.totalTime))", systemImage: "clock")
                    }
                    
                    HStack {
                        Label("\(String(format: "%.3fs", metrics.timeToFirstToken)) TTFT", systemImage: "timer")
                        Spacer()
                        Label("\(ByteCountFormatter.string(fromByteCount: Int64(metrics.memoryUsed), countStyle: .memory))", systemImage: "memorychip")
                    }
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemBackground))
            }
        }
        .background(Color(.systemBackground))
    }
    
    private var performanceView: some View {
        VStack(spacing: 16) {
            // Real-time performance charts
            PerformanceComparisonChart(
                dataA: viewModel.performanceDataA,
                dataB: viewModel.performanceDataB,
                frameworkA: viewModel.frameworkA,
                frameworkB: viewModel.frameworkB
            )
            .frame(height: 200)
            .padding()
            
            // Performance summary
            HStack(spacing: 20) {
                performanceSummaryCard(
                    framework: viewModel.frameworkA,
                    metrics: viewModel.metricsA,
                    color: .blue
                )
                
                performanceSummaryCard(
                    framework: viewModel.frameworkB,
                    metrics: viewModel.metricsB,
                    color: .green
                )
            }
            .padding()
            
            Spacer()
        }
    }
    
    private func performanceSummaryCard(
        framework: LLMFramework,
        metrics: ComparisonMetrics?,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(framework.displayName)
                .font(.headline)
                .foregroundColor(color)
            
            if let metrics = metrics {
                VStack(alignment: .leading, spacing: 8) {
                    statRow("Speed", value: "\(String(format: "%.1f", metrics.tokensPerSecond)) t/s")
                    statRow("TTFT", value: "\(String(format: "%.3f", metrics.timeToFirstToken))s")
                    statRow("Memory", value: ByteCountFormatter.string(fromByteCount: Int64(metrics.memoryUsed), countStyle: .memory))
                    statRow("Total Time", value: "\(String(format: "%.2f", metrics.totalTime))s")
                }
            } else {
                Text("No data yet")
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.caption)
    }
    
    private var metricsView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Detailed metrics comparison
                if let metricsA = viewModel.metricsA,
                   let metricsB = viewModel.metricsB {
                    
                    MetricsComparisonTable(
                        frameworkA: viewModel.frameworkA,
                        frameworkB: viewModel.frameworkB,
                        metricsA: metricsA,
                        metricsB: metricsB
                    )
                    
                    // Winner summary
                    if let winner = viewModel.determineWinner() {
                        VStack(spacing: 8) {
                            Image(systemName: "trophy.fill")
                                .font(.largeTitle)
                                .foregroundColor(.yellow)
                            
                            Text("\(winner.displayName) performs better")
                                .font(.headline)
                            
                            Text("Based on speed and efficiency metrics")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                } else {
                    Text("Run a comparison to see metrics")
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
            .padding()
        }
    }
    
    private var inputArea: some View {
        VStack(spacing: 12) {
            // Prompt input
            HStack {
                TextField("Enter prompt...", text: $prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(8)
                
                Button(action: runComparison) {
                    Image(systemName: "play.fill")
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(viewModel.isGenerating ? Color.gray : Color.accentColor)
                        .cornerRadius(22)
                }
                .disabled(prompt.isEmpty || viewModel.isGenerating)
            }
            
            // Quick prompts
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.quickPrompts, id: \.self) { quickPrompt in
                        Button(action: {
                            prompt = quickPrompt
                            runComparison()
                        }) {
                            Text(quickPrompt)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(.tertiarySystemBackground))
                                .cornerRadius(16)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }
    
    // MARK: - Actions
    
    private func runComparison() {
        guard !prompt.isEmpty else { return }
        
        Task {
            await viewModel.runComparison(prompt: prompt)
        }
    }
}

// MARK: - Performance Chart

struct PerformanceComparisonChart: View {
    let dataA: [Double]
    let dataB: [Double]
    let frameworkA: LLMFramework
    let frameworkB: LLMFramework
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.tertiarySystemBackground))
                
                // Chart
                VStack {
                    HStack {
                        Text("Tokens/Second")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        HStack(spacing: 16) {
                            Label(frameworkA.displayName, systemImage: "circle.fill")
                                .font(.caption)
                                .foregroundColor(.blue)
                            Label(frameworkB.displayName, systemImage: "circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                    .padding()
                    
                    // Line chart
                    Canvas { context, size in
                        drawChart(
                            context: context,
                            size: size,
                            dataA: dataA,
                            dataB: dataB
                        )
                    }
                    .padding()
                }
            }
        }
    }
    
    private func drawChart(context: GraphicsContext, size: CGSize, dataA: [Double], dataB: [Double]) {
        guard !dataA.isEmpty || !dataB.isEmpty else { return }
        
        let maxValue = max(dataA.max() ?? 0, dataB.max() ?? 0, 1)
        let xStep = size.width / CGFloat(max(dataA.count, dataB.count, 1) - 1)
        
        // Draw grid lines
        for i in 0...4 {
            let y = size.height * CGFloat(i) / 4
            context.stroke(
                Path { path in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                },
                with: .color(.secondary.opacity(0.2))
            )
        }
        
        // Draw data lines
        if !dataA.isEmpty {
            drawLine(context: context, size: size, data: dataA, maxValue: maxValue, color: .blue)
        }
        
        if !dataB.isEmpty {
            drawLine(context: context, size: size, data: dataB, maxValue: maxValue, color: .green)
        }
    }
    
    private func drawLine(context: GraphicsContext, size: CGSize, data: [Double], maxValue: Double, color: Color) {
        var path = Path()
        
        for (index, value) in data.enumerated() {
            let x = CGFloat(index) * size.width / CGFloat(data.count - 1)
            let y = size.height - (CGFloat(value / maxValue) * size.height)
            
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        
        context.stroke(path, with: .color(color), lineWidth: 2)
    }
}

// MARK: - Metrics Table

struct MetricsComparisonTable: View {
    let frameworkA: LLMFramework
    let frameworkB: LLMFramework
    let metricsA: ComparisonMetrics
    let metricsB: ComparisonMetrics
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Metric")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(frameworkA.displayName)
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.blue)
                Text(frameworkB.displayName)
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.green)
            }
            .font(.caption)
            .fontWeight(.semibold)
            .padding()
            .background(Color(.secondarySystemBackground))
            
            Divider()
            
            // Rows
            metricRow("Tokens/Second", 
                     valueA: String(format: "%.1f", metricsA.tokensPerSecond),
                     valueB: String(format: "%.1f", metricsB.tokensPerSecond),
                     higherIsBetter: true)
            
            metricRow("Time to First Token",
                     valueA: String(format: "%.3fs", metricsA.timeToFirstToken),
                     valueB: String(format: "%.3fs", metricsB.timeToFirstToken),
                     higherIsBetter: false)
            
            metricRow("Memory Usage",
                     valueA: ByteCountFormatter.string(fromByteCount: Int64(metricsA.memoryUsed), countStyle: .memory),
                     valueB: ByteCountFormatter.string(fromByteCount: Int64(metricsB.memoryUsed), countStyle: .memory),
                     higherIsBetter: false)
            
            metricRow("Total Time",
                     valueA: String(format: "%.2fs", metricsA.totalTime),
                     valueB: String(format: "%.2fs", metricsB.totalTime),
                     higherIsBetter: false)
            
            metricRow("Token Count",
                     valueA: "\(metricsA.tokenCount)",
                     valueB: "\(metricsB.tokenCount)",
                     higherIsBetter: nil)
        }
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separator), lineWidth: 1)
        )
    }
    
    private func metricRow(_ label: String, valueA: String, valueB: String, higherIsBetter: Bool?) -> some View {
        HStack {
            Text(label)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Text(valueA)
                .frame(maxWidth: .infinity)
                .fontWeight(isBetter(valueA: valueA, valueB: valueB, higherIsBetter: higherIsBetter) ? .semibold : .regular)
                .foregroundColor(isBetter(valueA: valueA, valueB: valueB, higherIsBetter: higherIsBetter) ? .blue : .primary)
            
            Text(valueB)
                .frame(maxWidth: .infinity)
                .fontWeight(isBetter(valueA: valueB, valueB: valueA, higherIsBetter: higherIsBetter) ? .semibold : .regular)
                .foregroundColor(isBetter(valueA: valueB, valueB: valueA, higherIsBetter: higherIsBetter) ? .green : .primary)
        }
        .font(.caption)
        .padding()
        .background(Color(.systemBackground))
    }
    
    private func isBetter(valueA: String, valueB: String, higherIsBetter: Bool?) -> Bool {
        guard let higherIsBetter = higherIsBetter else { return false }
        
        // Extract numeric values for comparison
        let numA = Double(valueA.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 0
        let numB = Double(valueB.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 0
        
        return higherIsBetter ? numA > numB : numA < numB
    }
}

// MARK: - Settings View

struct ComparisonSettingsView: View {
    @Binding var settings: ComparisonSettings
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("Generation") {
                    Stepper("Max Tokens: \(settings.maxTokens)", value: $settings.maxTokens, in: 50...500, step: 50)
                    
                    VStack(alignment: .leading) {
                        Text("Temperature: \(String(format: "%.2f", settings.temperature))")
                        Slider(value: $settings.temperature, in: 0...2, step: 0.1)
                    }
                }
                
                Section("Comparison") {
                    Toggle("Synchronize Start", isOn: $settings.synchronizeStart)
                    Toggle("Show Real-time Metrics", isOn: $settings.showRealtimeMetrics)
                    Toggle("Auto-run Benchmarks", isOn: $settings.autoRunBenchmarks)
                }
            }
            .navigationTitle("Comparison Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}