/// DartBridge+StructuredOutput
///
/// Structured output FFI bindings - wraps C++ rac_structured_output_* APIs.
/// Mirrors Swift's CppBridge extensions for structured output.
library dart_bridge_structured_output;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';

/// Structured output FFI bridge for C++ interop.
///
/// Provides access to C++ structured output functions:
/// - rac_structured_output_get_system_prompt
/// - rac_structured_output_extract_json
/// - rac_structured_output_prepare_prompt
/// - rac_structured_output_validate
class DartBridgeStructuredOutput {
  static final DartBridgeStructuredOutput shared =
      DartBridgeStructuredOutput._();

  DartBridgeStructuredOutput._();

  final _logger = SDKLogger('DartBridge.StructuredOutput');

  /// Get system prompt for structured output generation
  /// Uses C++ rac_structured_output_get_system_prompt
  String getSystemPrompt(String schema) {
    final schemaPtr = schema.toNativeUtf8();
    final promptPtrPtr = calloc<Pointer<Utf8>>();

    try {
      final lib = PlatformLoader.loadCommons();
      final getSystemPromptFn = lib.lookupFunction<
          Int32 Function(Pointer<Utf8>, Pointer<Pointer<Utf8>>),
          int Function(Pointer<Utf8>, Pointer<Pointer<Utf8>>)>(
          'rac_structured_output_get_system_prompt');

      final result = getSystemPromptFn(schemaPtr, promptPtrPtr);

      if (result != RAC_SUCCESS) {
        _logger.warning(
            'getSystemPrompt failed with code $result, using fallback');
        return _fallbackSystemPrompt(schema);
      }

      final promptPtr = promptPtrPtr.value;
      if (promptPtr == nullptr) {
        return _fallbackSystemPrompt(schema);
      }

      final prompt = promptPtr.toDartString();
      lib.lookupFunction<Void Function(Pointer<Void>), void Function(
          Pointer<Void>)>('rac_free')(promptPtr.cast<Void>());

      return prompt;
    } catch (e) {
      _logger.error('getSystemPrompt exception: $e');
      return _fallbackSystemPrompt(schema);
    } finally {
      calloc.free(schemaPtr);
      calloc.free(promptPtrPtr);
    }
  }

