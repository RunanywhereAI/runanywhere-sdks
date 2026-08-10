//
//  MarkdownBlock.swift
//  RunAnywhereAI
//
//  Block structure of an assistant reply. Pure Foundation: no SwiftUI, so it can
//  be reasoned about (and run) without a view hierarchy.
//
//  ## Why this replaced the rendering-strategy detector
//
//  The previous pipeline asked a detector which *renderer* to use — `.plain`,
//  `.light`, `.basic`, or `.rich` — and dispatched to a different view for each.
//  Two of those four (`.light`, `.basic`) resolved to the same view, so the only
//  real distinction was "one `Text`" versus "a `VStack` of blocks".
//
//  That decision was made inside `body`, which means it was re-made on every
//  render, which during streaming means once per token. So the moment a reply's
//  first ``` arrived, the bubble stopped being one `Text` and became a `VStack` —
//  a full teardown and re-layout of the whole reply, mid-sentence, in front of
//  the reader. Same on the way back if a lookahead in the inline regex stopped
//  matching as the next character landed (`*a*` matches, `*a*s` does not), which
//  could drop `.light` back to `.plain`.
//
//  A monotonic latch would have papered over that. Parsing to blocks removes it:
//  there is one renderer, its shape does not depend on a threshold, and a fence
//  arriving appends a block instead of changing what kind of view the reply is.
//  Nothing can flip, because there is nothing left to flip between.
//

import Foundation

// MARK: - Blocks

/// One renderable block of a reply, in source order.
enum MarkdownBlock: Equatable {
    /// Consecutive prose lines, newlines preserved.
    case paragraph(String)
    /// `#` … `######`. `level` is 1–6 as written; clamping to the screen's own
    /// type scale is the renderer's job, not the parser's.
    case heading(level: Int, text: String)
    /// A run of adjacent list items, bulleted or numbered.
    case list([MarkdownListItem])
    /// Consecutive `>` lines, markers stripped.
    case quote(String)
    /// A fenced block. `language` is whatever followed the opening fence.
    case code(language: String?, source: String)
    /// A thematic break.
    case rule
}

/// One row of a list.
///
/// `label` is resolved here rather than in the view so that "the model started
/// this list at 3" survives to the screen: a numbered item carries the number as
/// written, and renumbering from 1 would silently rewrite the reply.
struct MarkdownListItem: Equatable {
    /// Rendered marker — a bullet glyph, or the model's own number plus `.`.
    let label: String
    /// Nesting level, 0-based, derived from leading spaces.
    let depth: Int
    /// Item content, still carrying inline markdown.
    let text: String
    /// True for `1.` / `1)` rows. Numbers get a wider, right-aligned gutter so
    /// `9.` and `10.` do not stagger the text beside them.
    let isOrdered: Bool
}

// MARK: - Parser

enum MarkdownBlockParser {
    /// Split `content` into blocks.
    ///
    /// Tolerant by construction, because it is fed half-written text: an unclosed
    /// fence still yields a code block (so a reply that is mid-listing does not
    /// show raw backticks), and an unterminated inline delimiter is simply left
    /// in the text for the inline layer to render literally until its closer
    /// arrives. That is what keeps a streaming reply from flickering.
    static func parse(_ content: String) -> [MarkdownBlock] {
        var accumulator = Accumulator()
        var fence: OpenFence?

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if var open = fence {
                if trimmed.hasPrefix("```") {
                    accumulator.append(open.block)
                    fence = nil
                } else {
                    open.lines.append(line)
                    fence = open
                }
                continue
            }

            if trimmed.hasPrefix("```") {
                accumulator.flush()
                fence = OpenFence(language: Self.fenceLanguage(trimmed))
                continue
            }

            accumulator.consume(line: line, trimmed: trimmed)
        }

        if let open = fence {
            accumulator.append(open.block)
        }
        accumulator.flush()
        return accumulator.blocks
    }

    /// The info string after an opening fence, or nil for a bare ```` ``` ````.
    /// Only the first word is kept: models emit ```` ```swift title=foo ````.
    private static func fenceLanguage(_ trimmed: String) -> String? {
        let info = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
        guard let first = info.split(separator: " ").first, !first.isEmpty else { return nil }
        return String(first)
    }
}

// MARK: - Open fence

private struct OpenFence {
    let language: String?
    var lines: [String] = []

    var block: MarkdownBlock {
        .code(language: language, source: lines.joined(separator: "\n"))
    }
}

// MARK: - Accumulator

/// Line-at-a-time state machine.
///
/// Only one of the three multi-line accumulators can be non-empty at a time —
/// every branch closes the other two — so flush order is irrelevant and the
/// blocks always come out in source order.
private struct Accumulator {
    var blocks: [MarkdownBlock] = []

