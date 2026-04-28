// Wave 3: StructuredOutput namespace extension.
// Mirrors Swift RunAnywhere+StructuredOutput.swift.
// Delegates to the JSON-schema path in the native LLM bridge.

import 'dart:convert';

import 'package:runanywhere/foundation/error_types/sdk_exception.dart';
import 'package:runanywhere/generated/structured_output.pb.dart';
import 'package:runanywhere/internal/sdk_state.dart';
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_structured_output.dart';

class RunAnywhereStructuredOutput {
  RunAnywhereStructuredOutput._();

  /// Generate text constrained by a JSON schema string [jsonSchema],
  /// returning a [StructuredOutputResult] with parsedJson bytes and rawText.
  static Future<StructuredOutputResult> generate(
    String prompt, {
    required String jsonSchema,
    int maxTokens = 512,
    double temperature = 0.0,
  }) async {
    if (!SdkState.shared.isInitialized) throw SDKException.notInitialized();
    if (!DartBridge.llm.isLoaded) {
      throw SDKException.componentNotReady('LLM model not loaded.');
    }

    final systemPrompt =
        DartBridgeStructuredOutput.shared.getSystemPrompt(jsonSchema);

    final raw = await DartBridge.llm.generate(
      prompt,
      maxTokens: maxTokens,
      temperature: temperature,
      systemPrompt: systemPrompt,
    );

    final jsonStr =
        DartBridgeStructuredOutput.shared.extractJson(raw.text) ?? '';
    final parsedBytes = _tryEncodeJson(jsonStr);

    final validation = StructuredOutputValidation(
      isValid: parsedBytes != null,
    );

    return StructuredOutputResult(
      rawText: raw.text,
      parsedJson: parsedBytes ?? [],
      validation: validation,
    );
  }

  static List<int>? _tryEncodeJson(String s) {
    if (s.isEmpty) return null;
    try {
      jsonDecode(s);
      return utf8.encode(s);
    } catch (_) {
      return null;
    }
  }
}
