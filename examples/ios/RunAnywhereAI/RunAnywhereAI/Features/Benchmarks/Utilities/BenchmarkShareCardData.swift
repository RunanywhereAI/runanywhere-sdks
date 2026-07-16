//
//  BenchmarkShareCardData.swift
//  RunAnywhereAI
//
//  Deterministic, presentation-ready projection of ONE modality of a benchmark run,
//  used to draw the branded share card. Mirrors the Android `ShareCardData` mapper
//  one-to-one so the iOS and Android cards are comparable. A run can span several
//  modalities (LLM/STT/TTS/VLM) and many models, which can't stay clean in a single
//  image — so each card is scoped to a single modality and the share sheet lets the
//  user pick which to share. Only the important metrics are surfaced.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// One labelled metric shown on the share card (e.g. "tok/s" -> "42").
struct ShareCardMetric: Identifiable, Sendable {
    let value: String
    let label: String
    var id: String { "\(label)-\(value)" }
}

/// One model's row on the share card: name/framework plus its headline metrics.
struct ShareCardRow: Identifiable, Sendable {
    let model: String
    let framework: String
    let metrics: [ShareCardMetric]
    var id: String { model }
}

/// The card's full, ready-to-render content for a single modality.
struct ShareCardData: Sendable {
    let modalityLabel: String
    let deviceLine: String
    let hero: ShareCardMetric?
    let heroCaption: String
    // A compact secondary stat for the hero model (e.g. TTFT), so the top model's
    // detail lives with the headline instead of being repeated in a row below.
    let heroSecondary: ShareCardMetric?
    // Only the models BEYOND the hero — the top model is never repeated as a row.
    let rows: [ShareCardRow]
    let dateLine: String
    // Prepopulated, post-ready caption that already includes the run's headline
    // numbers, the @runanywhereai tag and the download CTA.
    let shareMessage: String

    // Keep the card clean — only the top few models make the social image.
    private static let maxRows = 3

    /// Modalities with at least one successful result, in canonical display order.
    /// Empty when the run produced nothing shareable (all failed / cancelled).
    static func availableModalities(_ run: BenchmarkRun) -> [BenchmarkCategory] {
        BenchmarkCategory.allCases.filter { category in
            run.results.contains { $0.metrics.didSucceed && $0.category == category }
        }
    }

    /// Builds the card for a single modality. Callers pass a category returned by
    /// `availableModalities`; such a category always has at least one row.
    static func from(_ run: BenchmarkRun, category: BenchmarkCategory) -> ShareCardData {
        let successes = run.results.filter { $0.metrics.didSucceed && $0.category == category }
        // One row per model, using its best (highest sortKey) scenario.
        let byModel = Dictionary(grouping: successes) { $0.modelInfo.name }
            .values
            .compactMap { perModel in perModel.max { sortKey($0) < sortKey($1) } }
            .sorted { sortKey($0) > sortKey($1) }

        let top = byModel.first
        let hero = top.flatMap { heroMetric(category, $0) }
        let heroCaption = top.map { "\($0.modelInfo.name) · \($0.modelInfo.framework)" } ?? ""
        let heroSecondary = top.flatMap { makeRow($0).metrics.dropFirst().first }
        // Rows are the OTHER models only — the top model already headlines the card.
        let additional = Array(byModel.dropFirst().prefix(maxRows))

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, yyyy"
        dateFormatter.locale = Locale(identifier: "en_US")

        // Device + chipset are the important "flex" facts; use the marketing model
        // name (e.g. "iPhone 16 Pro"), never the raw identifier.
        let deviceName = DeviceMarketName.resolve(fallback: run.deviceInfo.modelName)
        let deviceLine = [deviceName, run.deviceInfo.chipName]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")

        return ShareCardData(
            modalityLabel: cardLabel(category),
            deviceLine: deviceLine,
            hero: hero,
            heroCaption: heroCaption,
            heroSecondary: heroSecondary,
            rows: additional.map(Self.makeRow),
            dateLine: dateFormatter.string(from: run.startedAt),
            shareMessage: buildShareMessage(model: top?.modelInfo.name, hero: hero, device: deviceLine)
        )
    }

    // A clean, post-ready caption seeded with the run's headline numbers.
    private static func buildShareMessage(model: String?, hero: ShareCardMetric?, device: String) -> String {
        let headline: String
        if let model, let hero {
            headline = "\(model) hit \(hero.value) \(hero.label) running 100% on-device on my \(device)"
        } else {
            headline = "Running AI models 100% on-device on my \(device)"
        }
        return """
        \(headline) with @runanywhereai ⚡
        No cloud. No API keys. Full privacy.

        Download the RunAnywhere app → runanywhere.ai
        """
    }

