//
//  Generated code. Do not modify.
//  source: llm_service.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'llm_service.pbenum.dart';

export 'llm_service.pbenum.dart';

class LLMGenerateRequest extends $pb.GeneratedMessage {
  factory LLMGenerateRequest({
    $core.String? prompt,
    $core.int? maxTokens,
    $core.double? temperature,
    $core.double? topP,
    $core.int? topK,
    $core.String? systemPrompt,
    $core.bool? emitThoughts,
  }) {
    final $result = create();
    if (prompt != null) {
      $result.prompt = prompt;
    }
    if (maxTokens != null) {
      $result.maxTokens = maxTokens;
    }
    if (temperature != null) {
      $result.temperature = temperature;
    }
    if (topP != null) {
      $result.topP = topP;
    }
    if (topK != null) {
      $result.topK = topK;
    }
    if (systemPrompt != null) {
      $result.systemPrompt = systemPrompt;
    }
    if (emitThoughts != null) {
      $result.emitThoughts = emitThoughts;
    }
    return $result;
  }
  LLMGenerateRequest._() : super();
  factory LLMGenerateRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LLMGenerateRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LLMGenerateRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'prompt')
    ..a<$core.int>(2, _omitFieldNames ? '' : 'maxTokens', $pb.PbFieldType.O3)
    ..a<$core.double>(3, _omitFieldNames ? '' : 'temperature', $pb.PbFieldType.OF)
    ..a<$core.double>(4, _omitFieldNames ? '' : 'topP', $pb.PbFieldType.OF)
    ..a<$core.int>(5, _omitFieldNames ? '' : 'topK', $pb.PbFieldType.O3)
    ..aOS(6, _omitFieldNames ? '' : 'systemPrompt')
    ..aOB(7, _omitFieldNames ? '' : 'emitThoughts')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LLMGenerateRequest clone() => LLMGenerateRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LLMGenerateRequest copyWith(void Function(LLMGenerateRequest) updates) => super.copyWith((message) => updates(message as LLMGenerateRequest)) as LLMGenerateRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LLMGenerateRequest create() => LLMGenerateRequest._();
  LLMGenerateRequest createEmptyInstance() => create();
  static $pb.PbList<LLMGenerateRequest> createRepeated() => $pb.PbList<LLMGenerateRequest>();
  @$core.pragma('dart2js:noInline')
  static LLMGenerateRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LLMGenerateRequest>(create);
  static LLMGenerateRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get prompt => $_getSZ(0);
  @$pb.TagNumber(1)
  set prompt($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasPrompt() => $_has(0);
  @$pb.TagNumber(1)
  void clearPrompt() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get maxTokens => $_getIZ(1);
  @$pb.TagNumber(2)
  set maxTokens($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasMaxTokens() => $_has(1);
  @$pb.TagNumber(2)
  void clearMaxTokens() => clearField(2);

  @$pb.TagNumber(3)
  $core.double get temperature => $_getN(2);
  @$pb.TagNumber(3)
  set temperature($core.double v) { $_setFloat(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTemperature() => $_has(2);
  @$pb.TagNumber(3)
  void clearTemperature() => clearField(3);

  @$pb.TagNumber(4)
  $core.double get topP => $_getN(3);
  @$pb.TagNumber(4)
  set topP($core.double v) { $_setFloat(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTopP() => $_has(3);
  @$pb.TagNumber(4)
  void clearTopP() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get topK => $_getIZ(4);
  @$pb.TagNumber(5)
  set topK($core.int v) { $_setSignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasTopK() => $_has(4);
  @$pb.TagNumber(5)
  void clearTopK() => clearField(5);

  @$pb.TagNumber(6)
  $core.String get systemPrompt => $_getSZ(5);
  @$pb.TagNumber(6)
  set systemPrompt($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasSystemPrompt() => $_has(5);
  @$pb.TagNumber(6)
  void clearSystemPrompt() => clearField(6);

  @$pb.TagNumber(7)
  $core.bool get emitThoughts => $_getBF(6);
  @$pb.TagNumber(7)
  set emitThoughts($core.bool v) { $_setBool(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasEmitThoughts() => $_has(6);
  @$pb.TagNumber(7)
  void clearEmitThoughts() => clearField(7);
}

/// v2 close-out Phase G-2: unified per-token streaming event. Replaces
/// LLMToken (deleted) and the per-SDK hand-rolled AsyncThrowingStream /
/// callbackFlow / StreamController / tokenQueue. One serialized event
/// per generated token. Mirrors VoiceEvent's seq + timestamp_us pattern
/// from voice_events.proto so frontends can reuse gap-detection logic.
class LLMStreamEvent extends $pb.GeneratedMessage {
  factory LLMStreamEvent({
    $fixnum.Int64? seq,
    $fixnum.Int64? timestampUs,
    $core.String? token,
    $core.bool? isFinal,
    LLMTokenKind? kind,
    $core.int? tokenId,
    $core.double? logprob,
    $core.String? finishReason,
    $core.String? errorMessage,
  }) {
    final $result = create();
    if (seq != null) {
      $result.seq = seq;
    }
    if (timestampUs != null) {
      $result.timestampUs = timestampUs;
    }
    if (token != null) {
      $result.token = token;
    }
    if (isFinal != null) {
      $result.isFinal = isFinal;
    }
    if (kind != null) {
      $result.kind = kind;
    }
    if (tokenId != null) {
      $result.tokenId = tokenId;
    }
    if (logprob != null) {
      $result.logprob = logprob;
    }
    if (finishReason != null) {
      $result.finishReason = finishReason;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    return $result;
  }
  LLMStreamEvent._() : super();
  factory LLMStreamEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LLMStreamEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LLMStreamEvent', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'seq', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aInt64(2, _omitFieldNames ? '' : 'timestampUs')
    ..aOS(3, _omitFieldNames ? '' : 'token')
    ..aOB(4, _omitFieldNames ? '' : 'isFinal')
    ..e<LLMTokenKind>(5, _omitFieldNames ? '' : 'kind', $pb.PbFieldType.OE, defaultOrMaker: LLMTokenKind.LLM_TOKEN_KIND_UNSPECIFIED, valueOf: LLMTokenKind.valueOf, enumValues: LLMTokenKind.values)
    ..a<$core.int>(6, _omitFieldNames ? '' : 'tokenId', $pb.PbFieldType.OU3)
    ..a<$core.double>(7, _omitFieldNames ? '' : 'logprob', $pb.PbFieldType.OF)
    ..aOS(8, _omitFieldNames ? '' : 'finishReason')
    ..aOS(9, _omitFieldNames ? '' : 'errorMessage')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LLMStreamEvent clone() => LLMStreamEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LLMStreamEvent copyWith(void Function(LLMStreamEvent) updates) => super.copyWith((message) => updates(message as LLMStreamEvent)) as LLMStreamEvent;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LLMStreamEvent create() => LLMStreamEvent._();
  LLMStreamEvent createEmptyInstance() => create();
  static $pb.PbList<LLMStreamEvent> createRepeated() => $pb.PbList<LLMStreamEvent>();
  @$core.pragma('dart2js:noInline')
  static LLMStreamEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LLMStreamEvent>(create);
  static LLMStreamEvent? _defaultInstance;

  /// Monotonic per-process sequence number. Useful for frontends that
  /// need to detect gaps or out-of-order delivery.
  @$pb.TagNumber(1)
  $fixnum.Int64 get seq => $_getI64(0);
  @$pb.TagNumber(1)
  set seq($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSeq() => $_has(0);
  @$pb.TagNumber(1)
  void clearSeq() => clearField(1);

  /// Wall-clock timestamp captured at the C++ edge, in microseconds
  /// since Unix epoch. Frontends may re-timestamp for UI display.
  @$pb.TagNumber(2)
  $fixnum.Int64 get timestampUs => $_getI64(1);
  @$pb.TagNumber(2)
  set timestampUs($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTimestampUs() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestampUs() => clearField(2);

  /// Generated token text. Empty on terminal events where only
  /// finish_reason or error_message is populated.
  @$pb.TagNumber(3)
  $core.String get token => $_getSZ(2);
  @$pb.TagNumber(3)
  set token($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasToken() => $_has(2);
  @$pb.TagNumber(3)
  void clearToken() => clearField(3);

  /// True on the last event of a generation.
  @$pb.TagNumber(4)
  $core.bool get isFinal => $_getBF(3);
  @$pb.TagNumber(4)
  set isFinal($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasIsFinal() => $_has(3);
  @$pb.TagNumber(4)
  void clearIsFinal() => clearField(4);

  /// Token semantic category (answer / thought / tool-call).
  @$pb.TagNumber(5)
  LLMTokenKind get kind => $_getN(4);
  @$pb.TagNumber(5)
  set kind(LLMTokenKind v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasKind() => $_has(4);
  @$pb.TagNumber(5)
  void clearKind() => clearField(5);

  /// Backend-provided token id when the engine exposes it; 0 = unset
  /// (proto3 scalar default).
  @$pb.TagNumber(6)
  $core.int get tokenId => $_getIZ(5);
  @$pb.TagNumber(6)
  set tokenId($core.int v) { $_setUnsignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasTokenId() => $_has(5);
  @$pb.TagNumber(6)
  void clearTokenId() => clearField(6);

  /// Per-token log-probability when supported; 0.0 = unset.
  @$pb.TagNumber(7)
  $core.double get logprob => $_getN(6);
  @$pb.TagNumber(7)
  set logprob($core.double v) { $_setFloat(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasLogprob() => $_has(6);
  @$pb.TagNumber(7)
  void clearLogprob() => clearField(7);

  /// Reason the stream stopped: "stop", "length", "cancelled", "error",
  /// "" = unset (proto3 scalar default). Only populated when is_final.
  @$pb.TagNumber(8)
  $core.String get finishReason => $_getSZ(7);
  @$pb.TagNumber(8)
  set finishReason($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasFinishReason() => $_has(7);
  @$pb.TagNumber(8)
  void clearFinishReason() => clearField(8);

  /// Error message on failure events (kind may be unset, is_final true).
  /// Empty on success.
  @$pb.TagNumber(9)
  $core.String get errorMessage => $_getSZ(8);
  @$pb.TagNumber(9)
  set errorMessage($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasErrorMessage() => $_has(8);
  @$pb.TagNumber(9)
  void clearErrorMessage() => clearField(9);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
