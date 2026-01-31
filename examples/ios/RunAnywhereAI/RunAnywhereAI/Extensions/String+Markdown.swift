//
//  String+Markdown.swift
//  RunAnywhereAI
//
//  Extension to strip markdown formatting for TTS
//

import Foundation

extension String {
    /// Remove markdown formatting for clean text-to-speech
    /// Removes: **, *, _, `, ##, code blocks, etc.
    func strippingMarkdown() -> String {
        var text = self

        // Remove code blocks (```...```)
        text = text.replacingOccurrences(
            of: "```[^`]*```",
            with: "",
            options: .regularExpression
        )

        // Remove inline code (`...`)
        text = text.replacingOccurrences(
            of: "`([^`]+)`",
            with: "$1",
            options: .regularExpression
        )

        // Remove bold (**text** or __text__)
        text = text.replacingOccurrences(
            of: "\\*\\*([^*]+)\\*\\*",
            with: "$1",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: "__([^_]+)__",
            with: "$1",
            options: .regularExpression
        )

        // Remove italic (*text* or _text_)
        text = text.replacingOccurrences(
            of: "\\*([^*]+)\\*",
            with: "$1",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: "_([^_]+)_",
            with: "$1",
            options: .regularExpression
        )

        // Remove headings (# ## ### etc)
        text = text.replacingOccurrences(
            of: "^#{1,6}\\s+",
            with: "",
            options: .regularExpression
        )

        // Remove links [text](url) -> text
        text = text.replacingOccurrences(
            of: "\\[([^\\]]+)\\]\\([^)]+\\)",
            with: "$1",
            options: .regularExpression
        )

        // Remove images ![alt](url)
        text = text.replacingOccurrences(
            of: "!\\[[^\\]]*\\]\\([^)]+\\)",
            with: "",
            options: .regularExpression
        )

        // Clean up multiple spaces
        text = text.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
