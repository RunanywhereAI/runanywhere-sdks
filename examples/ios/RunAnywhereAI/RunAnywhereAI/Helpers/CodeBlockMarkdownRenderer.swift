//
//  CodeBlockMarkdownRenderer.swift
//  RunAnywhereAI
//
//  Specialized renderer for markdown with code blocks (```language)
//  Extracts code blocks → Renders in styled containers with copy button
//  Delegates text portions to InlineMarkdownRenderer
//

import SwiftUI

/// Code block markdown renderer
/// Parses ```language blocks and renders them with syntax highlighting UI
/// Text between code blocks is rendered using InlineMarkdownRenderer
struct RichMarkdownText: View {
    let content: String
    let baseFont: Font
    let textColor: Color

    init(_ content: String, font: Font = .body, color: Color = .primary) {
        self.content = content
        self.baseFont = font
        self.textColor = color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(parseContent().enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let text):
                    MarkdownText(text, font: baseFont, color: textColor)
                case .codeBlock(let code, let language):
                    CodeBlockView(code: code, language: language)
                }
            }
        }
    }

    /// Parse content into text and code blocks
    private func parseContent() -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        var currentText = ""
        var inCodeBlock = false
        var currentCode = ""
        var currentLanguage: String? = nil

        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            // Detect code block markers - must be at start of line (trimmed)
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if trimmedLine.hasPrefix("```") {
                if inCodeBlock {
                    // End of code block - only if it's exactly ``` (or ```language on same line as start)
                    if !currentCode.isEmpty {
                        blocks.append(.codeBlock(currentCode, currentLanguage))
                        currentCode = ""
                        currentLanguage = nil
                    }
                    inCodeBlock = false
                } else {
                    // Start of code block
                    if !currentText.isEmpty {
                        blocks.append(.text(currentText))
                        currentText = ""
                    }
                    // Extract language if specified (everything after ```)
                    let langPart = trimmedLine.dropFirst(3).trimmingCharacters(in: .whitespaces)
                    currentLanguage = langPart.isEmpty ? nil : langPart
                    inCodeBlock = true
                }
            } else {
                if inCodeBlock {
                    currentCode += line + "\n"
                } else {
                    currentText += line + "\n"
                }
            }
        }

        // Add remaining content (handle unclosed blocks gracefully)
        if !currentText.isEmpty {
            blocks.append(.text(currentText))
        }
        if !currentCode.isEmpty {
            // Trim only trailing newlines, preserve code formatting
            let trimmedCode = currentCode.trimmingCharacters(in: .newlines)
            blocks.append(.codeBlock(trimmedCode, currentLanguage))
        }

        return blocks
    }
}

// MARK: - Content Block Types

enum ContentBlock {
    case text(String)
    case codeBlock(String, String?) // code, language
}

// MARK: - Code Block View

struct CodeBlockView: View {
    let code: String
    let language: String?
    @State private var isCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with language and copy button
            HStack {
                // Language badge
                if let lang = language {
                    Text(lang.uppercased())
                        .font(.system(.caption2, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundColor(AppColors.textWhite)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(syntaxColor(for: lang))
                        )
                }

                Spacer()

                // Copy button
                Button(action: copyToClipboard) {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                        Text(isCopied ? "Copied!" : "Copy")
                            .font(.caption)
                    }
                    .foregroundColor(isCopied ? AppColors.statusGreen : AppColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppColors.backgroundGray6.opacity(0.5))

            // Code content with syntax highlighting
            ScrollView(.horizontal, showsIndicators: false) {
                Text(highlightedCode)
                    .font(.system(.body, design: .monospaced))
                    .padding(12)
                    .textSelection(.enabled)
            }
            .background(Color(red: 0.97, green: 0.97, blue: 0.98))
        }
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(AppColors.borderMedium, lineWidth: 1)
        )
    }

    /// Simple syntax highlighting using AttributedString
    private var highlightedCode: AttributedString {
        // For now, just use monospace font with basic coloring
        // Advanced syntax highlighting can be added later with a dedicated library
        var result = AttributedString(code)

        // Apply monospace font and code color
        result.font = .system(.body, design: .monospaced)
        result.foregroundColor = Color(red: 0.2, green: 0.2, blue: 0.3)

        return result
    }

    /// Get color for language badge
    private func syntaxColor(for language: String) -> Color {
        switch language.lowercased() {
        case "swift": return Color(red: 0.95, green: 0.38, blue: 0.21)
        case "python", "py": return Color(red: 0.25, green: 0.53, blue: 0.76)
        case "javascript", "js", "typescript", "ts": return Color(red: 0.94, green: 0.76, blue: 0.16)
        case "kotlin", "kt": return Color(red: 0.49, green: 0.40, blue: 0.93)
        case "java": return Color(red: 0.87, green: 0.27, blue: 0.22)
        default: return AppColors.primaryPurple
        }
    }

    /// Copy code to clipboard
    private func copyToClipboard() {
        #if os(iOS)
        UIPasteboard.general.string = code
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        #endif

        withAnimation {
            isCopied = true
        }

        // Reset after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }
}

// MARK: - Preview
#if DEBUG
struct RichMarkdownText_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RichMarkdownText("""
                Here's a simple Swift program:

                ```swift
                import Foundation

                func sumTwoIntegers(_ a: Int, _ b: Int) -> Int {
                    return a + b  // Return sum
                }

                let num1 = 5
                let num2 = 10
                let result = sumTwoIntegers(num1, num2)
                print("The sum is \\(result)")
                ```

                This program defines a function **sumTwoIntegers** that takes two parameters.
                """)
                .padding()
            }
        }
    }
}
#endif
