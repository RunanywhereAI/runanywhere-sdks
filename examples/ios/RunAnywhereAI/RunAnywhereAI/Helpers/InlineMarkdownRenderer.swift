//
//  InlineMarkdownRenderer.swift
//  RunAnywhereAI
//
//  Inline markdown for assistant replies: emphasis, inline code, headings, and
//  hierarchical lists, via `AttributedString`'s CommonMark parser.
//
//  ## Why there is a normalization pass
//
//  CommonMark requires a closing `**` to be *right-flanking* — no whitespace
//  between the last content character and the delimiter. Small local models
//  routinely emit `**Heading  **`, and the parser correctly refuses it, so the
//  reader sees literal asterisks in the middle of a reply. Verified: for
//  `"**The Industrial Revolution and Modernization  **"` the parser reports no
//  `.stronglyEmphasized` run and returns the source text unchanged.
//
//  Worse, this renderer used to *manufacture* that case. `preprocessListMarkers`
//  rewrote a heading by wrapping everything after the `#` run in `**…**` — and a
//  heading line ending in whitespace (a markdown hard break, extremely common in
//  model output) became exactly the unparseable form. So `## Foo  ` rendered as
//  `**Foo  **` on screen.
//
//  The fix is one normalization pass that pulls whitespace outside the
//  delimiters, plus trimming the heading text before wrapping it. Both are
//  presentation repairs: nothing here changes what the model said, it only makes
//  emphasis the model clearly intended actually render as emphasis.
//

import SwiftUI

/// Inline markdown renderer: bold, italic, inline code, headings-as-bold, and
/// hierarchical list bullets.
struct MarkdownText: View {
    let content: String
    let baseFont: Font
    let textColor: Color

    init(_ content: String, font: Font = .body, color: Color = .primary) {
        self.content = content
        self.baseFont = font
        self.textColor = color
    }

    var body: some View {
        Text(attributedString)
            .textSelection(.enabled)
    }

    // MARK: - Parsing

    private var attributedString: AttributedString {
        let processed = Self.normalizeEmphasis(Self.rewriteBlockMarkers(content))

        guard var parsed = try? AttributedString(
            markdown: processed,
            options: AttributedString.MarkdownParsingOptions(
                // `inlineOnlyPreservingWhitespace` keeps the author's line
                // structure: full-document parsing would collapse the reply's
                // paragraphs and re-flow its lists into its own layout.
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) else {
            return plainFallback
        }

        parsed.foregroundColor = textColor

        for run in parsed.runs {
            parsed[run.range].mergeAttributes(container(for: run))
        }

        return parsed
    }

    /// Style for one parsed run. Bold and italic compose: a `***both***` run
    /// carries both intents and must end up semibold *and* italic, which is why
    /// this accumulates into one font rather than assigning twice.
    private func container(for run: AttributedString.Runs.Run) -> AttributeContainer {
        var container = AttributeContainer()
        let intent = run.inlinePresentationIntent

        if intent?.contains(.code) == true {
            // Inline code is the one run that changes color: it is a different
            // kind of content, not emphasized prose.
            container.font = .system(.body, design: .monospaced)
            container.foregroundColor = AppColors.primaryPurple
            container.backgroundColor = AppColors.primaryPurple.opacity(0.12)
            return container
        }

        var font = baseFont
        if intent?.contains(.stronglyEmphasized) == true {
            // Semibold, not bold: at body size in a chat bubble, `.bold` against
            // `.regular` is a heavier jump than emphasis needs.
            font = font.weight(.semibold)
        }
        if intent?.contains(.emphasized) == true {
            font = font.italic()
        }
        container.font = font
        return container
    }

    private var plainFallback: AttributedString {
        var fallback = AttributedString(content)
        fallback.foregroundColor = textColor
        fallback.font = baseFont
        return fallback
    }

    // MARK: - Emphasis normalization

    /// Delimiter runs this repairs. Ordered longest-first so `**` is consumed
    /// before the `*` pass can bite into it.
    private static let emphasisDelimiters = ["***", "___", "**", "__", "*", "_"]

    /// Pulls whitespace out from between a delimiter and its content, so
    /// `** text **` becomes `**text**` and renders as the emphasis the model
    /// meant. Whitespace is preserved — moved outside the delimiters, not
    /// dropped — so word spacing in the sentence is unchanged.
    ///
    /// Operates per line: an emphasis run cannot span a blank line, and scoping
    /// to a line keeps a stray delimiter from pairing with one paragraphs away.
    static func normalizeEmphasis(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { normalizeLine(String($0)) }
            .joined(separator: "\n")
    }

    private static func normalizeLine(_ line: String) -> String {
        var result = line
        for delimiter in emphasisDelimiters {
            result = normalize(delimiter: delimiter, in: result)
        }
        return result
    }

    /// Rewrites balanced pairs of `delimiter` on one line, moving any inner
    /// padding to the outside.
    ///
    /// Only *pairs* are touched: an odd trailing delimiter is left exactly as
    /// written, because a lone `*` is far more likely to be a literal asterisk
    /// (a footnote marker, a glob, a multiplication sign) than a broken
    /// emphasis run.
    private static func normalize(delimiter: String, in line: String) -> String {
        let segments = line.components(separatedBy: delimiter)
        // n segments = n-1 delimiters. Fewer than 3 segments means no pair.
        guard segments.count >= 3 else { return line }

        var output = segments[0]
        var index = 1

        while index < segments.count {
            // The closing delimiter for this run, if there is one.
            guard index + 1 < segments.count else {
                // Unpaired tail: re-emit verbatim.
                output += delimiter + segments[index]
                break
            }

            let inner = segments[index]
            let trimmed = inner.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                // `****` or `**  **` — no content to emphasize. Emitting a
                // repaired empty run would produce `****`, which the parser
                // then eats as a literal. Leave the source alone.
                output += delimiter + inner + delimiter
            } else {
                let leading = String(inner.prefix { $0 == " " || $0 == "\t" })
                let trailing = String(inner.reversed().prefix { $0 == " " || $0 == "\t" }.reversed())
                output += leading + delimiter + trimmed + delimiter + trailing
            }

            output += segments[index + 1]
            index += 2
        }

        return output
    }

