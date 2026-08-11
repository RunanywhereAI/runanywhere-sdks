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
    $fixnum.Int64? timeToFirstContentTokenMs,
    $core.double? contentTokensPerSecond,
    $core.bool? batchBuffered,
    $core.bool? countsEstimated,
  }) {
    final result = create();
    if (inputTokens != null) result.inputTokens = inputTokens;
    if (outputTokens != null) result.outputTokens = outputTokens;
    if (totalTokens != null) result.totalTokens = totalTokens;
    if (decodeTokensPerSecond != null)
      result.decodeTokensPerSecond = decodeTokensPerSecond;
    if (prefillMs != null) result.prefillMs = prefillMs;
    if (ttftMs != null) result.ttftMs = ttftMs;
    if (timeToFirstContentTokenMs != null)
      result.timeToFirstContentTokenMs = timeToFirstContentTokenMs;
    if (contentTokensPerSecond != null)
      result.contentTokensPerSecond = contentTokensPerSecond;
    if (batchBuffered != null) result.batchBuffered = batchBuffered;
    if (countsEstimated != null) result.countsEstimated = countsEstimated;
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
    ..aInt64(7, _omitFieldNames ? '' : 'timeToFirstContentTokenMs')
    ..aD(8, _omitFieldNames ? '' : 'contentTokensPerSecond')
    ..aOB(9, _omitFieldNames ? '' : 'batchBuffered')
    ..aOB(10, _omitFieldNames ? '' : 'countsEstimated')
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

  /// Request start to first output token of any kind (reasoning or content).
  /// The canonical spelling for every result type: LLMGenerationResult and
  /// VLMResult report TTFT here and nowhere else. SDKEvent's own telemetry
  /// fields (GenerationEvent.time_to_first_token_ms, first_token_latency_ms)
  /// keep their separate event-stream spelling.
  @$pb.TagNumber(6)
  $fixnum.Int64 get ttftMs => $_getI64(5);
  @$pb.TagNumber(6)
  set ttftMs($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasTtftMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearTtftMs() => $_clearField(6);

  /// Request start to the first CONTENT delta — what the user actually waits
  /// for when the model reasons first. 0 when no content token was ever
  /// delivered. Distinct from ttft_ms; do not alias the two.
  @$pb.TagNumber(7)
  $fixnum.Int64 get timeToFirstContentTokenMs => $_getI64(6);
  @$pb.TagNumber(7)
  set timeToFirstContentTokenMs($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasTimeToFirstContentTokenMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearTimeToFirstContentTokenMs() => $_clearField(7);

  /// Content-only throughput over first-content-delta → last delta. Excludes
  /// reasoning tokens the accelerator also decoded. 0 when content count or
  /// window is unavailable.
  @$pb.TagNumber(8)
  $core.double get contentTokensPerSecond => $_getN(7);
  @$pb.TagNumber(8)
  set contentTokensPerSecond($core.double value) => $_setDouble(7, value);
  @$pb.TagNumber(8)
  $core.bool hasContentTokensPerSecond() => $_has(7);
  @$pb.TagNumber(8)
  void clearContentTokensPerSecond() => $_clearField(8);

  /// True when the backend buffered the whole generation and flushed deltas
  /// at once, so the decode window is an artifact of the flush. Platforms
  /// must not re-derive this heuristic.
  @$pb.TagNumber(9)
  $core.bool get batchBuffered => $_getBF(8);
  @$pb.TagNumber(9)
  set batchBuffered($core.bool value) => $_setBool(8, value);
  @$pb.TagNumber(9)
  $core.bool hasBatchBuffered() => $_has(8);
  @$pb.TagNumber(9)
  void clearBatchBuffered() => $_clearField(9);

  /// True when input_tokens / output_tokens were estimated (e.g. chars/4)
  /// rather than reported by the engine. Absence of the flag (false) means
  /// the counts are engine-measured.
  @$pb.TagNumber(10)
  $core.bool get countsEstimated => $_getBF(9);
  @$pb.TagNumber(10)
  set countsEstimated($core.bool value) => $_setBool(9, value);
  @$pb.TagNumber(10)
  $core.bool hasCountsEstimated() => $_has(9);
  @$pb.TagNumber(10)
  void clearCountsEstimated() => $_clearField(10);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
