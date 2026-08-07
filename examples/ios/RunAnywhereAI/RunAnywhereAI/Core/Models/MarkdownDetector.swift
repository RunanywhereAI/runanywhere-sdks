//
//  MarkdownDetector.swift
//  RunAnywhereAI
//
//  Content-based markdown detection and rendering strategy.
//
//  Routing is on *presence*, not on a weighted score. The previous scoring gate
//  (`headings*0.5 + bold*0.3 + code*0.2 + lists*0.3 > 1.0`) meant a reply
//  containing one `**bold**` scored 0.3, fell through every branch, and rendered
//  as `.plain` — so the user read literal asterisks. It took four separate bolds
//  before any markdown was parsed at all. A single markdown construct is not
//  "not enough markdown to bother"; it is markdown.
//

import Foundation

// MARK: - Markdown Detector

/// Detects markdown usage in content and recommends a rendering strategy.
class MarkdownDetector {
    static let shared = MarkdownDetector()

    /// Analyze content and determine the best rendering strategy
    func detectRenderingStrategy(from content: String) -> RenderingStrategy {
        let analysis = analyzeContent(content)

        if analysis.hasCodeBlocks {
            // Fenced code needs the block extractor, not inline parsing.
            return .rich
        }
        if analysis.hasBlockMarkdown {
            // Headings / lists: block structure the inline renderer rewrites into
            // bullets and bold runs.
            return .basic
        }
        if analysis.hasInlineMarkdown {
            // Emphasis or inline code only.
            return .light
        }
        return .plain
    }

    // Compiled once. Recompiling per call was a hot-path cost: the streaming tail
    // bubble re-runs detection on every token, so a per-render NSRegularExpression
    // build ran once per token over the whole message.
    //
    // `[^\s*]` on the opening side rejects `** ` (a stray separator) while still
    // matching `**a**`. The underscore variants cover models that emit `__bold__`
    // and `_italic_`.
    private static let inlinePattern = [
        "\\*\\*[^\\s*][^*]*\\*\\*",                     // **bold**
        "__[^\\s_][^_]*__",                             // __bold__
        "(?<![\\*\\w])\\*[^\\s*][^*\\n]*\\*(?![\\*\\w])", // *italic*
        "(?<![_\\w])_[^\\s_][^_\\n]*_(?![_\\w])",       // _italic_
        "`[^`\\n]+`",                                   // `code`
        "\\[[^\\]\\n]+\\]\\([^)\\s]+\\)"                // [link](url)
    ].joined(separator: "|")

    private static let inlineRegex = try? NSRegularExpression(pattern: inlinePattern)

    private func analyzeContent(_ content: String) -> ContentAnalysis {
        var analysis = ContentAnalysis()

        // Fenced code. A single opening fence counts: a streaming reply shows its
        // fence long before its closer, and flipping strategies mid-stream would
        // re-lay out the whole transcript.
        analysis.hasCodeBlocks = content.contains("```")

        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            // Heading: 1–6 `#` then a space.
            if trimmed.hasPrefix("#") {
                let hashes = trimmed.prefix { $0 == "#" }
                if hashes.count <= 6, trimmed.dropFirst(hashes.count).hasPrefix(" ") {
                    analysis.hasBlockMarkdown = true
                }
            }

            // Bullet or ordered list.
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ")
                || trimmed.range(of: "^\\d+[.)]\\s", options: .regularExpression) != nil {
                analysis.hasBlockMarkdown = true
            }

            // Blockquote and thematic break also read as structure.
            if trimmed.hasPrefix("> ") || trimmed == "---" || trimmed == "***" {
                analysis.hasBlockMarkdown = true
            }

            if analysis.hasBlockMarkdown { break }
        }

        if !analysis.hasBlockMarkdown {
            let range = NSRange(content.startIndex..., in: content)
            analysis.hasInlineMarkdown = Self.inlineRegex?
                .firstMatch(in: content, range: range) != nil
        }

        return analysis
    }
}

// MARK: - Content Analysis

struct ContentAnalysis {
    /// A triple-backtick fence is present.
    var hasCodeBlocks: Bool = false
    /// Headings, lists, blockquotes, or rules — line-level structure.
    var hasBlockMarkdown: Bool = false
    /// Emphasis, inline code, or links — run-level formatting only.
    var hasInlineMarkdown: Bool = false
}

// MARK: - Rendering Strategy

enum RenderingStrategy {
    case rich       // Full markdown with code blocks
    case basic      // Standard markdown (headings, bold, italic, inline code)
    case light      // Minimal markdown (just bold/italic)
    case plain      // No markdown processing

    var shouldExtractCodeBlocks: Bool {
        self == .rich
    }

    var shouldParseMarkdown: Bool {
        self != .plain
    }

    var shouldStyleHeadings: Bool {
        self == .rich || self == .basic
    }
}