    private var paragraph: [String] = []
    private var items: [MarkdownListItem] = []
    private var quote: [String] = []

    mutating func append(_ block: MarkdownBlock) {
        flush()
        blocks.append(block)
    }

    mutating func consume(line: String, trimmed: String) {
        if trimmed.isEmpty {
            flush()
            return
        }
        if Self.isRule(trimmed) {
            append(.rule)
            return
        }
        if let heading = Self.heading(trimmed) {
            append(heading)
            return
        }
        if let item = Self.listItem(line: line, trimmed: trimmed) {
            flushParagraph()
            flushQuote()
            items.append(item)
            return
        }
        if trimmed.hasPrefix(">") {
            flushParagraph()
            flushList()
            quote.append(Self.stripQuoteMarker(trimmed))
            return
        }
        flushList()
        flushQuote()
        paragraph.append(trimmed)
    }

    mutating func flush() {
        flushParagraph()
        flushList()
        flushQuote()
    }

    private mutating func flushParagraph() {
        guard !paragraph.isEmpty else { return }
        blocks.append(.paragraph(paragraph.joined(separator: "\n")))
        paragraph = []
    }

    private mutating func flushList() {
        guard !items.isEmpty else { return }
        blocks.append(.list(items))
        items = []
    }

    private mutating func flushQuote() {
        guard !quote.isEmpty else { return }
        blocks.append(.quote(quote.joined(separator: "\n")))
        quote = []
    }
}

// MARK: - Line classification

private extension Accumulator {
    /// `---`, `***`, `___` — three or more of one character, nothing else.
    ///
    /// Three or more, not exactly three, and the character must be uniform: `--`
    /// is an em-dash a model typed, and `-*-` is not a rule.
    static func isRule(_ trimmed: String) -> Bool {
        guard trimmed.count >= 3, let first = trimmed.first, "-*_".contains(first) else { return false }
        return trimmed.allSatisfy { $0 == first }
    }

    /// `#{1,6}` followed by a space. A `#` with no space is a hashtag, and seven
    /// hashes is not a heading in CommonMark either.
    static func heading(_ trimmed: String) -> MarkdownBlock? {
        guard trimmed.hasPrefix("#") else { return nil }
        let hashes = trimmed.prefix { $0 == "#" }
        guard hashes.count <= 6 else { return nil }
        let rest = trimmed.dropFirst(hashes.count)
        guard rest.hasPrefix(" ") else { return nil }

        // Trailing `#`s are a closed ATX heading; trailing spaces are a hard
        // break the heading has no use for.
        let leading = rest.drop { $0 == " " }
        let text = String(leading.reversed().drop { $0 == "#" || $0 == " " }.reversed())
        guard !text.isEmpty else { return nil }
        return .heading(level: hashes.count, text: text)
    }

    /// `- `, `* `, `+ `, `1. `, `1) `.
    static func listItem(line: String, trimmed: String) -> MarkdownListItem? {
        let depth = Self.depth(of: line)

        if let marker = trimmed.first, "-*+".contains(marker), trimmed.dropFirst().hasPrefix(" ") {
            let text = String(trimmed.dropFirst().drop { $0 == " " })
            guard !text.isEmpty else { return nil }
            return MarkdownListItem(label: bullet(at: depth), depth: depth, text: text, isOrdered: false)
        }

        let digits = trimmed.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let afterDigits = trimmed.dropFirst(digits.count)
        guard let punctuation = afterDigits.first, punctuation == "." || punctuation == ")",
              afterDigits.dropFirst().hasPrefix(" ") else { return nil }

        let text = String(afterDigits.dropFirst().drop { $0 == " " })
        guard !text.isEmpty else { return nil }
        // The model's own number, not a counter of our own: a list that starts
        // at 3 is a continuation, and renumbering it to 1 changes the answer.
        return MarkdownListItem(label: "\(digits).", depth: depth, text: text, isOrdered: true)
    }

    /// Leading whitespace → nesting level. Two spaces per level, tabs count as
    /// two, which covers both conventions models emit without needing to guess.
    static func depth(of line: String) -> Int {
        var columns = 0
        for character in line {
            if character == " " {
                columns += 1
            } else if character == "\t" {
                columns += 2
            } else {
                break
            }
        }
        return min(columns / 2, 3)
    }

    /// Bullet glyph by depth. Filled → hollow → triangle → dot: each level reads
    /// as subordinate to the one above it at body size.
    static func bullet(at depth: Int) -> String {
        switch depth {
        case 0: "\u{2022}"   // •
        case 1: "\u{25E6}"   // ◦
        case 2: "\u{2023}"   // ‣
        default: "\u{00B7}"  // ·
        }
    }

    static func stripQuoteMarker(_ trimmed: String) -> String {
        String(trimmed.dropFirst().drop { $0 == " " })
    }
}
