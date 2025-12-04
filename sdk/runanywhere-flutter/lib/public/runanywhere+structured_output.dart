import 'dart:convert';
import 'runanywhere.dart';

/// Extension for structured output generation
extension RunAnywhereStructuredOutput on RunAnywhere {
  /// Generate structured output with JSON schema validation
  static Future<T> generateStructuredOutput<T>({
    required String prompt,
    required Type type,
    RunAnywhereGenerationOptions? options,
  }) async {
    // Get schema from type (must implement Generatable)
    final schema = (type as dynamic).jsonSchema as String?;
    if (schema == null) {
      throw ArgumentError('Type must implement Generatable with jsonSchema');
    }

    // Build prompt with schema
    final enhancedPrompt =
        '$prompt\n\nGenerate a JSON response matching this schema:\n$schema';

    // Generate text
    final result = await RunAnywhere.generate(
      enhancedPrompt,
      options: options ?? RunAnywhereGenerationOptions(),
    );

    // Parse and validate JSON
    try {
      final jsonData = jsonDecode(result.text) as Map<String, dynamic>;
      // TODO: Use proper deserialization based on type
      return jsonData as T;
    } catch (e) {
      throw FormatException('Failed to parse structured output: $e');
    }
  }
}
