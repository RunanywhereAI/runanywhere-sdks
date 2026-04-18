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

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    static func formatMarkdown(run: BenchmarkRun) -> String {
        var lines: [String] = []
        lines.append("# Benchmark Report")
        lines.append("")
        lines.append("**Device:** \(run.deviceInfo.modelName)")
        lines.append("**Chip:** \(run.deviceInfo.chipName)")
        let ramString = ByteCountFormatter.string(
            fromByteCount: run.deviceInfo.totalMemoryBytes,
            countStyle: .memory
        )
        lines.append("**RAM:** \(ramString)")
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

        let grouped = Dictionary(grouping: run.results) { $0.category }
        for category in BenchmarkCategory.allCases {
            guard let results = grouped[category], !results.isEmpty else { continue }
            lines.append("## \(category.displayName)")
            lines.append("")
            for result in results {
                let metrics = result.metrics
                lines.append("### \(result.scenario.name) — \(result.modelInfo.name)")
                lines.append("- Framework: \(result.modelInfo.framework)")
                if !metrics.didSucceed {
                    lines.append("- **Error:** \(metrics.errorMessage ?? "Unknown")")
                } else {
                    lines.append("- Load: \(String(format: "%.0f", metrics.loadTimeMs))ms")
                    if metrics.warmupTimeMs > 0 {
                        lines.append("- Warmup: \(String(format: "%.0f", metrics.warmupTimeMs))ms")
                    }
                    lines.append("- End-to-end: \(String(format: "%.0f", metrics.endToEndLatencyMs))ms")
                    if let decode = metrics.decodeTokensPerSecond {
                        lines.append("- Decode: \(String(format: "%.1f", decode)) tok/s")
                    }
                    if let prefill = metrics.prefillTokensPerSecond {
                        lines.append("- Prefill: \(String(format: "%.1f", prefill)) tok/s")
                    }
                    if let tps = metrics.tokensPerSecond {
                        lines.append("- Tokens/s: \(String(format: "%.1f", tps))")
                    }
                    if let ttft = metrics.ttftMs {
                        lines.append("- TTFT: \(String(format: "%.0f", ttft))ms")
                    }
                    if let inp = metrics.inputTokens { lines.append("- Input tokens: \(inp)") }
                    if let out = metrics.outputTokens { lines.append("- Output tokens: \(out)") }
                    if let rtf = metrics.realTimeFactor {
                        lines.append("- RTF: \(String(format: "%.2f", rtf))x")
                    }
                    if let dur = metrics.audioLengthSeconds {
                        lines.append("- Audio length: \(String(format: "%.1f", dur))s")
                    }
                    if let dur = metrics.audioDurationSeconds {
                        lines.append("- Audio duration: \(String(format: "%.1f", dur))s")
                    }
                    if let chars = metrics.charactersProcessed { lines.append("- Characters: \(chars)") }
                    if let pt = metrics.promptTokens { lines.append("- Prompt tokens: \(pt)") }
                    if let ct = metrics.completionTokens { lines.append("- Completion tokens: \(ct)") }
                    if let genMs = metrics.generationTimeMs {
                        lines.append("- Gen time: \(String(format: "%.0f", genMs))ms")
                    }
                    if metrics.memoryDeltaBytes != 0 {
                        let memStr = ByteCountFormatter.string(
                            fromByteCount: metrics.memoryDeltaBytes,
                            countStyle: .memory
                        )
                        lines.append("- Memory delta: \(memStr)")
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
        var csv = "Category,Scenario,Model,Framework,LoadMs,WarmupMs,E2EMs,DecodeTPS,PrefillTPS,"
            + "TPS,TTFT,InTokens,OutTokens,RTF,AudioLen,AudioDur,Chars,PromptTok,CompTok,"
            + "GenMs,MemDeltaBytes,Success,Error\n"
        for result in run.results {
            let metrics = result.metrics
            var row: [String] = []
            row.append(result.category.displayName)
            row.append(result.scenario.name)
            row.append(result.modelInfo.name)
            row.append(result.modelInfo.framework)
            row.append(String(format: "%.0f", metrics.loadTimeMs))
            row.append(String(format: "%.0f", metrics.warmupTimeMs))
            row.append(String(format: "%.0f", metrics.endToEndLatencyMs))
            row.append(metrics.decodeTokensPerSecond.map { String(format: "%.1f", $0) } ?? "")
            row.append(metrics.prefillTokensPerSecond.map { String(format: "%.1f", $0) } ?? "")
            row.append(metrics.tokensPerSecond.map { String(format: "%.1f", $0) } ?? "")
            row.append(metrics.ttftMs.map { String(format: "%.0f", $0) } ?? "")
            row.append(metrics.inputTokens.map { "\($0)" } ?? "")
            row.append(metrics.outputTokens.map { "\($0)" } ?? "")
            row.append(metrics.realTimeFactor.map { String(format: "%.2f", $0) } ?? "")
            row.append(metrics.audioLengthSeconds.map { String(format: "%.1f", $0) } ?? "")
            row.append(metrics.audioDurationSeconds.map { String(format: "%.1f", $0) } ?? "")
            row.append(metrics.charactersProcessed.map { "\($0)" } ?? "")
            row.append(metrics.promptTokens.map { "\($0)" } ?? "")
            row.append(metrics.completionTokens.map { "\($0)" } ?? "")
            row.append(metrics.generationTimeMs.map { String(format: "%.0f", $0) } ?? "")
            row.append(String(metrics.memoryDeltaBytes))
            row.append(metrics.didSucceed ? "true" : "false")
            row.append(metrics.errorMessage ?? "")
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
