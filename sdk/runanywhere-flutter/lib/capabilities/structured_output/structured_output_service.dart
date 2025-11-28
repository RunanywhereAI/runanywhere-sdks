import 'dart:convert';
import '../../../foundation/logging/sdk_logger.dart';
import '../../../foundation/error_types/sdk_error.dart';

/// Service for structured output generation with JSON schema validation
class StructuredOutputService {
  final SDKLogger logger = SDKLogger(category: 'StructuredOutputService');

  /// Validate structured output against JSON schema
  StructuredOutputValidation validateStructuredOutput({
    required String text,
    required StructuredOutputConfig config,
  }) {
    try {
      // Try to parse as JSON
      final jsonData = jsonDecode(text);

      // Validate against schema if provided
      if (config.schema != null) {
        final isValid = _validateAgainstSchema(jsonData, config.schema!);
        return StructuredOutputValidation(
          isValid: isValid,
          errors: isValid ? [] : ['JSON does not match schema'],
        );
      }

      return StructuredOutputValidation(isValid: true, errors: []);
    } catch (e) {
      logger.error('Failed to parse structured output: $e');
      return StructuredOutputValidation(
        isValid: false,
        errors: ['Invalid JSON: $e'],
      );
    }
  }

  /// Validate JSON data against schema (simplified implementation)
  bool _validateAgainstSchema(dynamic jsonData, Map<String, dynamic> schema) {
    // Simplified schema validation
    // In production, use a proper JSON schema validator
    if (schema['type'] == 'object' && jsonData is! Map) {
      return false;
    }
    if (schema['type'] == 'array' && jsonData is! List) {
      return false;
    }
    // Add more validation as needed
    return true;
  }
}

/// Structured output configuration
class StructuredOutputConfig {
  final Map<String, dynamic>? schema;
  final String? format;

  StructuredOutputConfig({
    this.schema,
    this.format,
  });
}

/// Structured output validation result
class StructuredOutputValidation {
  final bool isValid;
  final List<String> errors;

  StructuredOutputValidation({
    required this.isValid,
    this.errors = const [],
  });
}

/// Protocol for types that can generate structured output
abstract class Generatable {
  /// JSON schema for this type
  static String get jsonSchema {
    throw UnimplementedError('jsonSchema must be implemented');
  }

  /// Generation hints
  static Map<String, dynamic>? get generationHints => null;
}

