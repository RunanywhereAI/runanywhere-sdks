//
//  SmartMarkdownRenderer.swift
//  RunAnywhereAI
//
//  Intelligent router that analyzes content and selects optimal renderer
//  Automatically chooses between inline, code block, or plain text rendering
//

import SwiftUI

/// Smart markdown renderer router
/// Analyzes content complexity → Routes to appropriate renderer
/// No configuration needed - just pass the content!
struct AdaptiveMarkdownText: View {
    let content: String
    let baseFont: Font
    let textColor: Color

    init(_ content: String, font: Font = .body, color: Color = .primary) {
        self.content = content
        self.baseFont = font
        self.textColor = color
    }

    var body: some View {
        let strategy = MarkdownDetector.shared.detectRenderingStrategy(from: content)
        renderContent(with: strategy)
    }

    /// Render content based on detected strategy
    @ViewBuilder
    private func renderContent(with strategy: RenderingStrategy) -> some View {
        switch strategy {
        case .rich:
            // Full markdown with code blocks
            RichMarkdownText(content, font: baseFont, color: textColor)

        case .basic, .light:
            // Standard markdown (bold, italic, headings, inline code)
            MarkdownText(content, font: baseFont, color: textColor)

        case .plain:
            // Plain text - no markdown processing
            Text(content)
                .font(baseFont)
                .foregroundColor(textColor)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Preview
#if DEBUG
struct AdaptiveMarkdownText_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Rich markdown example (code blocks)
                VStack(alignment: .leading) {
                    Text("Rich Markdown (Code Blocks)")
                        .font(.headline)

                    AdaptiveMarkdownText("""
                    #### Stock Market
                    **Definition:** A marketplace
                    ```swift
                    let x = 5
                    ```
                    """)
                }

                Divider()

                // Basic markdown example
                VStack(alignment: .leading) {
                    Text("Basic Markdown")
                        .font(.headline)

                    AdaptiveMarkdownText("""
                    **Stock Market:** A place to trade stocks.
                    It shows *economic health*.
                    """)
                }

                Divider()

                // Plain text example
                VStack(alignment: .leading) {
                    Text("Plain Text")
                        .font(.headline)

                    AdaptiveMarkdownText("This is plain text without any formatting.")
                }
            }
            .padding()
        }
    }
}
#endif
