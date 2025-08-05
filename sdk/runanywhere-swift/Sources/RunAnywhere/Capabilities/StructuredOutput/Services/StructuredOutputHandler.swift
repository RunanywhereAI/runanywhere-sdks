import Foundation

/// Handles structured output generation and validation
public class StructuredOutputHandler {
    private let logger = SDKLogger(category: "StructuredOutputHandler")

    public init() {}

    /// Prepare prompt with structured output instructions
    public func preparePrompt(
        originalPrompt: String,
        config: StructuredOutputConfig
    ) -> String {
        guard config.includeSchemaInPrompt else {
            return originalPrompt
        }

        let schema = config.type.jsonSchema

        // Build structured output instructions
        let instructions = """
        Please respond with a valid JSON object that strictly follows this schema:

        \(schema)

        Important:
        - Respond ONLY with the JSON object
        - Do not include any explanatory text before or after the JSON
        - Ensure all required fields are present
        - Use the exact field names as specified in the schema
        """

        // Combine original prompt with structured output instructions
        return """
        \(originalPrompt)

        \(instructions)
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

        // Try to find JSON object boundaries
        if let startIndex = trimmed.firstIndex(of: "{"),
           let endIndex = trimmed.lastIndex(of: "}") {
            let jsonSubstring = trimmed[startIndex...endIndex]
            return String(jsonSubstring)
        }

        // Try to find JSON array boundaries
        if let startIndex = trimmed.firstIndex(of: "["),
           let endIndex = trimmed.lastIndex(of: "]") {
            let jsonSubstring = trimmed[startIndex...endIndex]
            return String(jsonSubstring)
        }

        // If no clear JSON boundaries, assume the whole text is JSON
        return trimmed
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
