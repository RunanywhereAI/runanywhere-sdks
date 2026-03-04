//
//  BenchmarkReportFormatter.swift
//  RunAnywhereAI
//
//  Formats benchmark runs as Markdown, JSON, or CSV for export.
//

import Foundation

// MARK: - Export Format

enum BenchmarkExportFormat: String, CaseIterable, Identifiable, Sendable {
    case markdown
    case json

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .markdown: return "Markdown"
        case .json: return "JSON"
        }
    }

    var iconName: String {
        switch self {
        case .markdown: return "doc.text"
        case .json: return "curlybraces"
        }
    }
}

// MARK: - Formatter

enum BenchmarkReportFormatter {

    // MARK: - Clipboard String (Markdown or JSON)

    static func formattedString(run: BenchmarkRun, format: BenchmarkExportFormat) -> String {
        switch format {
        case .markdown: return formatMarkdown(run: run)
        case .json: return formatJSON(run: run)
        }
    }

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

        let successCount = run.results.filter(\.metrics.didSucceed).count
        let failCount = run.results.count - successCount
        lines.append("**Results:** \(run.results.count) total, \(successCount) passed, \(failCount) failed")
        lines.append("")

        let grouped = Dictionary(grouping: run.results, by: { $0.category })
        for category in BenchmarkCategory.allCases {
            guard let results = grouped[category], !results.isEmpty else { continue }
            lines.append("## \(category.displayName)")
            lines.append("")
            for result in results {
                let m = result.metrics
                lines.append("### \(result.scenario.name) — \(result.modelInfo.name)")
                lines.append("- Framework: \(result.modelInfo.framework)")
                if !m.didSucceed {
                    lines.append("- **Error:** \(m.errorMessage ?? "Unknown")")
                } else {
                    lines.append("- Load: \(String(format: "%.0f", m.loadTimeMs))ms")
                    if m.warmupTimeMs > 0 {
                        lines.append("- Warmup: \(String(format: "%.0f", m.warmupTimeMs))ms")
                    }
                    lines.append("- End-to-end: \(String(format: "%.0f", m.endToEndLatencyMs))ms")
                    if let tps = m.tokensPerSecond { lines.append("- Tokens/s: \(String(format: "%.1f", tps))") }
                    if let ttft = m.ttftMs { lines.append("- TTFT: \(String(format: "%.0f", ttft))ms") }
                    if let inp = m.inputTokens { lines.append("- Input tokens: \(inp)") }
                    if let out = m.outputTokens { lines.append("- Output tokens: \(out)") }
                    if let rtf = m.realTimeFactor { lines.append("- RTF: \(String(format: "%.2f", rtf))x") }
                    if let dur = m.audioLengthSeconds { lines.append("- Audio length: \(String(format: "%.1f", dur))s") }
                    if let dur = m.audioDurationSeconds { lines.append("- Audio duration: \(String(format: "%.1f", dur))s") }
                    if let chars = m.charactersProcessed { lines.append("- Characters: \(chars)") }
                    if let pt = m.promptTokens { lines.append("- Prompt tokens: \(pt)") }
                    if let ct = m.completionTokens { lines.append("- Completion tokens: \(ct)") }
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

    // MARK: - JSON (pretty-printed string for clipboard)

    static func formatJSON(run: BenchmarkRun) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(run),
              let jsonString = String(data: data, encoding: .utf8) else {
            return "{\"error\": \"Failed to encode benchmark run\"}"
        }
        return jsonString
    }

    // MARK: - File Export: JSON

    static func writeJSON(run: BenchmarkRun) -> URL {
        let jsonString = formatJSON(run: run)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("benchmark_\(run.id.uuidString.prefix(8)).json")
        try? jsonString.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - File Export: CSV

    static func writeCSV(run: BenchmarkRun) -> URL {
        var csv = "Category,Scenario,Model,Framework,LoadMs,WarmupMs,E2EMs,TPS,TTFT,RTF,AudioLen,AudioDur,Chars,PromptTok,CompTok,GenMs,MemDeltaBytes,Success,Error\n"
        for r in run.results {
            let m = r.metrics
            var row: [String] = []
            row.append(r.category.displayName)
            row.append(r.scenario.name)
            row.append(r.modelInfo.name)
            row.append(r.modelInfo.framework)
            row.append(String(format: "%.0f", m.loadTimeMs))
            row.append(String(format: "%.0f", m.warmupTimeMs))
            row.append(String(format: "%.0f", m.endToEndLatencyMs))
            row.append(m.tokensPerSecond.map { String(format: "%.1f", $0) } ?? "")
            row.append(m.ttftMs.map { String(format: "%.0f", $0) } ?? "")
            row.append(m.realTimeFactor.map { String(format: "%.2f", $0) } ?? "")
            row.append(m.audioLengthSeconds.map { String(format: "%.1f", $0) } ?? "")
            row.append(m.audioDurationSeconds.map { String(format: "%.1f", $0) } ?? "")
            row.append(m.charactersProcessed.map { "\($0)" } ?? "")
            row.append(m.promptTokens.map { "\($0)" } ?? "")
            row.append(m.completionTokens.map { "\($0)" } ?? "")
            row.append(m.generationTimeMs.map { String(format: "%.0f", $0) } ?? "")
            row.append(String(m.memoryDeltaBytes))
            row.append(m.didSucceed ? "true" : "false")
            row.append(m.errorMessage ?? "")
            let escaped = row.map { field -> String in
                if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
                    return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
                }
                return field
            }
            csv += escaped.joined(separator: ",") + "\n"
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("benchmark_\(run.id.uuidString.prefix(8)).csv")
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
