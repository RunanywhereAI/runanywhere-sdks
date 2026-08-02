//
//  AmbientDigestPrompt.swift
//  RunAnywhere SDK
//
//  Prompt construction and response parsing for Notion-style note digests.
//

import Foundation

/// Prompt construction and response parsing for note summarization.
enum AmbientDigestPrompt {

    struct Parsed: Equatable {
        let title: String
        let summary: String
        let sections: [RAAmbientDigestSection]
        let actionItems: [RAAmbientDigestActionItem]
    }

    static func system(mode: RAAmbientDigestMode, maxActionItems: Int) -> String {
        let task: String
        switch mode {
        case .chunk:
            task = """
            You summarize one part of a longer meeting into a tight structured note. \
            Extract decisions, goals, disagreements, and commitments — not a play-by-play. \
            Drop filler, greetings, and repeated wording. Cover only this part.
            """
        case .merge:
            task = """
            You write a draft meeting note from partial summaries of one conversation. \
            Cluster into themes (not one section per partial). Deduplicate. \
            Prefer 4–8 topical sections. Do NOT keep Part N headings.
            """
        case .polish:
            task = """
            You rewrite a messy meeting draft into a sharp Notion-style note. \
            Preserve coverage across the draft's themes (sales, product, fundraising, \
            open source, process, etc.) — do not drop whole topics just to be short. \
            Capture meaning: goals, tradeoffs, decisions, risks, next steps. \
            Drop greetings, filler, and "Speaker N:" prefixes. \
            Return 5–6 thematic sections with 3–5 bullets each. \
            Title must name the meeting topic (never "Meeting notes"). \
            actionItems is REQUIRED when the draft mentions follow-ups, asks, \
            or commitments (e.g. "need to", "follow up", "next steps", pilots). \
            Put those as short imperatives in actionItems — do not only bury them \
            inside section bullets. Prefer 3–8 actionItems; use [] only if none exist. \
            Keep JSON complete and valid (actionItems last is fine, but do not omit it).
            """
        }

        let sectionRule: String
        switch mode {
        case .chunk: sectionRule = "1–3"
        case .merge: sectionRule = "4–8 topical headings (hard max 8)"
        case .polish: sectionRule = "5–6 thematic headings (hard max 6)"
        }

        return """
        \(task)
        The transcript lines are marked like [S12] Speaker 1: text. Cite those numbers \
        in sourceSegmentIndices when a bullet or action item comes from that turn.
        Reply with JSON only, no prose and no code fences, in exactly this shape:
        {"title":"short title","sections":[{"heading":"Topic","bullets":[{"lead":"Key","text":"detail","sourceSegmentIndices":[12]}]}],"actionItems":[{"text":"Do the thing","sourceSegmentIndices":[12]}]}
        Rules:
        - sections: \(sectionRule) with scannable bullets
        - each bullet has an optional short lead (entity/topic) and a concise text
        - prefer fewer stronger bullets over many weak ones
        - never start a bullet with "Speaker N:"
        - actionItems: at most \(maxActionItems) short imperatives actually stated
        - sourceSegmentIndices must refer only to [S#] markers present in the input
        - if you cannot structure, still return {"title":"","sections":[{"heading":"Overview","bullets":[{"lead":"","text":"...","sourceSegmentIndices":[]}]}],"actionItems":[]}
        - legacy {"summary":"...","actionItems":["..."]} is also accepted
        """
    }

    static func user(text: String, mode: RAAmbientDigestMode) -> String {
        let heading: String
        switch mode {
        case .chunk: heading = "Transcript:"
        case .merge: heading = "Partial summaries:"
        case .polish: heading = "Draft meeting note to rewrite:"
        }
        return """
        \(heading)
        \(text)

        JSON:
        """
    }

