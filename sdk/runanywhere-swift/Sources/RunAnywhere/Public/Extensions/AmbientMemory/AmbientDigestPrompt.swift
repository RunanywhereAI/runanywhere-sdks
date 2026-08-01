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
            You summarize one part of a longer voice note into structured sections. \
            Cover only what this part says; do not invent context from before or after it.
            """
        case .merge:
            task = """
            You merge partial structured summaries of one voice note into a single note. \
            Deduplicate overlapping bullets and action items, keep the clearest wording, \
            and re-cluster under stable topical headings.
            """
        }

        return """
        \(task)
        The transcript lines are marked like [S12] Speaker 1: text. Cite those numbers \
        in sourceSegmentIndices when a bullet or action item comes from that turn.
        Reply with JSON only, no prose and no code fences, in exactly this shape:
        {"title":"short title","sections":[{"heading":"Topic","bullets":[{"lead":"Key","text":"detail","sourceSegmentIndices":[12]}]}],"actionItems":[{"text":"Do the thing","sourceSegmentIndices":[12]}]}
        Rules:
        - sections: 1–6 topical headings with scannable bullets
        - each bullet has an optional short lead (entity/topic) and a concise text
        - actionItems: at most \(maxActionItems) short imperatives actually stated
        - sourceSegmentIndices must refer only to [S#] markers present in the input
        - if you cannot structure, still return {"title":"","sections":[{"heading":"Overview","bullets":[{"lead":"","text":"...","sourceSegmentIndices":[]}]}],"actionItems":[]}
        - legacy {"summary":"...","actionItems":["..."]} is also accepted
        """
    }

    static func user(text: String, mode: RAAmbientDigestMode) -> String {
        let heading = mode == .merge ? "Partial summaries:" : "Transcript:"
        return """
        \(heading)
        \(text)

        JSON:
        """
    }

    static func parse(_ response: String, fallbackText: String) -> Parsed {
        let fallbackSummary = String(fallbackText.prefix(200))
        let cleaned = stripThinking(response)
        guard let payload = jsonObject(in: cleaned) else {
            return Parsed(
                title: "",
                summary: fallbackSummary,
                sections: [overviewSection(fallbackSummary)],
                actionItems: []
            )
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
            resolvedSections = [overviewSection(prose)]
        } else {
            resolvedSections = sections
        }

        let summary = flattenSummary(title: title, sections: resolvedSections, legacy: legacySummary)
        return Parsed(
            title: title,
            summary: summary.isEmpty ? fallbackSummary : summary,
            sections: resolvedSections,
            actionItems: citedItems
        )
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
