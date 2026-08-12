// SPDX-License-Identifier: Apache-2.0
//
// DartBridge+StructuredOutput
//
// Structured-output bridge. Mirrors Swift's `CppBridge+StructuredOutput.swift`.
// All orchestration (prompt preparation, thinking-tag stripping, JSON
// extraction, schema validation) lives in commons C++. This file only packs
// the request proto bytes and unpacks the result proto bytes.
//
// `rac_structured_output_generate_proto` is a permanently-retired stub
// (idl/structured_output.proto, API-realignment so-p2 —
// `StructuredOutputRequest` was deleted outright): commons now reports
// `RAC_ERROR_FEATURE_NOT_AVAILABLE` unconditionally and directs callers to
// `rac_llm_generate_proto` with `LLMGenerationOptions.structuredOutput` set
// instead. There is therefore no `generate()`/`makeGenerateRequest()` here
// anymore — structured GENERATION routes through the normal LLM path (see
// `RunAnywhereStructuredOutput.generateWithStructuredOutput` /
// `namespaces/llm.dart`'s `generateStructured`), and this bridge keeps only
// the surviving extract/validate/prepare-prompt surface over
// `StructuredOutputParseRequest`.
library;

import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/generated/structured_output.pb.dart'
    show
        StructuredOutputOptions,
        StructuredOutputParseRequest,
        StructuredOutputPromptResult,
        StructuredOutputResult;
import 'package:runanywhere/native/dart_bridge_proto_utils.dart';

/// Thin C ABI bridge for structured-output parse / prepare-prompt.
class DartBridgeStructuredOutput {
  DartBridgeStructuredOutput._();

  static final DartBridgeStructuredOutput shared =
      DartBridgeStructuredOutput._();

  /// Parse structured output from raw model text via commons.
  StructuredOutputResult parse(StructuredOutputParseRequest request) {
    final fn = RacNative.bindings.rac_structured_output_parse_proto;
    return DartBridgeProtoUtils.callRequest<StructuredOutputResult>(
      request: request,
      invoke: fn,
      decode: StructuredOutputResult.fromBuffer,
      symbol: 'rac_structured_output_parse_proto',
    );
  }

  /// Build the schema-instrumented prompt for structured output via commons.
  StructuredOutputPromptResult preparePrompt({
    required String prompt,
    required StructuredOutputOptions options,
    String requestId = '',
  }) {
    final fn = RacNative.bindings.rac_structured_output_prepare_prompt_proto;
    final request = StructuredOutputParseRequest(text: prompt, options: options);
    if (requestId.isNotEmpty) {
      request.requestId = requestId;
    }
    return DartBridgeProtoUtils.callRequest<StructuredOutputPromptResult>(
      request: request,
      invoke: fn,
      decode: StructuredOutputPromptResult.fromBuffer,
      symbol: 'rac_structured_output_prepare_prompt_proto',
    );
  }

  /// Build a `StructuredOutputParseRequest` for the given text + schema.
  ///
  /// `StructuredOutputParseRequest` (request_id, text, options, metadata) is
  /// now the sole request envelope shared by parse/validate/prepare-prompt
  /// (idl/structured_output.proto) — `text` plays the role the old `prompt`
  /// field did on the deleted `StructuredOutputRequest`.
  StructuredOutputParseRequest makeParseRequest({
    required String text,
    required String schema,
    String requestId = '',
  }) {
    final request = StructuredOutputParseRequest()
      ..text = text
      ..options = StructuredOutputOptions(schema: schema);
    if (requestId.isNotEmpty) {
      request.requestId = requestId;
    }
    return request;
  }
}
