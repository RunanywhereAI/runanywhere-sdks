import Foundation

/// Handles structured output generation and validation
public class StructuredOutputHandler {
    private let logger = SDKLogger(category: "StructuredOutputHandler")

    public init() {}

    /// Get system prompt for structured output generation
    public func getSystemPrompt<T: Generatable>(for type: T.Type) -> String {
        let schema = type.jsonSchema

        return """
        You are a JSON generator that outputs ONLY valid JSON without any additional text.

        CRITICAL RULES:
        1. Your entire response must be valid JSON that can be parsed
        2. Start with { and end with }
        3. No text before the opening {
        4. No text after the closing }
        5. Follow the provided schema exactly
        6. Include all required fields
        7. Use proper JSON syntax (quotes, commas, etc.)

        Expected JSON Schema:
        \(schema)

        Remember: Output ONLY the JSON object, nothing else.
        """
    }

    /// Build user prompt for structured output (simplified without instructions)
    public func buildUserPrompt<T: Generatable>(
        for type: T.Type,
        content: String
    ) -> String {
        // Return clean user prompt without JSON instructions
        // The instructions are now in the system prompt
        return content
    }

    /// Prepare prompt with structured output instructions
    public func preparePrompt(
        originalPrompt: String,
        config: StructuredOutputConfig
    ) -> String {
        guard config.includeSchemaInPrompt else {
            return originalPrompt
        }

        let schema = config.type.jsonSchema

        // Build structured output instructions with stronger emphasis
        let instructions = """
        CRITICAL INSTRUCTION: You MUST respond with ONLY a valid JSON object. No other text is allowed.

        JSON Schema:
        \(schema)

        RULES:
        1. Start your response with { and end with }
        2. Include NO text before the opening {
        3. Include NO text after the closing }
        4. Follow the schema exactly
        5. All required fields must be present
        6. Use exact field names from the schema
        7. Ensure proper JSON syntax (quotes, commas, etc.)

        IMPORTANT: Your entire response must be valid JSON that can be parsed. Do not include any explanations, comments, or additional text.
        """

        // Combine with system-like instruction at the beginning
        return """
        System: You are a JSON generator. You must output only valid JSON.

        \(originalPrompt)

        \(instructions)

        Remember: Output ONLY the JSON object, nothing else.
        """
    }

    /// Parse and validate structured output from generated text
    public func parseStructuredOutput<T: Generatable>(
        from text: String,
        type: T.Type,
        validationMode: SchemaValidationMode
    ) throws -> T {
        // Extract JSON from the response
        let jsonString = try extractJSON(from: text)

        // Convert to Data
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw StructuredOutputError.invalidJSON("Failed to convert string to data")
        }