  /// Fallback system prompt when C++ fails
  String _fallbackSystemPrompt(String schema) {
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

  /// Extract JSON from generated text
  /// Uses C++ rac_structured_output_extract_json
  String? extractJson(String text) {
    final textPtr = text.toNativeUtf8();
    final jsonPtrPtr = calloc<Pointer<Utf8>>();

    try {
      final lib = PlatformLoader.loadCommons();
      final extractJsonFn = lib.lookupFunction<
          Int32 Function(Pointer<Utf8>, Pointer<Pointer<Utf8>>, Pointer<Void>),
          int Function(Pointer<Utf8>, Pointer<Pointer<Utf8>>, Pointer<Void>)>(
          'rac_structured_output_extract_json');

      final result = extractJsonFn(textPtr, jsonPtrPtr, nullptr);

      if (result != RAC_SUCCESS) {
        _logger.warning('extractJson failed with code $result');
        return _fallbackExtractJson(text);
      }

      final jsonPtr = jsonPtrPtr.value;
      if (jsonPtr == nullptr) {
        return _fallbackExtractJson(text);
      }

      final jsonString = jsonPtr.toDartString();
      lib.lookupFunction<Void Function(Pointer<Void>), void Function(
          Pointer<Void>)>('rac_free')(jsonPtr.cast<Void>());

      return jsonString;
    } catch (e) {
      _logger.error('extractJson exception: $e');
      return _fallbackExtractJson(text);
    } finally {
      calloc.free(textPtr);
      calloc.free(jsonPtrPtr);
    }
  }

  /// Fallback JSON extraction when C++ fails
  String? _fallbackExtractJson(String text) {
    final trimmed = text.trim();

    // Try to find complete JSON object
    final startIndex = trimmed.indexOf('{');
    final endIndex = trimmed.lastIndexOf('}');

    if (startIndex != -1 && endIndex != -1 && startIndex < endIndex) {
      return trimmed.substring(startIndex, endIndex + 1);
    }

    // Try array
    final arrayStart = trimmed.indexOf('[');
    final arrayEnd = trimmed.lastIndexOf(']');

    if (arrayStart != -1 && arrayEnd != -1 && arrayStart < arrayEnd) {
      return trimmed.substring(arrayStart, arrayEnd + 1);
    }

    return null;
  }

  /// Prepare prompt with structured output instructions
  /// Uses C++ rac_structured_output_prepare_prompt
  String preparePrompt(String originalPrompt, String schema,
      {bool includeSchemaInPrompt = true}) {
    final promptPtr = originalPrompt.toNativeUtf8();
    final schemaPtr = schema.toNativeUtf8();

    // Build config struct
    final configPtr = calloc<RacStructuredOutputConfigStruct>();
    configPtr.ref.jsonSchema = schemaPtr;
    configPtr.ref.includeSchemaInPrompt = includeSchemaInPrompt ? 1 : 0;

    final preparedPtrPtr = calloc<Pointer<Utf8>>();

    try {
      final lib = PlatformLoader.loadCommons();
      final preparePromptFn = lib.lookupFunction<
          Int32 Function(Pointer<Utf8>, Pointer<RacStructuredOutputConfigStruct>,
              Pointer<Pointer<Utf8>>),
          int Function(Pointer<Utf8>, Pointer<RacStructuredOutputConfigStruct>,
              Pointer<Pointer<Utf8>>)>(
          'rac_structured_output_prepare_prompt');

      final result = preparePromptFn(promptPtr, configPtr, preparedPtrPtr);

      if (result != RAC_SUCCESS) {
        _logger.warning('preparePrompt failed with code $result');
        return _fallbackPreparePrompt(originalPrompt, schema);
      }

      final preparedPtr = preparedPtrPtr.value;
      if (preparedPtr == nullptr) {
        return _fallbackPreparePrompt(originalPrompt, schema);
      }

      final prepared = preparedPtr.toDartString();
      lib.lookupFunction<Void Function(Pointer<Void>), void Function(
          Pointer<Void>)>('rac_free')(preparedPtr.cast<Void>());

      return prepared;
    } catch (e) {
      _logger.error('preparePrompt exception: $e');
      return _fallbackPreparePrompt(originalPrompt, schema);
    } finally {
      calloc.free(promptPtr);
      calloc.free(schemaPtr);
      calloc.free(configPtr);
      calloc.free(preparedPtrPtr);
    }
  }

  /// Fallback prepare prompt when C++ fails
  String _fallbackPreparePrompt(String originalPrompt, String schema) {
    return '''
System: You are a JSON generator. You must output only valid JSON.

$originalPrompt

CRITICAL INSTRUCTION: You MUST respond with ONLY a valid JSON object. No other text is allowed.

JSON Schema:
$schema

RULES:
1. Start your response with { and end with }
2. Include NO text before the opening {
3. Include NO text after the closing }
4. Follow the schema exactly
5. All required fields must be present

Remember: Output ONLY the JSON object, nothing else.
''';
  }

  /// Validate structured output
  /// Uses C++ rac_structured_output_validate
  StructuredOutputValidationResult validate(String text, String schema) {
    final textPtr = text.toNativeUtf8();
    final schemaPtr = schema.toNativeUtf8();

    final configPtr = calloc<RacStructuredOutputConfigStruct>();
    configPtr.ref.jsonSchema = schemaPtr;
    configPtr.ref.includeSchemaInPrompt = 1;

    final validationPtr = calloc<RacStructuredOutputValidationStruct>();

    try {
      final lib = PlatformLoader.loadCommons();
      final validateFn = lib.lookupFunction<
          Int32 Function(Pointer<Utf8>, Pointer<RacStructuredOutputConfigStruct>,
              Pointer<RacStructuredOutputValidationStruct>),
          int Function(Pointer<Utf8>, Pointer<RacStructuredOutputConfigStruct>,
              Pointer<RacStructuredOutputValidationStruct>)>(
          'rac_structured_output_validate');

      final result = validateFn(textPtr, configPtr, validationPtr);

      if (result != RAC_SUCCESS) {
        return _fallbackValidate(text);
      }

      final validation = validationPtr.ref;
      final isValid = validation.isValid == 1;

      String? errorMessage;
      if (validation.errorMessage != nullptr) {
        errorMessage = validation.errorMessage.toDartString();
      }

      return StructuredOutputValidationResult(
        isValid: isValid,
        containsJSON: isValid,
        error: errorMessage,
      );
    } catch (e) {
      _logger.error('validate exception: $e');
      return _fallbackValidate(text);
    } finally {
      calloc.free(textPtr);
      calloc.free(schemaPtr);
      calloc.free(configPtr);
      calloc.free(validationPtr);
    }
  }

  /// Fallback validation when C++ fails
  StructuredOutputValidationResult _fallbackValidate(String text) {
    try {
      // Simple JSON validation
      final trimmed = text.trim();
      if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
        return const StructuredOutputValidationResult(
          isValid: true,
          containsJSON: true,
          error: null,
        );
      }
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        return const StructuredOutputValidationResult(
          isValid: true,
          containsJSON: true,
          error: null,
        );
      }
      return const StructuredOutputValidationResult(
        isValid: false,
        containsJSON: false,
        error: 'No valid JSON found',
      );
    } catch (e) {
      return StructuredOutputValidationResult(
        isValid: false,
        containsJSON: false,
        error: e.toString(),
      );
    }
  }
}

/// Structured output validation result
class StructuredOutputValidationResult {
  final bool isValid;
  final bool containsJSON;
  final String? error;

  const StructuredOutputValidationResult({
    required this.isValid,
    required this.containsJSON,
    this.error,
  });
}
