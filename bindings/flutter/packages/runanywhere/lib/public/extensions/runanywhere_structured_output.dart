// SPDX-License-Identifier: Apache-2.0
//
// StructuredOutput public façade. Mirrors Swift's
// `RunAnywhere+StructuredOutput.swift`: structured GENERATION is
// `LLMGenerationOptions.structuredOutput` on the ordinary LLM request
// (idl/structured_output.proto file header) — commons' dedicated
// `rac_structured_output_generate_proto`/`StructuredOutputRequest` were
// deleted outright (API-realignment so-p2; the ABI now unconditionally
// reports `RAC_ERROR_FEATURE_NOT_AVAILABLE` and points callers at
// `rac_llm_generate_proto`). This façade therefore prepares the prompt (when
// asked), runs the NORMAL LLM generate path, and leaves extraction/
// validation to `rac_structured_output_parse_proto`
// (`DartBridgeStructuredOutput.parse`) — commons still owns extraction,
// canonicalization, and schema validation end to end.
//
// The dedicated streaming variant (`generateStructuredStream`,
// `StructuredOutputStreamEvent`/`StructuredOutputStreamEventKind`) is
// likewise deleted outright with no replacement: structured generation now
// streams through the ordinary `RunAnywhere.llm.generateStream` path with
// `LLMGenerationOptions.structuredOutput` set. Mirrors the Kotlin/Swift
// SDKs' identical deletion.

import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/generated/llm_options.pb.dart'
    show LLMGenerationOptions, LLMGenerationResult;
import 'package:runanywhere/generated/structured_output.pb.dart'
    show StructuredOutputOptions, StructuredOutputResult;
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_structured_output.dart';
import 'package:runanywhere/public/capabilities/runanywhere_llm.dart';

class RunAnywhereStructuredOutput {
  RunAnywhereStructuredOutput._();

  /// Generate structured output from a JSON Schema string.
  ///
  /// Mirrors Swift `RunAnywhere.generateStructured(prompt:schema:options:)`
  /// (deprecated free-function facade): caller-supplied [options]
  /// (maxOutputTokens, temperature, topP, systemPrompt, …) are forwarded to
  /// the underlying LLM through [generateWithStructuredOutput]; the
  /// resulting raw text is then parsed via the commons extraction/
  /// validation path.
  static Future<StructuredOutputResult> generateStructured({
    required String prompt,
    required String schema,
    LLMGenerationOptions? options,
  }) async {
    if (!DartBridge.isInitialized) throw SDKException.notInitialized();
    final generation = await generateWithStructuredOutput(
      prompt: prompt,
      structuredOutput: StructuredOutputOptions(
        schema: schema,
        includeSchemaInPrompt: true,
      ),
      options: options,
    );
    return RunAnywhereLLM.shared.extractStructuredOutput(
      text: generation.text,
      schema: schema,
    );
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
      if (result.hasError()) {
        // Mirrors Swift `.processingFailed` on prep failure.
        throw SDKException.processingFailed(
          result.error.message.isNotEmpty
              ? result.error.message
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
  /// if SDK is not initialized; throws [SDKException.processingFailed] on
  /// non-zero commons error.
  static String preparePromptForStructuredOutput({
    required String prompt,
    required String jsonSchema,
  }) {
    if (!DartBridge.isInitialized) throw SDKException.notInitialized();

    final options = StructuredOutputOptions(
      schema: jsonSchema,
      includeSchemaInPrompt: true,
    );
    final result = DartBridgeStructuredOutput.shared.preparePrompt(
      prompt: prompt,
      options: options,
    );
    if (result.hasError()) {
      // Mirrors Swift `.processingFailed` on prep failure.
      throw SDKException.processingFailed(
        result.error.message.isNotEmpty
            ? result.error.message
            : 'preparePromptForStructuredOutput failed',
      );
    }
    final systemPrompt = result.systemPrompt;
    return systemPrompt.isNotEmpty ? systemPrompt : prompt;
  }
}
