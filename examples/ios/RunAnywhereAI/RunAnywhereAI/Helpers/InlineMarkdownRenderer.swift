//
//  InlineMarkdownRenderer.swift
//  RunAnywhereAI
//
//  Inline runs *within* one block: bold, italic, inline code, links, and
//  strikethrough, via `AttributedString`'s CommonMark parser.
//
//  Block structure — headings, lists, quotes, rules, fences — is not this file's
//  job. `MarkdownBlockParser` has already split the reply and handed each block
//  down separately, which is why the heading- and bullet-rewriting that used to
//  live here is gone: it existed only because there was no block layer, and it
//  was actively harmful (it wrapped heading text in `**…**`, and a heading ending
//  in a markdown hard break became `**Foo  **`, whose closing delimiter is not
//  right-flanking, so it rendered as literal asterisks — this renderer's own
//  doing).
//
//  ## Why there is still a normalization pass
//
//  CommonMark requires a closing `**` to be *right-flanking* — no whitespace
//  between the last content character and the delimiter. Small local models
//  routinely emit `**Heading  **`, and the parser correctly refuses it, so the
//  reader sees literal asterisks mid-reply. Verified: for
//  `"**The Industrial Revolution and Modernization  **"` the parser reports no
//  `.stronglyEmphasized` run and returns the source text unchanged.
//
//  That is a presentation repair: nothing here changes what the model said, it
//  only makes emphasis the model clearly intended actually render as emphasis.
//
//  ## What is deliberately not repaired
//
//  An unterminated delimiter stays literal. `**start` renders as `**start` until
//  its closer arrives, which is precisely what stops a streaming reply from
//  flickering between plain and bold as tokens land.
//

import SwiftUI

