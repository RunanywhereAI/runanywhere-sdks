import SwiftUI
import RunAnywhereSDK

struct PerformanceView: View {
    @State private var performanceMetrics: LiveMetrics?
    @State private var isMonitoring = false

    private let sdk = RunAnywhereSDK.shared

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    monitoringToggle
                    metricsSection
                    refreshButton
                }
                .padding()
            }
            .navigationTitle("Performance")
            .onAppear {
                Task {
                    await refreshMetrics()
                }
            }
        }
    }

    private var monitoringToggle: some View {
        Toggle("Enable Performance Monitoring", isOn: $isMonitoring)
            .padding()
            .onChange(of: isMonitoring) { _, newValue in
                if newValue {
                    sdk.performanceMonitor.startMonitoring()
                } else {
                    sdk.performanceMonitor.stopMonitoring()
                }
            }
    }

    private var metricsSection: some View {
        Group {
            if let metrics = performanceMetrics {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Performance Metrics")
                        .font(.headline)

                    PerformanceMetricRow(label: "CPU Usage", value: "\(Int(metrics.cpuUsage * 100))%")
                    PerformanceMetricRow(label: "Memory Usage", value: formatBytes(metrics.memoryUsage))
                    PerformanceMetricRow(label: "Available Memory", value: formatBytes(metrics.availableMemory))
                    PerformanceMetricRow(label: "Thermal State", value: "\(metrics.thermalState)")

                    if metrics.timeToFirstToken > 0 {
                        PerformanceMetricRow(label: "Time to First Token", value: String(format: "%.2f ms", metrics.timeToFirstToken * 1000))
                    }

                    if metrics.currentTokensPerSecond > 0 {
                        PerformanceMetricRow(label: "Tokens/sec", value: String(format: "%.1f", metrics.currentTokensPerSecond))
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
            }
        }
    }

    private var refreshButton: some View {
        Button(action: {
            Task {
                await refreshMetrics()
            }
        }) {
            Text("Refresh Metrics")
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
        }
    }

    private func refreshMetrics() async {
        performanceMetrics = sdk.performanceMonitor.currentMetrics
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}

struct PerformanceMetricRow: View {
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
