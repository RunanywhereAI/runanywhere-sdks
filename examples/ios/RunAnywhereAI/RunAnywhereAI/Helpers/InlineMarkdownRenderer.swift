//
//  InlineMarkdownRenderer.swift
//  RunAnywhereAI
//
//  Renders inline markdown: **bold**, *italic*, `code`, headings, lists
//  Uses AttributedString for native iOS markdown parsing
//  Pre-processes to fix markdown conflicts (list bullets + bold text)
//

import SwiftUI

/// Inline markdown renderer for text with basic formatting
/// Handles: bold, italic, inline code, headings (as bold), hierarchical lists
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
            .textSelection(.enabled) // Allow text selection
    }

    /// Convert markdown string to AttributedString with custom styling
    private var attributedString: AttributedString {
        do {
            // Pre-process to fix list markers conflicting with bold syntax
            // Replace "* **text**" with "• **text**" to avoid markdown conflicts
            let processedContent = preprocessListMarkers(content)

            // Parse with inlineOnly to preserve text structure
            // This prevents numbers and periods from being interpreted as lists
            var attributedString = try AttributedString(
                markdown: processedContent,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            )

            // Apply custom styling to the entire string
            attributedString.foregroundColor = textColor

            // Enhanced styling for specific markdown elements
            for run in attributedString.runs {
                var container = AttributeContainer()

                // Inline presentation intent (bold, italic, code)
                if let inlineIntent = run.inlinePresentationIntent {
                    // Bold text (**text**) - make it semibold
                    if inlineIntent.contains(.stronglyEmphasized) {
                        container.font = fontToUIFont(baseFont.weight(.semibold))
                    }

                    // Italic text (*text*) - make it italic
                    if inlineIntent.contains(.emphasized) {
                        container.font = fontToUIFont(baseFont.italic())
                    }

                    // Code (`code`) - monospaced font with background
                    if inlineIntent.contains(.code) {
                        container.font = .system(.body, design: .monospaced)
                        container.foregroundColor = .purple
                        container.backgroundColor = Color.purple.opacity(0.1)
                    }
                }

                // Apply base font if no specific styling was set
                if container.font == nil {
                    container.font = fontToUIFont(baseFont)
                }

                // Apply custom styling
                // Note: AttributedString's markdown parser already handles bold+italic merging correctly
                attributedString[run.range].mergeAttributes(container)
            }

            return attributedString

        } catch {
            // Fallback to plain text if markdown parsing fails
            var fallback = AttributedString(content)
            fallback.foregroundColor = textColor
            fallback.font = fontToUIFont(baseFont)
            return fallback
        }
    }

    /// Preprocess list markers and headings to avoid conflicts with bold syntax
    private func preprocessListMarkers(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        let processedLines = lines.map { line -> String in
            // 1. Remove heading symbols (###) and make text bold
            if let range = line.range(of: "^\\s*#{1,6}\\s+", options: .regularExpression) {
                let leadingSpaces = line.prefix(while: { $0 == " " })
                let headingText = line[range.upperBound...]

                // Make heading text bold
                return String(leadingSpaces) + "**\(headingText)**"
            }

            // 2. Replace markdown list markers (* or -) with hierarchical bullet points
            // This prevents conflicts when list items contain bold text: "* **Bold**"
            if let range = line.range(of: "^\\s*[*-]\\s+", options: .regularExpression) {
                let leadingSpaces = String(line.prefix(while: { $0 == " " }))
                let restOfLine = line[range.upperBound...]

                // Determine bullet style based on indentation level
                // Support both 2-space and 4-space indents (common markdown standards)
                let spaceCount = leadingSpaces.count
                let indentLevel: Int
                if spaceCount == 0 {
                    indentLevel = 0
                } else if spaceCount <= 3 {
                    indentLevel = 1  // 1-3 spaces = level 1
                } else if spaceCount <= 6 {
                    indentLevel = 2  // 4-6 spaces = level 2
                } else {
                    indentLevel = 3  // 7+ spaces = level 3+
                }

                let bullet: String
                switch indentLevel {
                case 0:
                    bullet = "•"   // Main level: filled bullet (U+2022)
                case 1:
                    bullet = "◦"   // Second level: hollow bullet (U+25E6)
                case 2:
                    bullet = "‣"   // Third level: triangular bullet (U+2023) - cleaner than squares
                default:
                    bullet = "·"   // Deeper levels: middle dot (U+00B7) - subtle
                }

                // Replace with appropriate bullet point
                return leadingSpaces + bullet + " " + restOfLine
            }

            return line
        }

        return processedLines.joined(separator: "\n")
    }

    /// Convert SwiftUI Font to UIKit/AppKit font
    private func fontToUIFont(_ font: Font) -> Font {
        // SwiftUI Font is already the right type for AttributedString
        return font
    }
}
