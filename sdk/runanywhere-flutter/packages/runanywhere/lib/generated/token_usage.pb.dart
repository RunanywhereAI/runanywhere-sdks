// This is a generated file - do not edit.
//
// Generated from token_usage.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// One token-accounting shape embedded by every result and metrics message,
/// replacing the input/output/total/throughput quadruple that was copied inline
/// across LLM, VLM, and RAG results. Names follow the OpenAI Responses API; the
/// timing fields follow llama.cpp's `timings` object, which names the phase it
/// measures.
class TokenUsage extends $pb.GeneratedMessage {
  factory TokenUsage({
    $core.int? inputTokens,
    $core.int? outputTokens,
    $core.int? totalTokens,
    $core.double? decodeTokensPerSecond,
    $fixnum.Int64? prefillMs,
    $fixnum.Int64? ttftMs,
  }) {
    final result = create();
    if (inputTokens != null) result.inputTokens = inputTokens;
    if (outputTokens != null) result.outputTokens = outputTokens;
    if (totalTokens != null) result.totalTokens = totalTokens;
    if (decodeTokensPerSecond != null)
      result.decodeTokensPerSecond = decodeTokensPerSecond;
    if (prefillMs != null) result.prefillMs = prefillMs;
    if (ttftMs != null) result.ttftMs = ttftMs;
    return result;
  }

  TokenUsage._();

  factory TokenUsage.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TokenUsage.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TokenUsage',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'inputTokens')
    ..aI(2, _omitFieldNames ? '' : 'outputTokens')
    ..aI(3, _omitFieldNames ? '' : 'totalTokens')
    ..aD(4, _omitFieldNames ? '' : 'decodeTokensPerSecond')
    ..aInt64(5, _omitFieldNames ? '' : 'prefillMs')
    ..aInt64(6, _omitFieldNames ? '' : 'ttftMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TokenUsage clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TokenUsage copyWith(void Function(TokenUsage) updates) =>
      super.copyWith((message) => updates(message as TokenUsage)) as TokenUsage;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TokenUsage create() => TokenUsage._();
  @$core.override
  TokenUsage createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TokenUsage getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TokenUsage>(create);
  static TokenUsage? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get inputTokens => $_getIZ(0);
  @$pb.TagNumber(1)
  set inputTokens($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasInputTokens() => $_has(0);
  @$pb.TagNumber(1)
  void clearInputTokens() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get outputTokens => $_getIZ(1);
  @$pb.TagNumber(2)
  set outputTokens($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOutputTokens() => $_has(1);
  @$pb.TagNumber(2)
  void clearOutputTokens() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get totalTokens => $_getIZ(2);
  @$pb.TagNumber(3)
  set totalTokens($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTotalTokens() => $_has(2);
  @$pb.TagNumber(3)
  void clearTotalTokens() => $_clearField(3);

  /// Decode-phase throughput only: output_tokens / decode_ms. Excludes
  /// prefill. cf. llama.cpp timings.predicted_per_second.
  @$pb.TagNumber(4)
  $core.double get decodeTokensPerSecond => $_getN(3);
  @$pb.TagNumber(4)
  set decodeTokensPerSecond($core.double value) => $_setDouble(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDecodeTokensPerSecond() => $_has(3);
  @$pb.TagNumber(4)
  void clearDecodeTokensPerSecond() => $_clearField(4);

  /// Prefill (prompt eval) wall time. cf. llama.cpp timings.prompt_ms,
  /// Ollama prompt_eval_duration. 0 when the backend does not report it.
  @$pb.TagNumber(5)
  $fixnum.Int64 get prefillMs => $_getI64(4);
  @$pb.TagNumber(5)
  set prefillMs($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPrefillMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearPrefillMs() => $_clearField(5);

  /// Request start to first output token. The canonical spelling for every
  /// result type: LLMGenerationResult, LLMStreamFinalResult and VLMResult all
  /// report TTFT here and nowhere else. SDKEvent's own telemetry fields
  /// (GenerationEvent.time_to_first_token_ms, first_token_latency_ms) keep
  /// their separate event-stream spelling.
  @$pb.TagNumber(6)
  $fixnum.Int64 get ttftMs => $_getI64(5);
  @$pb.TagNumber(6)
  set ttftMs($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasTtftMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearTtftMs() => $_clearField(6);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
