// SPDX-License-Identifier: Apache-2.0
//
// DartBridge+StructuredOutput
//
// Structured-output bridge. Mirrors Swift's `CppBridge+StructuredOutput.swift`.
// All orchestration (prompt preparation, generation, thinking-tag stripping,
// JSON extraction, schema validation) lives in commons C++. This file only
// packs the request proto bytes and unpacks the result proto bytes.
library;

import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/generated/structured_output.pb.dart'
    show
        JSONSchema,
        StructuredOutputOptions,
        StructuredOutputParseRequest,
        StructuredOutputPromptResult,
        StructuredOutputRequest,
        StructuredOutputResult;
import 'package:runanywhere/native/dart_bridge_proto_utils.dart';

/// Thin C ABI bridge for structured-output parse / generate / prepare-prompt.
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

  /// Run full structured-output generation against the lifecycle-owned LLM via
  /// commons. Commons handles prompt preparation, LLM generation, thinking-tag
  /// stripping, JSON extraction, and schema validation.
  StructuredOutputResult generate(StructuredOutputRequest request) {
    final fn = RacNative.bindings.rac_structured_output_generate_proto;
    return DartBridgeProtoUtils.callRequest<StructuredOutputResult>(
      request: request,
      invoke: fn,
      decode: StructuredOutputResult.fromBuffer,
      symbol: 'rac_structured_output_generate_proto',
    );
  }

  /// Build the schema-instrumented prompt for structured output via commons.
  StructuredOutputPromptResult preparePrompt({
    required String prompt,
    required StructuredOutputOptions options,
    String requestId = '',
  }) {
    final fn = RacNative.bindings.rac_structured_output_prepare_prompt_proto;
    final request = makeGenerateRequest(
      prompt: prompt,
      options: options,
      requestId: requestId,
    );
    return DartBridgeProtoUtils.callRequest<StructuredOutputPromptResult>(
      request: request,
      invoke: fn,
      decode: StructuredOutputPromptResult.fromBuffer,
      symbol: 'rac_structured_output_prepare_prompt_proto',
    );
  }

  /// Build a `StructuredOutputParseRequest` for the given text + schema.
  StructuredOutputParseRequest makeParseRequest({
    required String text,
    required JSONSchema schema,
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

  /// Build a `StructuredOutputRequest` for the given prompt + options.
  StructuredOutputRequest makeGenerateRequest({
    required String prompt,
    required StructuredOutputOptions options,
    String requestId = '',
  }) {
    final request = StructuredOutputRequest()
      ..prompt = prompt
      ..options = options;
    if (requestId.isNotEmpty) {
      request.requestId = requestId;
    }
    return request;
  }
}
