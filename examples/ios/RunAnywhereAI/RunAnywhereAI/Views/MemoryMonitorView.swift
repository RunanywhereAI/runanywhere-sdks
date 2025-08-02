//
//  MemoryMonitorView.swift
//  RunAnywhereAI
//

import SwiftUI
import Charts

struct MemoryMonitorView: View {
    @StateObject private var viewModel = MemoryMonitorViewModel()

    var body: some View {
        NavigationView {
            List {
                // Current Memory Stats
                Section("Current Memory Usage") {
                    VStack(alignment: .leading, spacing: 12) {
                        // Memory Pressure Indicator
                        MemoryPressureView(pressure: viewModel.memoryPressure)

                        // Memory Stats
                        MemoryStatRow(title: "Used", value: viewModel.formattedUsedMemory)
                        MemoryStatRow(title: "Available", value: viewModel.formattedAvailableMemory)
                        MemoryStatRow(title: "Total", value: viewModel.formattedTotalMemory)
                    }
                    .padding(.vertical, 8)
                }

                // Memory Usage Chart
                Section("Memory Usage Trend") {
                    if !viewModel.memoryHistory.isEmpty {
                        Chart(viewModel.memoryHistory) { point in
                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Usage %", point.usedPercentage)
                            )
                            .foregroundStyle(point.pressure.color)
                        }
                        .frame(height: 200)
                        .padding(.vertical)
                    } else {
                        Text("No data available")
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }
            }
            .navigationTitle("Memory Monitor")
            .onAppear {
                viewModel.startMonitoring()
            }
            .onDisappear {
                viewModel.stopMonitoring()
            }
        }
    }
}

// MARK: - Supporting Views

struct MemoryPressureView: View {
    let pressure: MemoryPressure

    var body: some View {
        HStack {
            Circle()
                .fill(pressure.color)
                .frame(width: 12, height: 12)
            Text(pressure.displayName)
                .font(.subheadline)
                .fontWeight(.medium)
            Spacer()
            Text(pressure.description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct MemoryStatRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

// MARK: - View Model

class MemoryMonitorViewModel: ObservableObject {
    @Published var usedMemory: Int64 = 0
    @Published var availableMemory: Int64 = 0
    @Published var totalMemory: Int64 = 0
    @Published var memoryPressure: MemoryPressure = .normal
    @Published var memoryHistory: [MemoryDataPoint] = []

    private var timer: Timer?

    var formattedUsedMemory: String {
        ByteCountFormatter.string(fromByteCount: usedMemory, countStyle: .memory)
    }

    var formattedAvailableMemory: String {
        ByteCountFormatter.string(fromByteCount: availableMemory, countStyle: .memory)
    }

    var formattedTotalMemory: String {
        ByteCountFormatter.string(fromByteCount: totalMemory, countStyle: .memory)
    }

    func startMonitoring() {
        updateMemoryStats()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.updateMemoryStats()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func updateMemoryStats() {
        totalMemory = Int64(ProcessInfo.processInfo.physicalMemory)

        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }

        if result == KERN_SUCCESS {
            usedMemory = Int64(info.resident_size)
            availableMemory = totalMemory - usedMemory

            let usageRatio = Double(usedMemory) / Double(totalMemory)

            // Update pressure
            if usageRatio > 0.9 {
                memoryPressure = .critical
            } else if usageRatio > 0.75 {
                memoryPressure = .warning
            } else {
                memoryPressure = .normal
            }

            // Add to history
            let dataPoint = MemoryDataPoint(
                timestamp: Date(),
                usedPercentage: usageRatio * 100,
                pressure: memoryPressure
            )
            memoryHistory.append(dataPoint)

            // Keep only last 60 points
            if memoryHistory.count > 60 {
                memoryHistory.removeFirst()
            }
        }
    }
}

// MARK: - Data Types

enum MemoryPressure {
    case normal
    case warning
    case critical

    var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }

    var description: String {
        switch self {
        case .normal: return "Memory usage is healthy"
        case .warning: return "Memory usage is high"
        case .critical: return "Memory critically low"
        }
    }

    var color: Color {
        switch self {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

struct MemoryDataPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let usedPercentage: Double
    let pressure: MemoryPressure
}

// MARK: - Preview

#Preview {
    MemoryMonitorView()
}