    // Ordering key: throughput-like metric where higher is better. STT uses the
    // realtime speedup (1/RTF) so faster transcription sorts first.
    private static func sortKey(_ result: BenchmarkResult) -> Double {
        let m = result.metrics
        switch result.category {
        case .llm, .vlm: return m.tokensPerSecond ?? -1
        case .stt: return (m.realTimeFactor.map { $0 > 0 ? 1 / $0 : -1 }) ?? -1
        case .tts: return charsPerSecond(result) ?? -1
        }
    }

    // The single headline metric for a modality's fastest model.
    private static func heroMetric(_ category: BenchmarkCategory, _ result: BenchmarkResult) -> ShareCardMetric? {
        let m = result.metrics
        switch category {
        case .llm, .vlm:
            return m.tokensPerSecond.map { ShareCardMetric(value: String(format: "%.0f", $0), label: "tokens / sec") }
        case .stt:
            guard let rtf = m.realTimeFactor, rtf > 0 else { return nil }
            return ShareCardMetric(value: String(format: "%.1f×", 1 / rtf), label: "faster than realtime")
        case .tts:
            return charsPerSecond(result).map { ShareCardMetric(value: String(format: "%.0f", $0), label: "chars / sec") }
        }
    }

    private static func charsPerSecond(_ result: BenchmarkResult) -> Double? {
        guard let chars = result.metrics.charactersProcessed else { return nil }
        let seconds = result.metrics.endToEndLatencyMs / 1000
        return seconds > 0 ? Double(chars) / seconds : nil
    }

    private static func makeRow(_ result: BenchmarkResult) -> ShareCardRow {
        let m = result.metrics
        let optionalCells: [ShareCardMetric?]
        switch result.category {
        case .llm, .vlm:
            optionalCells = [
                m.tokensPerSecond.map { ShareCardMetric(value: String(format: "%.1f", $0), label: "tok/s") },
                m.ttftMs.map { ShareCardMetric(value: String(format: "%.0fms", $0), label: "TTFT") }
            ]
        case .stt:
            optionalCells = [
                m.realTimeFactor.map { ShareCardMetric(value: String(format: "%.2fx", $0), label: "RTF") },
                ShareCardMetric(value: String(format: "%.0fms", m.loadTimeMs), label: "load")
            ]
        case .tts:
            optionalCells = [
                charsPerSecond(result).map { ShareCardMetric(value: String(format: "%.0f", $0), label: "chars/s") },
                ShareCardMetric(value: String(format: "%.0fms", m.loadTimeMs), label: "load")
            ]
        }
        return ShareCardRow(
            model: result.modelInfo.name,
            framework: result.modelInfo.framework,
            metrics: optionalCells.compactMap { $0 }
        )
    }

    // Short, social-friendly modality label shown on the card (matches Android).
    private static func cardLabel(_ category: BenchmarkCategory) -> String {
        switch category {
        case .llm: return "LANGUAGE MODELS"
        case .stt: return "SPEECH → TEXT"
        case .tts: return "TEXT → SPEECH"
        case .vlm: return "VISION"
        }
    }
}

// MARK: - Device Marketing Name

/// Resolves the current device's marketing name (e.g. "iPhone 16 Pro") from its
/// hardware identifier. `BenchmarkDeviceInfo.modelName` is only the family name
/// ("iPhone"), so we map the identifier here — sharing always happens on the same
/// device that ran the benchmark, so reading it live is correct.
enum DeviceMarketName {
    static func resolve(fallback: String) -> String {
        #if os(iOS)
        let id = machineIdentifier()
        return names[id] ?? (id.hasPrefix("iPhone") || id.hasPrefix("iPad") ? fallback : fallback)
        #else
        return fallback
        #endif
    }

    #if os(iOS)
    private static func machineIdentifier() -> String {
        // Simulator reports the host arch via uname; the real model is in the env.
        if let simID = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simID
        }
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafeBytes(of: &systemInfo.machine) { raw -> String in
            let ptr = raw.bindMemory(to: CChar.self).baseAddress!
            return String(cString: ptr)
        }
        return machine
    }

    // Marketing names for the identifiers this app is likely to run on. Unknown
    // identifiers fall back to the family name so the card never shows "iPhone17,1".
    private static let names: [String: String] = [
        "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12",
        "iPhone13,3": "iPhone 12 Pro", "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13",
        "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus",
        "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,5": "iPhone 16e"
    ]
    #endif
}
