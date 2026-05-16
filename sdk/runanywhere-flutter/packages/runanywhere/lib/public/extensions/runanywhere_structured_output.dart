// SPDX-License-Identifier: Apache-2.0
//
// StructuredOutput public façade. Mirrors Swift's
// `RunAnywhere+StructuredOutput.swift`. All orchestration — prompt preparation,
// model invocation, thinking-tag stripping, JSON extraction, schema validation
// — lives in commons C++ behind `rac_structured_output_*_proto`. Dart only
// packs request bytes and unpacks result bytes via
// `DartBridgeStructuredOutput`.

import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/generated/llm_options.pb.dart'
    show LLMGenerationOptions, LLMGenerationResult;
import 'package:runanywhere/generated/structured_output.pb.dart';
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_structured_output.dart';
import 'package:runanywhere/public/capabilities/runanywhere_llm.dart';

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
    if (RunAnywhereLLM.shared.currentModelId == null) {
      throw SDKException.componentNotReady(
        'LLM model not loaded. Call RunAnywhere.llm.load(modelId) first.',
      );
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
    return generateRequest(request);
  }

  /// Generate structured output from a typed JSON schema.
  ///
  /// Mirrors Swift `RunAnywhere.generateStructured(prompt:schema:options:)`.
  static Future<StructuredOutputResult> generateStructured({
    required String prompt,
    required JSONSchema schema,
    LLMGenerationOptions? options,
  }) async {
    final request = DartBridgeStructuredOutput.shared.makeGenerateRequest(
      prompt: prompt,
      options: StructuredOutputOptionsDefaults.defaults(schema: schema),
    );
    return generateRequest(request);
  }

  /// Generated-proto structured output entrypoint.
  static Future<StructuredOutputResult> generateRequest(
    StructuredOutputRequest request,
  ) async {
    if (!DartBridge.isInitialized) throw SDKException.notInitialized();
    if (RunAnywhereLLM.shared.currentModelId == null) {
      throw SDKException.componentNotReady(
        'LLM model not loaded. Call RunAnywhere.llm.load(modelId) first.',
      );
    }
    return DartBridgeStructuredOutput.shared.generate(request);
  }

  /// Stream-shaped structured output API. When the linked commons build lacks
  /// a native structured-output stream ABI, this emits the generated result as
  /// a single terminal proto event instead of inventing a Dart-only event type.
  static Stream<StructuredOutputStreamEvent> generateStructuredStream({
    required String prompt,
    required JSONSchema schema,
    LLMGenerationOptions? options,
  }) async* {
    try {
      final result = await generateStructured(
        prompt: prompt,
        schema: schema,
        options: options,
      );
      yield StructuredOutputStreamEvent(
        kind: StructuredOutputStreamEventKind
            .STRUCTURED_OUTPUT_STREAM_EVENT_KIND_COMPLETED,
        result: result,
      );
    } catch (e) {
      yield StructuredOutputStreamEvent(
        kind: StructuredOutputStreamEventKind
            .STRUCTURED_OUTPUT_STREAM_EVENT_KIND_ERROR,
        errorMessage: e.toString(),
      );
    }
  }

  /// Apply a structured-output configuration to a normal LLM generation.
  ///
  /// Mirrors Swift `RunAnywhere.generateWithStructuredOutput(...)`: prompt
  /// preparation remains in commons, then the standard generated LLM request
  /// path runs through `rac_llm_generate_proto`.
  static Future<LLMGenerationResult> generateWithStructuredOutput({
    required String prompt,
    required StructuredOutputOptions structuredOutput,
    LLMGenerationOptions? options,
  }) async {
    final effectiveOptions = LLMGenerationOptions();
    if (options != null) {
      effectiveOptions.mergeFromMessage(options);
    }
    effectiveOptions.structuredOutput = structuredOutput;

    if (structuredOutput.includeSchemaInPrompt) {
      final result = DartBridgeStructuredOutput.shared.preparePrompt(
        prompt: prompt,
        options: structuredOutput,
      );
      if (result.errorCode != 0) {
        throw SDKException.generationFailed(
          result.errorMessage.isNotEmpty
              ? result.errorMessage
              : 'Structured-output prompt preparation failed',
        );
      }
      if (result.hasSystemPrompt()) {
        effectiveOptions.systemPrompt = result.systemPrompt;
      }
    }

    return RunAnywhereLLM.shared.generate(prompt, effectiveOptions);
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

extension StructuredOutputOptionsDefaults on StructuredOutputOptions {
  /// Canonical defaults matching Swift `RAStructuredOutputOptions.defaults`.
  static StructuredOutputOptions defaults({
    required JSONSchema schema,
    bool includeSchemaInPrompt = true,
    bool strict = false,
  }) {
    return StructuredOutputOptions(
      schema: schema,
      includeSchemaInPrompt: includeSchemaInPrompt,
      strictMode: strict,
      jsonSchema: schema.jsonSchemaString,
      mode: StructuredOutputMode.STRUCTURED_OUTPUT_MODE_JSON_SCHEMA,
    );
  }
}

extension JSONSchemaStringHelpers on JSONSchema {
  /// JSON Schema text consumed by the structured-output C ABI.
  String get jsonSchemaString => rawJson.isNotEmpty ? rawJson : '{}';
}