    // MARK: - Block markers

    /// Turns line-level markdown the inline parser ignores into something it can
    /// render: headings become bold runs, list markers become real bullet
    /// glyphs.
    ///
    /// List markers are replaced rather than left in place because `* **Bold**`
    /// gives the parser three `*` runs on one line to pair up, and it reliably
    /// picks the wrong two.
    static func rewriteBlockMarkers(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map(rewriteLine)
            .joined(separator: "\n")
    }

    private static func rewriteLine(_ line: String) -> String {
        if let range = line.range(of: "^\\s*#{1,6}\\s+", options: .regularExpression) {
            let indent = String(line.prefix { $0 == " " })
            // Trim before wrapping. `## Foo  ` used to become `**Foo  **`,
            // whose closing delimiter is not right-flanking, so it rendered as
            // literal asterisks — this renderer's own doing.
            let heading = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            guard !heading.isEmpty else { return line }
            return indent + "**" + heading + "**"
        }

        if let range = line.range(of: "^\\s*[*+-]\\s+", options: .regularExpression) {
            let indent = String(line.prefix { $0 == " " })
            let rest = line[range.upperBound...]
            return indent + bullet(forIndent: indent.count) + " " + rest
        }

        return line
    }

    /// Bullet glyph by depth. Filled → hollow → triangle → dot: each level reads
    /// as subordinate to the one above it at body size.
    private static func bullet(forIndent spaces: Int) -> String {
        switch spaces {
        case 0: return "\u{2022}"        // •
        case 1...3: return "\u{25E6}"    // ◦
        case 4...6: return "\u{2023}"    // ‣
        default: return "\u{00B7}"       // ·
        }
    }
}

// MARK: - Preview

#Preview("Slack delimiters") {
    VStack(alignment: .leading, spacing: Space.lg) {
        // The exact string captured from a live Qwen3 reply.
        MarkdownText("**The Industrial Revolution and Modernization  **", font: AppType.font(.body))
        MarkdownText("## A heading with a trailing hard break  ", font: AppType.font(.body))
        MarkdownText("Well-formed **bold**, *italic*, and `code`.", font: AppType.font(.body))
        MarkdownText("A literal 3 * 4 asterisk should stay literal.", font: AppType.font(.body))
    }
    .padding(Space.xl)
    .frame(width: 420)
    .background(AppColors.background)
}
