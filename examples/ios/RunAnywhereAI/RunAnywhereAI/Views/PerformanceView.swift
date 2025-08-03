//
//  PerformanceView.swift
//  RunAnywhereAI
//
//  Example view showing SDK performance monitoring
//

import SwiftUI
import RunAnywhereSDK

struct PerformanceView: View {
    @State private var performanceMetrics: PerformanceMetrics?
    @State private var isMonitoring = false

    private let sdk = RunAnywhereSDK.shared

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Monitoring Toggle
                    Toggle("Enable Performance Monitoring", isOn: $isMonitoring)
                        .padding()
                        .onChange(of: isMonitoring) { _, newValue in
                            if newValue {
                                sdk.performanceMonitor.startMonitoring()
                            } else {
                                sdk.performanceMonitor.stopMonitoring()
                            }
                        }

                    // Performance Metrics
                    if let metrics = performanceMetrics {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Performance Metrics")
                                .font(.headline)

                            MetricRow(label: "CPU Usage", value: "\(Int(metrics.cpuUsage * 100))%")
                            MetricRow(label: "Memory Usage", value: formatBytes(metrics.memoryUsage))
                            MetricRow(label: "Active Models", value: "\(metrics.activeModelCount)")

                            if let latency = metrics.averageLatency {
                                MetricRow(label: "Avg Latency", value: String(format: "%.2f ms", latency * 1000))
                            }

                            if let tokensPerSecond = metrics.tokensPerSecond {
                                MetricRow(label: "Tokens/sec", value: String(format: "%.1f", tokensPerSecond))
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(10)
                    }

                    // Refresh Button
                    Button(action: {
                        Task {
                            await refreshMetrics()
                        }
                    }) {
                        Label("Refresh Metrics", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Performance Monitor")
            .task {
                await refreshMetrics()
            }
        }
    }

    private func refreshMetrics() async {
        performanceMetrics = sdk.performanceMonitor.getCurrentMetrics()
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}

struct MetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    PerformanceView()
}
