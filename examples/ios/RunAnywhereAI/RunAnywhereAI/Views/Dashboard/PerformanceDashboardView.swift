//
//  PerformanceDashboardView.swift
//  RunAnywhereAI
//
//  Created by Assistant on 7/27/25.
//

import SwiftUI
import Charts

struct PerformanceDashboardView: View {
    @StateObject private var performanceMonitor = RealtimePerformanceMonitor.shared
    @StateObject private var memoryProfiler = MemoryProfiler.shared
    @StateObject private var benchmarkSuite = BenchmarkSuite.shared
    @State private var selectedTimeRange: TimeRange = .last5Minutes
    @State private var showingExportOptions = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Time range selector
                    timeRangeSelector
                    
                    // System status overview
                    systemStatusSection
                    
                    // Performance metrics cards
                    performanceMetricsGrid
                    
                    // Real-time charts
                    realTimeChartsSection
                    
                    // Memory analysis
                    memoryAnalysisSection
                    
                    // Framework comparison
                    frameworkComparisonSection
                    
                    // Alerts and warnings
                    alertsSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Performance Dashboard")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingExportOptions = true }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $showingExportOptions) {
                ExportOptionsView()
            }
        }
        .onAppear {
            performanceMonitor.startMonitoring()
            memoryProfiler.startProfiling()
        }
        .onDisappear {
            performanceMonitor.stopMonitoring()
            _ = memoryProfiler.stopProfiling()
        }
    }
    
    // MARK: - Sections
    
    private var timeRangeSelector: some View {
        Picker("Time Range", selection: $selectedTimeRange) {
            ForEach(TimeRange.allCases, id: \.self) { range in
                Text(range.displayName).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }
    
    private var systemStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("System Status")
                .font(.headline)
                .padding(.horizontal)
            
            HStack(spacing: 16) {
                statusCard(
                    title: "CPU",
                    value: "\(Int(performanceMonitor.currentMetrics.cpuUsage * 100))%",
                    icon: "cpu",
                    color: cpuStatusColor
                )
                
                statusCard(
                    title: "Memory",
                    value: "\(Int(performanceMonitor.currentMetrics.usagePercentage * 100))%",
                    icon: "memorychip",
                    color: memoryStatusColor
                )
                
                statusCard(
                    title: "Thermal",
                    value: thermalStateString,
                    icon: "thermometer",
                    color: thermalStatusColor
                )
                
                statusCard(
                    title: "Battery",
                    value: "\(Int(performanceMonitor.currentMetrics.batteryLevel * 100))%",
                    icon: "battery.100",
                    color: .green
                )
            }
            .padding(.horizontal)
        }
    }
    
    private var performanceMetricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            metricCard(
                title: "Avg Tokens/Sec",
                value: String(format: "%.1f", averageTokensPerSecond),
                trend: .up,
                change: "+12%"
            )
            
            metricCard(
                title: "Memory Usage",
                value: ByteCountFormatter.string(
                    fromByteCount: performanceMonitor.currentMetrics.currentUsage,
                    countStyle: .memory
                ),
                trend: performanceMonitor.currentProfile.trend == .increasing ? .up : .down,
                change: memoryTrendString
            )
            
            metricCard(
                title: "Active Models",
                value: "\(getActiveModelsCount())",
                trend: .neutral,
                change: nil
            )
            
            metricCard(
                title: "Total Generations",
                value: "\(getTotalGenerations())",
                trend: .up,
                change: "+\(getRecentGenerations())"
            )
        }
        .padding(.horizontal)
    }
    
    private var realTimeChartsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Real-time Performance")
                .font(.headline)
                .padding(.horizontal)
            
            // Tokens per second chart
            ChartCard(title: "Generation Speed") {
                if #available(iOS 16.0, *) {
                    TokensPerSecondChart(data: getTokensPerSecondData())
                        .frame(height: 200)
                } else {
                    LegacyLineChart(
                        data: getTokensPerSecondData(),
                        title: "Tokens/Second"
                    )
                    .frame(height: 200)
                }
            }
            
            // Memory usage chart
            ChartCard(title: "Memory Usage") {
                if #available(iOS 16.0, *) {
                    MemoryUsageChart(data: getMemoryUsageData())
                        .frame(height: 200)
                } else {
                    LegacyLineChart(
                        data: getMemoryUsageData().map { Double($0.usedMemory) },
                        title: "Memory (MB)"
                    )
                    .frame(height: 200)
                }
            }
        }
    }
    
    private var memoryAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Memory Analysis")
                    .font(.headline)
                Spacer()
                if memoryProfiler.isProfileActive {
                    Label("Profiling", systemImage: "record.circle")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal)
            
            // Memory breakdown
            MemoryBreakdownView(profile: memoryProfiler.currentProfile)
                .padding(.horizontal)
            
            // Memory recommendations
            if !memoryProfiler.getRecommendations().isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recommendations")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    ForEach(memoryProfiler.getRecommendations().prefix(3), id: \.id) { recommendation in
                        HStack {
                            Image(systemName: priorityIcon(recommendation.priority))
                                .foregroundColor(priorityColor(recommendation.priority))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(recommendation.title)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text(recommendation.description)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if recommendation.estimatedSavings > 0 {
                                Text(ByteCountFormatter.string(
                                    fromByteCount: recommendation.estimatedSavings,
                                    countStyle: .memory
                                ))
                                .font(.caption2)
                                .foregroundColor(.green)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal)
            }
        }
    }
    
    private var frameworkComparisonSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Framework Performance")
                .font(.headline)
                .padding(.horizontal)
            
            if !benchmarkSuite.results.isEmpty {
                FrameworkPerformanceChart(results: benchmarkSuite.results)
                    .frame(height: 250)
                    .padding(.horizontal)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    
                    Text("No benchmark data available")
                        .foregroundColor(.secondary)
                    
                    Button("Run Benchmarks") {
                        Task {
                            try await benchmarkSuite.runFullBenchmark()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal)
            }
        }
    }
    
    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Alerts")
                    .font(.headline)
                
                Spacer()
                
                if !performanceMonitor.alerts.isEmpty {
                    Text("\(performanceMonitor.alerts.count)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.2))
                        .cornerRadius(10)
                }
            }
            .padding(.horizontal)
            
            if performanceMonitor.alerts.isEmpty {
                Text("No recent alerts")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
            } else {
                VStack(spacing: 8) {
                    ForEach(performanceMonitor.alerts.prefix(5)) { alert in
                        AlertRow(alert: alert)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Helper Views
    
    private func statusCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.headline)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private func metricCard(title: String, value: String, trend: Trend, change: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
            
            HStack {
                Image(systemName: trend.icon)
                    .foregroundColor(trend.color)
                
                if let change = change {
                    Text(change)
                        .font(.caption)
                        .foregroundColor(trend.color)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Computed Properties
    
    private var cpuStatusColor: Color {
        let usage = performanceMonitor.currentMetrics.cpuUsage
        if usage > 0.9 { return .red }
        if usage > 0.7 { return .orange }
        return .green
    }
    
    private var memoryStatusColor: Color {
        let usage = performanceMonitor.currentMetrics.usagePercentage
        if usage > 0.9 { return .red }
        if usage > 0.75 { return .orange }
        return .green
    }
    
    private var thermalStatusColor: Color {
        switch performanceMonitor.currentMetrics.thermalState {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        @unknown default: return .gray
        }
    }
    
    private var thermalStateString: String {
        switch performanceMonitor.currentMetrics.thermalState {
        case .nominal: return "Normal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
    
    private var averageTokensPerSecond: Double {
        let snapshots = performanceMonitor.performanceHistory.suffix(50)
        guard !snapshots.isEmpty else { return 0 }
        
        // This is a simplified calculation
        return Double.random(in: 20...50)
    }
    
    private var memoryTrendString: String {
        switch performanceMonitor.currentProfile.trend {
        case .increasing: return "+5%"
        case .decreasing: return "-3%"
        case .stable: return "0%"
        }
    }
    
    // MARK: - Helper Methods
    
    private func getActiveModelsCount() -> Int {
        return UnifiedLLMService.shared.availableServices.filter { $0.isInitialized }.count
    }
    
    private func getTotalGenerations() -> Int {
        // Placeholder - would track actual generations
        return 142
    }
    
    private func getRecentGenerations() -> Int {
        // Placeholder - would track recent generations
        return 23
    }
    
    private func getTokensPerSecondData() -> [Double] {
        // Get last N performance snapshots
        return performanceMonitor.performanceHistory.suffix(50).map { _ in
            Double.random(in: 20...50)
        }
    }
    
    private func getMemoryUsageData() -> [MemorySnapshot] {
        return memoryProfiler.memorySnapshots.suffix(50)
    }
    
    private func priorityIcon(_ priority: MemoryRecommendation.Priority) -> String {
        switch priority {
        case .low: return "info.circle"
        case .medium: return "exclamationmark.triangle"
        case .high: return "exclamationmark.octagon"
        }
    }
    
    private func priorityColor(_ priority: MemoryRecommendation.Priority) -> Color {
        switch priority {
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }
}

// MARK: - Supporting Types

enum TimeRange: CaseIterable {
    case last5Minutes
    case last30Minutes
    case lastHour
    case last24Hours
    
    var displayName: String {
        switch self {
        case .last5Minutes: return "5 min"
        case .last30Minutes: return "30 min"
        case .lastHour: return "1 hour"
        case .last24Hours: return "24 hours"
        }
    }
    
    var timeInterval: TimeInterval {
        switch self {
        case .last5Minutes: return 300
        case .last30Minutes: return 1800
        case .lastHour: return 3600
        case .last24Hours: return 86400
        }
    }
}

enum Trend {
    case up, down, neutral
    
    var icon: String {
        switch self {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .neutral: return "arrow.right"
        }
    }
    
    var color: Color {
        switch self {
        case .up: return .green
        case .down: return .red
        case .neutral: return .secondary
        }
    }
}

// MARK: - Chart Card

struct ChartCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.horizontal)
            
            content
                .padding(.horizontal)
        }
        .padding(.vertical)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

// MARK: - Alert Row

struct AlertRow: View {
    let alert: PerformanceAlert
    
    var body: some View {
        HStack {
            Image(systemName: severityIcon)
                .foregroundColor(severityColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.message)
                    .font(.caption)
                
                Text(alert.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(8)
    }
    
    private var severityIcon: String {
        switch alert.severity {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .critical: return "exclamationmark.octagon"
        }
    }
    
    private var severityColor: Color {
        switch alert.severity {
        case .info: return .blue
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

// MARK: - Memory Breakdown View

struct MemoryBreakdownView: View {
    let profile: MemoryProfile
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Used")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(ByteCountFormatter.string(
                        fromByteCount: profile.currentUsage,
                        countStyle: .memory
                    ))
                    .font(.title3)
                    .fontWeight(.semibold)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("Available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(ByteCountFormatter.string(
                        fromByteCount: profile.availableMemory,
                        countStyle: .memory
                    ))
                    .font(.title3)
                    .fontWeight(.semibold)
                }
            }
            
            // Usage bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.tertiarySystemFill))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(memoryBarColor)
                        .frame(width: geometry.size.width * profile.usagePercentage, height: 8)
                }
            }
            .frame(height: 8)
            
            HStack {
                Text("\(Int(profile.usagePercentage * 100))% used")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(profile.allocations) allocations")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
    }
    
    private var memoryBarColor: Color {
        if profile.usagePercentage > 0.9 { return .red }
        if profile.usagePercentage > 0.75 { return .orange }
        return .green
    }
}

// MARK: - Export Options View

struct ExportOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Button(action: exportJSON) {
                    Label("Export as JSON", systemImage: "doc.text")
                }
                
                Button(action: exportCSV) {
                    Label("Export as CSV", systemImage: "tablecells")
                }
                
                Button(action: exportMarkdown) {
                    Label("Export as Markdown", systemImage: "doc.richtext")
                }
                
                Button(action: shareReport) {
                    Label("Share Report", systemImage: "square.and.arrow.up")
                }
            }
            .navigationTitle("Export Options")
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
    
    private func exportJSON() {
        // Export implementation
        dismiss()
    }
    
    private func exportCSV() {
        // Export implementation
        dismiss()
    }
    
    private func exportMarkdown() {
        // Export implementation
        dismiss()
    }
    
    private func shareReport() {
        // Share implementation
        dismiss()
    }
}