//
//  PerformanceDashboardView.swift
//  RunAnywhereAI
//
//  Simplified performance view
//

import SwiftUI
#if canImport(Charts)
import Charts
#endif

struct PerformanceDashboardView: View {
    @State private var tokensPerSecond: Double = 0
    @State private var memoryUsage: Double = 0
    @State private var isMonitoring = false
    @State private var performanceHistory: [PerformanceDataPoint] = []

    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Current Performance
                HStack(spacing: 16) {
                    MetricCard(
                        title: "Tokens/Sec",
                        value: String(format: "%.1f", tokensPerSecond),
                        icon: "speedometer",
                        color: .blue
                    )

                    MetricCard(
                        title: "Memory",
                        value: String(format: "%.0f%%", memoryUsage),
                        icon: "memorychip",
                        color: .green
                    )
                }
                .padding(.horizontal)

                // Performance Chart
                if !performanceHistory.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Performance History")
                            .font(.headline)
                            .padding(.horizontal)

                        #if canImport(Charts) && os(iOS)
                        if #available(iOS 16.0, *) {
                            Chart(performanceHistory) { point in
                                LineMark(
                                    x: .value("Time", point.timestamp),
                                    y: .value("Tokens/s", point.tokensPerSecond)
                                )
                                .foregroundStyle(.blue)
                            }
                            .frame(height: 200)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        } else {
                            Text("Charts require iOS 16+")
                                .frame(height: 200)
                                .frame(maxWidth: .infinity)
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                                .padding(.horizontal)
                        }
                        #else
                        Text("Charts not available")
                            .frame(height: 200)
                            .frame(maxWidth: .infinity)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        #endif
                    }
                }

                // Control Button
                Button(action: toggleMonitoring) {
                    HStack {
                        Image(systemName: isMonitoring ? "pause.circle.fill" : "play.circle.fill")
                        Text(isMonitoring ? "Stop Monitoring" : "Start Monitoring")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(isMonitoring ? Color.red : Color.blue)
                    .cornerRadius(10)
                }
                .padding()
            }
        }
        .navigationTitle("Performance")
        .navigationBarTitleDisplayMode(.large)
        .onReceive(timer) { _ in
            if isMonitoring {
                updateMetrics()
            }
        }
    }

    private func toggleMonitoring() {
        isMonitoring.toggle()
        if !isMonitoring {
            // Clear history when stopping
            performanceHistory.removeAll()
            tokensPerSecond = 0
            memoryUsage = 0
        }
    }

    private func updateMetrics() {
        // Simulate performance data
        tokensPerSecond = Double.random(in: 10...50)
        memoryUsage = Double.random(in: 30...70)

        // Add to history
        let dataPoint = PerformanceDataPoint(
            timestamp: Date(),
            tokensPerSecond: tokensPerSecond,
            memoryUsage: memoryUsage
        )
        performanceHistory.append(dataPoint)

        // Keep only last 60 points (1 minute)
        if performanceHistory.count > 60 {
            performanceHistory.removeFirst()
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundColor(color)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct PerformanceDataPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let tokensPerSecond: Double
    let memoryUsage: Double
}

#Preview {
    NavigationView {
        PerformanceDashboardView()
    }
}
