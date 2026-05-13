// SPDX-License-Identifier: Apache-2.0
//
// StructuredOutput public façade. Mirrors Swift's
// `RunAnywhere+StructuredOutput.swift`. All orchestration — prompt preparation,
// model invocation, thinking-tag stripping, JSON extraction, schema validation
// — lives in commons C++ behind `rac_structured_output_*_proto`. Dart only
// packs request bytes and unpacks result bytes via
// `DartBridgeStructuredOutput`.

import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/generated/structured_output.pb.dart';
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_structured_output.dart';

class RunAnywhereStructuredOutput {
  RunAnywhereStructuredOutput._();

  /// Generate text constrained by a JSON schema string [jsonSchema] using the
  /// lifecycle-owned LLM. Commons owns the full pipeline (prepare prompt → run
  /// LLM → strip thinking tags → extract JSON → validate). [maxTokens] and
  /// [temperature] are accepted for cross-SDK API parity; commons currently
  /// uses default generation parameters.
  static Future<StructuredOutputResult> generate(
    String prompt, {
    required String jsonSchema,
    int maxTokens = 512,
    double temperature = 0.0,
  }) async {
    if (!DartBridge.isInitialized) throw SDKException.notInitialized();
    if (!DartBridge.llm.isLoaded) {
      throw SDKException.componentNotReady('LLM model not loaded.');
    }

    final options = StructuredOutputOptions(
      schema: JSONSchema(rawJson: jsonSchema),
      jsonSchema: jsonSchema,
      includeSchemaInPrompt: true,
    );
    final request = DartBridgeStructuredOutput.shared.makeGenerateRequest(
      prompt: prompt,
      options: options,
    );
    return DartBridgeStructuredOutput.shared.generate(request);
  }

  /// Two-step prompt preparation: ask commons to format [prompt] with the
  /// supplied [jsonSchema] BEFORE invoking the LLM. Returns the schema-
  /// augmented system prompt. Mirrors Swift's
  /// `RunAnywhere+StructuredOutput.swift` `preparePrompt(prompt:options:)`
  /// helper used inside `generateWithStructuredOutput`.
  ///
  /// Falls back to [prompt] verbatim when commons returns an empty system
  /// prompt or the ABI is unavailable. Throws [SDKException.notInitialized]
  /// if SDK is not initialized; throws [SDKException.generationFailed] on
  /// non-zero commons error.
  static String preparePromptForStructuredOutput({
    required String prompt,
    required String jsonSchema,
  }) {
    if (!DartBridge.isInitialized) throw SDKException.notInitialized();

    final options = StructuredOutputOptions(
      schema: JSONSchema(rawJson: jsonSchema),
      jsonSchema: jsonSchema,
      includeSchemaInPrompt: true,
    );
    final result = DartBridgeStructuredOutput.shared.preparePrompt(
      prompt: prompt,
      options: options,
    );
    if (result.errorCode != 0) {
      throw SDKException.generationFailed(
        'preparePromptForStructuredOutput failed (rc=${result.errorCode})',
      );
    }
    final systemPrompt = result.systemPrompt;
    return systemPrompt.isNotEmpty ? systemPrompt : prompt;
  }
}
