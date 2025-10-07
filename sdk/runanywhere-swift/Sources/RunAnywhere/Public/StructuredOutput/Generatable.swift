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
public struct StructuredOutputConfig {
    /// The type to generate
    public let type: Generatable.Type

    /// Validation mode
    public let validationMode: SchemaValidationMode

    /// Generation strategy
    public let strategy: StructuredOutputStrategy

    /// Whether to include schema in prompt
    public let includeSchemaInPrompt: Bool

    public init(
        type: Generatable.Type,
        validationMode: SchemaValidationMode = .strict,
        strategy: StructuredOutputStrategy = .automatic,
        includeSchemaInPrompt: Bool = true
    ) {
        self.type = type
        self.validationMode = validationMode
        self.strategy = strategy
        self.includeSchemaInPrompt = includeSchemaInPrompt
    }
}

/// Schema validation modes
public enum SchemaValidationMode {
    /// Fail if output doesn't match schema exactly
    case strict

    /// Allow minor deviations (extra fields, etc)
    case lenient

    /// Extract what's possible from the output
    case bestEffort
}

/// Structured output generation strategies
public enum StructuredOutputStrategy {
    /// Let the SDK choose the best strategy
    case automatic

    /// Include JSON schema in the prompt
    case jsonSchemaInPrompt

    /// Use framework-specific constraints (if supported)
    case frameworkConstraints

    /// Post-process and validate after generation
    case postProcessing
}