        // Decode based on validation mode
        switch validationMode {
        case .strict:
            return try strictDecode(jsonData, type: type)
        case .lenient:
            return try lenientDecode(jsonData, type: type)
        case .bestEffort:
            return try bestEffortDecode(jsonData, type: type)
        }
    }

    /// Extract JSON from potentially mixed text
    private func extractJSON(from text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // First, try to find a complete JSON object
        if let jsonRange = findCompleteJSON(in: trimmed) {
            return String(trimmed[jsonRange])
        }

        // Fallback: Try to find JSON object boundaries
        if let startIndex = trimmed.firstIndex(of: "{"),
           let endIndex = findMatchingBrace(in: trimmed, startingFrom: startIndex) {
            let jsonSubstring = trimmed[startIndex...endIndex]
            return String(jsonSubstring)
        }

        // Try to find JSON array boundaries
        if let startIndex = trimmed.firstIndex(of: "["),
           let endIndex = findMatchingBracket(in: trimmed, startingFrom: startIndex) {
            let jsonSubstring = trimmed[startIndex...endIndex]
            return String(jsonSubstring)
        }

        // If no clear JSON boundaries, check if the entire text might be JSON
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return trimmed
        }

        // Log the text that couldn't be parsed
        logger.error("Failed to extract JSON from text: \(trimmed.prefix(200))...")
        throw StructuredOutputError.extractionFailed("No valid JSON found in the response")
    }

    /// Find a complete JSON object or array in the text
    private func findCompleteJSON(in text: String) -> Range<String.Index>? {
        // Try to parse different segments of the text to find valid JSON
        for startChar in ["{", "["] {
            if let startIndex = text.firstIndex(of: Character(startChar)) {
                var depth = 0
                var inString = false
                var escaped = false

                let endChar = startChar == "{" ? "}" : "]"

                for (offset, char) in text[startIndex...].enumerated() {
                    if escaped {
                        escaped = false
                        continue
                    }

                    if char == "\\" {
                        escaped = true
                        continue
                    }

                    if char == "\"" && !escaped {
                        inString.toggle()
                        continue
                    }

                    if !inString {
                        if String(char) == startChar {
                            depth += 1
                        } else if String(char) == endChar {
                            depth -= 1
                            if depth == 0 {
                                let endIndex = text.index(startIndex, offsetBy: offset)
                                return startIndex..<text.index(after: endIndex)
                            }
                        }
                    }
                }
            }
        }
        return nil
    }

    /// Find matching closing brace for an opening brace
    private func findMatchingBrace(in text: String, startingFrom startIndex: String.Index) -> String.Index? {
        var depth = 0
        var inString = false
        var escaped = false

        for (offset, char) in text[startIndex...].enumerated() {
            if escaped {
                escaped = false
                continue
            }

            if char == "\\" {
                escaped = true
                continue
            }

            if char == "\"" && !escaped {
                inString.toggle()
                continue
            }

            if !inString {
                if char == "{" {
                    depth += 1
                } else if char == "}" {
                    depth -= 1
                    if depth == 0 {
                        return text.index(startIndex, offsetBy: offset)
                    }
                }
            }
        }
        return nil
    }

    /// Find matching closing bracket for an opening bracket
    private func findMatchingBracket(in text: String, startingFrom startIndex: String.Index) -> String.Index? {
        var depth = 0
        var inString = false
        var escaped = false

        for (offset, char) in text[startIndex...].enumerated() {
            if escaped {
                escaped = false
                continue
            }

            if char == "\\" {
                escaped = true
                continue
            }

            if char == "\"" && !escaped {
                inString.toggle()
                continue
            }

            if !inString {
                if char == "[" {
                    depth += 1
                } else if char == "]" {
                    depth -= 1
                    if depth == 0 {
                        return text.index(startIndex, offsetBy: offset)
                    }
                }
            }
        }
        return nil
    }

    /// Strict JSON decoding - fails on any deviation
    private func strictDecode<T: Generatable>(_ data: Data, type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw StructuredOutputError.validationFailed("Strict validation failed: \(error.localizedDescription)")
        }
    }

    /// Lenient JSON decoding - allows extra fields
    private func lenientDecode<T: Generatable>(_ data: Data, type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Note: JSONDecoder already ignores extra fields by default

        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw StructuredOutputError.validationFailed("Lenient validation failed: \(error.localizedDescription)")
        }
    }

    /// Best effort decoding - tries to extract what's possible
    private func bestEffortDecode<T: Generatable>(_ data: Data, type: T.Type) throws -> T {
        // First try normal decoding
        do {
            return try lenientDecode(data, type: type)
        } catch {
            // If that fails, we could implement more sophisticated extraction
            // For now, just throw the error
            throw StructuredOutputError.validationFailed("Best effort validation failed: \(error.localizedDescription)")
        }
    }

    /// Validate that generated text contains valid structured output
    public func validateStructuredOutput(
        text: String,
        config: StructuredOutputConfig
    ) -> StructuredOutputValidation {
        do {
            _ = try extractJSON(from: text)
            return StructuredOutputValidation(
                isValid: true,
                containsJSON: true,
                error: nil
            )
        } catch {
            return StructuredOutputValidation(
                isValid: false,
                containsJSON: false,
                error: error.localizedDescription
            )
        }
    }
}

/// Structured output validation result
public struct StructuredOutputValidation {
    public let isValid: Bool
    public let containsJSON: Bool
    public let error: String?
}

/// Structured output errors
public enum StructuredOutputError: LocalizedError {
    case invalidJSON(String)
    case validationFailed(String)
    case extractionFailed(String)
    case unsupportedType(String)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON(let detail):
            return "Invalid JSON: \(detail)"
        case .validationFailed(let detail):
            return "Validation failed: \(detail)"
        case .extractionFailed(let detail):
            return "Failed to extract structured output: \(detail)"
        case .unsupportedType(let type):
            return "Unsupported type for structured output: \(type)"
        }
    }
}
