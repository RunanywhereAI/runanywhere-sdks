import 'dart:convert';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';

/// Handles structured output generation and validation
/// Matches iOS StructuredOutputHandler from Features/LLM/StructuredOutput/StructuredOutputHandler.swift
class StructuredOutputHandler {
  final SDKLogger _logger = SDKLogger('StructuredOutputHandler');

  StructuredOutputHandler();

  /// Get system prompt for structured output generation
  String getSystemPrompt(String schema) {
    return '''
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
$schema

Remember: Output ONLY the JSON object, nothing else.
''';
  }

  /// Build user prompt for structured output (simplified without instructions)
  String buildUserPrompt(String content) {
    // Return clean user prompt without JSON instructions
    // The instructions are now in the system prompt
    return content;
  }

  /// Prepare prompt with structured output instructions
  String preparePrompt({
    required String originalPrompt,
    required StructuredOutputConfig config,
  }) {
    if (!config.includeSchemaInPrompt) {
      return originalPrompt;
    }

    final instructions = '''
CRITICAL INSTRUCTION: You MUST respond with ONLY a valid JSON object. No other text is allowed.

JSON Schema:
${config.schema}

RULES:
1. Start your response with { and end with }
2. Include NO text before the opening {
3. Include NO text after the closing }
4. Follow the schema exactly
5. All required fields must be present
6. Use exact field names from the schema
7. Ensure proper JSON syntax (quotes, commas, etc.)

IMPORTANT: Your entire response must be valid JSON that can be parsed. Do not include any explanations, comments, or additional text.
''';

    return '''
System: You are a JSON generator. You must output only valid JSON.

$originalPrompt

$instructions

Remember: Output ONLY the JSON object, nothing else.
''';
  }

  /// Parse and validate structured output from generated text
  T parseStructuredOutput<T>(
      String text, T Function(Map<String, dynamic>) fromJson) {
    // Extract JSON from the response
    final jsonString = extractJSON(text);

    // Parse JSON
    final jsonData = jsonDecode(jsonString);

    if (jsonData is! Map<String, dynamic>) {
      throw StructuredOutputError.validationFailed(
        'Expected JSON object, got ${jsonData.runtimeType}',
      );
    }

    return fromJson(jsonData);
  }

  /// Extract JSON from potentially mixed text
  String extractJSON(String text) {
    final trimmed = text.trim();

    // First, try to find a complete JSON object
    final completeJson = _findCompleteJSON(trimmed);
    if (completeJson != null) {
      return completeJson;
    }

    // Fallback: Try to find JSON object boundaries
    final startIndex = trimmed.indexOf('{');
    final endIndex = trimmed.lastIndexOf('}');

    if (startIndex != -1 && endIndex != -1 && startIndex < endIndex) {
      final jsonSubstring = trimmed.substring(startIndex, endIndex + 1);
      try {
        jsonDecode(jsonSubstring);
        return jsonSubstring;
      } catch (_) {
        // Not valid JSON, continue to other methods
      }
    }

    // Try to find JSON array boundaries
    final arrayStartIndex = trimmed.indexOf('[');
    final arrayEndIndex = trimmed.lastIndexOf(']');

    if (arrayStartIndex != -1 &&
        arrayEndIndex != -1 &&
        arrayStartIndex < arrayEndIndex) {
      final jsonSubstring =
          trimmed.substring(arrayStartIndex, arrayEndIndex + 1);
      try {
        jsonDecode(jsonSubstring);
        return jsonSubstring;
      } catch (_) {
        // Not valid JSON
      }
    }

    // If no clear JSON boundaries, check if the entire text might be JSON
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        jsonDecode(trimmed);
        return trimmed;
      } catch (_) {
        // Not valid JSON
      }
    }

    // Log the text that couldn't be parsed
    _logger.error(
        'Failed to extract JSON from text: ${trimmed.length > 200 ? trimmed.substring(0, 200) : trimmed}...');
    throw StructuredOutputError.extractionFailed(
        'No valid JSON found in the response');
  }

  /// Find a complete JSON object or array in the text
  String? _findCompleteJSON(String text) {
    for (final startChar in ['{', '[']) {
      final startIndex = text.indexOf(startChar);
      if (startIndex == -1) continue;

      final endChar = startChar == '{' ? '}' : ']';
      final match = _findMatchingBrace(text, startIndex, startChar, endChar);
      if (match != null) {
        final jsonSubstring = text.substring(match.start, match.end);
        try {
          jsonDecode(jsonSubstring);
          return jsonSubstring;
        } catch (_) {
          // Not valid JSON, continue
        }
      }
    }
    return null;
  }

  /// Find matching closing brace/bracket
  _BraceMatch? _findMatchingBrace(
      String text, int startIndex, String startChar, String endChar) {
    int depth = 0;
    bool inString = false;
    bool escaped = false;

    for (int i = startIndex; i < text.length; i++) {
      final char = text[i];

      if (escaped) {
        escaped = false;
        continue;
      }

      if (char == '\\') {
        escaped = true;
        continue;
      }

      if (char == '"' && !escaped) {
        inString = !inString;
        continue;
      }

      if (!inString) {
        if (char == startChar) {
          depth++;
        } else if (char == endChar) {
          depth--;
          if (depth == 0) {
            return _BraceMatch(start: startIndex, end: i + 1);
          }
        }
      }
    }
    return null;
  }

  /// Validate that generated text contains valid structured output
  StructuredOutputValidation validateStructuredOutput({
    required String text,
    required StructuredOutputConfig config,
  }) {
    try {
      final jsonString = extractJSON(text);
      jsonDecode(jsonString);
      return const StructuredOutputValidation(
        isValid: true,
        containsJSON: true,
        error: null,
      );
    } catch (e) {
      return StructuredOutputValidation(
        isValid: false,
        containsJSON: false,
        error: e.toString(),
      );
    }
  }
}

/// Brace match result
class _BraceMatch {
  final int start;
  final int end;
  _BraceMatch({required this.start, required this.end});
}

/// Structured output validation result
/// Matches iOS StructuredOutputValidation
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
/// Matches iOS StructuredOutputError
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

/// Configuration for structured output generation
/// Matches iOS StructuredOutputConfig from Features/LLM/StructuredOutput/
class StructuredOutputConfig {
  /// The type being generated
  final Type type;

  /// JSON schema describing the expected output
  final String schema;

  /// Whether to include schema instructions in the prompt
  final bool includeSchemaInPrompt;

  /// Name for the structured output (optional)
  final String? name;

  /// Whether to enforce strict schema validation
  final bool strict;

  const StructuredOutputConfig({
    required this.type,
    required this.schema,
    this.includeSchemaInPrompt = true,
    this.name,
    this.strict = false,
  });
}

/// Result container for streaming structured output
/// Matches iOS StructuredOutputStreamResult from Features/LLM/StructuredOutput/
class StructuredOutputStreamResult<T> {
  /// Stream of individual tokens as they are generated
  final Stream<String> stream;

  /// Future that resolves to the final parsed object
  final Future<T> result;

  const StructuredOutputStreamResult({
    required this.stream,
    required this.result,
  });
}
