/// Structured Output Types
///
/// Types for structured output generation.
/// Mirrors Swift's Structured Output types.
library structured_output_types;

import 'dart:async';

/// Configuration for structured output generation
/// Mirrors Swift's StructuredOutputConfig
class StructuredOutputConfig {
  /// The type name being generated
  final String typeName;

  /// JSON schema describing the expected output
  final String schema;

  /// Whether to include schema instructions in the prompt
  final bool includeSchemaInPrompt;

  /// Name for the structured output (optional)
  final String? name;

  /// Whether to enforce strict schema validation
  final bool strict;

  const StructuredOutputConfig({
    required this.typeName,
    required this.schema,
    this.includeSchemaInPrompt = true,
    this.name,
    this.strict = false,
  });
}

/// Token emitted during streaming structured output
/// Mirrors Swift's StreamToken
class StreamToken {
  final String text;
  final DateTime timestamp;
  final int tokenIndex;

  StreamToken({
    required this.text,
    DateTime? timestamp,
    required this.tokenIndex,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Result container for streaming structured output
/// Mirrors Swift's StructuredOutputStreamResult<T>
class StructuredOutputStreamResult<T> {
  /// Stream of individual tokens as they are generated
  final Stream<StreamToken> stream;

  /// Future that resolves to the final parsed object
  final Future<T> result;

  /// Function to cancel the streaming generation
  final void Function() cancel;

  const StructuredOutputStreamResult({
    required this.stream,
    required this.result,
    required this.cancel,
  });
}

/// Structured output validation result
/// Mirrors Swift's StructuredOutputValidation
class StructuredOutputValidation {
  final bool isValid;
  final bool containsJSON;
  final String? error;

  const StructuredOutputValidation({
    required this.isValid,
    required this.containsJSON,
    this.error,
  });
}

/// Structured output errors
/// Mirrors Swift's StructuredOutputError
class StructuredOutputError implements Exception {
  final String message;

  StructuredOutputError(this.message);

  factory StructuredOutputError.invalidJSON(String detail) {
    return StructuredOutputError('Invalid JSON: $detail');
  }

  factory StructuredOutputError.validationFailed(String detail) {
    return StructuredOutputError('Validation failed: $detail');
  }

  factory StructuredOutputError.extractionFailed(String detail) {
    return StructuredOutputError(
        'Failed to extract structured output: $detail');
  }

  factory StructuredOutputError.unsupportedType(String type) {
    return StructuredOutputError(
        'Unsupported type for structured output: $type');
  }

  @override
  String toString() => message;
}

/// Result for structured output generation with parsed result and metrics
class StructuredOutputResult<T> {
  /// The parsed structured output object
  final T result;

  /// Raw text from generation
  final String rawText;

  /// Generation metrics
  final int inputTokens;
  final int tokensUsed;
  final double latencyMs;
  final double tokensPerSecond;

  const StructuredOutputResult({
    required this.result,
    required this.rawText,
    required this.inputTokens,
    required this.tokensUsed,
    required this.latencyMs,
    required this.tokensPerSecond,
  });
}
