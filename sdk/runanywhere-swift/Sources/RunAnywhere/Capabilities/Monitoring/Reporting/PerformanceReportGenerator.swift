//
//  ReportGenerator.swift
//  RunAnywhere SDK
//
//  Generates performance reports
//

import Foundation

/// Generates performance reports
internal class ReportGenerator {
    private let logger = SDKLogger(category: "ReportGenerator")

    /// Generate a performance report for a time range
    func generateReport(
        timeRange: TimeInterval,
        snapshots: [PerformanceSnapshot],
        alerts: [PerformanceAlert]
    ) -> PerformanceReport {

        // Filter snapshots for the time range
        let cutoffTime = Date().timeIntervalSince1970 - timeRange
        let relevantSnapshots = snapshots.filter {
            $0.timestamp.timeIntervalSince1970 > cutoffTime
        }

        // Calculate statistics
        let stats = calculateStatistics(for: relevantSnapshots)

        // Count alerts in time range
        let alertCount = alerts.filter {
            $0.timestamp.timeIntervalSince1970 > cutoffTime
        }.count

        return PerformanceReport(
            timeRange: timeRange,
            averageMemoryUsage: stats.avgMemory,
            peakMemoryUsage: stats.peakMemory,
            averageCPUUsage: stats.avgCPU,
            peakCPUUsage: stats.peakCPU,
            alertCount: alertCount,
            snapshots: relevantSnapshots
        )
    }

    /// Export report as JSON
    func exportAsJSON(_ report: PerformanceReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }

    /// Export report as CSV
    func exportAsCSV(_ report: PerformanceReport) -> Data {
        var csv = "Timestamp,Memory Usage,CPU Usage,Framework\n"

        let formatter = ISO8601DateFormatter()

        for snapshot in report.snapshots {
            csv += "\(formatter.string(from: snapshot.timestamp)),"
            csv += "\(snapshot.memoryUsage),"
            csv += "\(String(format: "%.2f", snapshot.cpuUsage)),"
            csv += "\(snapshot.activeFramework?.rawValue ?? "none")\n"
        }

        return csv.data(using: .utf8) ?? Data()
    }

    /// Calculate statistics for snapshots
    private func calculateStatistics(for snapshots: [PerformanceSnapshot]) -> (
        avgMemory: Int64,
        peakMemory: Int64,
        avgCPU: Double,
        peakCPU: Double
    ) {
        guard !snapshots.isEmpty else {
            return (0, 0, 0, 0)
        }

        let memoryUsages = snapshots.map { $0.memoryUsage }
        let cpuUsages = snapshots.map { $0.cpuUsage }

        let avgMemory = memoryUsages.reduce(0, +) / Int64(memoryUsages.count)
        let peakMemory = memoryUsages.max() ?? 0
        let avgCPU = cpuUsages.reduce(0, +) / Double(cpuUsages.count)
        let peakCPU = cpuUsages.max() ?? 0

        return (avgMemory, peakMemory, avgCPU, peakCPU)
    }
}
