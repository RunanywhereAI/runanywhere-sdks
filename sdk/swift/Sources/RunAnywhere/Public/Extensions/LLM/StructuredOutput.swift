// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import Foundation

/// Produces a Decodable value from an LLM by instructing it to emit JSON
/// conforming to a schema. Works with any ChatSession — no engine-side
/// grammar constraint required. For guaranteed-valid JSON, pair with a
/// grammar-supporting engine (llama.cpp via `ra_llm_structured_output`
/// once that native primitive lands).
///
///     struct Person: Codable { let name: String; let age: Int }
///     let person: Person = try await StructuredOutput.generate(
///         from: chat,
///         query: "Generate a random person",
///         schema: Person.self)
public enum StructuredOutput {

    public enum Error: Swift.Error {
        case noJSONFound(String)
        case decodeFailed(String, underlying: Swift.Error)
    }

    /// Generates a value of type `T` by prompting the model to emit JSON
    /// matching a schema. Retries up to `maxAttempts` on parse failure.
    public static func generate<T: Decodable>(
        from chat: ChatSession,
        query: String,
        schema: T.Type,
        maxAttempts: Int = 3
    ) async throws -> T {
        let schemaHint = jsonSchemaHint(for: schema)
        let fullQuery = """
        \(query)

        Respond with a JSON object matching this schema:
        \(schemaHint)

        Respond ONLY with valid JSON. No prose before or after. No markdown
        code fences. Just the JSON object.
        """

        var lastError: Swift.Error?
        for _ in 0..<maxAttempts {
            do {
                let text = try await chat.generateText(messages: [.user(fullQuery)])
                let json = try extractJSON(from: text)
                let data = json.data(using: .utf8) ?? Data()
                return try JSONDecoder().decode(schema, from: data)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? Error.noJSONFound("all retries failed")
    }

    /// Extract the first top-level JSON object from arbitrary text.
    /// Strips markdown fences, prose, and trailing whitespace.
    internal static func extractJSON(from text: String) throws -> String {
        // Try fenced ```json ... ``` first using NSRegularExpression (supports multiline).
        let fencePattern = #"```(?:json)?\s*([\s\S]*?)```"#
        if let regex = try? NSRegularExpression(pattern: fencePattern, options: []),
           let match = regex.firstMatch(in: text, options: [],
                                         range: NSRange(text.startIndex..., in: text)),
           match.numberOfRanges > 1,
           let range = Range(match.range(at: 1), in: text)
        {
            let captured = String(text[range])
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if captured.hasPrefix("{") || captured.hasPrefix("[") {
                return captured
            }
        }
        // Otherwise find the first balanced { … } span
        guard let start = text.firstIndex(of: "{") else {
            throw Error.noJSONFound("no '{' in response: \(text)")
        }
        var depth = 0
        var inString = false
        var escaped = false
        var end: String.Index = start
        for idx in text.indices[start...] {
            let c = text[idx]
            if escaped { escaped = false; continue }
            if c == "\\" { escaped = true; continue }
            if c == "\"" { inString.toggle(); continue }
            if inString { continue }
            if c == "{" { depth += 1 }
            else if c == "}" {
                depth -= 1
                if depth == 0 { end = idx; break }
            }
        }
        guard depth == 0 else {
            throw Error.noJSONFound("unbalanced braces in: \(text)")
        }
        return String(text[start...end])
    }

    /// Emits a minimal schema description for the type. Best-effort —
    /// doesn't introspect the Decodable metadata at runtime (Swift doesn't
    /// expose that). Call sites with strict schema requirements should
    /// pass `queryBuilder:` and construct their own schema string.
    internal static func jsonSchemaHint<T>(for type: T.Type) -> String {
        "{ ... (infer fields from the request above, match Swift type \(type)) }"
    }
}
