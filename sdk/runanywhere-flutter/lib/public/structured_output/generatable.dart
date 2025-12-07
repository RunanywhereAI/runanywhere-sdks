import 'dart:async';
import 'dart:convert';

import '../runanywhere.dart' show RunAnywhereGenerationOptions, RunAnywhere;

/// Protocol for types that can be generated as structured output from LLMs
abstract class Generatable {
  /// The JSON schema for this type
  static String get jsonSchema {
    throw UnimplementedError('jsonSchema must be implemented');
  }

  /// Generation hints (optional)
  static Map<String, dynamic>? get generationHints => null;
}

/// Structured output configuration
class StructuredOutputConfig {
  /// The type to generate
  final Type type;

  /// Whether to include schema in prompt
  final bool includeSchemaInPrompt;

  StructuredOutputConfig({
    required this.type,
    this.includeSchemaInPrompt = true,
  });
}

/// Generate structured output
Future<T> generateStructuredOutput<T extends Generatable>({
  required String prompt,
  required RunAnywhereGenerationOptions options,
  required StructuredOutputConfig config,
}) async {
  // Get schema from type
  final schema = (config.type as dynamic).jsonSchema as String?;
  if (schema == null) {
    throw ArgumentError('Type must implement Generatable with jsonSchema');
  }

  // Build prompt with schema
  final enhancedPrompt = config.includeSchemaInPrompt
      ? '$prompt\n\nGenerate a JSON response matching this schema:\n$schema'
      : prompt;

  // Generate text
  final result = await RunAnywhere.generate(enhancedPrompt, options: options);

  // Parse and validate JSON
  try {
    final jsonData = jsonDecode(result.text);
    // TODO: Validate against schema
    return jsonData as T;
  } catch (e) {
    throw FormatException('Failed to parse structured output: $e');
  }
}
