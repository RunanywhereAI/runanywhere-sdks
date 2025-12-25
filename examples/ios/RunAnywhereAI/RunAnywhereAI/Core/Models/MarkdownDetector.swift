//
//  MarkdownDetector.swift
//  RunAnywhereAI
//
//  Content-based markdown detection and rendering strategy
//

import Foundation

// MARK: - Markdown Detector

/// Intelligently detects markdown usage in content and recommends rendering strategy
class MarkdownDetector {
    static let shared = MarkdownDetector()

    /// Analyze content and determine the best rendering strategy
    func detectRenderingStrategy(from content: String) -> RenderingStrategy {
        let analysis = analyzeContent(content)

        // Decision tree based on content analysis
        if analysis.hasCodeBlocks {
            // Rich rendering with code block extraction
            return .rich
        } else if analysis.hasRichMarkdown {
            // Basic markdown parsing (bold, italic, headings)
            return .basic
        } else if analysis.hasMinimalMarkdown {
            // Light markdown (just bold/italic)
            return .light
        } else {
            // Plain text
            return .plain
        }
    }

    /// Analyze content for markdown patterns
    private func analyzeContent(_ content: String) -> ContentAnalysis {
        var analysis = ContentAnalysis()

        // Detect code blocks (```language)
        analysis.hasCodeBlocks = content.contains("```")

        // Detect headings (#### text) - must be 1-6 # followed by space
        let headingCount = content.components(separatedBy: .newlines)
            .filter { line in
                // Trim leading spaces
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Must start with 1-6 # characters followed by a space
                guard trimmed.hasPrefix("#") else { return false }
                let hashes = trimmed.prefix(while: { $0 == "#" })
                return hashes.count >= 1 && hashes.count <= 6
                    && trimmed.count > hashes.count
                    && trimmed[trimmed.index(trimmed.startIndex, offsetBy: hashes.count)] == " "
            }.count
        analysis.headingCount = headingCount

        // Detect bold (**text**)
        let boldParts = content.components(separatedBy: "**")
        analysis.boldCount = max(0, (boldParts.count - 1) / 2)

        // Detect inline code (`code`)
        let codeParts = content.components(separatedBy: "`")
        analysis.inlineCodeCount = max(0, (codeParts.count - 1) / 2)

        // Detect lists (only count lines that start with list markers after trimming leading spaces)
        let listCount = content.components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") ||
                       trimmed.range(of: "^\\d+\\.\\s", options: .regularExpression) != nil
            }.count
        analysis.listCount = listCount

        // Calculate markdown richness
        let markdownScore = Double(analysis.headingCount) * 0.5 +
                           Double(analysis.boldCount) * 0.3 +
                           Double(analysis.inlineCodeCount) * 0.2 +
                           Double(analysis.listCount) * 0.3

        // Classify based on score
        if markdownScore > 3.0 {
            analysis.hasRichMarkdown = true
        } else if markdownScore > 1.0 {
            analysis.hasMinimalMarkdown = true
        }

        return analysis
    }
}

// MARK: - Content Analysis

struct ContentAnalysis {
    var hasCodeBlocks: Bool = false
    var hasRichMarkdown: Bool = false
    var hasMinimalMarkdown: Bool = false
    var headingCount: Int = 0
    var boldCount: Int = 0
    var inlineCodeCount: Int = 0
    var listCount: Int = 0
}

// MARK: - Rendering Strategy

enum RenderingStrategy {
    case rich       // Full markdown with code blocks
    case basic      // Standard markdown (headings, bold, italic, inline code)
    case light      // Minimal markdown (just bold/italic)
    case plain      // No markdown processing

    var shouldExtractCodeBlocks: Bool {
        return self == .rich
    }

    var shouldParseMarkdown: Bool {
        return self != .plain
    }

    var shouldStyleHeadings: Bool {
        return self == .rich || self == .basic
    }
}
