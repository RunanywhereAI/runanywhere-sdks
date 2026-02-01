//
//  String+Markdown.swift
//  RunAnywhereAI
//
//  Extension to strip markdown formatting for TTS
//

import Foundation

extension String {
    /// Looks up the proper model name from ModelListViewModel if this is a model ID
    @MainActor
    func modelNameFromID() -> String {
        // Try to find the model in the available models list
        if let model = ModelListViewModel.shared.availableModels.first(where: { $0.id == self }) {
            return model.name
        }

        // If not found, return as-is (might already be a proper name)
        return self
    }

    /// Shortens model name by removing parenthetical info and limiting length
    @MainActor
    func shortModelName(maxLength: Int = 15) -> String {
        // First look up the proper name if this is an ID
        let displayName = self.modelNameFromID()

        // Remove content in parentheses
        var cleaned = displayName.replacingOccurrences(
            of: "\\s*\\([^)]*\\)",
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)

        // If still too long, truncate and add ellipsis
        if cleaned.count > maxLength {
            cleaned = String(cleaned.prefix(maxLength - 1)) + "…"
        }

        return cleaned
    }

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
