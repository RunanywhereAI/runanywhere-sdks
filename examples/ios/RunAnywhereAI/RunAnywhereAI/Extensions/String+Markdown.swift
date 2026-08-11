//
//  String+Markdown.swift
//  RunAnywhereAI
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
        let withoutParens = displayName.replacingOccurrences(
            of: "\\s*\\([^)]*\\)",
            with: "",
            options: .regularExpression
        )
        var cleaned = withoutParens.trimmingCharacters(in: .whitespaces)

        // If still too long, truncate and add ellipsis
        if cleaned.count > maxLength {
            cleaned = String(cleaned.prefix(maxLength - 1)) + "…"
        }

        return cleaned
    }
}
