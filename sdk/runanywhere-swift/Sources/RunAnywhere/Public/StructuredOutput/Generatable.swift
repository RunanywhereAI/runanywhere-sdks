import Foundation

/// Protocol for types that can be generated as structured output from LLMs
public protocol Generatable: Codable {
    /// The JSON schema for this type
    static var jsonSchema: String { get }
}

/// Extension to provide default JSON schema generation
public extension Generatable {
    /// Generate a basic JSON schema from the type
    /// Note: In a full implementation, this would be replaced by a macro
    static var jsonSchema: String {
        // This is a simplified version - the full implementation would use Swift macros
        return """
        {
          "type": "object",
          "additionalProperties": false
        }
        """
    }
}

/// Structured output configuration
public struct StructuredOutputConfig: Sendable {
    /// The type to generate
    public let type: Generatable.Type

    /// Whether to include schema in prompt
    public let includeSchemaInPrompt: Bool

    public init(
        type: Generatable.Type,
        includeSchemaInPrompt: Bool = true
    ) {
        self.type = type
        self.includeSchemaInPrompt = includeSchemaInPrompt
    }
}
