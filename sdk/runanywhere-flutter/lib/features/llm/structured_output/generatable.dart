/// Protocol for types that can be generated as structured output from LLMs
/// Matches iOS Generatable from Features/LLM/StructuredOutput/Generatable.swift
abstract class Generatable {
  /// The JSON schema for this type
  static String get jsonSchema => '''
{
  "type": "object",
  "additionalProperties": false
}
''';

  /// Convert from JSON map
  factory Generatable.fromJson(Map<String, dynamic> json) {
    throw UnimplementedError('Subclasses must implement fromJson');
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson();
}

/// Structured output configuration
/// Matches iOS StructuredOutputConfig from Features/LLM/StructuredOutput/Generatable.swift
class StructuredOutputConfig {
  /// The type to generate
  final Type type;

  /// The JSON schema for the type
  final String schema;

  /// Whether to include schema in prompt
  final bool includeSchemaInPrompt;

  const StructuredOutputConfig({
    required this.type,
    required this.schema,
    this.includeSchemaInPrompt = true,
  });

  /// Create config from a Generatable type
  static StructuredOutputConfig fromType<T extends Generatable>(
    String schema, {
    bool includeSchemaInPrompt = true,
  }) {
    return StructuredOutputConfig(
      type: T,
      schema: schema,
      includeSchemaInPrompt: includeSchemaInPrompt,
    );
  }
}