/// Inline markdown for one block of text: emphasis, code spans, links,
/// strikethrough.
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
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Parsing

    private var attributedString: AttributedString {
        guard var parsed = try? AttributedString(
            markdown: Self.normalizeEmphasis(content),
            options: AttributedString.MarkdownParsingOptions(
                // `inlineOnlyPreservingWhitespace` keeps the block's own line
                // structure. Full-document parsing would re-flow it into
                // Foundation's layout and drop the single newlines a model uses
                // for a wrapped sentence or an address.
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

    /// Style for one parsed run.
    ///
    /// Intents compose: `***both***` carries strong *and* emphasized and must end
    /// up semibold *and* italic, and `~~*x*~~` carries strikethrough as well —
    /// which is why this accumulates into one font and one container rather than
    /// returning early per intent.
    private func container(for run: AttributedString.Runs.Run) -> AttributeContainer {
        var container = AttributeContainer()
        let intent = run.inlinePresentationIntent

        if intent?.contains(.code) == true {
            // A code span is different *content*, not emphasized prose, so it is
            // the one run that changes color. Its own delimiters win over any
            // emphasis markers inside it: `` `**not bold**` `` renders literally,
            // which the parser already guarantees.
            container.font = AppType.font(.mono)
            container.foregroundColor = AppColors.brandInk
            container.backgroundColor = AppColors.brand.opacity(0.10)
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

        if intent?.contains(.strikethrough) == true {
            container.strikethroughStyle = .single
        }

        if run.link != nil {
            // Links get the brand color and an underline. Both, not one: color
            // alone fails a reader who cannot distinguish it, and this is the
            // only run type that is actionable.
            container.foregroundColor = AppColors.brand
            container.underlineStyle = .single
        }

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

    /// Repairs a *closing* delimiter that whitespace has pushed out of
    /// right-flanking position, so `**text  **` becomes `**text**  ` and renders
    /// as the emphasis the model meant. Whitespace is preserved — moved outside
    /// the delimiters, not dropped — so word spacing is unchanged.
    ///
    /// ## Why only the closing side
    ///
    /// An earlier version also pulled whitespace off the *opening* side, turning
    /// `** text **` into `**text**`. That looked more thorough and was wrong: a
    /// delimiter followed by a space is, per CommonMark's left-flanking rule,
    /// deliberately *not* an opener, and that rule is the only thing protecting
    /// arithmetic and globs. Verified failure: `5 * 3 * 2` was rewritten to
    /// `5  *3*  2` and rendered with an italic 3. Requiring the opener to be
    /// left-flanking already is what makes `rm *.txt`, `a * b`, `2*3`,
    /// `2 * 3 = 6 and 4 * 5 = 20` and `get_user_name` all stay literal.
    ///
    /// So the contract is narrow on purpose: the model must have written a valid
    /// opener. Only its closer gets un-slacked.
    ///
    /// Operates per line: an emphasis run cannot span a blank line, and scoping
    /// to a line keeps a stray delimiter from pairing with one paragraphs away.
    static func normalizeEmphasis(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { normalizeLine(String($0)) }
            .joined(separator: "\n")
    }

    /// Normalizes the prose on a line while leaving code spans untouched.
    ///
    /// Code spans have to be carved out first, because a `*` inside one is
    /// literal but is still just a character to `components(separatedBy:)`.
    /// Verified failure: on
    /// `` "Literal: 5 * 3 * 2, `rm *.txt`, a * b" `` the `*` in `` `rm *.txt` ``
    /// paired with the `*` in `a * b`, and the line was rewritten to `a*  b` —
    /// a code span silently reached out and corrupted prose two clauses away.
    ///
    /// This is the same precedence the web renderer applies (code spans win over
    /// the emphasis markers they contain) and the same the parser applies to
    /// `` `**not bold**` ``.
    private static func normalizeLine(_ line: String) -> String {
        var result = ""
        var rest = Substring(line)

        while let open = rest.firstIndex(of: "`") {
            let afterOpen = rest.index(after: open)
            guard let close = rest[afterOpen...].firstIndex(of: "`") else { break }
            // Prose before the span gets normalized; the span itself is copied
            // through verbatim, delimiters included.
            result += normalizeProse(String(rest[rest.startIndex..<open]))
            result += rest[open...close]
            rest = rest[rest.index(after: close)...]
        }

        return result + normalizeProse(String(rest))
    }

    private static func normalizeProse(_ fragment: String) -> String {
        var result = fragment
        for delimiter in emphasisDelimiters {
            result = normalize(delimiter: delimiter, in: result)
        }
        return result
    }

    /// Rewrites balanced pairs of `delimiter` on one line, moving any inner
    /// trailing padding to the outside.
    ///
    /// Only *pairs* are touched: an odd trailing delimiter is left exactly as
    /// written, because a lone `*` is far more likely to be a literal asterisk
    /// (a footnote marker, a glob, a multiplication sign) than a broken emphasis
    /// run — and because during streaming it is simply an opener whose closer has
    /// not arrived yet.
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
            let opensWithSpace = inner.first == " " || inner.first == "\t"

            if inner.trimmingCharacters(in: .whitespaces).isEmpty || opensWithSpace {
                // Either no content to emphasize (`****`, `**  **`), or the
                // opening delimiter is not left-flanking so it was never an
                // opener at all (`5 * 3 * 2`). Both re-emit verbatim.
                output += delimiter + inner + delimiter
            } else {
                let content = String(inner.reversed().drop { $0 == " " || $0 == "\t" }.reversed())
                let trailing = String(inner.dropFirst(content.count))
                output += delimiter + content + delimiter + trailing
            }

            output += segments[index + 1]
            index += 2
        }

        return output
    }
}

// MARK: - Preview

#Preview("Inline runs") {
    VStack(alignment: .leading, spacing: Space.lg) {
        // The exact string captured from a live Qwen3 reply.
        MarkdownText("**The Industrial Revolution and Modernization  **", font: AppType.font(.body))
        MarkdownText("Well-formed **bold**, *italic*, ***both***, and `code`.", font: AppType.font(.body))
        MarkdownText("A ~~struck~~ run and a [link](https://runanywhere.ai).", font: AppType.font(.body))
        MarkdownText("Literal: 5 * 3 * 2, `rm *.txt`, a * b, get_user_name.", font: AppType.font(.body))
        MarkdownText("Mid-stream: **start", font: AppType.font(.body))
    }
    .padding(Space.xl)
    .frame(width: 420)
    .background(AppColors.background)
}
