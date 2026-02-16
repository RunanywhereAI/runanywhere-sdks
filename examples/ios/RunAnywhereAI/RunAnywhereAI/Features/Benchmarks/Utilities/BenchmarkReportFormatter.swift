//
//  BenchmarkReportFormatter.swift
//  RunAnywhereAI
//
//  Formats benchmark runs as Markdown, JSON, or CSV for export.
//

import Foundation

enum BenchmarkReportFormatter {

    // MARK: - Markdown

    static func formatMarkdown(run: BenchmarkRun) -> String {
        var lines: [String] = []
        lines.append("# Benchmark Report")
        lines.append("")
        lines.append("**Device:** \(run.deviceInfo.modelName)")
        lines.append("**Chip:** \(run.deviceInfo.chipName)")
        lines.append("**RAM:** \(ByteCountFormatter.string(fromByteCount: run.deviceInfo.totalMemoryBytes, countStyle: .memory))")
        lines.append("**OS:** \(run.deviceInfo.osVersion)")
        lines.append("**Date:** \(run.startedAt.formatted())")
        if let duration = run.duration {
            lines.append("**Duration:** \(String(format: "%.1f", duration))s")
        }
        lines.append("**Status:** \(run.status.rawValue)")
        lines.append("")

        let grouped = Dictionary(grouping: run.results, by: { $0.category })
        for category in BenchmarkCategory.allCases {
            guard let results = grouped[category], !results.isEmpty else { continue }
            lines.append("## \(category.displayName)")
            lines.append("")
            for result in results {
                let m = result.metrics
                lines.append("### \(result.scenario.name) — \(result.modelInfo.name)")
                if !m.didSucceed {
                    lines.append("- **Error:** \(m.errorMessage ?? "Unknown")")
                } else {
                    lines.append("- Load: \(String(format: "%.0f", m.loadTimeMs))ms")
                    if let warmup = m.warmupTimeMs as Double?, warmup > 0 {
                        lines.append("- Warmup: \(String(format: "%.0f", warmup))ms")
                    }
                    lines.append("- End-to-end: \(String(format: "%.0f", m.endToEndLatencyMs))ms")
                    if let tps = m.tokensPerSecond { lines.append("- Tokens/s: \(String(format: "%.1f", tps))") }
                    if let ttft = m.ttftMs { lines.append("- TTFT: \(String(format: "%.0f", ttft))ms") }
                    if let rtf = m.realTimeFactor { lines.append("- RTF: \(String(format: "%.2f", rtf))x") }
                    if let genMs = m.generationTimeMs { lines.append("- Gen time: \(String(format: "%.0f", genMs))ms") }
                    if m.memoryDeltaBytes != 0 {
                        lines.append("- Memory delta: \(ByteCountFormatter.string(fromByteCount: m.memoryDeltaBytes, countStyle: .memory))")
                    }
                }
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - JSON

    static func writeJSON(run: BenchmarkRun) -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = (try? encoder.encode(run)) ?? Data()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("benchmark_\(run.id.uuidString.prefix(8)).json")
        try? data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - CSV

    static func writeCSV(run: BenchmarkRun) -> URL {
        var csv = "Category,Scenario,Model,Framework,LoadMs,WarmupMs,E2EMs,TPS,TTFT,RTF,GenMs,MemDeltaBytes,Error\n"
        for r in run.results {
            let m = r.metrics
            let row = [
                r.category.displayName,
                r.scenario.name,
                r.modelInfo.name,
                r.modelInfo.framework,
                String(format: "%.0f", m.loadTimeMs),
                String(format: "%.0f", m.warmupTimeMs),
                String(format: "%.0f", m.endToEndLatencyMs),
                m.tokensPerSecond.map { String(format: "%.1f", $0) } ?? "",
                m.ttftMs.map { String(format: "%.0f", $0) } ?? "",
                m.realTimeFactor.map { String(format: "%.2f", $0) } ?? "",
                m.generationTimeMs.map { String(format: "%.0f", $0) } ?? "",
                String(m.memoryDeltaBytes),
                m.errorMessage ?? "",
            ]
            csv += row.map { $0.contains(",") ? "\"\($0)\"" : $0 }.joined(separator: ",") + "\n"
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("benchmark_\(run.id.uuidString.prefix(8)).csv")
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
