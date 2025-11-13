import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere/capabilities/structured_output/structured_output_handler.dart';

void main() {
  group('StructuredOutputHandler Tests', () {
    late StructuredOutputHandler handler;

    setUp(() {
      handler = StructuredOutputHandler();
    });

    test('Extract JSON from clean text', () {
      const jsonText = '{"name": "test", "value": 123}';
      final extracted = handler.extractJSON(jsonText);
      expect(extracted, equals(jsonText));
    });

    test('Extract JSON from mixed text', () {
      const mixedText = 'Here is the result: {"name": "test", "value": 123} That\'s it!';
      final extracted = handler.extractJSON(mixedText);
      expect(extracted, contains('"name"'));
      expect(extracted, contains('"test"'));
    });

    test('Extract JSON from text with newlines', () {
      const jsonText = '''
      {
        "name": "test",
        "value": 123
      }
      ''';
      final extracted = handler.extractJSON(jsonText);
      expect(extracted, contains('"name"'));
    });

    test('Validation with valid JSON', () {
      const jsonText = '{"name": "test"}';
      const schema = '{"type": "object"}';

      final validation = handler.validateStructuredOutput(
        text: jsonText,
        schema: schema,
      );

      expect(validation.isValid, isTrue);
      expect(validation.containsJSON, isTrue);
    });

    test('Validation with invalid JSON', () {
      const invalidText = 'This is not JSON';
      const schema = '{"type": "object"}';

      final validation = handler.validateStructuredOutput(
        text: invalidText,
        schema: schema,
      );

      expect(validation.isValid, isFalse);
      expect(validation.containsJSON, isFalse);
    });

    test('Build prompt with schema', () {
      const originalPrompt = 'Generate a user profile';
      const schema = '{"type": "object", "properties": {"name": {"type": "string"}}}';

      final enhancedPrompt = handler.buildPromptWithSchema(
        originalPrompt: originalPrompt,
        schema: schema,
      );

      expect(enhancedPrompt, contains(originalPrompt));
      expect(enhancedPrompt, contains(schema));
      expect(enhancedPrompt, contains('CRITICAL INSTRUCTION'));
    });
  });
}