    static func parse(
        _ response: String,
        fallbackText: String,
        mode: RAAmbientDigestMode = .chunk
    ) -> Parsed {
        let fallbackSummary = fallbackSummary(for: fallbackText, mode: mode)
        let cleaned = stripThinking(response)
        guard let payload = jsonObject(in: cleaned) else {
            return parsedFromFallback(fallbackSummary, mode: mode)
        }

        let title = (payload["title"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sections = parseSections(payload)
        let citedItems = parseActionItems(payload["actionItems"])
        let legacySummary = (payload["summary"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let resolvedSections: [RAAmbientDigestSection]
        if sections.isEmpty {
            let prose = legacySummary.isEmpty ? fallbackSummary : legacySummary
            resolvedSections = sectionsFromProse(prose, mode: mode)
        } else {
            resolvedSections = sections
        }

        let summary = flattenSummary(title: title, sections: resolvedSections, legacy: legacySummary)
        var parsed = Parsed(
            title: title,
            summary: summary.isEmpty ? fallbackSummary : summary,
            sections: resolvedSections,
            actionItems: citedItems
        )

        // Only replace genuinely collapsed merges. A tight note is success even
        // when much shorter than the joined map partials.
        if (mode == .merge || mode == .polish), isCollapsed(parsed), fallbackText.count > 500 {
            parsed = parsedFromFallback(fallbackSummary, mode: .merge)
        }
        let maxSections = mode == .polish ? 6 : 8
        if (mode == .merge || mode == .polish), parsed.sections.count > maxSections {
            parsed = Parsed(
                title: parsed.title,
                summary: parsed.summary,
                sections: Array(parsed.sections.prefix(maxSections)),
                actionItems: parsed.actionItems
            )
        }
        return parsed
    }

    /// True when merge output is a near-empty collapse (not merely concise).
    static func isThin(_ parsed: Parsed) -> Bool { isCollapsed(parsed) }

    static func isCollapsed(_ parsed: Parsed) -> Bool {
        let bullets = parsed.sections.reduce(0) { $0 + $1.bullets.count }
        if parsed.sections.isEmpty { return true }
        if parsed.sections.count <= 1 && bullets <= 2 { return true }
        if parsed.summary.count < 180 && bullets < 3 { return true }
        return false
    }

    /// True when fallback still looks like "one section per map chunk".
    static func isChunkDump(_ parsed: Parsed, partialCount: Int) -> Bool {
        partialCount > 8 && parsed.sections.count >= min(partialCount, 12)
    }

    /// Pull actionable lines when the model left `actionItems` empty.
    static func harvestActionItems(
        fromSections sections: [RAAmbientDigestSection],
        fallbackText: String,
        max: Int
    ) -> [RAAmbientDigestActionItem] {
        var seen = Set<String>()
        var items: [RAAmbientDigestActionItem] = []

        func consider(_ raw: String) {
            var text = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "•- "))
            text = text.replacingOccurrences(
                of: #"^Speaker\s+\d+\s*:\s*"#,
                with: "",
                options: .regularExpression
            )
            guard text.count >= 18, text.count <= 160 else { return }
            let low = text.lowercased()
            let looksAction =
                low.hasPrefix("next")
                || low.contains("follow up")
                || low.contains("follow-up")
                || low.contains("need to")
                || low.contains("should ")
                || low.contains("action")
                || low.contains("pilot")
                || low.contains("schedule")
                || low.contains("define ")
                || low.contains("set a ")
                || low.contains("set an ")
            guard looksAction else { return }
            let key = low
            guard seen.insert(key).inserted else { return }
            // Prefer imperative tone without forcing awkward rewrites.
            items.append(RAAmbientDigestActionItem(text: text))
        }

        for section in sections {
            let heading = section.heading.lowercased()
            let nextish = heading.contains("next") || heading.contains("action") || heading.contains("follow")
            for bullet in section.bullets {
                let line = bullet.lead.isEmpty ? bullet.text : "\(bullet.lead): \(bullet.text)"
                if nextish { consider(line) }
                else { consider(line) }
            }
        }
        if items.count < 2 {
            for line in fallbackText.split(whereSeparator: \.isNewline) {
                consider(String(line))
                if items.count >= max { break }
            }
        }
        return Array(items.prefix(max))
    }

    // MARK: - Fallback / heuristics

    private static func fallbackSummary(for text: String, mode: RAAmbientDigestMode) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if mode == .merge || mode == .polish {
            return cleanedMergeFallback(trimmed)
        }
        return String(trimmed.prefix(200))
    }

    /// Keep the full map-pass text when merge JSON fails — never truncate to 200.
    private static func cleanedMergeFallback(_ text: String) -> String {
        text
            .replacingOccurrences(
                of: #"Part\s+\d+\s*:\s*"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parsedFromFallback(_ summary: String, mode: RAAmbientDigestMode) -> Parsed {
        Parsed(
            title: (mode == .merge || mode == .polish) ? "Meeting notes" : "",
            summary: summary,
            sections: sectionsFromProse(summary, mode: mode),
            actionItems: []
        )
    }

    private static func sectionsFromProse(_ prose: String, mode: RAAmbientDigestMode) -> [RAAmbientDigestSection] {
        let trimmed = prose.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return [overviewSection("")]
        }
        if mode == .merge || mode == .polish {
            let blocks = trimmed
                .components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if blocks.count >= 2 {
                return blocks.enumerated().map { index, block in
                    let lines = block.components(separatedBy: "\n")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    let heading = lines.first.flatMap { line -> String? in
                        let cleaned = line.trimmingCharacters(in: CharacterSet(charactersIn: "•- "))
                        return cleaned.count <= 48 ? cleaned : nil
                    } ?? "Part \(index + 1)"
                    let bulletLines = lines.dropFirst().isEmpty ? lines : Array(lines.dropFirst())
                    let bullets = bulletLines.prefix(12).map { line in
                        let text = line.trimmingCharacters(in: CharacterSet(charactersIn: "•- "))
                        return RAAmbientDigestBullet(text: text)
                    }
                    return RAAmbientDigestSection(
                        heading: heading,
                        bullets: bullets.isEmpty ? [RAAmbientDigestBullet(text: block)] : Array(bullets)
                    )
                }
            }
        }
        return [overviewSection(trimmed)]
    }

    private static func overviewSection(_ text: String) -> RAAmbientDigestSection {
        RAAmbientDigestSection(
            heading: "Overview",
            bullets: [RAAmbientDigestBullet(text: text)]
        )
    }

    private static func flattenSummary(
        title: String,
        sections: [RAAmbientDigestSection],
        legacy: String
    ) -> String {
        if !legacy.isEmpty { return legacy }
        var lines: [String] = []
        if !title.isEmpty { lines.append(title) }
        for section in sections {
            lines.append(section.heading)
            for bullet in section.bullets {
                if bullet.lead.isEmpty {
                    lines.append("• \(bullet.text)")
                } else {
                    lines.append("• \(bullet.lead): \(bullet.text)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func parseSections(_ payload: [String: Any]) -> [RAAmbientDigestSection] {
        guard let rawSections = payload["sections"] as? [Any] else { return [] }
        return rawSections.compactMap { entry in
            guard let object = entry as? [String: Any] else { return nil }
            let heading = (object["heading"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !heading.isEmpty else { return nil }
            let bullets = parseBullets(object["bullets"])
            guard !bullets.isEmpty else { return nil }
            return RAAmbientDigestSection(heading: heading, bullets: bullets)
        }
    }

    private static func parseBullets(_ raw: Any?) -> [RAAmbientDigestBullet] {
        guard let items = raw as? [Any] else { return [] }
        return items.compactMap { entry in
            if let string = entry as? String {
                let text = string.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : RAAmbientDigestBullet(text: text)
            }
            guard let object = entry as? [String: Any] else { return nil }
            let lead = (object["lead"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let text = ((object["text"] as? String) ?? (object["body"] as? String))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return nil }
            return RAAmbientDigestBullet(
                lead: lead,
                text: text,
                sourceSegmentIndices: parseIndices(object["sourceSegmentIndices"])
            )
        }
    }

    private static func parseActionItems(_ raw: Any?) -> [RAAmbientDigestActionItem] {
        guard let items = raw as? [Any] else { return [] }
        var seen = Set<String>()
        var result: [RAAmbientDigestActionItem] = []
        for entry in items {
            let text: String?
            let indices: [Int]
            if let string = entry as? String {
                text = string
                indices = []
            } else if let object = entry as? [String: Any] {
                text = (object["text"] ?? object["item"] ?? object["action"]) as? String
                indices = parseIndices(object["sourceSegmentIndices"])
            } else {
                text = nil
                indices = []
            }
            guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty,
                  seen.insert(trimmed.lowercased()).inserted else { continue }
            result.append(RAAmbientDigestActionItem(text: trimmed, sourceSegmentIndices: indices))
        }
        return result
    }

    private static func parseIndices(_ raw: Any?) -> [Int] {
        guard let values = raw as? [Any] else { return [] }
        var result: [Int] = []
        for value in values {
            if let int = value as? Int {
                result.append(int)
            } else if let number = value as? NSNumber {
                result.append(number.intValue)
            } else if let string = value as? String,
                      let int = Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
                result.append(int)
            }
        }
        return result
    }

    private static func stripThinking(_ response: String) -> String {
        var text = response
        let patterns = [
            #"<think>[\s\S]*?</think>"#,
            #"<thinking>[\s\S]*?</thinking>"#,
            #"◁think▷[\s\S]*?◁/think▷"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func jsonObject(in response: String) -> [String: Any]? {
        guard let start = response.firstIndex(of: "{"),
              let end = response.lastIndex(of: "}"),
              start < end else { return nil }
        let slice = String(response[start...end])
        guard let data = slice.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return raw as? [String: Any]
    }
}
