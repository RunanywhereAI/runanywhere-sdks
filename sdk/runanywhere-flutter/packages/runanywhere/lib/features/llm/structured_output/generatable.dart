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

// Note: StructuredOutputConfig is defined in public/types/structured_output_types.dart
// and imported by structured_output_handler.dart
