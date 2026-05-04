// StructuredOutput namespace extension.
// Delegates to the generated-proto LLM request/result path.

import 'dart:convert';

import 'package:runanywhere/foundation/error_types/sdk_exception.dart';
import 'package:runanywhere/generated/llm_options.pb.dart';
import 'package:runanywhere/generated/structured_output.pb.dart';
import 'package:runanywhere/internal/sdk_state.dart';
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/public/capabilities/runanywhere_llm.dart';

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

    final raw = await RunAnywhereLLM.shared.generate(
      prompt,
      LLMGenerationOptions(
        maxTokens: maxTokens,
        temperature: temperature,
        jsonSchema: jsonSchema,
        structuredOutput: StructuredOutputOptions(jsonSchema: jsonSchema),
      ),
    );

    return StructuredOutputResult(
      rawText: raw.text,
      parsedJson: raw.jsonOutput.isEmpty ? [] : utf8.encode(raw.jsonOutput),
      validation: raw.hasStructuredOutputValidation()
          ? raw.structuredOutputValidation
          : StructuredOutputValidation(isValid: raw.jsonOutput.isNotEmpty),
    );
  }
}
