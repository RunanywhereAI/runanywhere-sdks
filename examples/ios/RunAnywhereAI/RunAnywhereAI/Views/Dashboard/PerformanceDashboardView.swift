//
//  PerformanceDashboardView.swift
//  RunAnywhereAI
//
//  Simplified performance view using SDK directly
//

import SwiftUI
import Charts
import RunAnywhereSDK

struct PerformanceDashboardView: View {
    @State private var metrics: RunAnywhereSDK.PerformanceMetrics?
    @State private var memoryInfo: RunAnywhereSDK.MemoryReport?
    @State private var isMonitoring = false

    private let sdk = RunAnywhereSDK.shared
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Monitoring toggle
                    Toggle("Enable Monitoring", isOn: $isMonitoring)
                        .padding()
                        .onChange(of: isMonitoring) { _, newValue in
                            if newValue {
                                sdk.performanceMonitor.startMonitoring()
                                sdk.memoryProfiler.startProfiling()
                            } else {
                                sdk.performanceMonitor.stopMonitoring()
                                sdk.memoryProfiler.stopProfiling()
                            }
                        }

                    // Performance metrics
                    if let metrics = metrics {
                        performanceCard(metrics: metrics)
                    }

                    // Memory info
                    if let memory = memoryInfo {
                        memoryCard(memory: memory)
                    }

                    // Run benchmark button
                    Button("Run Benchmark") {
                        Task {
                            await runBenchmark()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle("Performance")
            .onReceive(timer) { _ in
                if isMonitoring {
                    updateMetrics()
                }
            }
        }
    }

    private func performanceCard(metrics: RunAnywhereSDK.PerformanceMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Performance Metrics")
                .font(.headline)

            HStack {
                Label("\(metrics.tokensPerSecond, specifier: "%.1f") tokens/s", systemImage: "speedometer")
                Spacer()
                Label("\(metrics.latency, specifier: "%.0f") ms", systemImage: "clock")
            }

            if metrics.cpuUsage > 0 {
                ProgressView(value: metrics.cpuUsage / 100)
                    .progressViewStyle(.linear)
                Text("CPU: \(metrics.cpuUsage, specifier: "%.0f")%")
                    .font(.caption)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    private func memoryCard(memory: RunAnywhereSDK.MemoryReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Memory Usage")
                .font(.headline)

            HStack {
                Label("\(memory.usedMemory / 1_000_000) MB", systemImage: "memorychip")
                Spacer()
                Text("\(memory.availableMemory / 1_000_000) MB free")
                    .foregroundColor(.secondary)
            }

            if memory.peakMemory > 0 {
                Text("Peak: \(memory.peakMemory / 1_000_000) MB")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    private func updateMetrics() {
        metrics = sdk.performanceMonitor.currentMetrics
        memoryInfo = sdk.memoryProfiler.generateReport()
    }

    private func runBenchmark() async {
        do {
            let results = try await sdk.benchmarkSuite.runBenchmark()
            // Handle benchmark results
            print("Benchmark completed: \(results)")
        } catch {
            print("Benchmark failed: \(error)")
        }
    }
}
